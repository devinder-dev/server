terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "9.14.0"
    }
  }
}

provider "oci" {
  region = var.region
}
