terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~>7.29.0"
    }
  }
}

provider "oci" {
  region = var.region
}
