#!/bin/bash

set -x

mkdir -p /home/opc/ocisge/{scripts,logs}

cat << 'EOF' > /home/opc/ocisge/scripts/cluster-info
# Use instance principals for OCI CLI authentication
export OCI_CLI_LOCATION=/home/opc/bin/oci
export OCI_CLI_AUTH=instance_principal
export SGE_ADMIN=opc

# Cluster info populated by Terraform
export COMPARTMENT_ID=${compartment_id}
export SUBNET_ID=${subnet_id}
export REGION=${region}
export AD=${ad}
export INSTANCE_POOL_ID=${instance_pool_id}
export CLUSTER_POSTFIX=${cluster_postfix}
export CLUSTER_INITIAL_SIZE=${cluster_initial_size}
export CLUSTER_MIN_SIZE=${cluster_min_size}
export CLUSTER_MAX_SIZE=${cluster_max_size}
export SLAVE_SHAPE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.shape' --raw-output)

export SGE_ROOT=${sge_root}
export CONFIG_FILE=/home/opc/uge_configuration.conf
export CLUSTER_SCALING_FREQUENCY=300
export SCALING_LOG=/home/opc/ocisge/logs/scaling_history.log
EOF

cat << 'EOF' > /home/opc/ocisge/scripts/cluster_init.sh
#!/bin/bash

set -x

. /home/opc/ocisge/scripts/cluster-info

echo "$(date) Starting to initializing cluster"
# Add ADMIN and SUBMIT host
MASTER_PRIVATE_IP=$(curl -s http://169.254.169.254/opc/v1/vnics/ | jq -r '.[].privateIp')
MASTER_HOSTNAME=$(host $MASTER_PRIVATE_IP | awk '{ sub(/\.$/, ""); print $NF }')
CELL_NAME=$MASTER_HOSTNAME

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)

cp $SGE_ROOT/util/install_modules/uge_configuration.conf $CONFIG_FILE
sed -i 's/^ADMIN_HOST_LIST=.*/ADMIN_HOST_LIST="'"$MASTER_HOSTNAME"'"/' $CONFIG_FILE
sed -i 's/^SUBMIT_HOST_LIST=.*/SUBMIT_HOST_LIST="'"$MASTER_HOSTNAME"'"/' $CONFIG_FILE
sed -i 's/^CELL_NAME=.*/CELL_NAME="'"$CELL_NAME"'"/' $CONFIG_FILE

cd $SGE_ROOT
echo "Adding $MASTER_HOSTNAME as admin and submit host"
./inst_sge -m -s -auto $CONFIG_FILE
cp $SGE_ROOT/$CELL_NAME/common/settings.sh /etc/profile.d/SGE.sh
chmod +x /etc/profile.d/SGE.sh
. /etc/profile.d/SGE.sh

# Add EXEC hosts
until [ $($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID | jq -r '.data."lifecycle-state"') == "RUNNING" ]; do
    echo "Waiting for Instance Pool state to be RUNNING"
    sleep 5
    done

INSTANCE_IDS=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.data[]."id"')

    for INSTANCE in $INSTANCE_IDS; do
        PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
        NEW_SLAVE_DISPLAY_NAME=$(host $PRIVATE_IP | awk '{ sub(/\.$/, ""); print $NF }' | cut -d. -f1)
        $OCI_CLI_LOCATION compute instance update --instance-id $INSTANCE --display-name $NEW_SLAVE_DISPLAY_NAME
        SLAVE_HOSTNAME_TO_ADD=$(host $PRIVATE_IP | awk '{ sub(/\.$/, ""); print $NF }')
        sed -i 's/^EXEC_HOST_LIST=.*/EXEC_HOST_LIST="'"$SLAVE_HOSTNAME_TO_ADD"'"/' $CONFIG_FILE
        until su - $SGE_ADMIN -c "ssh -q -oStrictHostKeyChecking=no $SGE_ADMIN@$SLAVE_HOSTNAME_TO_ADD exit"; do
            sleep 5
        done
    su - $SGE_ADMIN -c "scp $CONFIG_FILE $SLAVE_HOSTNAME_TO_ADD:$CONFIG_FILE"
    su - $SGE_ADMIN -c "cd $SGE_ROOT && ./inst_sge -x -auto $CONFIG_FILE"
    done
    echo "$(date) Cluster initialization completed"
fi
EOF

cat << 'EOF' > /home/opc/ocisge/scripts/add-exec-host.sh
#!/bin/bash

set -x

. /home/opc/ocisge/scripts/cluster-info

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)
NUMBER_OF_INSTANCES_TO_ADD=$1
NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE + NUMBER_OF_INSTANCES_TO_ADD))

if [ "$NEW_INSTANCE_POOL_SIZE" -gt "$CLUSTER_MAX_SIZE" ]
then
	echo "$(date) Cluster already has the maximum number of $CLUSTER_MAX_SIZE nodes"
elif [ $(expr $(date +%s) - $(stat $SCALING_LOG -c %Y)) -le "$CLUSTER_SCALING_FREQUENCY" ]
then
	echo "$(date) Last scaling operation happened in the last $CLUSTER_SCALING_FREQUENCY seconds, skipping"
else
	echo "$(date) Starting to scale out the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes"
    $OCI_CLI_LOCATION compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID --size $NEW_INSTANCE_POOL_SIZE
    until [ $($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID | jq -r '.data."lifecycle-state"') == "RUNNING" ]; do
    echo "Waiting for Instance Pool state to be RUNNING"
    sleep 5
    done
    INSTANCE_IDS=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.data[]."id"')

    for INSTANCE in $INSTANCE_IDS; do
        PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
        NEW_SLAVE_DISPLAY_NAME=$(host $PRIVATE_IP | awk '{ sub(/\.$/, ""); print $NF }' | cut -d. -f1)
        $OCI_CLI_LOCATION compute instance update --instance-id $INSTANCE --display-name $NEW_SLAVE_DISPLAY_NAME
        SLAVE_HOSTNAME_TO_ADD=$(host $PRIVATE_IP | awk '{ sub(/\.$/, ""); print $NF }')
        sed -i 's/^EXEC_HOST_LIST=.*/EXEC_HOST_LIST="'"$SLAVE_HOSTNAME_TO_ADD"'"/' $CONFIG_FILE
        until su - $SGE_ADMIN -c "ssh -q -oStrictHostKeyChecking=no $SGE_ADMIN@$SLAVE_HOSTNAME_TO_ADD exit"; do
            sleep 5
        done
    su - $SGE_ADMIN -c "scp $CONFIG_FILE $SLAVE_HOSTNAME_TO_ADD:$CONFIG_FILE"
    su - $SGE_ADMIN -c "cd $SGE_ROOT && ./inst_sge -x -auto $CONFIG_FILE"
    done
    echo "$(date) Scaled out the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_LOG
fi
EOF

cat << 'EOF' > /home/opc/ocisge/scripts/remove-exec-host.sh
#!/bin/bash
set -x

. /home/opc/ocisge/scripts/cluster-info

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)
NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE - 1))

if [ "$NEW_INSTANCE_POOL_SIZE" -lt "$CLUSTER_MIN_SIZE" ]
then
	echo "$(date) Cluster already has the minimum number of $CLUSTER_MIN_SIZE nodes"
elif [ $(expr $(date +%s) - $(stat $SCALING_LOG -c %Y)) -le "$CLUSTER_SCALING_FREQUENCY" ]
then
	echo "$(date) Last scaling operation happened in the last $CLUSTER_SCALING_FREQUENCY seconds, skipping"
else
	echo "$(date) Starting to scale in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes"
    INSTANCE=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.data[0].id')
    PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
    SLAVE_HOSTNAME_TO_REMOVE=$(host $PRIVATE_IP | awk '{ sub(/\.$/, ""); print $NF }')
    sed -i 's/^EXEC_HOST_LIST_RM=.*/EXEC_HOST_LIST_RM="'"$SLAVE_HOSTNAME_TO_REMOVE"'"/' $CONFIG_FILE
    su - $SGE_ADMIN -c "scp $CONFIG_FILE $SLAVE_HOSTNAME_TO_REMOVE:/home/opc/uge_configuration.conf"
    su - $SGE_ADMIN -c "cd $SGE_ROOT && ./inst_sge -ux -auto $CONFIG_FILE"
    $OCI_CLI_LOCATION compute instance terminate --region $REGION --instance-id $CREATED_INSTANCE_ID --force
    $OCI_CLI_LOCATION compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID --size $NEW_INSTANCE_POOL_SIZE
    echo "$(date) Scaled in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_LOG
fi
EOF

cat << 'EOF' > /home/opc/ocisge/scripts/autoscaling.sh
#!/bin/bash
set -x

. /etc/profile.d/SGE.sh
. /home/opc/ocisge/scripts/cluster-info

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)
NUMBER_OF_CORES_PER_SLAVE=$(echo "$${SLAVE_SHAPE##*.}")
NUMBER_OF_TOTAL_CORES=$((CURRENT_INSTANCE_POOL_SIZE * NUMBER_OF_CORES_PER_SLAVE))

RUNNING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "r") print $0 }' | wc -l)
PENDING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "qw" || $5 == "hqw")  print $0 }' | wc -l)

echo -e "\n$(date) Checking the cluster for autoscaling"
echo "$(date) Number of running jobs in the cluster: $RUNNING_JOBS"
echo "$(date) Number of pending jobs in the cluster: $PENDING_JOBS"

if [ "$PENDING_JOBS" -ge "$NUMBER_OF_CORES" ]
then
	echo "SCALING: There are $PENDING_JOBS pending jobs, adding a new exec node"
    /home/opc/ocisge/scripts/add-exec-host.sh 1
elif [ "$PENDING_JOBS" -eq 0 ] && [ "$RUNNING_JOBS" -eq 0 ]
then
	echo "SCALING: There are no jobs running in the cluster, will try to remove one exec node"
    /home/opc/ocisge/scripts/remove-exec-host.sh
fi
EOF

chown -R opc /home/opc/ocisge
chmod +x /home/opc/ocisge/scripts/cluster_init.sh
chmod +x /home/opc/ocisge/scripts/add-exec-host.sh
chmod +x /home/opc/ocisge/scripts/remove-exec-host.sh
chmod +x /home/opc/ocisge/scripts/autoscaling.sh

. /home/opc/ocisge/scripts/cluster-info
/home/opc/ocisge/scripts/cluster_init.sh >> /home/opc/ocisge/logs/cluster_init.log

(crontab -u 2>/dev/null; echo "* * * * * /home/opc/ocisge/scripts/autoscaling.sh >> /home/opc/ocisge/logs/autoscaling.log") | crontab -