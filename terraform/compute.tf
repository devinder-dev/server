locals {
  shape = "VM.Standard.A1.Flex"
}

data "oci_identity_availability_domains" "home" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = var.ubuntu_lts_version
  shape                    = local.shape
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"

  filter {
    name   = "display_name"
    values = ["^Canonical-Ubuntu-[0-9]+[.][0-9]+-aarch64-[0-9]"]
    regex  = true
  }
}

resource "oci_core_instance" "vm" {
  for_each            = var.vms
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.home.availability_domains[var.availability_domain_index].name
  display_name        = "${var.name_prefix}-${each.key}"
  shape               = local.shape

  shape_config {
    ocpus         = each.value.ocpus
    memory_in_gbs = each.value.memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = each.value.boot_volume_gb
    boot_volume_vpus_per_gb = 10
  }

  metadata = {
    ssh_authorized_keys = trimspace(var.ssh_public_key)
    user_data           = filebase64("${path.module}/${each.value.cloud_init_file}")
  }

  lifecycle {
    # A new catalog image is used on the next intentional rebuild.
    ignore_changes = [source_details[0].source_id]
  }
}
