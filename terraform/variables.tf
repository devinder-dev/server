variable "tenancy_ocid" {
  type        = string
  description = "OCID of the Always Free tenancy."
}

variable "compartment_ocid" {
  type        = string
  description = "OCID of an existing dedicated child compartment for the shared servers."

  # Plan only reads through the tenancy, so a placeholder here would pass plan
  # and fail first at apply. Check the shape up front.
  validation {
    condition     = can(regex("^ocid1\\.compartment\\.oc1\\.\\.[a-z0-9]{60}$", var.compartment_ocid))
    error_message = "Set compartment_ocid to the dedicated compartment's OCID (ocid1.compartment.oc1.. followed by 60 lowercase letters or digits), not the example placeholder."
  }
}

variable "photos_app_email" {
  type        = string
  description = "Email for the photos app user. The tenancy's identity domain requires one on every user. Keep it in the private tfvars."
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.photos_app_email)) && !endswith(lower(var.photos_app_email), "@example.com")
    error_message = "Set photos_app_email to a real address you can receive mail at, not the example placeholder."
  }
}

variable "backups_app_email" {
  type        = string
  description = "Email for the backups app user. The tenancy's identity domain requires one on every user. Keep it in the private tfvars."
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.backups_app_email)) && !endswith(lower(var.backups_app_email), "@example.com")
    error_message = "Set backups_app_email to a real address you can receive mail at, not the example placeholder."
  }
}

variable "region" {
  type        = string
  description = "The tenancy's commercial OCI home region."
}

variable "availability_domain_index" {
  type        = number
  description = "Zero-based position in the home region's list of availability domains."
  default     = 0

  validation {
    condition = length(var.vms) == 0 ? true : (
      var.availability_domain_index >= 0 &&
      floor(var.availability_domain_index) == var.availability_domain_index &&
      var.availability_domain_index < length(data.oci_identity_availability_domains.home[0].availability_domains)
    )
    error_message = "Set availability_domain_index to a whole number from 0 to the number of availability domains in the region minus 1."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for shared server resources and bucket names."
  default     = "shared-server"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.name_prefix))
    error_message = "Use 1–31 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "ssh_public_key" {
  type        = string
  description = "Single OpenSSH public key line for deploy, required when a VM is configured."
  default     = ""

  validation {
    condition     = length(var.vms) == 0 || can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/]+={0,2}( [^\r\n]*)?$", trimspace(var.ssh_public_key)))
    error_message = "Supply the contents of one OpenSSH public key, such as an id_ed25519.pub line."
  }
}

variable "ubuntu_lts_version" {
  type        = string
  description = "Canonical Ubuntu LTS family to search for the newest standard Arm image."
  default     = "24.04"
}

variable "vms" {
  description = "VM names and sizes. Cloud-init paths are relative to this Terraform module."
  type = map(object({
    ocpus           = number
    memory_gb       = number
    boot_volume_gb  = number
    cloud_init_file = string
  }))
  default = {
    apps = {
      ocpus           = 1
      memory_gb       = 4
      boot_volume_gb  = 50
      cloud_init_file = "../cloud-init.yaml"
    }
  }

  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      vm.ocpus >= 1 && floor(vm.ocpus) == vm.ocpus &&
      vm.memory_gb >= vm.ocpus && floor(vm.memory_gb) == vm.memory_gb &&
      vm.boot_volume_gb >= 50 && floor(vm.boot_volume_gb) == vm.boot_volume_gb
    ])
    error_message = "For each VM, set whole OCPUs (minimum 1), whole GB of RAM (minimum 1 per OCPU), and a boot disk of at least 50 GB."
  }

  validation {
    condition = (
      sum(concat([0], [for vm in values(var.vms) : vm.ocpus])) <= 2 &&
      sum(concat([0], [for vm in values(var.vms) : vm.memory_gb])) <= 12 &&
      sum(concat([0], [for vm in values(var.vms) : vm.boot_volume_gb])) <= 200
    )
    error_message = "Always Free VM totals must stay within 2 OCPUs, 12 GB RAM and 200 GB boot storage."
  }
}
