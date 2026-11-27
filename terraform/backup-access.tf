# The operator creates the S3 key outside Terraform to keep it out of state.

locals {
  backups_app_name = "${var.name_prefix}-backups-app"

  # One object is overwritten nightly. Older versions can be read and listed.
  backups_app_permissions = ["OBJECT_CREATE", "OBJECT_OVERWRITE", "OBJECT_READ", "OBJECT_INSPECT"]
}

resource "oci_identity_user" "backups_app" {
  compartment_id = var.tenancy_ocid
  name           = local.backups_app_name
  description    = "App account for the backups bucket. S3 customer secret keys only."
  email          = var.backups_app_email
}

# S3 keys only: no console password, API signing keys, auth tokens or SMTP.
# Removing this resource leaves the user's capabilities as they are.
resource "oci_identity_user_capabilities_management" "backups_app" {
  user_id                      = oci_identity_user.backups_app.id
  can_use_customer_secret_keys = true
  can_use_console_password     = false
  can_use_api_keys             = false
  can_use_auth_tokens          = false
  can_use_smtp_credentials     = false
}

resource "oci_identity_group" "backups_app" {
  compartment_id = var.tenancy_ocid
  name           = local.backups_app_name
  description    = "Members may write, read and list object versions in the backups bucket only."
}

resource "oci_identity_user_group_membership" "backups_app" {
  user_id  = oci_identity_user.backups_app.id
  group_id = oci_identity_group.backups_app.id
}

# "all { bucket, any { permission } }" = this bucket AND one of these permissions.
# The group is named by OCID, so the rule can't match a same-named group elsewhere.
resource "oci_identity_policy" "backups_app" {
  compartment_id = var.tenancy_ocid
  name           = local.backups_app_name
  description    = "Lets the backups app write, read and list object versions in the backups bucket."
  statements = [
    "Allow group id ${oci_identity_group.backups_app.id} to manage objects in compartment id ${var.compartment_ocid} where all {target.bucket.name = '${oci_objectstorage_bucket.server["backups"].name}', any {${join(", ", [for p in local.backups_app_permissions : "request.permission = '${p}'"])}}}",
  ]
}
