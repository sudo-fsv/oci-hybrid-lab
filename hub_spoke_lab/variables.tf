variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-phoenix-1"
}

variable "config_file_profile" {
  description = "OCI CLI config profile to use for provider authentication"
  type        = string
  default     = "DEFAULT"
}

variable "oci_cli_profile" {
  description = "OCI CLI profile name to use in external/local-exec calls"
  type        = string
  default     = "DEFAULT"
}

variable "compartment_id" {
  description = "Compartment OCID"
  type        = string
}

variable "ad" {
  description = "Availability Domain index"
  type        = string
  default     = "1"
}

variable "ad_ha" {
  description = "Availability Domain index for HA instances"
  type        = string
  default     = "2"
}

variable "shape" {
  description = "Instance shape"
  type        = string
  default     = "VM.Standard.E6.Flex"
}

variable "pfsense_image_source_local_path" {
  description = <<-EOF
  Local path to the pfSense image to upload to OCI Object Storage.
  EOF
  type        = string
  default     = "./images/pfSense-CE-memstick-serial-2.7.2-RELEASE-amd64.img.gz"
  }

variable "libreswan_image_id" {
  description = "Image OCID for Libreswan (on-prem)"
  type        = string
  # default     = "ocid1.image.oc1.phx.aaaaaaaamdjb6c37rxomys4zrxelv3xeyxq27efrpttwwuwfnftksplud2ra" # oracle linux 8 with latest updates as of 2024-06-01, which includes libreswan 3.36
  default     = "ocid1.image.oc1.phx.aaaaaaaa5gpxxac3r7wcxdumlaoac3o6hby3rqawsi3sorcr734cyx37yvca" # ubuntu
}

variable "ssh_public_key" {
  description = "SSH public key for instances"
  type        = string
  sensitive   = true // not really, but it is too noisy in logs
  default     = "./secrets/lab-key.pub"
}

variable "ubuntu_image_id" {
  description = "Image OCID for Ubuntu (for web and representative workloads)"
  type        = string
  default     = "ocid1.image.oc1.phx.aaaaaaaa5gpxxac3r7wcxdumlaoac3o6hby3rqawsi3sorcr734cyx37yvca"
}

variable "web_domains" {
  description = "Two domains for web backends"
  type        = list(string)
  default     = ["web1.example.com", "web2.example.com"]
}

variable "lb_shape" {
  description = "Load balancer shape"
  type        = string
  default     = "100Mbps"
}

variable "pfsense_admin_password" {
  description = "Password for the lab-admin user on pfSense (sensitive)"
  type        = string
  sensitive   = true
}

variable "carp_password" {
  description = "CARP shared password for pfSense HA (sensitive)"
  type        = string
  sensitive   = true
}

variable "kms_key_ocid" {
  description = "KMS key OCID to encrypt instance boot volume metadata"
  type        = string
  default     = ""
}

variable "onprem_cidr" {
  description = "On-prem VCN CIDR to advertise from Libreswan"
  type        = string
  default     = "172.16.0.0/16"
}

variable "libreswan_vm_private_ip" {
  description = "Static private IP to assign to the Libreswan VM's primary VNIC"
  type        = string
  default     = "172.16.0.55"
}

variable "oci_bgp_peer_ip_1" {
  description = "Oracle side BGP peer IP for tunnel 1"
  type        = string
  default     = "169.254.2.5/30"
}

variable "cpe_bgp_peer_ip_1" {
  description = "CPE (Libreswan) BGP interface IP for tunnel 1 (local endpoint)"
  type        = string
  default     = "169.254.2.6/30"
}

variable "oci_bgp_peer_ip_2" {
  description = "Oracle side BGP peer IP for tunnel 2"
  type        = string
  default     = "169.254.2.9/30"
}

variable "cpe_bgp_peer_ip_2" {
  description = "CPE (Libreswan) BGP interface IP for tunnel 2 (local endpoint)"
  type        = string
  default     = "169.254.2.10/30"
}

variable "cpe_bgp_asn" {
  description = "BGP ASN for the CPE (Libreswan)"
  type        = number
  default     = 65000
}
