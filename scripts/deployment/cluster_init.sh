#!/bin/bash

. /home/sgeadmin/ocisge/scripts/info.sh

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

INSTANCE_IDS=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.data[]."id"')

    for INSTANCE in $INSTANCES_TO_ADD; do
        PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
        COMPUTE_HOSTNAME_TO_ADD=$($OCI_CLI_LOCATION compute instance get --instance-id $INSTANCE | jq -r '.data."display-name"')
        echo $PRIVATE_IP $COMPUTE_HOSTNAME_TO_ADD | sudo tee -a /etc/hosts
            until ssh -q -oStrictHostKeyChecking=no $SGE_ADMIN@$COMPUTE_HOSTNAME_TO_ADD exit; do
                echo "$(date) Waiting for remote exec host to respond"
                sleep 10
            done
        sudo -i -u sgeadmin bash << EOF
        ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo hostname $COMPUTE_HOSTNAME_TO_ADD"
EOF
        sudo -i -u sgeadmin bash << EOF
        echo $PRIVATE_IP $COMPUTE_HOSTNAME_TO_ADD | ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo sh -c 'cat >>/etc/hosts'"
        echo $MASTER_PRIVATE_IP $MASTER_HOSTNAME | ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo sh -c 'cat >>/etc/hosts'"
EOF
        sed -i 's/^EXEC_HOST_LIST=.*/EXEC_HOST_LIST="'"$COMPUTE_HOSTNAME_TO_ADD"'"/' $CONFIG_FILE
        scp $CONFIG_FILE $COMPUTE_HOSTNAME_TO_ADD:$CONFIG_FILE
        cd $SGE_ROOT && ./inst_sge -x -auto $CONFIG_FILE
        sleep 10
        sudo -i -u sgeadmin bash << EOF
        ssh sgeadmin@$COMPUTE_HOSTNAME_TO_ADD "sudo $SGE_ROOT/$CELL_NAME/common/sgeexecd stop && sudo /tools/gridengine/uge/sge-master-default/common/sgeexecd start"
EOF
    done
    
echo "$(date) Changing all.q's tmpdir to /nvme/tmp"
qconf -rattr queue tmpdir /nvme/tmp all.q
qconf -Ap $SGE_ROOT/simcores_pe
qconf -aattr queue pe_list simcores all.q
echo "$(date) Cluster initialization completed"
