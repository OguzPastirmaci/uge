#!/bin/bash

set -x

main () {
    # TODO: Change to correct sge profile script
    . /etc/profile.d/SGE.sh
    . /home/opc/ocisge/scripts/cluster-info

    export CLUSTER_SCALING_FREQUENCY=300
    export CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)

    local NUMBER_OF_CORES_PER_SLAVE=$(echo "${SLAVE_SHAPE##*.}")
    local NUMBER_OF_TOTAL_CORES=$((CURRENT_INSTANCE_POOL_SIZE * NUMBER_OF_CORES_PER_SLAVE))

    local RUNNING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "r") print $0 }' | wc -l)
    local PENDING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "qw" || $5 == "hqw")  print $0 }' | wc -l)

    echo -e "\n$(date) Checking the cluster for autoscaling"
    echo "$(date) Number of running jobs in the cluster: $RUNNING_JOBS"
    echo "$(date) Number of pending jobs in the cluster: $PENDING_JOBS"

    if [ "$PENDING_JOBS" -ge "$NUMBER_OF_TOTAL_CORES" ]
    then
    	echo "SCALING: There are $PENDING_JOBS pending jobs, will try adding a new exec node"
        add-exec-host 1
    elif [ "$PENDING_JOBS" -eq 0 ] && [ "$RUNNING_JOBS" -eq 0 ]
    then
    	echo "SCALING: There are no jobs running in the cluster, will try removing an exec node"
        remove-exec-host
    fi
}

add-exec-host () {
    local NUMBER_OF_INSTANCES_TO_ADD=$1
    local NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE + NUMBER_OF_INSTANCES_TO_ADD))

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
}

remove-exec-host () {
    local NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE - 1))

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
}

main "$@"