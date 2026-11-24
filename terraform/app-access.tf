# An app account for the photos bucket. Its S3 customer secret key goes in the
# application's environment, so a leaked key reaches photo objects only: no other
# bucket, no console login, no API calls. The key is created by hand in the
# Console; a Terraform-made key would sit in plain text in the state file.

locals {
  photos_app_name = "${var.name_prefix}-photos-app"

  # Upload (photo names are new random IDs, so no overwrite), presigned GET and
  # HEAD (OBJECT_READ covers both), and delete. Nothing else.
  photos_app_permissions = ["OBJECT_CREATE", "OBJECT_READ", "OBJECT_DELETE"]
}

resource "oci_identity_user" "photos_app" {
  compartment_id = var.tenancy_ocid
  name           = local.photos_app_name
  description    = "App account for the photos bucket. S3 customer secret keys only."
  email          = var.photos_app_email
}

# S3 keys only: no console password, API signing keys, auth tokens or SMTP.
# Removing this resource leaves the user's capabilities as they are.
resource "oci_identity_user_capabilities_management" "photos_app" {
  user_id                      = oci_identity_user.photos_app.id
  can_use_customer_secret_keys = true
  can_use_console_password     = false
  can_use_api_keys             = false
  can_use_auth_tokens          = false
  can_use_smtp_credentials     = false
}

resource "oci_identity_group" "photos_app" {
  compartment_id = var.tenancy_ocid
  name           = local.photos_app_name
  description    = "Members may create, read and delete objects in the photos bucket only."
}

resource "oci_identity_user_group_membership" "photos_app" {
  user_id  = oci_identity_user.photos_app.id
  group_id = oci_identity_group.photos_app.id
}

# "all { bucket, any { permission } }" = this bucket AND one of these permissions.
# The group is named by OCID, so the rule can't match a same-named group elsewhere.
resource "oci_identity_policy" "photos_app" {
  compartment_id = var.tenancy_ocid
  name           = local.photos_app_name
  description    = "Lets the photos app create, read and delete objects in the photos bucket."
  statements = [
    "Allow group id ${oci_identity_group.photos_app.id} to manage objects in compartment id ${var.compartment_ocid} where all {target.bucket.name = '${oci_objectstorage_bucket.server["photos"].name}', any {${join(", ", [for p in local.photos_app_permissions : "request.permission = '${p}'"])}}}",
  ]
}
