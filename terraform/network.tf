resource "oci_core_vcn" "server" {
  compartment_id = var.compartment_ocid
  display_name   = var.name_prefix
  cidr_blocks    = ["10.11.0.0/16"]
}

resource "oci_core_internet_gateway" "server" {
  compartment_id = var.compartment_ocid
  display_name   = var.name_prefix
  vcn_id         = oci_core_vcn.server.id
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.server.id
  display_name   = "${var.name_prefix}-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.server.id
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.server.id
  display_name   = "${var.name_prefix}-public"

  dynamic "ingress_security_rules" {
    for_each = toset([22, 80, 443])
    content {
      protocol = "6"
      source   = "0.0.0.0/0"

      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.server.id
  display_name               = "${var.name_prefix}-public"
  cidr_block                 = "10.11.1.0/24"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
}
