#!/bin/bash

set -x

echo "Cluster postfix: $CLUSTER_POSTFIX"

. /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts/info.sh

echo "$(date) Starting cluster initialization"
# Add ADMIN and SUBMIT host
MASTER_PRIVATE_IP=$(curl -s http://169.254.169.254/opc/v1/vnics/ | jq -r '.[].privateIp')
MASTER_HOSTNAME=$(hostname)
echo $MASTER_PRIVATE_IP $MASTER_HOSTNAME | tee -a /etc/hosts

cd /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts
wget https://raw.githubusercontent.com/OguzPastirmaci/misc/master/uge.conf
cp /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts/uge.conf $CONFIG_FILE
sed -i 's/^ADMIN_HOST_LIST=.*/ADMIN_HOST_LIST="'"$MASTER_HOSTNAME"'"/' $CONFIG_FILE
sed -i 's/^SUBMIT_HOST_LIST=.*/SUBMIT_HOST_LIST="'"$MASTER_HOSTNAME"'"/' $CONFIG_FILE
sed -i 's/^CELL_NAME=.*/CELL_NAME="'"$CELL_NAME"'"/' $CONFIG_FILE

cd $SGE_ROOT
echo "$(date) Adding $MASTER_HOSTNAME as admin and submit host"
./inst_sge -m -s -auto $CONFIG_FILE
#sudo cp $SGE_ROOT/$CELL_NAME/common/settings.sh /etc/profile.d/SGE.sh
#sudo cp $SGE_ROOT/$CELL_NAME/common/settings.csh /etc/profile.d/SGE.csh
#sudo chmod +x /etc/profile.d/SGE.sh
#sudo chmod +x /etc/profile.d/SGE.csh
#. /etc/profile.d/SGE.sh
#. /etc/profile.d/SGE.csh
. $SGE_ROOT/$CELL_NAME/common/settings.sh

#echo "$(date) Changing all.q's tmpdir to /nvme/tmp"
#qconf -rattr queue tmpdir /nvme/tmp all.q
qconf -Ap $SGE_ROOT/simcores_pe
qconf -aattr queue pe_list simcores all.q

echo "$(date) Cluster initialization completed"
