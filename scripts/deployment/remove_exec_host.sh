#!/bin/bash
#set -x

. /home/sgeadmin/ocisge/<clusterpostfix>/scripts/info.sh

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)
NEW_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE - 1))

echo "$(pdate) -- Starting to scale in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_IN_LOG

INSTANCE_TO_DELETE=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID --sort-by TIMECREATED --sort-order DESC | jq -r '.data[-1] | select(.state=="Running") | .id')
#INSTANCE_TO_DELETE=$($OCI_CLI_LOCATION compute-management instance-pool list-instances --instance-pool-id $INSTANCE_POOL_ID --region $REGION --compartment-id $COMPARTMENT_ID | jq -r '.[] |= sort_by(."time-created")[0] | .data.id')
PRIVATE_IP=$($OCI_CLI_LOCATION compute instance list-vnics --instance-id $INSTANCE_TO_DELETE --compartment-id $COMPARTMENT_ID | jq -r '.data[]."private-ip"')
COMPUTE_HOSTNAME_TO_REMOVE=$($OCI_CLI_LOCATION compute instance get --instance-id $INSTANCE_TO_DELETE | jq -r '.data."display-name"')

sed -i 's/^EXEC_HOST_LIST_RM=.*/EXEC_HOST_LIST_RM="'"$COMPUTE_HOSTNAME_TO_REMOVE"'"/' $CONFIG_FILE
scp $CONFIG_FILE $COMPUTE_HOSTNAME_TO_REMOVE:$CONFIG_FILE
cd $SGE_ROOT && ./inst_sge -ux -auto $CONFIG_FILE
sudo sed -i".bak" "/$COMPUTE_HOSTNAME_TO_REMOVE/d" /etc/hosts

MAX_CPU=$(oci monitoring metric-data summarize-metrics-data --namespace oci_computeagent --compartment-id $COMPARTMENT_ID --query-text='(CPUUtilization[1m]{resourceId = "'"$INSTANCE_TO_DELETE"'"}.max())' | jq -r '.data[]."aggregated-datapoints"[].value' | sort -r | head -n1 | xargs printf "%.2f")
MAX_MEMORY=$(oci monitoring metric-data summarize-metrics-data --namespace oci_computeagent --compartment-id $COMPARTMENT_ID --query-text='(MemoryUtilization[1m]{resourceId = "'"$INSTANCE_TO_DELETE"'"}.max())' | jq -r '.data[]."aggregated-datapoints"[].value' | sort -r | head -n1 | xargs printf "%.2f")
AVG_MEMORY=$(oci monitoring metric-data summarize-metrics-data --namespace oci_computeagent --compartment-id $COMPARTMENT_ID --query-text='(MemoryUtilization[1m]{resourceId = "'"$INSTANCE_TO_DELETE"'"}.mean())' | jq -r '.data[]."aggregated-datapoints"[].value' | awk '{ total += $0; count++ } END { print total/count }' | xargs printf "%.2f")
AVG_CPU=$(oci monitoring metric-data summarize-metrics-data --namespace oci_computeagent --compartment-id $COMPARTMENT_ID --query-text='(CPUUtilization[1m]{resourceId = "'"$INSTANCE_TO_DELETE"'"}.mean())' | jq -r '.data[]."aggregated-datapoints"[].value' | awk '{ total += $0; count++ } END { print total/count }' | xargs printf "%.2f")

$OCI_CLI_LOCATION compute instance terminate --region $REGION --instance-id $INSTANCE_TO_DELETE --force
$OCI_CLI_LOCATION compute-management instance-pool update --instance-pool-id $INSTANCE_POOL_ID --size $NEW_INSTANCE_POOL_SIZE
echo "$(pdate) -- Scaled in the cluster from $CURRENT_INSTANCE_POOL_SIZE nodes to $NEW_INSTANCE_POOL_SIZE nodes" >> $SCALING_IN_LOG
