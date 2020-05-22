output "instance_public_ips" {
  value = [oci_core_instance.sge_master.*.public_ip]
}

