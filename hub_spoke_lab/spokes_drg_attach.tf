### VCN-B and VCN-C (DRG attachments)
resource "oci_core_vcn" "vcn_b" {
  compartment_id = var.compartment_id
  cidr_block     = "10.30.0.0/16"
  display_name   = "VCN-B"
}

resource "oci_core_subnet" "vcn_b_public" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.vcn_b.id
  cidr_block         = "10.30.1.0/24"
  display_name       = "vcn-b-public-subnet"
  route_table_id     = oci_core_route_table.vcn_b_rt.id
}

resource "oci_core_instance" "vcn_b_workload" {
  compartment_id = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[local.ad_index].name
  shape = var.shape
  display_name = "vcn-b-workload"

  shape_config {
    ocpus = 8
    memory_in_gbs = 16
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.vcn_b_public.id
    assign_public_ip = true
    display_name = "vcn-b-workload-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_id
    kms_key_id  = var.kms_key_ocid != "" ? var.kms_key_ocid : null
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key)
    user_data = base64encode(templatefile("${path.module}/scripts/web_user_data.tpl", { TITLE = "vcn-b-workload", LB_PRIV_SUBNET_CIDR = oci_core_subnet.vcn_a_private.cidr_block, ONPREM_CIDR = var.onprem_cidr }))
  }
}

resource "oci_core_vcn" "vcn_c" {
  compartment_id = var.compartment_id
  cidr_block     = "10.40.0.0/16"
  display_name   = "VCN-C"
}

resource "oci_core_subnet" "vcn_c_public" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.vcn_c.id
  cidr_block         = "10.40.1.0/24"
  display_name       = "vcn-c-public-subnet"
  route_table_id     = oci_core_route_table.vcn_c_rt.id
}

resource "oci_core_instance" "vcn_c_workload" {
  compartment_id = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[local.ad_index].name
  shape = var.shape
  display_name = "vcn-c-workload"

  shape_config {
    ocpus = 8
    memory_in_gbs = 16
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.vcn_c_public.id
    assign_public_ip = true
    display_name = "vcn-c-workload-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_id
    kms_key_id  = var.kms_key_ocid != "" ? var.kms_key_ocid : null
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key)
    user_data = base64encode(templatefile("${path.module}/scripts/web_user_data.tpl", { TITLE = "vcn-c-workload", LB_PRIV_SUBNET_CIDR = oci_core_subnet.vcn_a_private.cidr_block, ONPREM_CIDR = var.onprem_cidr}))
  }
}

# Attach VCN-B to the transit DRG
resource "oci_core_drg_attachment" "vcn_b_drg_attach" {
  drg_id         = oci_core_drg.drg.id
  vcn_id         = oci_core_vcn.vcn_b.id
}

# Attach VCN-C to the transit DRG
resource "oci_core_drg_attachment" "vcn_c_drg_attach" {
  drg_id         = oci_core_drg.drg.id
  vcn_id         = oci_core_vcn.vcn_c.id
}

resource "oci_core_route_table" "vcn_b_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn_b.id
  route_rules {
    destination = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.drg.id
    description = "Default route to Firewall Hub via DRG"
  }
}

resource "oci_core_route_table" "vcn_c_rt" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.vcn_c.id
  route_rules {
    destination = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    network_entity_id = oci_core_drg.drg.id
    description = "Default route to Firewall Hub via DRG"
  }
}
