#!/bin/bash

. /home/sgeadmin/ocisge/<clusterpostfix>/scripts/info.sh
. $SGE_ROOT/$CELL_NAME/common/settings.sh

CURRENT_INSTANCE_POOL_SIZE=$($OCI_CLI_LOCATION compute-management instance-pool get --instance-pool-id $INSTANCE_POOL_ID --region $REGION --query 'data.size' --raw-output)
ADDED_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE + 1))
REMOVED_INSTANCE_POOL_SIZE=$((CURRENT_INSTANCE_POOL_SIZE - 1))

NUMBER_OF_CORES_PER_SLAVE=$(echo "${SLAVE_SHAPE##*.}")
NUMBER_OF_TOTAL_CORES=$(qstat -g c | grep all.q | awk '{print $6}')
NUMBER_OF_USED_CORES=$(qstat -g c | grep all.q | awk '{print $3}')
RUNNING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "r") print $0 }' | wc -l)
PENDING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "qw" || $5 == "hqw")  print $0 }' | wc -l)

CURRENT_UTILIZATION=$(echo "scale=2; 100 / $NUMBER_OF_TOTAL_CORES * $NUMBER_OF_USED_CORES" | bc)
TARGET_UTILIZATION=50
UTILIZATION_RATIO=$(echo "$CURRENT_UTILIZATION > $TARGET_UTILIZATION" | bc -q )
TIME_ELAPSED_SINCE_LAST_SCALING_OUT=$(echo $(expr $(date +%s) - $(stat $SCALING_OUT_LOG -c %Y)))
TIME_ELAPSED_SINCE_LAST_SCALING_IN=$(echo $(expr $(date +%s) - $(stat $SCALING_IN_LOG -c %Y)))

if [ $TIME_ELAPSED_SINCE_LAST_SCALING_OUT -ge $SCALING_OUT_COOLDOWN_IN_SECONDS ]
then
    SCALING_OUT_COOLDOWN=1
else
    SCALING_OUT_COOLDOWN=0
fi

if [ $TIME_ELAPSED_SINCE_LAST_SCALING_IN -ge $SCALING_IN_COOLDOWN_IN_SECONDS ]
then
    SCALING_IN_COOLDOWN=1
else
    SCALING_IN_COOLDOWN=0
fi

echo -e "\n$(pdate) -- Checking the cluster for autoscaling"
echo "$(pdate) -- Number of running jobs in the cluster: $RUNNING_JOBS"
echo "$(pdate) -- Number of pending jobs in the cluster: $PENDING_JOBS"
echo "$(pdate) -- Number of total cores in the cluster: $NUMBER_OF_TOTAL_CORES"
echo "$(pdate) -- Number of used cores in the cluster: $NUMBER_OF_USED_CORES"
echo "$(pdate) -- Current utilization of cores: $CURRENT_UTILIZATION%"
echo "$(pdate) -- Target utilization of cores: $TARGET_UTILIZATION%"
echo "$(pdate) -- Current number of EXEC nodes: $CURRENT_INSTANCE_POOL_SIZE"
echo "$(pdate) -- Minimum number of EXEC nodes allowed: $CLUSTER_MIN_SIZE"
echo "$(pdate) -- Maximum number of EXEC nodes allowed: $CLUSTER_MAX_SIZE"
echo "$(pdate) -- Cooldown between scale out operations: $SCALING_OUT_COOLDOWN_IN_SECONDS seconds"
echo "$(pdate) -- Cooldown between scale in operations: $SCALING_IN_COOLDOWN_IN_SECONDS seconds"
echo "$(pdate) -- Time elapsed since the last scale out: $TIME_ELAPSED_SINCE_LAST_SCALING_OUT seconds"
echo "$(pdate) -- Time elapsed since the last scale in: $TIME_ELAPSED_SINCE_LAST_SCALING_IN seconds"

if [ $UTILIZATION_RATIO = 1 ] && [ $SCALING_OUT_COOLDOWN = 1 ] && [ $ADDED_INSTANCE_POOL_SIZE -le $CLUSTER_MAX_SIZE ]
then
    echo "$(pdate) -- SCALING OUT: Current core utilization of $CURRENT_UTILIZATION% is higher than the target core utilization of $TARGET_UTILIZATION%"
    /home/sgeadmin/ocisge/<clusterpostfix>/scripts/add_exec_host.sh 2 >> /home/sgeadmin/ocisge/<clusterpostfix>/logs/autoscaling_detailed.log
elif [ $PENDING_JOBS -eq 0 ] && [ $RUNNING_JOBS -eq 0 ] && [ $SCALING_IN_COOLDOWN = 1 ] && [ $REMOVED_INSTANCE_POOL_SIZE -ge $CLUSTER_MIN_SIZE ]
then
   echo "$(pdate) -- SCALING IN: There are no running jobs or pending jobs in the cluster"
   /home/sgeadmin/ocisge/<clusterpostfix>/scripts/remove_exec_host.sh >> /home/sgeadmin/ocisge/<clusterpostfix>/logs/autoscaling_detailed.log
else
   echo "$(pdate) -- NOTHING TO DO: Scaling conditions did not happen"
fi
