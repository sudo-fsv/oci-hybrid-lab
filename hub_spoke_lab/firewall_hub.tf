### Hub and firewall resources
resource "oci_core_vcn" "firewall_hub" {
  compartment_id = var.compartment_id
  cidr_block     = "10.10.1.0/16"
  display_name   = "Firewall-Hub"
  dns_label      = "firewallhub"
}

# Hub public subnet
resource "oci_core_subnet" "hub_wan" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.firewall_hub.id
  cidr_block         = "10.10.1.0/24"
  display_name       = "hub-wan-subnet"
  dns_label          = "hubwan"
  availability_domain = var.ad
  route_table_id     = oci_core_route_table.hub_rt.id
}

resource "oci_core_internet_gateway" "hub_igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.firewall_hub.id
  display_name   = "hub-igw"
  enabled     = true
}

# Hub trust/LAN subnet for firewall LAN interfaces
resource "oci_core_subnet" "hub_trust" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.firewall_hub.id
  cidr_block         = "10.10.2.0/24"
  display_name       = "hub-trust-subnet"
  dns_label          = "hubtrust"
  availability_domain = var.ad
  route_table_id     = oci_core_route_table.hub_trust_rt.id
}

# Hub route table: Internet + placeholders for spoke peering routes
resource "oci_core_route_table" "hub_rt" {
  # WAN route table for firewall WAN interface - has Internet route
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.firewall_hub.id

  route_rules {
    destination        = "0.0.0.0/0"
    destination_type   = "CIDR_BLOCK"
    network_entity_id  = oci_core_internet_gateway.hub_igw.id
    description        = "Internet"
  }
}

# Trust route table for firewall LAN/trust interfaces: routes back to spokes via LPG/DRG
resource "oci_core_route_table" "hub_trust_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.firewall_hub.id

  route_rules {
    destination = "10.20.0.0/16" # VCN-A
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_local_peering_gateway.hub_lpg.id
    description = "Route to VCN-A via Hub LPG"
  }

  route_rules {
    destination = "10.30.0.0/16" # VCN-B
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.drg.id
    description = "Route to VCN-B via DRG"
  }

  route_rules {
    destination = "10.40.0.0/16" # VCN-C
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.drg.id
    description = "Route to VCN-C via DRG"
  }
}

resource "oci_core_security_list" "hub_sec" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.firewall_hub.id
  display_name   = "hub-security-list"
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options { 
      min = 22 
      max = 22 
      }
  }
  egress_security_rules {
    protocol = "all"
    destination = "0.0.0.0/0"
  }
}

# Transit DRG used by the hub (kept as in original layout)
resource "oci_core_drg" "drg" {
  compartment_id = var.compartment_id
  display_name   = "transit-drg"
}

resource "oci_core_drg_attachment" "hub_drg_attach" {
  drg_id         = oci_core_drg.drg.id
  vcn_id         = oci_core_vcn.firewall_hub.id
}

### Firewall (pfsense) and remote CPE (libreswan)
### pfSense HA pair (CARP)
resource "oci_core_image" "pfsense_custom" {
  compartment_id = var.compartment_id
  display_name   = "pfsense-custom"

  image_source_details {
    source_type = "objectStorageUri"
    source_uri = var.pfsense_image_source_uri
    operating_system = "FreeBSD"
  }
}

resource "oci_core_instance" "pfsense_a" {
  compartment_id = var.compartment_id
  availability_domain = var.ad
  shape = var.shape
  display_name = "pfsense-a"

  # WAN vNIC
  # create_vnic_details {
  #   subnet_id = oci_core_subnet.hub_wan.id
  #   assign_public_ip = true
  #   display_name = "pfsense-a-wan"
  # }

  # TRUST/LAN vNIC
  create_vnic_details {
    subnet_id = oci_core_subnet.hub_trust.id
    assign_public_ip = false
    display_name = "pfsense-a-trust"
  }

  source_details {
    source_type = "image"
    source_id   = oci_core_image.pfsense_custom.id
    kms_key_id  = var.kms_key_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/pfsense_user_data.tpl", {
      PFSENSE_ADMIN_PASSWORD = var.pfsense_admin_password,
      CARP_PASSWORD = var.carp_password,
      WAN_IF = "vtnet0",
      TRUST_IF = "vtnet1",
      WAN_VIP = "10.10.1.10",
      TRUST_VIP = "10.10.2.10",
      VHID = "1",
      ADV_SKEW = "0",
      TRUST_PREFIXES = "10.20.0.0/16 10.30.0.0/16 10.40.0.0/16"
    }))
  }
}

resource "oci_core_instance" "pfsense_b" {
  compartment_id = var.compartment_id
  availability_domain = var.ad
  shape = var.shape
  display_name = "pfsense-b"

  # create_vnic_details {
  #   subnet_id = oci_core_subnet.hub_wan.id
  #   assign_public_ip = true
  #   display_name = "pfsense-b-wan"
  # }

  create_vnic_details {
    subnet_id = oci_core_subnet.hub_trust.id
    assign_public_ip = false
    display_name = "pfsense-b-trust"
  }

  source_details {
    source_type = "image"
    source_id   = oci_core_image.pfsense_custom.id
    kms_key_id  = var.kms_key_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/pfsense_user_data.tpl", {
      PFSENSE_ADMIN_PASSWORD = var.pfsense_admin_password,
      CARP_PASSWORD = var.carp_password,
      WAN_IF = "vtnet0",
      TRUST_IF = "vtnet1",
      WAN_VIP = "10.10.1.10",
      TRUST_VIP = "10.10.2.10",
      VHID = "1",
      ADV_SKEW = "0",
      TRUST_PREFIXES = "10.20.0.0/16 10.30.0.0/16 10.40.0.0/16"
    }))
  }
}

# Local Peering Gateway on the Firewall Hub VCN (used for VCN-A local peering)
resource "oci_core_local_peering_gateway" "hub_lpg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.firewall_hub.id
  display_name   = "firewall-hub-lpg"
}
