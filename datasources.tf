data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}

data "oci_core_instance_configuration" "test_instance_configuration_datasource" {
  instance_configuration_id = var.instance_configuration_id
}

data "oci_core_instance_configurations" "test_instance_configurations_datasource" {
  compartment_id = var.compartment_ocid

  filter {
    name   = "id"
    values = [var.instance_configuration_id]
  }
}

data "oci_core_instance_pool" "test_instance_pool_datasource" {
  instance_pool_id = oci_core_instance_pool.test_instance_pool.id
}

data "oci_core_instance_pools" "test_instance_pools_datasource" {
  compartment_id = var.compartment_ocid
  display_name   = "sge-slave-pool-${random_pet.server.id}"
  state          = "RUNNING"

  filter {
    name   = "id"
    values = [oci_core_instance_pool.test_instance_pool.id]
  }
}

data "oci_core_instance_pool_instances" "test_instance_pool_instances_datasource" {
  compartment_id   = var.compartment_ocid
  instance_pool_id = oci_core_instance_pool.test_instance_pool.id
  display_name     = "sge-slave-pool-${random_pet.server.id}"
}

