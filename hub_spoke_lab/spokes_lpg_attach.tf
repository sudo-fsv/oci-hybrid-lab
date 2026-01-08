### VCN-A (VCN-A and LPG peering attachments)
resource "oci_core_vcn" "vcn_a" {
  compartment_id = var.compartment_id
  cidr_block     = "10.20.0.0/16"
  display_name   = "VCN-A"
}

resource "oci_core_subnet" "vcn_a_public" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.vcn_a.id
  cidr_block         = "10.20.1.0/24"
  display_name       = "vcn-a-public-subnet"
  route_table_id     = oci_core_route_table.vcn_a_rt.id
}

# Private subnet for internal load balancer
resource "oci_core_subnet" "vcn_a_private" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.vcn_a.id
  cidr_block         = "10.20.2.0/24"
  display_name       = "vcn-a-private-subnet"
  route_table_id     = oci_core_route_table.vcn_a_rt.id
}

# Web backend instances (VCN-A)
resource "oci_core_instance" "vcn_a_web1" {
  compartment_id = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[local.ad_index].name
  shape = var.shape
  display_name = "vcn-a-web1"

  shape_config {
    ocpus = 8
    memory_in_gbs = 16
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.vcn_a_public.id
    assign_public_ip = true
    display_name = "vcn-a-web1-vnic"
    nsg_ids = [oci_core_network_security_group.webserver_nsg.id]
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_id
    kms_key_id  = var.kms_key_ocid != "" ? var.kms_key_ocid : null
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key)
    user_data = base64encode(templatefile("${path.module}/scripts/web_user_data.tpl", { TITLE = var.web_domains[0], LB_PRIV_SUBNET_CIDR = oci_core_subnet.vcn_a_private.cidr_block, ONPREM_CIDR = var.onprem_cidr }))
  }
}

resource "oci_core_instance" "vcn_a_web2" {
  compartment_id = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[local.ad_index].name
  shape = var.shape
  display_name = "vcn-a-web2"

  shape_config {
    ocpus = 8
    memory_in_gbs = 16
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.vcn_a_public.id
    assign_public_ip = true
    display_name = "vcn-a-web2-vnic"
    nsg_ids = [oci_core_network_security_group.webserver_nsg.id]
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_id
    kms_key_id  = var.kms_key_ocid != "" ? var.kms_key_ocid : null
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key)
    user_data = base64encode(templatefile("${path.module}/scripts/web_user_data.tpl", { TITLE = var.web_domains[1], LB_PRIV_SUBNET_CIDR = oci_core_subnet.vcn_a_private.cidr_block, ONPREM_CIDR = var.onprem_cidr }))
  }
}

# Load balancer for VCN-A (top-level LB plus separate backend set, backends and listener)
resource "oci_load_balancer_load_balancer" "vcn_a_lb" {
  compartment_id = var.compartment_id
  display_name   = "vcn-a-lb"
  shape          = var.lb_shape
  subnet_ids     = [oci_core_subnet.vcn_a_private.id]
  is_private     = true
  network_security_group_ids = [oci_core_network_security_group.webserver_nsg.id]
}

resource "oci_load_balancer_backend_set" "web_backend_set" {
  load_balancer_id = oci_load_balancer_load_balancer.vcn_a_lb.id
  name             = "web-backend-set"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol = "HTTP"
    url_path = "/"
    port     = 80
  }
}

resource "oci_load_balancer_backend" "web1" {
  load_balancer_id  = oci_load_balancer_load_balancer.vcn_a_lb.id
  backendset_name   = oci_load_balancer_backend_set.web_backend_set.name
  ip_address        = oci_core_instance.vcn_a_web1.create_vnic_details[0].private_ip
  port              = 80
  weight            = 1
}

resource "oci_load_balancer_backend" "web2" {
  load_balancer_id  = oci_load_balancer_load_balancer.vcn_a_lb.id
  backendset_name   = oci_load_balancer_backend_set.web_backend_set.name
  ip_address        = oci_core_instance.vcn_a_web2.create_vnic_details[0].private_ip
  port              = 80
  weight            = 1
}

resource "oci_load_balancer_listener" "listener_80" {
  load_balancer_id         = oci_load_balancer_load_balancer.vcn_a_lb.id
  name                    = "listener-80"
  default_backend_set_name = oci_load_balancer_backend_set.web_backend_set.name
  protocol                = "HTTP"
  port                    = 80
}


# ### Local peering gateway and connections for VCN-A
# resource "oci_core_local_peering_gateway" "vcn_a_lpg" {
#   compartment_id = var.compartment_id
#   vcn_id         = oci_core_vcn.vcn_a.id
#   display_name   = "vcn-a-lpg"
#   peer_id = oci_core_local_peering_gateway.hub_lpg.id
# }

### Optional DRG attachment for VCN-A
resource "oci_core_drg_attachment" "vcn_a_drg_attach" {
  drg_id         = oci_core_drg.drg.id
  vcn_id         = oci_core_vcn.vcn_a.id
  # Export the directly-attached VCN prefixes to the DRG's default export distribution
  export_drg_route_distribution_id = oci_core_drg.drg.default_export_drg_route_distribution_id
}


resource "oci_core_route_table" "vcn_a_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn_a.id
  # route_rules {
  #   destination = "0.0.0.0/0"
  #   destination_type = "CIDR_BLOCK"
  #   network_entity_id = oci_core_local_peering_gateway.vcn_a_lpg.id
  #   description = "Default route to Firewall Hub via LPG"
  # }
  
  # Optional route to transit DRG if VCN-A is attached to DRG
  route_rules {
    destination      = var.onprem_cidr
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.drg.id
    description = "Default route to transit DRG"
  }
  
  route_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.webserver_igw.id
    description      = "Default route to Internet"
  }

  route_rules {
    destination      = "${trimspace(data.http.my_ip.response_body)}/32"
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.webserver_igw.id
    description      = "Route to management public IP via IGW"
  }
}

resource "oci_core_network_security_group" "webserver_nsg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn_a.id
  display_name   = "webserver-nsg"
}

resource "oci_core_network_security_group_security_rule" "web_myip" {
  network_security_group_id = oci_core_network_security_group.webserver_nsg.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = "${trimspace(data.http.my_ip.response_body)}/32"
}

resource "oci_core_network_security_group_security_rule" "onprem_myip" {
  network_security_group_id = oci_core_network_security_group.webserver_nsg.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = var.onprem_cidr
}

# Allow load balancer health checks (HTTP/80) from the internal load balancer IP
resource "oci_core_network_security_group_security_rule" "web_lb_health_check" {
  network_security_group_id = oci_core_network_security_group.webserver_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_subnet.vcn_a_private.cidr_block
  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
  description = "Allow load balancer health checks (TCP/80)"
}

resource "oci_core_network_security_group_security_rule" "web_internet" {
  network_security_group_id = oci_core_network_security_group.webserver_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
}

# Internet gateway for the webserver to install packages only
resource "oci_core_internet_gateway" "webserver_igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn_a.id
  display_name   = "webserver-igw"
  enabled        = true
}
