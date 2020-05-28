#!/bin/bash
set -x

. /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts/info.sh

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
    echo "$(date) Scaled in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_LOG
fi
