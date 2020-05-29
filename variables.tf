variable "tenancy_ocid" {}

variable "user_ocid" {}

variable "fingerprint" {}

variable "private_key_path" {}

variable "region" {}

variable "compartment_ocid" {}

variable "ssh_public_key" {}

variable "existing_subnet_id" {
  default = "ocid1.subnet.oc1.iad.aaaaaaaarzx2l2zhfcnnmxxtqawqpyfggj4vnnxh2roxb6ml3swkvef6245a"
}

variable "sge_master_node_image_id" {
  default = "ocid1.image.oc1.iad.aaaaaaaao5wye53xhp4vvan3nkpcltuvzj552ahqmtgkwuqcpyxc5jeifwta"
}

variable "sge_compute_node_instance_configuration_id" {
  default = "ocid1.instanceconfiguration.oc1.iad.aaaaaaaai5yzak4d2ui4owengzkaemgmwcaachdlanyhkkk7uk5c2ws4cqbq"
}

variable "master_node_shape" {
  default = "VM.Standard2.8"
}

variable "sge_root" {
  default = "/tools/gridengine/uge"
}

# Settings for SGE cluster size
variable "cluster_initial_size" {
  default = 1
}

variable "cluster_min_size" {
  default = 1
}

variable "cluster_max_size" {
  default = 6
}

# Using local NVME for spooling
variable "execd_spool_dir_local" {
  default = "/nvme/sge/spool"
}

variable "sge_admin" {
  default = "sgeadmin"
}
