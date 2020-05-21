output "instance_public_ips" {
  value = [oci_core_instance.test_instance.*.public_ip]
}

