#!/bin/bash

set -x

mkdir -p /home/sgeadmin/ocisge/${cluster_postfix}/{scripts,logs}
chown -R sgeadmin /home/sgeadmin/ocisge/${cluster_postfix}

cat << 'EOF' > /home/sgeadmin/ocisge/${cluster_postfix}/scripts/info.sh
#!/bin/bash

pdate () {
    TZ=":US/Pacific" date
}

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
export CONFIG_FILE=/home/sgeadmin/${cluster_postfix}.conf
export SCALING_OUT_COOLDOWN_IN_SECONDS=300
export SCALING_IN_COOLDOWN_IN_SECONDS=720
export SCALING_OUT_LOG=/home/sgeadmin/ocisge/${cluster_postfix}/logs/scaling_out.log
export SCALING_IN_LOG=/home/sgeadmin/ocisge/${cluster_postfix}/logs/scaling_in.log
export COMPUTE_SHAPE=${sge_compute_instance_shape}
export CELL_NAME=${cluster_postfix}
EOF

cd /home/sgeadmin/ocisge/${cluster_postfix}/scripts

wget https://raw.githubusercontent.com/OguzPastirmaci/uge/master/scripts/deployment/add_exec_host.sh
wget https://raw.githubusercontent.com/OguzPastirmaci/uge/master/scripts/deployment/autoscaling.sh
wget https://raw.githubusercontent.com/OguzPastirmaci/uge/master/scripts/deployment/cluster_init_master.sh
wget https://raw.githubusercontent.com/OguzPastirmaci/uge/master/scripts/deployment/cluster_init_exec.sh
wget https://raw.githubusercontent.com/OguzPastirmaci/uge/master/scripts/deployment/remove_exec_host.sh


chmod +x *.sh
chown -R sgeadmin /home/sgeadmin/ocisge/${cluster_postfix}

sed -i "s/<clusterpostfix>/${cluster_postfix}/g" add_exec_host.sh
sed -i "s/<clusterpostfix>/${cluster_postfix}/g" autoscaling.sh
sed -i "s/<clusterpostfix>/${cluster_postfix}/g" cluster_init_master.sh
sed -i "s/<clusterpostfix>/${cluster_postfix}/g" cluster_init_exec.sh
sed -i "s/<clusterpostfix>/${cluster_postfix}/g" remove_exec_host.sh


/bin/su -c ". /home/sgeadmin/ocisge/${cluster_postfix}/scripts/info.sh" - sgeadmin
/bin/su -c "/home/sgeadmin/ocisge/${cluster_postfix}/scripts/cluster_init_master.sh >> /home/sgeadmin/ocisge/${cluster_postfix}/logs/cluster_init.log" - sgeadmin
/bin/su -c "/home/sgeadmin/ocisge/${cluster_postfix}/scripts/cluster_init_exec.sh >> /home/sgeadmin/ocisge/${cluster_postfix}/logs/cluster_init.log" - sgeadmin
#/bin/su -c "(crontab -u 2>/dev/null; echo "* * * * * /home/sgeadmin/ocisge/${cluster_postfix}/scripts/autoscaling.sh >> /home/sgeadmin/ocisge/${cluster_postfix}/logs/autoscaling.log") | crontab -" - sgeadmin
(crontab -u sgeadmin -l ; echo "* * * * * /home/sgeadmin/ocisge/${cluster_postfix}/scripts/autoscaling.sh >> /home/sgeadmin/ocisge/${cluster_postfix}/logs/autoscaling.log") | crontab -u sgeadmin -
