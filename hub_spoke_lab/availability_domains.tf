data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_id
}

# Helper locals to convert 1-based string index to 0-based number for list indexing
locals {
  ad_index    = tonumber(var.ad) - 1
  ad_ha_index = tonumber(var.ad_ha) - 1
}
