resource "oci_core_instance_pool" "test_instance_pool" {
  compartment_id            = var.compartment_ocid
  instance_configuration_id = var.slave_instance_configuration_id
  size                      = var.cluster_initial_size
  display_name              = "sge-slave-pool-${random_pet.server.id}"

  placement_configurations {
    availability_domain = data.oci_identity_availability_domain.ad.name
    primary_subnet_id   = var.existing_subnet_id
  }
}

