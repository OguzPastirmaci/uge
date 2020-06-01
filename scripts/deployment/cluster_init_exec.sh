#!/bin/bash

set -x

echo "Cluster postfix: $CLUSTER_POSTFIX"

. /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts/info.sh
. $SGE_ROOT/$CELL_NAME/common/settings.sh

echo "Starting adding EXEC hosts"

MASTER_PRIVATE_IP=$(curl -s http://169.254.169.254/opc/v1/vnics/ | jq -r '.[].privateIp')
MASTER_HOSTNAME=$(hostname)

INSTANCES_TO_ADD=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.data[]."id"')
    
#until [ $($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID | jq -r '.data."lifecycle-state"') == "RUNNING" ]; do
#echo "$(date) Waiting for Instance Pool state to be RUNNING"
#sleep 15
#done
 
sleep 30

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
    ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo $SGE_ROOT/$CELL_NAME/common/sgeexecd stop && sleep 5 && sudo $SGE_ROOT/$CELL_NAME/common/sgeexecd start"
    echo "Cluster init completed" >> $SCALING_LOG
done
