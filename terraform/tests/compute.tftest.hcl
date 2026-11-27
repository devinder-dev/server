mock_provider "oci" {
  override_during = plan

  mock_data "oci_identity_availability_domains" {
    defaults = { availability_domains = [{ name = "zzt-AD-1" }] }
  }

  mock_data "oci_core_images" {
    defaults = { images = [{ id = "ocid1.image.oc1..zzt" }] }
  }
}

variables {
  tenancy_ocid      = "ocid1.tenancy.oc1..zzt"
  compartment_ocid  = "ocid1.compartment.oc1..zzt000000000000000000000000000000000000000000000000000000000"
  region            = "eu-stockholm-1"
  photos_app_email  = "zzt+photos-app@zzt.test"
  backups_app_email = "zzt+backups-app@zzt.test"
}

run "buckets_only" {
  command = plan

  variables {
    vms = {}
  }

  assert {
    condition     = length(output.public_ips) == 0 && length(oci_objectstorage_bucket.server) == 2
    error_message = "A buckets-only plan must include both buckets and no VM public IPs."
  }

  assert {
    condition     = length(data.oci_core_images.ubuntu) == 0 && length(data.oci_identity_availability_domains.home) == 0
    error_message = "A buckets-only plan must skip compute catalog lookups."
  }
}

run "three_ocpus_exceeds_free_quota" {
  command = plan

  variables {
    ssh_public_key = "ssh-ed25519 AAAA zzt"
    vms = {
      apps = {
        ocpus           = 3
        memory_gb       = 4
        boot_volume_gb  = 50
        cloud_init_file = "../cloud-init.yaml"
      }
    }
  }

  expect_failures = [var.vms]
}
