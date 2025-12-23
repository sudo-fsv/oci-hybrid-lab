### VCN-A (VCN-A and LPG peering attachments)
resource "oci_core_vcn" "vcn_a" {
  compartment_id = var.compartment_id
  cidr_block     = "10.20.0.0/16"
  display_name   = "VCN-A"
  dns_label      = "vcna"
}

resource "oci_core_subnet" "vcn_a_public" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.vcn_a.id
  cidr_block         = "10.20.1.0/24"
  display_name       = "vcn-a-public-subnet"
  dns_label          = "vcna-pub"
  availability_domain = var.ad
  route_table_id     = oci_core_route_table.vcn_a_rt.id
}

# Private subnet for internal load balancer
resource "oci_core_subnet" "vcn_a_private" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.vcn_a.id
  cidr_block         = "10.20.2.0/24"
  display_name       = "vcn-a-private-subnet"
  dns_label          = "vcna-priv"
  availability_domain = var.ad
  route_table_id     = oci_core_route_table.vcn_a_rt.id
}

# Web backend instances (VCN-A)
resource "oci_core_instance" "vcn_a_web1" {
  compartment_id = var.compartment_id
  availability_domain = var.ad
  shape = var.shape
  display_name = "vcn-a-web1"

  create_vnic_details {
    subnet_id = oci_core_subnet.vcn_a_public.id
    assign_public_ip = true
    display_name = "vcn-a-web1-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_id
    kms_key_id  = var.kms_key_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/web_user_data.tpl", { TITLE = var.web_domains[0] }))
  }
}

resource "oci_core_instance" "vcn_a_web2" {
  compartment_id = var.compartment_id
  availability_domain = var.ad
  shape = var.shape
  display_name = "vcn-a-web2"

  create_vnic_details {
    subnet_id = oci_core_subnet.vcn_a_public.id
    assign_public_ip = true
    display_name = "vcn-a-web2-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_id
    kms_key_id  = var.kms_key_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/web_user_data.tpl", { TITLE = var.web_domains[1] }))
  }
}

# Load balancer for VCN-A (top-level LB plus separate backend set, backends and listener)
resource "oci_load_balancer_load_balancer" "vcn_a_lb" {
  compartment_id = var.compartment_id
  display_name   = "vcn-a-lb"
  shape          = var.lb_shape
  subnet_ids     = [oci_core_subnet.vcn_a_private.id]
  is_private     = true
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


### Local peering gateway and connections for VCN-A
resource "oci_core_local_peering_gateway" "vcn_a_lpg" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn_a.id
  display_name   = "vcn-a-lpg"
  peer_id = oci_core_local_peering_gateway.hub_lpg.id
}

resource "oci_core_route_table" "vcn_a_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn_a.id
  route_rules {
    destination = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_local_peering_gateway.vcn_a_lpg.id
    description = "Default route to Firewall Hub via LPG"
  }
}
