data "oci_objectstorage_namespace" "server" {
  compartment_id = var.tenancy_ocid
}

locals {
  buckets = {
    photos = {
      versioning = "Disabled"
      target     = "objects"
      days       = 2
    }
    backups = {
      versioning = "Enabled"
      target     = "previous-object-versions"
      days       = 14
    }
  }
}

resource "oci_objectstorage_bucket" "server" {
  for_each       = local.buckets
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.server.namespace
  name           = "${var.name_prefix}-${each.key}"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = each.value.versioning
}

resource "oci_identity_policy" "bucket_expiry" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name_prefix}-bucket-expiry"
  description    = "Allow regional Object Storage to run deletion rules in the server compartment."
  statements = [
    "Allow service objectstorage-${var.region} to manage object-family in compartment id ${var.compartment_ocid} where any {request.permission='BUCKET_INSPECT', request.permission='BUCKET_READ', request.permission='OBJECT_INSPECT', request.permission='OBJECT_DELETE', request.permission='OBJECT_VERSION_DELETE'}",
  ]
}

resource "oci_objectstorage_object_lifecycle_policy" "expiry" {
  for_each  = local.buckets
  namespace = oci_objectstorage_bucket.server[each.key].namespace
  bucket    = oci_objectstorage_bucket.server[each.key].name

  rules {
    name        = "expire-${each.key}"
    action      = "DELETE"
    is_enabled  = true
    target      = each.value.target
    time_amount = each.value.days
    time_unit   = "DAYS"
  }

  depends_on = [oci_identity_policy.bucket_expiry]
}
