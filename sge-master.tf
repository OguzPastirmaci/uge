resource "random_pet" "server" {
  length = 2
}

resource "oci_core_instance" "test_instance" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "sge-master-${random_pet.server.id}"
  shape               = var.master_shape

  create_vnic_details {
    subnet_id        = var.existing_subnet_id
    display_name     = "PrimaryVnic"
    assign_public_ip = true
    hostname_label   = "sge-master-${random_pet.server.id}"
  }

  source_details {
    source_type = "image"
    source_id   = var.master_image_id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("scripts/sge.sh", {
      instance_pool_id     = oci_core_instance_pool.test_instance_pool.id
      region               = var.region
      compartment_id       = var.compartment_ocid
      subnet_id            = var.existing_subnet_id
      ad                   = data.oci_identity_availability_domain.ad.name
      cluster_postfix      = random_pet.server.id
      sge_root             = var.sge_root
      cluster_initial_size = var.cluster_initial_size
      cluster_min_size     = var.cluster_min_size
      cluster_max_size     = var.cluster_max_size
    }))
  }
}

