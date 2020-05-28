#!/bin/bash

add_exec_host () {
. /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts/info.sh

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION | jq -r .data.size)
NUMBER_OF_INSTANCES_TO_ADD=$1
NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE + NUMBER_OF_INSTANCES_TO_ADD))

if [ "$NEW_INSTANCE_POOL_SIZE" -gt "$CLUSTER_MAX_SIZE" ]
then
	echo "$(date) -- EXEC NODE ADDITION CANCELLED: Cluster already has the maximum number of $CLUSTER_MAX_SIZE nodes"
elif [ $(expr $(date +%s) - $(stat $SCALING_LOG -c %Y)) -le "$SCALING_COOLDOWN_IN_SECONDS" ]
then
	echo "$(date) -- EXEC NODE ADDITION CANCELLED: Last scaling operation happened in the last $SCALING_COOLDOWN_IN_SECONDS seconds"
else
	echo "$(date) -- Starting to scale out the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes"
    $OCI_CLI_LOCATION compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID --size $NEW_INSTANCE_POOL_SIZE
    sleep 30
    INSTANCES_TO_ADD=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.data[] | select(.state=="Provisioning") | .id')
    until [ $($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID | jq -r '.data."lifecycle-state"') == "RUNNING" ]; do
    echo "$(date) Waiting for Instance Pool state to be RUNNING"
    sleep 15
    done
    MASTER_PRIVATE_IP=$(curl -s http://169.254.169.254/opc/v1/vnics/ | jq -r '.[].privateIp')
    MASTER_HOSTNAME=$(hostname)
    for INSTANCE in $INSTANCES_TO_ADD; do
        PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
        echo $PRIVATE_IP
        COMPUTE_HOSTNAME_TO_ADD=$($OCI_CLI_LOCATION compute instance get --instance-id $INSTANCE | jq -r '.data."display-name"')
        echo $COMPUTE_HOSTNAME_TO_ADD
        echo $PRIVATE_IP $COMPUTE_HOSTNAME_TO_ADD | sudo tee -a /etc/hosts
            until ssh -q -oStrictHostKeyChecking=no $SGE_ADMIN@$COMPUTE_HOSTNAME_TO_ADD exit; do
                echo "$(date) Waiting for remote exec host to respond"
                sleep 10
            done
        ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo hostname $COMPUTE_HOSTNAME_TO_ADD"
        echo $PRIVATE_IP $COMPUTE_HOSTNAME_TO_ADD | ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo sh -c 'cat >>/etc/hosts'"
        echo $MASTER_PRIVATE_IP $MASTER_HOSTNAME sge-master | ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo sh -c 'cat >>/etc/hosts'"
        sed -i 's/^EXEC_HOST_LIST=.*/EXEC_HOST_LIST="'"$COMPUTE_HOSTNAME_TO_ADD"'"/' $CONFIG_FILE
        scp $CONFIG_FILE $COMPUTE_HOSTNAME_TO_ADD:$CONFIG_FILE
        cd $SGE_ROOT && ./inst_sge -x -auto $CONFIG_FILE
        sleep 10
        ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo $SGE_ROOT/$CELL_NAME/common/sgeexecd stop && sudo $SGE_ROOT/$CELL_NAME/common/sgeexecd start"
    done
    echo "$(date) -- Scaled out the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_LOG
fi
}

remove_exec_host () {
. /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts/info.sh

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)
NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE - 1))

if [ "$NEW_INSTANCE_POOL_SIZE" -lt "$CLUSTER_MIN_SIZE" ]
then
	echo "$(date) -- EXEC NODE REMOVAL CANCELLED: Cluster already has the minimum number of $CLUSTER_MIN_SIZE nodes"
elif [ $(expr $(date +%s) - $(stat $SCALING_LOG -c %Y)) -le "$SCALING_COOLDOWN_IN_SECONDS" ]
then
	echo "$(date) -- EXEC NODE REMOVAL CANCELLED: Last scaling operation happened in the last $SCALING_COOLDOWN_IN_SECONDS seconds"
else
	echo "$(date) -- Starting to scale in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes"
    INSTANCE_TO_DELETE=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID --sort-by TIMECREATED --sort-order DESC | jq -r '.data[-1] | select(.state=="Running") | .id')
    echo $INSTANCE_TO_DELETE
    PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE_TO_DELETE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
    echo $PRIVATE_IP
    COMPUTE_HOSTNAME_TO_REMOVE=$($OCI_CLI_LOCATION compute instance get --instance-id $INSTANCE_TO_DELETE | jq -r '.data."display-name"')
    echo $COMPUTE_HOSTNAME_TO_REMOVE
    sed -i 's/^EXEC_HOST_LIST_RM=.*/EXEC_HOST_LIST_RM="'"$COMPUTE_HOSTNAME_TO_REMOVE"'"/' $CONFIG_FILE
    scp $CONFIG_FILE $COMPUTE_HOSTNAME_TO_REMOVE:$CONFIG_FILE
    cd $SGE_ROOT && ./inst_sge -ux -auto $CONFIG_FILE
    sudo sed -i".bak" "/$COMPUTE_HOSTNAME_TO_REMOVE/d" /etc/hosts
    $OCI_CLI_LOCATION compute instance terminate --region $REGION --instance-id $INSTANCE_TO_DELETE --force
    $OCI_CLI_LOCATION compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID --size $NEW_INSTANCE_POOL_SIZE
    echo "$(date) -- Scaled in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_LOG
fi
}


. /home/sgeadmin/ocisge/scripts/info.sh
. $SGE_ROOT/$CELL_NAME/common/settings.sh

NUMBER_OF_CORES_PER_SLAVE=$(echo "${SLAVE_SHAPE##*.}")
NUMBER_OF_TOTAL_CORES=$(qstat -g c | grep all.q | awk '{print $6}')
NUMBER_OF_USED_CORES=$(qstat -g c | grep all.q | awk '{print $3}')
RUNNING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "r") print $0 }' | wc -l)
PENDING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "qw" || $5 == "hqw")  print $0 }' | wc -l)

CURRENT_UTILIZATION=$(echo "scale=2; 100 / $NUMBER_OF_TOTAL_CORES * $NUMBER_OF_USED_CORES" | bc)
DESIRED_UTILIZATION=10
UTILIZATION_RATIO=$(echo "$CURRENT_UTILIZATION > $DESIRED_UTILIZATION" | bc -q )

echo -e "\n$(date) -- Checking the cluster for autoscaling"
echo "$(date) -- Number of running jobs in the cluster: $RUNNING_JOBS"
echo "$(date) -- Number of pending jobs in the cluster: $PENDING_JOBS"
echo "$(date) -- Number of total cores in the cluster: $NUMBER_OF_TOTAL_CORES"
echo "$(date) -- Number of used cores in the cluster: $NUMBER_OF_USED_CORES"
echo "$(date) -- Current utilization of cores: $CURRENT_UTILIZATION%"

if [ $UTILIZATION_RATIO = 1 ]
then
    echo "$(date) -- ADDING A NODE: Current core utilization of $CURRENT_UTILIZATION% is higher than the desired core utilization of $DESIRED_UTILIZATION%"
    /home/sgeadmin/ocisge/scripts/add_exec_host.sh 1 >> /home/sgeadmin/ocisge/logs/autoscaling.log
elif [ "$PENDING_JOBS" -eq 0 ] && [ "$RUNNING_JOBS" -eq 0 ]
then
   echo "$(date) -- REMOVING A NODE: There are no running jobs or pending jobs in the cluster"
   /home/sgeadmin/ocisge/scripts/remove_exec_host.sh >> /home/sgeadmin/ocisge/logs/autoscaling.log
else
   echo "$(date) -- NOTHING TO DO: Current core utilization of $CURRENT_UTILIZATION% is within limits or there are running/pending in the cluster"
fi

