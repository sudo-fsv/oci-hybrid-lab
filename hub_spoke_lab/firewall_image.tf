data "oci_objectstorage_namespace" "ns" {}

resource "random_id" "pfsense_bucket_suffix" {
  byte_length = 4
}

resource "oci_objectstorage_bucket" "pfsense_bucket" {
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = lower(format("pfsense-images-%s", random_id.pfsense_bucket_suffix.hex))
}

resource "oci_objectstorage_object" "pfsense_image" {
  namespace = data.oci_objectstorage_namespace.ns.namespace
  bucket    = oci_objectstorage_bucket.pfsense_bucket.name
  object    = basename(var.pfsense_image_source_local_path)
  source    = var.pfsense_image_source_local_path
}
