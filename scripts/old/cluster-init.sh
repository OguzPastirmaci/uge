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