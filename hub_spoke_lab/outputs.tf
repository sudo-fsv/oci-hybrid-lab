output "libreswan_public_ip" {
  value = oci_core_public_ip.libreswan_reserved_ip.ip_address
}

# output "pfsense_a_public_ip" {
#   value = oci_core_instance.pfsense_a.public_ip
# }

# output "pfsense_b_public_ip" {
#   value = oci_core_instance.pfsense_b.public_ip
# }

output "vcn_a_web1_public_ip" {
  value = oci_core_instance.vcn_a_web1.public_ip
}

output "vcn_a_web2_public_ip" {
  value = oci_core_instance.vcn_a_web2.public_ip
}

output "vcn_a_lb_private_ip" {
  value = oci_load_balancer_load_balancer.vcn_a_lb.ip_address_details[0].ip_address
}
