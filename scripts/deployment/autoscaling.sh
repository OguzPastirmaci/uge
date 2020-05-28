#!/bin/bash

set -x

. /home/sgeadmin/ocisge/scripts/info.sh
. $SGE_ROOT/$CELL_NAME/common/settings.sh

export CLUSTER_SCALING_FREQUENCY=300
export CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)

NUMBER_OF_CORES_PER_SLAVE=$(echo "${SLAVE_SHAPE##*.}")
NUMBER_OF_TOTAL_CORES=$(qstat -g c | grep all.q | awk '{print $6}')
NUMBER_OF_USED_CORES=$(qstat -g c | grep all.q | awk '{print $3}')
RUNNING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "r") print $0 }' | wc -l)
PENDING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "qw" || $5 == "hqw")  print $0 }' | wc -l)

CURRENT_UTILIZATION=$(echo "scale=2; 100 / $NUMBER_OF_TOTAL_CORES * $NUMBER_OF_USED_CORES" | bc -l)
DESIRED_UTILIZATION=50

echo "scale=2; 100 / $NUMBER_OF_TOTAL_CORES * $NUMBER_OF_USED_CORES" | bc -l

echo -e "\n$(date) Checking the cluster for autoscaling"
echo "$(date) Number of running jobs in the cluster: $RUNNING_JOBS"
echo "$(date) Number of pending jobs in the cluster: $PENDING_JOBS"
echo "$(date) Number of total cores in the cluster: $NUMBER_OF_TOTAL_CORES"
echo "$(date) Number of used cores in the cluster: $NUMBER_OF_USED_CORES"

if [ "$CURRENT_UTILIZATION" -gt "$DESIRED_RATIO" ]
then
    echo "SCALING: $NUMBER_OF_USED_CORES cores are being used out of $NUMBER_OF_TOTAL_CORES in the cluster, will try adding a new exec node"
    /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts/add-exec-host 1
elif [ "$PENDING_JOBS" -eq 0 ] && [ "$RUNNING_JOBS" -eq 0 ]
then
    echo "SCALING: $NUMBER_OF_USED_CORES cores are being used out of $NUMBER_OF_TOTAL_CORES in the cluster, will try removing an exec node"
    /home/sgeadmin/ocisge/$CLUSTER_POSTFIX/scripts/remove-exec-host
fi
