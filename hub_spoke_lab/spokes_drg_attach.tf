### VCN-B and VCN-C (DRG attachments)
resource "oci_core_vcn" "vcn_b" {
  compartment_id = var.compartment_id
  cidr_block     = "10.30.0.0/16"
  display_name   = "VCN-B"
  dns_label      = "vcnb"
}

resource "oci_core_subnet" "vcn_b_public" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.vcn_b.id
  cidr_block         = "10.30.1.0/24"
  display_name       = "vcn-b-public-subnet"
  dns_label          = "vcnb-pub"
  availability_domain = var.ad
  route_table_id     = oci_core_route_table.vcn_b_rt.id
}

resource "oci_core_instance" "vcn_b_workload" {
  compartment_id = var.compartment_id
  availability_domain = var.ad
  shape = var.shape
  display_name = "vcn-b-workload"

  create_vnic_details {
    subnet_id = oci_core_subnet.vcn_b_public.id
    assign_public_ip = true
    display_name = "vcn-b-workload-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_id
    kms_key_id  = var.kms_key_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/web_user_data.tpl", { TITLE = "vcn-b-workload" }))
  }
}

resource "oci_core_vcn" "vcn_c" {
  compartment_id = var.compartment_id
  cidr_block     = "10.40.0.0/16"
  display_name   = "VCN-C"
  dns_label      = "vcnc"
}

resource "oci_core_subnet" "vcn_c_public" {
  compartment_id     = var.compartment_id
  vcn_id             = oci_core_vcn.vcn_c.id
  cidr_block         = "10.40.1.0/24"
  display_name       = "vcn-c-public-subnet"
  dns_label          = "vcnc-pub"
  availability_domain = var.ad
  route_table_id     = oci_core_route_table.vcn_c_rt.id
}

resource "oci_core_instance" "vcn_c_workload" {
  compartment_id = var.compartment_id
  availability_domain = var.ad
  shape = var.shape
  display_name = "vcn-c-workload"

  create_vnic_details {
    subnet_id = oci_core_subnet.vcn_c_public.id
    assign_public_ip = true
    display_name = "vcn-c-workload-vnic"
  }

  source_details {
    source_type = "image"
    source_id   = var.ubuntu_image_id
    kms_key_id  = var.kms_key_ocid
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/web_user_data.tpl", { TITLE = "vcn-c-workload" }))
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
