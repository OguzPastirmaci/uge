#!/bin/bash

set -ex

echo "Cluster postfix: <clusterpostfix>"

. /home/sgeadmin/ocisge/<clusterpostfix>/scripts/info.sh

echo "$(pdate) Starting cluster initialization"
# Add ADMIN and SUBMIT host
MASTER_PRIVATE_IP=$(curl -s http://169.254.169.254/opc/v1/vnics/ | jq -r '.[].privateIp')
MASTER_HOSTNAME=$(hostname)
echo $MASTER_PRIVATE_IP $MASTER_HOSTNAME | tee -a /etc/hosts

cd /home/sgeadmin/ocisge/<clusterpostfix>/scripts
wget https://raw.githubusercontent.com/OguzPastirmaci/misc/master/uge.conf
cp /home/sgeadmin/ocisge/<clusterpostfix>/scripts/uge.conf $CONFIG_FILE
sed -i 's/^ADMIN_HOST_LIST=.*/ADMIN_HOST_LIST="'"$MASTER_HOSTNAME"'"/' $CONFIG_FILE
sed -i 's/^SUBMIT_HOST_LIST=.*/SUBMIT_HOST_LIST="'"$MASTER_HOSTNAME"'"/' $CONFIG_FILE
sed -i 's/^CELL_NAME=.*/CELL_NAME="'"$CELL_NAME"'"/' $CONFIG_FILE

cd $SGE_ROOT
echo "$(pdate) Adding $MASTER_HOSTNAME as admin and submit host"
./inst_sge -m -s -auto $CONFIG_FILE
. $SGE_ROOT/$CELL_NAME/common/settings.sh

qconf -Ap $SGE_ROOT/simcores_pe
qconf -aattr queue pe_list simcores all.q

echo "$(pdate) Cluster initialization completed"
