#!/bin/bash

# Use instance principals for OCI CLI authentication
export OCI_CLI_LOCATION=/home/sgeadmin/bin/oci
#export OCI_CLI_AUTH=instance_principal
export SGE_ADMIN=sgeadmin

# Cluster info populated by Terraform
export COMPARTMENT_ID=${compartment_id}
export SUBNET_ID=${subnet_id}
export REGION=${region}
export INSTANCE_POOL_ID=${instance_pool_id}
export CLUSTER_POSTFIX=${cluster_postfix}
export CLUSTER_INITIAL_SIZE=${cluster_initial_size}
export CLUSTER_MIN_SIZE=${cluster_min_size}
export CLUSTER_MAX_SIZE=${cluster_max_size}
export LOCAL_SPOOL_DIR=${execd_spool_dir_local}
export SGE_ROOT=${sge_root}
export CONFIG_FILE=/home/sgeadmin/uge_configuration.conf
export SCALING_COOLDOWN_IN_SECONDS=300
export SCALING_LOG=/home/sgeadmin/ocisge/logs/scaling_history.log
export COMPUTE_SHAPE=${sge_compute_instance_shape}
