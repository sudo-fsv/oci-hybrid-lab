variable "region" {
  description = "OCI region"
  type        = string
  default     = "us-ashburn-1"
}

variable "compartment_id" {
  description = "Compartment OCID"
  type        = string
}

variable "ad" {
  description = "Availability Domain"
  type        = string
}

variable "shape" {
  description = "Instance shape"
  type        = string
  default     = "VM.Standard.E3.Flex"
}

variable "pfsense_image_id" {
  description = "Image OCID for pfSense appliance"
  type        = string
}

variable "libreswan_image_id" {
  description = "Image OCID for Libreswan (on-prem)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for instances"
  type        = string
}

variable "ubuntu_image_id" {
  description = "Image OCID for Ubuntu (for web and representative workloads)"
  type        = string
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
  default     = "192.168.100.0/24"
}

variable "oci_bgp_peer_ip" {
  description = "Optional: Oracle side BGP peer IP to configure in Libreswan user_data"
  type        = string
  default     = "169.254.2.5"
}

variable "cpe_bgp_peer_ip" {
  description = "Optional: CPE (Libreswan) BGP interface IP for tunnel local endpoint"
  type        = string
  default     = "169.254.2.6"
}

variable "cpe_bgp_asn" {
  description = "BGP ASN for the CPE (Libreswan)"
  type        = number
  default     = 65000
}

variable "oci_bgp_asn" {
  description = "BGP ASN for the OCI/DRG side"
  type        = number
  default     = 65001
}
