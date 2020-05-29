#!/bin/bash

set -x

export SGE_ADMIN=sgeadmin

mkdir -p /home/sgeadmin/ocisge/{scripts,logs}

cat << 'EOF' > /home/sgeadmin/ocisge/scripts/cluster-info
# Use instance principals for OCI CLI authentication
export OCI_CLI_LOCATION=/home/sgeadmin/bin/oci
#export OCI_CLI_AUTH=instance_principal
export SGE_ADMIN=sgeadmin

# Cluster info populated by Terraform
export COMPARTMENT_ID=${compartment_id}
export SUBNET_ID=${subnet_id}
export REGION=${region}
export INSTANCE_POOL_ID=${instance_pool_id}
export CLUSTER_POSTFIX=${cluster_postfix}
export CLUSTER_INITIAL_SIZE=${cluster_initial_size}
export CLUSTER_MIN_SIZE=${cluster_min_size}
export CLUSTER_MAX_SIZE=${cluster_max_size}
export LOCAL_SPOOL_DIR=${execd_spool_dir_local}
export SGE_ROOT=${sge_root}
export CONFIG_FILE=/home/sgeadmin/uge_configuration.conf
export SCALING_COOLDOWN_IN_SECONDS=300
export SCALING_LOG=/home/sgeadmin/ocisge/logs/scaling_history.log
export COMPUTE_SHAPE=${sge_compute_instance_shape}
EOF

cat << 'EOF' > /home/sgeadmin/ocisge/scripts/cluster_init.sh
#!/bin/bash

. /home/sgeadmin/ocisge/scripts/cluster-info

echo "$(date) Starting cluster initialization"
# Add ADMIN and SUBMIT host
MASTER_PRIVATE_IP=$(curl -s http://169.254.169.254/opc/v1/vnics/ | jq -r '.[].privateIp')
MASTER_HOSTNAME=$(hostname)
echo $MASTER_PRIVATE_IP $MASTER_HOSTNAME sge-master | tee -a /etc/hosts
CELL_NAME=$MASTER_HOSTNAME-default

wget https://raw.githubusercontent.com/OguzPastirmaci/misc/master/uge.conf
cp ./uge.conf $CONFIG_FILE
sed -i 's/^ADMIN_HOST_LIST=.*/ADMIN_HOST_LIST="'"$MASTER_HOSTNAME"'"/' $CONFIG_FILE
sed -i 's/^SUBMIT_HOST_LIST=.*/SUBMIT_HOST_LIST="'"$MASTER_HOSTNAME"'"/' $CONFIG_FILE
sed -i 's/^CELL_NAME=.*/CELL_NAME="'"$CELL_NAME"'"/' $CONFIG_FILE

cd $SGE_ROOT
echo "$(date) Adding $MASTER_HOSTNAME as admin and submit host"
./inst_sge -m -s -auto $CONFIG_FILE
cp $SGE_ROOT/$CELL_NAME/common/settings.sh /etc/profile.d/SGE.sh
cp $SGE_ROOT/$CELL_NAME/common/settings.csh /etc/profile.d/SGE.csh
chmod +x /etc/profile.d/SGE.sh
chmod +x /etc/profile.d/SGE.csh
. /etc/profile.d/SGE.sh
. /etc/profile.d/SGE.csh

# Add EXEC hosts
until [ $($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID | jq -r '.data."lifecycle-state"') == "RUNNING" ]; do
    echo "$(date) Waiting for Instance Pool state to be RUNNING"
    sleep 30
    done

INSTANCES_TO_ADF=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.data[]."id"')

for INSTANCE in $INSTANCES_TO_ADD; do
PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
COMPUTE_HOSTNAME_TO_ADD=$($OCI_CLI_LOCATION compute instance get --instance-id $INSTANCE | jq -r '.data."display-name"')
echo $PRIVATE_IP $COMPUTE_HOSTNAME_TO_ADD | sudo tee -a /etc/hosts
ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo hostname $COMPUTE_HOSTNAME_TO_ADD"
echo $PRIVATE_IP $COMPUTE_HOSTNAME_TO_ADD | ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo sh -c 'cat >>/etc/hosts'"
echo $MASTER_PRIVATE_IP $MASTER_HOSTNAME | ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo sh -c 'cat >>/etc/hosts'"
sed -i 's/^EXEC_HOST_LIST=.*/EXEC_HOST_LIST="'"$COMPUTE_HOSTNAME_TO_ADD"'"/' $CONFIG_FILE
scp $CONFIG_FILE $COMPUTE_HOSTNAME_TO_ADD:$CONFIG_FILE
cd $SGE_ROOT && ./inst_sge -x -auto $CONFIG_FILE
sleep 10
ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo $SGE_ROOT/$CELL_NAME/common/sgeexecd stop && sudo $SGE_ROOT/$CELL_NAME/common/sgeexecd start"
done
    
echo "$(date) Changing all.q's tmpdir to /nvme/tmp"
qconf -rattr queue tmpdir /nvme/tmp all.q
qconf -Ap $SGE_ROOT/simcores_pe
qconf -aattr queue pe_list simcores all.q
echo "$(date) Cluster initialization completed"
EOF

cat << 'EOF' > /home/sgeadmin/ocisge/scripts/add-exec-host.sh
#!/bin/bash

set -x

. /home/sgeadmin/ocisge/scripts/cluster-info

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION | jq -r .data.size)
NUMBER_OF_INSTANCES_TO_ADD=$1
NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE + NUMBER_OF_INSTANCES_TO_ADD))

if [ "$NEW_INSTANCE_POOL_SIZE" -gt "$CLUSTER_MAX_SIZE" ]
then
	echo "$(date) Cluster already has the maximum number of $CLUSTER_MAX_SIZE nodes"
elif [ $(expr $(date +%s) - $(stat $SCALING_LOG -c %Y)) -le "$SCALING_COOLDOWN_IN_SECONDS" ]
then
	echo "$(date) Last scaling operation happened in the last $SCALING_COOLDOWN_IN_SECONDS seconds, skipping"
else
	echo "$(date) Starting to scale out the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes"
    $OCI_CLI_LOCATION compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID --size $NEW_INSTANCE_POOL_SIZE
    sleep 30
    INSTANCES_TO_ADD=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.data[] | select(.state=="Provisioning") | .id')
    until [ $($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID | jq -r '.data."lifecycle-state"') == "RUNNING" ]; do
    echo "$(date) Waiting for Instance Pool state to be RUNNING"
    sleep 5
    done
    MASTER_PRIVATE_IP=$(curl -s http://169.254.169.254/opc/v1/vnics/ | jq -r '.[].privateIp')
    MASTER_HOSTNAME=$(hostname)
for INSTANCE in $INSTANCES_TO_ADD; do
        PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
        COMPUTE_HOSTNAME_TO_ADD=$($OCI_CLI_LOCATION compute instance get --instance-id $INSTANCE | jq -r '.data."display-name"')
        echo $PRIVATE_IP $COMPUTE_HOSTNAME_TO_ADD | sudo tee -a /etc/hosts
            until ssh -q -oStrictHostKeyChecking=no $SGE_ADMIN@$COMPUTE_HOSTNAME_TO_ADD exit; do
                echo "$(date) Waiting for remote exec host to respond"
                sleep 10
            done
        ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo hostname $COMPUTE_HOSTNAME_TO_ADD"
        echo $PRIVATE_IP $COMPUTE_HOSTNAME_TO_ADD | ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo sh -c 'cat >>/etc/hosts'"
        echo $MASTER_PRIVATE_IP $MASTER_HOSTNAME | ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo sh -c 'cat >>/etc/hosts'"
        sed -i 's/^EXEC_HOST_LIST=.*/EXEC_HOST_LIST="'"$COMPUTE_HOSTNAME_TO_ADD"'"/' $CONFIG_FILE
        scp $CONFIG_FILE $COMPUTE_HOSTNAME_TO_ADD:$CONFIG_FILE
        cd $SGE_ROOT && ./inst_sge -x -auto $CONFIG_FILE
        sleep 10
        ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo $SGE_ROOT/$CELL_NAME/common/sgeexecd stop && sudo /tools/gridengine/uge/sge-master-default/common/sgeexecd start"
    done
    echo "$(date) Scaled out the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_LOG
fi
EOF

cat << 'EOF' > /home/sgeadmin/ocisge/scripts/remove-exec-host.sh
#!/bin/bash
set -x

. /home/sgeadmin/ocisge/scripts/cluster-info

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)
NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE - 1))

if [ "$NEW_INSTANCE_POOL_SIZE" -lt "$CLUSTER_MIN_SIZE" ]
then
	echo "$(date) Cluster already has the minimum number of $CLUSTER_MIN_SIZE nodes"
elif [ $(expr $(date +%s) - $(stat $SCALING_LOG -c %Y)) -le "$SCALING_COOLDOWN_IN_SECONDS" ]
then
	echo "$(date) Last scaling operation happened in the last $SCALING_COOLDOWN_IN_SECONDS seconds, skipping"
else
	echo "$(date) Starting to scale in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes"
    INSTANCE_TO_DELETE=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID --sort-by TIMECREATED --sort-order DESC | jq -r '.data[] | select(.state=="Running") | .id')
    PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE_TO_DELETE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
    COMPUTE_HOSTNAME_TO_REMOVE=$($OCI_CLI_LOCATION compute instance get --instance-id $INSTANCE_TO_DELETE | jq -r '.data."display-name"')
    sed -i 's/^EXEC_HOST_LIST_RM=.*/EXEC_HOST_LIST_RM="'"$COMPUTE_HOSTNAME_TO_REMOVE"'"/' $CONFIG_FILE
    scp $CONFIG_FILE $COMPUTE_HOSTNAME_TO_REMOVE:$CONFIG_FILE
    cd $SGE_ROOT && ./inst_sge -ux -auto $CONFIG_FILE
    sudo sed -i".bak" "/$COMPUTE_HOSTNAME_TO_REMOVE/d" /etc/hosts
    $OCI_CLI_LOCATION compute instance terminate --region $REGION --instance-id $INSTANCE_TO_DELETE --force
    $OCI_CLI_LOCATION compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID --size $NEW_INSTANCE_POOL_SIZE
    echo "$(date) Scaled in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_LOG
fi
EOF

cat << 'EOF' > /home/sgeadmin/ocisge/scripts/autoscaling.sh
#!/bin/bash
set -x

. /etc/profile.d/SGE.sh
. /home/sgeadmin/ocisge/scripts/cluster-info

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)
NUMBER_OF_CORES_PER_COMPUTE_NODE=$(echo $COMPUTE_SHAPE | awk -F '\\.' '{print $NF}')
NUMBER_OF_TOTAL_CORES=$((CURRENT_INSTANCE_POOL_SIZE * NUMBER_OF_CORES_PER_COMPUTE_NODE))

RUNNING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "r") print $0 }' | wc -l)
PENDING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "qw" || $5 == "hqw")  print $0 }' | wc -l)

echo -e "\n$(date) Checking the cluster for autoscaling"
echo "$(date) Number of running jobs in the cluster: $RUNNING_JOBS"
echo "$(date) Number of pending jobs in the cluster: $PENDING_JOBS"

if [ "$PENDING_JOBS" -ge "$NUMBER_OF_CORES" ]
then
	echo "$(date) SCALING: There are $PENDING_JOBS pending jobs, adding a new exec node"
    /home/sgeadmin/ocisge/scripts/add-exec-host.sh 1
elif [ "$PENDING_JOBS" -eq 0 ] && [ "$RUNNING_JOBS" -eq 0 ]
then
	echo "$(date) SCALING: There are no jobs running in the cluster, will try to remove one exec node"
    /home/sgeadmin/ocisge/scripts/remove-exec-host.sh
fi
EOF

# Setup permissions of scripts
chown -R sgeadmin /home/sgeadmin/ocisge
chmod +x /home/sgeadmin/ocisge/scripts/cluster_init.sh
chmod +x /home/sgeadmin/ocisge/scripts/add-exec-host.sh
chmod +x /home/sgeadmin/ocisge/scripts/remove-exec-host.sh
chmod +x /home/sgeadmin/ocisge/scripts/autoscaling.sh

# Run cluster initialization
. /home/sgeadmin/ocisge/scripts/cluster-info
/home/sgeadmin/ocisge/scripts/cluster_init.sh >> /home/sgeadmin/ocisge/logs/cluster_init.log

# Add autoscaling script as a cron job that runs every minute
(crontab -u 2>/dev/null; echo "* * * * * /home/sgeadmin/ocisge/scripts/autoscaling.sh >> /home/sgeadmin/ocisge/logs/autoscaling.log") | crontab -


