resource "oci_core_vcn" "onprem" {
  compartment_id = var.compartment_id
  cidr_block     = "172.16.0.0/16"
  display_name   = "VCN-OnPrem"
  dns_label      = "vcnonprem"
}

# On-prem/public subnet for CPE
resource "oci_core_subnet" "onprem_public" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.onprem.id
  cidr_block         = "172.16.0.0/26"
  display_name       = "onprem-public-subnet"
  dns_label          = "onprempub"
  availability_domain = var.ad
}

# Reserve a public IP for the Libreswan CPE. This IP can be associated with the instance's
# VNIC after the instance is created if you want traffic to reach the VM directly.
data "oci_core_private_ips" "libreswan_private_ip" {
  subnet_id  = oci_core_subnet.onprem_public.id
}

resource "oci_core_public_ip" "libreswan_reserved" {
  compartment_id = var.compartment_id
  display_name   = "libreswan-reserved-pip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.libreswan_private_ip.private_ips[0]["id"]
}

resource "oci_core_instance" "libreswan" {
  compartment_id = var.compartment_id
  availability_domain = var.ad
  shape = var.shape
  display_name = "libreswan-cpe"
  depends_on = [
    oci_load_balancer_load_balancer.vcn_a_lb,
    oci_core_ipsec.libreswan_to_hub
  ]
  create_vnic_details {
    display_name     = "libreswan-vnic"
    subnet_id        = oci_core_subnet.onprem_public.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.libreswan_nsg.id]
    private_ip       = data.oci_core_private_ips.libreswan_private_ip.private_ips[0]["id"]
  }
  source_details {
    source_type = "image"
    source_id   = var.libreswan_image_id
    kms_key_id  = var.kms_key_ocid
  }
  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/libreswan_user_data.tpl", {
      PSK = random_password.libreswan_psk.result,
      ONPREM_CIDR = var.onprem_cidr,
      PRIVATE_LB_IP = oci_load_balancer_load_balancer.vcn_a_lb.ip_address_details[0].ip_address,
      OCI_IPSEC_PEER = oci_core_public_ip.libreswan_reserved.ip_address,
      OCI_BGP_PEER_IP = var.oci_bgp_peer_ip,
      OCI_BGP_AS = var.oci_bgp_asn,
      CPE_BGP_AS = var.cpe_bgp_asn
    }))
  }
}

resource "oci_core_network_security_group" "libreswan_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.onprem.id
  display_name   = "libreswan-nsg"
}

# generate a strong pre-shared key for the IPSec connection (sensitive)
resource "random_password" "libreswan_psk" {
  length  = 32
  special = true
}

# OCI representation of the customer gateway (use the public IP of the libreswan instance)
resource "oci_core_cpe" "libreswan_cpe" {
  compartment_id = var.compartment_id
  display_name   = "libreswan-cpe"
  # use a reserved public IP to avoid a cyclic dependency between the instance and the CPE
  ip_address     = oci_core_public_ip.libreswan_reserved.ip_address
}

# IPSec connection from the hub DRG to the Libreswan CPE. This will be created once the
# libreswan instance public IP (used by the CPE) is available.
resource "oci_core_ipsec" "libreswan_to_hub" {
  compartment_id = var.compartment_id
  drg_id         = oci_core_drg.drg.id
  cpe_id         = oci_core_cpe.libreswan_cpe.id
  display_name   = "libreswan-to-firewall-hub"
  // Static routes are ignored when using BGP.
  static_routes  = [format("%s/32", oci_load_balancer_load_balancer.vcn_a_lb.ip_address_details[0].ip_address)]
}

# Manage tunnel-specific settings (IKE, BGP, shared secret) for the IPSec connection
resource "oci_core_ipsec_connection_tunnel_management" "libreswan_tunnel" {
  ipsec_id   = oci_core_ipsec.libreswan_to_hub.id
  tunnel_id  = 1
  ike_version = "V2"
  routing     = "BGP"
    bgp_session_info {
      customer_bgp_asn = var.cpe_bgp_asn
      oracle_bgp_asn   = var.oci_bgp_asn
      customer_interface_ip = var.cpe_bgp_peer_ip
      oracle_interface_ip = var.oci_bgp_peer_ip
    }
  shared_secret = random_password.libreswan_psk.result
}
