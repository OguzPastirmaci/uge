variable "tenancy_ocid" {
}

variable "user_ocid" {
}

variable "fingerprint" {
}

variable "private_key_path" {
}

variable "region" {
}

variable "compartment_ocid" {
}

variable "ssh_public_key" {
}

variable "existing_subnet_id" {
  default = "ocid1.subnet.oc1.phx.aaaaaaaa4wwwywyhm44yvufqc4kswizr4cdz4vsik5upykrk5x544f3xplwq"
}

variable "master_image_id" {
  default = "ocid1.image.oc1.phx.aaaaaaaal6eih7io4zpx3nvypyhcgnv64nfeilkdinbz27lyt4co3hkdv5wa"
}

variable "slave_instance_configuration_id" {
  default = "ocid1.instanceconfiguration.oc1.phx.aaaaaaaa7nd25jujx3cbhoal2awxzez6tnp3z7a4ffryw5vfp6two4nke5ua"
}

variable "master_shape" {
  default = "VM.Standard2.4"
}

variable "instance_configuration_id" {
  default = "ocid1.instanceconfiguration.oc1.phx.aaaaaaaa7nd25jujx3cbhoal2awxzez6tnp3z7a4ffryw5vfp6two4nke5ua"
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

