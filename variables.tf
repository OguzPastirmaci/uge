variable "tenancy_ocid" {}

variable "user_ocid" {}

variable "fingerprint" {}

variable "private_key_path" {}

variable "region" {}

variable "compartment_ocid" {}

variable "ssh_public_key" {}

variable "existing_subnet_id" {
  default = "ocid1.subnet.oc1.phx.aaaaaaaa4wwwywyhm44yvufqc4kswizr4cdz4vsik5upykrk5x544f3xplwq"
}

variable "sge_master_node_image_id" {
  default = "ocid1.image.oc1.phx.aaaaaaaal6eih7io4zpx3nvypyhcgnv64nfeilkdinbz27lyt4co3hkdv5wa"
}

variable "sge_compute_node_instance_configuration_id" {
  default = "ocid1.instanceconfiguration.oc1.phx.aaaaaaaabqtvbrhbnbd4qdxqpfofaqvjl5mlitjgesmjdsccg5mihje32d4q"
}

variable "master_node_shape" {
  default = "VM.Standard2.8"
}

variable "sge_root" {
  default = "/nfs/sge"
}

# Settings for SGE cluster size
variable "cluster_initial_size" {
  default = 2
}

variable "cluster_min_size" {
  default = 1
}

variable "cluster_max_size" {
  default = 3
}

# Using local NVME for spooling
variable "execd_spool_dir_local" {
  default = "/nvme/sge/spool"
}

variable "sge_admin" {
  default = "opc"
}
