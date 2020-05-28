#!/bin/bash

set -x

. /home/sgeadmin/ocisge/scripts/info.sh
. $SGE_ROOT/$CELL_NAME/common/settings.sh

NUMBER_OF_CORES_PER_SLAVE=$(echo "${SLAVE_SHAPE##*.}")
NUMBER_OF_TOTAL_CORES=$(qstat -g c | grep all.q | awk '{print $6}')
NUMBER_OF_USED_CORES=$(qstat -g c | grep all.q | awk '{print $3}')
RUNNING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "r") print $0 }' | wc -l)
PENDING_JOBS=$(qstat -u '*' | awk ' { if ($5 == "qw" || $5 == "hqw")  print $0 }' | wc -l)

CURRENT_UTILIZATION=$(echo "scale=2; 100 / $NUMBER_OF_TOTAL_CORES * $NUMBER_OF_USED_CORES" | bc)
DESIRED_UTILIZATION=10
UTILIZATION_RATIO=$(echo "$CURRENT_UTILIZATION > $DESIRED_UTILIZATION" | bc -q )

echo -e "\n$(date) -- Checking the cluster for autoscaling"
echo "$(date) -- Number of running jobs in the cluster: $RUNNING_JOBS"
echo "$(date) -- Number of pending jobs in the cluster: $PENDING_JOBS"
echo "$(date) -- Number of total cores in the cluster: $NUMBER_OF_TOTAL_CORES"
echo "$(date) -- Number of used cores in the cluster: $NUMBER_OF_USED_CORES"
echo "$(date) -- Current utilization of cores: $CURRENT_UTILIZATION%"

if [ $UTILIZATION_RATIO = 1 ]
then
    echo "$(date) -- ADDING A NODE: Current core utilization of $CURRENT_UTILIZATION% is higher than the desired core utilization of $DESIRED_UTILIZATION%"
    /home/sgeadmin/ocisge/scripts/add_exec_host.sh 1 >> /home/sgeadmin/ocisge/logs/autoscaling.log
elif [ "$PENDING_JOBS" -eq 0 ] && [ "$RUNNING_JOBS" -eq 0 ]
then
   echo "$(date) -- REMOVING A NODE: There are no running jobs or pending jobs in the cluster"
   /home/sgeadmin/ocisge/scripts/remove_exec_host.sh >> /home/sgeadmin/ocisge/logs/autoscaling.log
else
   echo "$(date) -- NOTHING TO DO: Current core utilization of $CURRENT_UTILIZATION% is within limits or there are running/pending in the cluster"
fi
