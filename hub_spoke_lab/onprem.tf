resource "oci_core_vcn" "onprem" {
  compartment_id = var.compartment_id
  cidr_block     = "172.16.0.0/16"
  display_name   = "VCN-OnPrem"
}

# On-prem/public subnet for CPE
resource "oci_core_subnet" "onprem_public" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.onprem.id
  cidr_block         = "172.16.0.0/26"
  display_name       = "onprem-public-subnet"
  route_table_id     = oci_core_route_table.libreswan_cpe_rt.id
}

# Reserve a public IP for the Libreswan CPE. This IP can be associated with the instance's
# VNIC after the instance is created if you want traffic to reach the VM directly.
resource "oci_core_public_ip" "libreswan_reserved_ip" {
  compartment_id = var.compartment_id
  lifetime       = "RESERVED"
  display_name   = "libreswan-reserved-pip" 
  lifecycle {
    ignore_changes = [ private_ip_id ] # allow reassignment of the public IP without recreating the resource
  }
}

/* Replaced subnet-level security list with network security group rules attached
   to the Libreswan instance's NSG. The instance's `create_vnic_details.nsg_ids`
   already references `oci_core_network_security_group.libreswan_nsg`. */

resource "oci_core_network_security_group_security_rule" "libreswan_ingress_myip" {
  network_security_group_id = oci_core_network_security_group.libreswan_nsg.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = "${trimspace(data.http.my_ip.response_body)}/32"
}

resource "oci_core_network_security_group_security_rule" "libreswan_egress_internet" {
  network_security_group_id = oci_core_network_security_group.libreswan_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
}

resource "oci_core_network_security_group_security_rule" "libreswan_ingress_ipsec_peer1_udp500" {
  network_security_group_id = oci_core_network_security_group.libreswan_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "${local.libreswan_peer_1}/32"
  udp_options {
    destination_port_range {
      min = 500
      max = 500
    }
  }
  description = "Allow IKE (UDP/500) from OCI IPSEC peer 1"
}

resource "oci_core_network_security_group_security_rule" "libreswan_ingress_ipsec_peer1_udp4500" {
  network_security_group_id = oci_core_network_security_group.libreswan_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "${local.libreswan_peer_1}/32"
  udp_options {
    destination_port_range {
      min = 4500
      max = 4500
    }
  }
  description = "Allow NAT-T (UDP/4500) from OCI IPSEC peer 1"
}

resource "oci_core_network_security_group_security_rule" "libreswan_ingress_ipsec_peer2_udp500" {
  network_security_group_id = oci_core_network_security_group.libreswan_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "${local.libreswan_peer_2}/32"
  udp_options {
    destination_port_range {
      min = 500
      max = 500
    }
  }
  description = "Allow IKE (UDP/500) from OCI IPSEC peer 2"
}

resource "oci_core_network_security_group_security_rule" "libreswan_ingress_ipsec_peer2_udp4500" {
  network_security_group_id = oci_core_network_security_group.libreswan_nsg.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "${local.libreswan_peer_2}/32"
  udp_options {
    destination_port_range {
      min = 4500
      max = 4500
    }
  }
  description = "Allow NAT-T (UDP/4500) from OCI IPSEC peer 2"
}

# Pre-configure the DRG VPN with the reserved public IP, so we can bootstrap Libreswan
# generate a strong pre-shared key for the IPSec connection (sensitive)
resource "random_password" "libreswan_psk_1" {
  length  = 32
  special = false
}

resource "random_password" "libreswan_psk_2" {
  length  = 32
  special = false
}

# OCI representation of the customer gateway (use the public IP of the libreswan instance)
resource "oci_core_cpe" "libreswan_cpe" {
  compartment_id = var.compartment_id
  display_name   = "libreswan-cpe"
  ip_address     = oci_core_public_ip.libreswan_reserved_ip.ip_address
}

# IPSec connection from the hub DRG to the Libreswan CPE. This will be created once the
# libreswan instance public IP (used by the CPE) is available.
resource "oci_core_ipsec" "libreswan_to_hub" {
  compartment_id = var.compartment_id
  drg_id         = oci_core_drg.drg.id
  cpe_id         = oci_core_cpe.libreswan_cpe.id
  display_name   = "libreswan-to-firewall-hub"
  // Static routes are ignored when using BGP.
  static_routes  = [var.onprem_cidr]
}

# Manage tunnel-specific settings (IKE, BGP, shared secret) for the IPSec connection
data "oci_core_ipsec_connection_tunnels" "libreswan_tunnel" {
  ipsec_id   = oci_core_ipsec.libreswan_to_hub.id
}

locals {
  # Map of tunnel id -> tunnel object for tunnels that expose a vpn_ip
  libreswan_tunnels_map = { for t in data.oci_core_ipsec_connection_tunnels.libreswan_tunnel.ip_sec_connection_tunnels : t.id => t if lookup(t, "vpn_ip", "") != "" }
  libreswan_tunnel_ips = [for t in values(local.libreswan_tunnels_map) : t.vpn_ip]
  libreswan_peer_1 = length(local.libreswan_tunnel_ips) > 0 ? local.libreswan_tunnel_ips[0] : ""
  libreswan_peer_2 = length(local.libreswan_tunnel_ips) > 1 ? local.libreswan_tunnel_ips[1] : ""
}

# Internet gateway for the Libreswan VCN (onprem)
resource "oci_core_internet_gateway" "libreswan_igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.onprem.id
  display_name   = "libreswan-igw"
  enabled        = true
}

# Use the provider data to iterate tunnels, but fetch the tunnel vpn-ip via OCI CLI per tunnel
## Route table for the Libreswan CPE subnet: create /32 routes to each DRG tunnel VPN IP via the IGW
resource "oci_core_route_table" "libreswan_cpe_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.onprem.id

  route_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.libreswan_igw.id
    description      = "Default route to Internet"
  }

  route_rules {
    destination      = "${trimspace(data.http.my_ip.response_body)}/32"
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.libreswan_igw.id
    description      = "Route to management public IP via IGW"
  }

  dynamic "route_rules" {
    for_each = local.libreswan_tunnels_map
    content {
      destination      = format("%s/32", route_rules.value.vpn_ip)
      destination_type = "CIDR_BLOCK"
      network_entity_id = oci_core_internet_gateway.libreswan_igw.id
      description      = "Route to DRG tunnel VPN IP via IGW"
    }
  }
}
resource "oci_core_ipsec_connection_tunnel_management" "libreswan_tunnel_1" {
  ipsec_id   = oci_core_ipsec.libreswan_to_hub.id
  tunnel_id  = data.oci_core_ipsec_connection_tunnels.libreswan_tunnel.ip_sec_connection_tunnels[0].id
  ike_version = "V2"
  routing     = "BGP"
    bgp_session_info {
      customer_bgp_asn = var.cpe_bgp_asn
      customer_interface_ip = var.cpe_bgp_peer_ip_1
      oracle_interface_ip = var.oci_bgp_peer_ip_1
    }
  shared_secret = random_password.libreswan_psk_1.result
}

# Secondary tunnel management for tunnel 2
resource "oci_core_ipsec_connection_tunnel_management" "libreswan_tunnel_2" {
  ipsec_id   = oci_core_ipsec.libreswan_to_hub.id
  tunnel_id  = data.oci_core_ipsec_connection_tunnels.libreswan_tunnel.ip_sec_connection_tunnels[1].id
  ike_version = "V2"
  routing     = "BGP"
    bgp_session_info {
      customer_bgp_asn = var.cpe_bgp_asn
      customer_interface_ip = var.cpe_bgp_peer_ip_2
      oracle_interface_ip = var.oci_bgp_peer_ip_2
    }
  shared_secret = random_password.libreswan_psk_2.result
}

# Bootstrap Libreswan instance as CPE
resource "oci_core_network_security_group" "libreswan_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.onprem.id
  display_name   = "libreswan-nsg"
}

resource "oci_core_instance" "libreswan" {
  compartment_id = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[local.ad_index].name
  shape = var.shape
  display_name = "libreswan-cpe"
  
  depends_on = [ 
    oci_core_ipsec_connection_tunnel_management.libreswan_tunnel_1,
    oci_core_ipsec_connection_tunnel_management.libreswan_tunnel_2,
    oci_core_route_table.libreswan_cpe_rt,
    oci_core_network_security_group_security_rule.libreswan_ingress_myip,
    oci_core_network_security_group_security_rule.libreswan_egress_internet
  ]

  shape_config {
    ocpus = 8
    memory_in_gbs = 16
  }

  create_vnic_details {
    display_name     = "libreswan-vnic"
    subnet_id        = oci_core_subnet.onprem_public.id
    assign_public_ip = false
    nsg_ids          = [oci_core_network_security_group.libreswan_nsg.id]
    private_ip       = var.libreswan_vm_private_ip
  }

  source_details {
    source_type = "image"
    source_id   = var.libreswan_image_id
    kms_key_id  = var.kms_key_ocid != "" ? var.kms_key_ocid : null
  }
  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key)
    user_data = base64encode(templatefile("${path.module}/scripts/libreswan_user_data.tpl", {
      PSK_1 = random_password.libreswan_psk_1.result,
      PSK_2 = random_password.libreswan_psk_2.result,
      ONPREM_CIDR = cidrsubnet(var.onprem_cidr, 10, 0),
      OCI_IPSEC_PEER_1 = local.libreswan_peer_1,
      OCI_IPSEC_PEER_2 = local.libreswan_peer_2,
      OCI_BGP_PEER_IP_1 = split("/",var.oci_bgp_peer_ip_1)[0],
      OCI_BGP_PEER_IP_2 = split("/",var.oci_bgp_peer_ip_2)[0],
      OCI_BGP_AS = oci_core_ipsec_connection_tunnel_management.libreswan_tunnel_1.bgp_session_info[0].oracle_bgp_asn,
      CPE_BGP_AS = var.cpe_bgp_asn,
      CPE_BGP_PEER_IP_1 = var.cpe_bgp_peer_ip_1,
      CPE_BGP_PEER_IP_2 = var.cpe_bgp_peer_ip_2,
      LIBRESWAN_PRIVATE_IP = var.libreswan_vm_private_ip,
      LIBRESWAN_RESERVED_PUBLIC_IP = oci_core_public_ip.libreswan_reserved_ip.ip_address
    }))
  }
}

resource "null_resource" "libreswan_ip_association" {
  # Trigger when instance, subnet or reserved public ip change
  triggers = {
    instance_id   = oci_core_instance.libreswan.id
    subnet_id     = oci_core_subnet.onprem_public.id
    public_ip_id  = oci_core_public_ip.libreswan_reserved_ip.id
  }

  provisioner "local-exec" {
    # Lookup the private IP by address and associate the reserved public IP to it
    command = <<-EOT
      set -euo pipefail
      echo "Looking up private IP in subnet ${oci_core_subnet.onprem_public.id} for static address ${var.libreswan_vm_private_ip}"
        private_id=$(oci network private-ip list --subnet-id ${oci_core_subnet.onprem_public.id} --all --query 'data[0].id' --raw-output --profile ${var.oci_cli_profile} --auth security_token)
      if [ -z "$private_id" ] || [ "$private_id" = "null" ]; then
        echo "ERROR: private IP ${var.libreswan_vm_private_ip} not found in subnet ${oci_core_subnet.onprem_public.id}" >&2
        exit 1
      fi
      echo "Associating public ip ${oci_core_public_ip.libreswan_reserved_ip.id} -> private ip $private_id"
        oci network public-ip update --public-ip-id ${oci_core_public_ip.libreswan_reserved_ip.id} --private-ip-id "$private_id" --wait-for-state ASSIGNED --profile ${var.oci_cli_profile} --auth security_token
      echo '{"status":"ok"}'
    EOT
  }
}
