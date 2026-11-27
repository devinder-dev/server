mock_provider "oci" {
  override_during = plan

  # The policy text names the group by ID, so the plan needs one to check it.
  mock_resource "oci_identity_group" {
    defaults = { id = "ocid1.group.oc1..zzt" }
  }
}

variables {
  tenancy_ocid      = "ocid1.tenancy.oc1..zzt"
  compartment_ocid  = "ocid1.compartment.oc1..zzt000000000000000000000000000000000000000000000000000000000"
  region            = "eu-stockholm-1"
  photos_app_email  = "zzt+photos-app@zzt.test"
  backups_app_email = "zzt+backups-app@zzt.test"
  vms               = {}
}

run "photos_app_reaches_only_the_photos_bucket" {
  command = plan

  assert {
    condition     = length(oci_identity_policy.photos_app.statements) == 1
    error_message = "The photos app policy must have exactly one statement."
  }

  assert {
    condition = (
      strcontains(oci_identity_policy.photos_app.statements[0], "to manage objects in compartment id ${var.compartment_ocid} where all {target.bucket.name = 'shared-server-photos',") &&
      !strcontains(oci_identity_policy.photos_app.statements[0], "backups")
    )
    error_message = "The photos app may manage objects only in the photos bucket of the server compartment."
  }

  assert {
    condition = sort([
      for m in regexall("request\\.permission = '([A-Z_]+)'", oci_identity_policy.photos_app.statements[0]) : m[0]
    ]) == sort(["OBJECT_CREATE", "OBJECT_READ", "OBJECT_DELETE"])
    error_message = "The photos app gets exactly OBJECT_CREATE, OBJECT_READ and OBJECT_DELETE."
  }

  assert {
    condition = (
      oci_identity_user_capabilities_management.photos_app.can_use_customer_secret_keys == true &&
      oci_identity_user_capabilities_management.photos_app.can_use_console_password == false &&
      oci_identity_user_capabilities_management.photos_app.can_use_api_keys == false &&
      oci_identity_user_capabilities_management.photos_app.can_use_auth_tokens == false &&
      oci_identity_user_capabilities_management.photos_app.can_use_smtp_credentials == false
    )
    error_message = "The photos app user may use S3 customer secret keys and nothing else."
  }
}

run "placeholder_compartment_is_refused" {
  command = plan

  variables {
    compartment_ocid = "ocid1.compartment.oc1..replace"
  }

  expect_failures = [var.compartment_ocid]
}

run "placeholder_email_is_refused" {
  command = plan

  variables {
    photos_app_email = "replace+photos-app@example.com"
  }

  expect_failures = [var.photos_app_email]
}

run "backups_app_reaches_only_the_backups_bucket" {
  command = plan

  assert {
    condition     = length(oci_identity_policy.backups_app.statements) == 1
    error_message = "The backups app policy must have exactly one statement."
  }

  assert {
    condition = (
      strcontains(oci_identity_policy.backups_app.statements[0], "to manage objects in compartment id ${var.compartment_ocid} where all {target.bucket.name = 'shared-server-backups',") &&
      !strcontains(oci_identity_policy.backups_app.statements[0], "photos")
    )
    error_message = "The backups app may manage objects only in the backups bucket of the server compartment."
  }

  assert {
    condition = sort([
      for m in regexall("request\\.permission = '([A-Z_]+)'", oci_identity_policy.backups_app.statements[0]) : m[0]
    ]) == sort(["OBJECT_CREATE", "OBJECT_OVERWRITE", "OBJECT_READ", "OBJECT_INSPECT"])
    error_message = "The backups app gets exactly create, overwrite, read and inspect permissions."
  }

  assert {
    condition = (
      oci_identity_user_capabilities_management.backups_app.can_use_customer_secret_keys == true &&
      oci_identity_user_capabilities_management.backups_app.can_use_console_password == false &&
      oci_identity_user_capabilities_management.backups_app.can_use_api_keys == false &&
      oci_identity_user_capabilities_management.backups_app.can_use_auth_tokens == false &&
      oci_identity_user_capabilities_management.backups_app.can_use_smtp_credentials == false
    )
    error_message = "The backups app user may use S3 customer secret keys and nothing else."
  }
}
