# Northgate on Oracle Cloud (ADR 0009): a Network Load Balancer in a public subnet in front of one Ampere A1 VM in a
# private subnet with no public IP. SSH only through Oracle Bastion. Everything in its own compartment, tagged.

locals {
  tags         = { product = "northgate", environment = "production", managed_by = "terraform" }
  vcn_cidr     = "10.20.0.0/16"
  public_cidr  = "10.20.0.0/24" # load balancer and bastion
  private_cidr = "10.20.1.0/24" # the VM
}

resource "oci_identity_compartment" "northgate" {
  compartment_id = var.tenancy_ocid
  name           = "northgate"
  description    = "Northgate Dental: network, load balancer, bastion and VM (synthetic data only)"
  enable_delete  = true
  freeform_tags  = local.tags
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

# ---------- network ----------

resource "oci_core_vcn" "main" {
  compartment_id = oci_identity_compartment.northgate.id
  cidr_blocks    = [local.vcn_cidr]
  display_name   = "northgate-vcn"
  dns_label      = "northgate"
  freeform_tags  = local.tags
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = oci_identity_compartment.northgate.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "northgate-igw"
  freeform_tags  = local.tags
}

# Outbound only: updates, image pulls, Let's Encrypt and backups to S3 leave through here; nothing can come in.
resource "oci_core_nat_gateway" "nat" {
  compartment_id = oci_identity_compartment.northgate.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "northgate-nat"
  freeform_tags  = local.tags
}

# Oracle services (Object Storage, OS updates from Oracle's mirrors) without crossing the internet.
resource "oci_core_service_gateway" "sgw" {
  compartment_id = oci_identity_compartment.northgate.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "northgate-sgw"
  services { service_id = data.oci_core_services.all.services[0].id }
  freeform_tags = local.tags
}

resource "oci_core_route_table" "public" {
  compartment_id = oci_identity_compartment.northgate.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "northgate-public-rt"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
  freeform_tags = local.tags
}

resource "oci_core_route_table" "private" {
  compartment_id = oci_identity_compartment.northgate.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "northgate-private-rt"
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_nat_gateway.nat.id
  }
  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.sgw.id
  }
  freeform_tags = local.tags
}

# Public subnet: the balancer takes 80 and 443 from anyone; nothing else is open.
resource "oci_core_security_list" "public" {
  compartment_id = oci_identity_compartment.northgate.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "northgate-public-sl"
  dynamic "ingress_security_rules" {
    for_each = [80, 443]
    content {
      protocol = "6"
      source   = "0.0.0.0/0"
      tcp_options {
        min = ingress_security_rules.value
        max = ingress_security_rules.value
      }
    }
  }
  egress_security_rules {
    protocol    = "6"
    destination = local.private_cidr
  }
  freeform_tags = local.tags
}

# Private subnet: web traffic arrives from the balancer with the visitor's own address (source preserved), so
# 80 and 443 must accept any source; the VM has no public IP, so the balancer is the only way to reach it.
# SSH only from the public subnet, where the bastion lives.
resource "oci_core_security_list" "private" {
  compartment_id = oci_identity_compartment.northgate.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "northgate-private-sl"
  dynamic "ingress_security_rules" {
    for_each = [80, 443]
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
    protocol = "6"
    source   = local.public_cidr
    tcp_options {
      min = 22
      max = 22
    }
  }
  ingress_security_rules { # path MTU discovery
    protocol = "1"
    source   = local.vcn_cidr
    icmp_options {
      type = 3
      code = 4
    }
  }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
  freeform_tags = local.tags
}

resource "oci_core_subnet" "public" {
  compartment_id    = oci_identity_compartment.northgate.id
  vcn_id            = oci_core_vcn.main.id
  cidr_block        = local.public_cidr
  display_name      = "northgate-public"
  dns_label         = "pub"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.public.id]
  freeform_tags     = local.tags
}

resource "oci_core_subnet" "private" {
  compartment_id             = oci_identity_compartment.northgate.id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = local.private_cidr
  display_name               = "northgate-private"
  dns_label                  = "priv"
  prohibit_public_ip_on_vnic = true # nothing in this subnet can ever get a public IP
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  freeform_tags              = local.tags
}

# ---------- VM ----------

data "oci_core_images" "ol9" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "vm" {
  compartment_id      = oci_identity_compartment.northgate.id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "northgate-vm"
  shape               = var.shape
  dynamic "shape_config" { # fixed shapes such as E2.1.Micro take no size
    for_each = endswith(var.shape, ".Flex") ? [1] : []
    content {
      ocpus         = var.ocpus
      memory_in_gbs = var.memory_gbs
    }
  }
  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ol9.images[0].id
    boot_volume_size_in_gbs = 100 # 2026-11-22: room for Gemma (6 GB) and images; still inside the free 200 GB
  }
  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    hostname_label   = "vm${substr(md5(var.shape), 0, 6)}" # differs per shape, so old and new VMs can overlap
  }
  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
    # First boot: clone the repository and run the same hardening script used by hand (infra/scripts/bootstrap-vm.sh).
    user_data = base64encode(templatefile("${path.module}/cloud-init.sh", { repository = var.repository }))
  }
  agent_config {
    plugins_config {
      name          = "Bastion"
      desired_state = "ENABLED"
    }
  }
  freeform_tags = local.tags
  lifecycle {
    # A newer image or script must not replace a running VM.
    ignore_changes = [source_details[0].source_id, metadata, create_vnic_details[0].hostname_label]
    # A move to another shape builds the new VM first, so a failed build (no capacity) never leaves no VM.
    create_before_destroy = true
  }
}

# ---------- Network Load Balancer ----------

resource "oci_network_load_balancer_network_load_balancer" "nlb" {
  compartment_id                 = oci_identity_compartment.northgate.id
  display_name                   = "northgate-nlb"
  subnet_id                      = oci_core_subnet.public.id
  is_private                     = false
  is_preserve_source_destination = false
  freeform_tags                  = local.tags
}

resource "oci_network_load_balancer_backend_set" "web" {
  for_each                 = toset(["80", "443"])
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  name                     = "web-${each.key}"
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = true # the WAF and rate limits see each visitor's real address
  health_checker {
    protocol           = "TCP"
    port               = 443
    interval_in_millis = 10000
    timeout_in_millis  = 3000
    retries            = 3
  }
}

resource "oci_network_load_balancer_backend" "vm" {
  for_each                 = oci_network_load_balancer_backend_set.web
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  backend_set_name         = each.value.name
  port                     = tonumber(each.key)
  target_id                = oci_core_instance.vm.id
}

resource "oci_network_load_balancer_listener" "web" {
  for_each                 = oci_network_load_balancer_backend_set.web
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.nlb.id
  name                     = "tcp-${each.key}"
  default_backend_set_name = each.value.name
  port                     = tonumber(each.key)
  protocol                 = "TCP"
}

# ---------- Bastion ----------

resource "oci_bastion_bastion" "admin" {
  compartment_id               = oci_identity_compartment.northgate.id
  bastion_type                 = "STANDARD"
  name                         = "northgatebastion"
  target_subnet_id             = oci_core_subnet.public.id
  client_cidr_block_allow_list = [var.admin_cidr]
  max_session_ttl_in_seconds   = 10800
  freeform_tags                = local.tags
  lifecycle {
    ignore_changes = [defined_tags] # Oracle adds its own Oracle-Tags (CreatedBy, CreatedOn) after creation
  }
}
