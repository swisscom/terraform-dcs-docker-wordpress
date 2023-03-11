# ======================================================================================================================
terraform {
  required_providers {
    vcd = {
      source  = "vmware/vcd"
      version = "~> 3.8.2"
    }
  }
  required_version = ">= 1.2.0"
}

# configure vCloud provider
provider "vcd" {
  # See https://registry.terraform.io/providers/vmware/vcd/latest/docs#argument-reference for argument reference
  url                  = var.vcd_api_url
  user                 = var.vcd_api_username
  password             = var.vcd_api_password
  auth_type            = "integrated"
  org                  = var.vcd_org
  vdc                  = var.vcd_vdc
  allow_unverified_ssl = true
  max_retry_timeout    = 120
  logging              = var.vcd_logging_enabled
}
# ======================================================================================================================

# ======================================================================================================================
# get pre-provisioned vCD edge gateway
data "vcd_edgegateway" "edge_gateway" {
  name = var.vcd_edgegateway
}

# configure edge gateway
resource "vcd_edgegateway_settings" "edge_gateway" {
  edge_gateway_id         = data.vcd_edgegateway.edge_gateway.id
  lb_enabled              = false
  lb_acceleration_enabled = false
  lb_logging_enabled      = false

  fw_enabled                      = true
  fw_default_rule_logging_enabled = false
}
# ======================================================================================================================

# ======================================================================================================================
# routed network, connected to the edge gateway
resource "vcd_network_routed_v2" "network" {
  name = "${var.dns_hostname}-routed-network"

  interface_type  = "internal"
  edge_gateway_id = data.vcd_edgegateway.edge_gateway.id
  gateway         = cidrhost(var.network_cidr, 1)
  prefix_length   = split("/", var.network_cidr)[1]
  dns1            = "1.1.1.1"
  dns2            = "8.8.8.8"

  static_ip_pool {
    start_address = cidrhost(var.network_cidr, 10)
    end_address   = cidrhost(var.network_cidr, 50)
  }
}

# vApp for vms, disks, networks, etc.
resource "vcd_vapp" "wordpress" {
  name        = var.dns_hostname
  description = "vApp for WordPress"

  depends_on = [vcd_network_routed_v2.network]
}

# connect the routed network to the vApp
resource "vcd_vapp_org_network" "network" {
  vapp_name        = vcd_vapp.wordpress.name
  org_network_name = vcd_network_routed_v2.network.name

  depends_on = [vcd_vapp.wordpress, vcd_network_routed_v2.network]
}
# ======================================================================================================================

# ======================================================================================================================
# NAT settings
resource "vcd_nsxv_snat" "outbound" {
  edge_gateway = var.vcd_edgegateway

  network_type = "ext"
  network_name = var.vcd_edgegateway

  original_address   = var.network_cidr
  translated_address = data.vcd_edgegateway.edge_gateway.default_external_network_ip

  depends_on = [vcd_network_routed_v2.network]
}

resource "vcd_nsxv_snat" "hairpin" {
  edge_gateway = var.vcd_edgegateway

  network_type = "org"
  network_name = vcd_network_routed_v2.network.name

  original_address   = var.network_cidr
  translated_address = cidrhost(var.network_cidr, 1)

  depends_on = [vcd_network_routed_v2.network]
}

resource "vcd_nsxv_dnat" "ssh" {
  edge_gateway = var.vcd_edgegateway

  network_type       = "ext"
  network_name       = var.vcd_edgegateway
  original_address   = data.vcd_edgegateway.edge_gateway.default_external_network_ip
  original_port      = 2222
  translated_address = cidrhost(var.network_cidr, 10)
  translated_port    = 22
  protocol           = "tcp"

  depends_on = [vcd_network_routed_v2.network]
}

resource "vcd_nsxv_dnat" "http" {
  edge_gateway = var.vcd_edgegateway

  network_type       = "ext"
  network_name       = var.vcd_edgegateway
  original_address   = data.vcd_edgegateway.edge_gateway.default_external_network_ip
  original_port      = 80
  translated_address = cidrhost(var.network_cidr, 10)
  translated_port    = 80
  protocol           = "tcp"

  depends_on = [vcd_network_routed_v2.network]
}

resource "vcd_nsxv_dnat" "https" {
  edge_gateway = var.vcd_edgegateway

  network_type       = "ext"
  network_name       = var.vcd_edgegateway
  original_address   = data.vcd_edgegateway.edge_gateway.default_external_network_ip
  original_port      = 443
  translated_address = cidrhost(var.network_cidr, 10)
  translated_port    = 443
  protocol           = "tcp"

  depends_on = [vcd_network_routed_v2.network]
}
# ======================================================================================================================

# ======================================================================================================================
# firewall settings
resource "vcd_nsxv_firewall_rule" "internal" {
  org          = var.vcd_org
  vdc          = var.vcd_vdc
  edge_gateway = var.vcd_edgegateway
  name         = "internal network"

  action = "accept"
  source {
    gateway_interfaces = ["internal"]
  }
  destination {
    gateway_interfaces = ["internal"]
  }
  service {
    protocol = "any"
  }

  depends_on = [vcd_edgegateway_settings.edge_gateway]
}

resource "vcd_nsxv_firewall_rule" "external" {
  org          = var.vcd_org
  vdc          = var.vcd_vdc
  edge_gateway = var.vcd_edgegateway
  name         = "outbound traffic"

  action = "accept"
  source {
    gateway_interfaces = ["internal"]
  }
  destination {
    gateway_interfaces = ["external"]
  }
  service {
    protocol = "any"
  }

  depends_on = [vcd_edgegateway_settings.edge_gateway]
}

resource "vcd_nsxv_firewall_rule" "network" {
  org          = var.vcd_org
  vdc          = var.vcd_vdc
  edge_gateway = var.vcd_edgegateway
  name         = "vm network"

  action = "accept"
  source {
    ip_addresses = ["${var.network_cidr}"]
  }
  destination {
    ip_addresses = ["any"]
  }
  service {
    protocol = "any"
  }

  depends_on = [vcd_edgegateway_settings.edge_gateway]
}

resource "vcd_nsxv_firewall_rule" "ssh" {
  org          = var.vcd_org
  vdc          = var.vcd_vdc
  edge_gateway = var.vcd_edgegateway
  name         = "ssh"

  action = "accept"
  source {
    gateway_interfaces = ["external"]
  }
  destination {
    ip_addresses = ["${data.vcd_edgegateway.edge_gateway.default_external_network_ip}"]
  }
  service {
    protocol = "tcp"
    port     = "2222"
  }

  depends_on = [vcd_edgegateway_settings.edge_gateway]
}

resource "vcd_nsxv_firewall_rule" "web" {
  org          = var.vcd_org
  vdc          = var.vcd_vdc
  edge_gateway = var.vcd_edgegateway
  name         = "web traffic"

  action = "accept"
  source {
    gateway_interfaces = ["external"]
  }
  destination {
    ip_addresses = ["${data.vcd_edgegateway.edge_gateway.default_external_network_ip}"]
  }
  service {
    protocol = "tcp"
    port     = "80"
  }
  service {
    protocol = "tcp"
    port     = "443"
  }

  depends_on = [vcd_edgegateway_settings.edge_gateway]
}
# ======================================================================================================================

# ======================================================================================================================
# OS image catalog
resource "vcd_catalog" "catalog" {
  name = var.vcd_catalog != "" ? var.vcd_catalog : var.dns_hostname

  delete_recursive = "true"
  delete_force     = "true"

  depends_on = [vcd_vapp.wordpress]
}

# upload OS image
resource "vcd_catalog_vapp_template" "template" {
  catalog_id = vcd_catalog.catalog.id
  name       = var.vcd_template != "" ? var.vcd_template : "${var.dns_hostname}_ubuntu_os_22.04"

  ova_path          = "ubuntu-22.04-server-cloudimg-amd64.ova"
  upload_piece_size = 10
}
# ======================================================================================================================

# ======================================================================================================================
# virtual machine
resource "vcd_vapp_vm" "wordpress" {
  vapp_name     = vcd_vapp.wordpress.name
  name          = var.dns_hostname
  computer_name = var.dns_hostname

  vapp_template_id = vcd_catalog_vapp_template.template.id
  memory           = var.vm_memory
  cpus             = var.vm_cpus
  cpu_cores        = 1

  accept_all_eulas       = true
  power_on               = true
  cpu_hot_add_enabled    = true
  memory_hot_add_enabled = true

  override_template_disk {
    bus_type    = "paravirtual"
    size_in_mb  = var.vm_disk_size
    bus_number  = 0
    unit_number = 0
  }

  network {
    type               = "org"
    name               = vcd_vapp_org_network.network.org_network_name
    ip_allocation_mode = "MANUAL"
    ip                 = cidrhost(var.network_cidr, 10)
    is_primary         = true
  }

  guest_properties = {
    "instance-id"    = "${var.dns_hostname}"
    "guest.hostname" = "${var.dns_hostname}"
    "hostname"       = "${var.dns_hostname}"
    "public-keys"    = file("ssh_key_id_rsa.pub")
    "user-data" = base64encode(templatefile("${path.module}/user_data.tmpl", {
      "hostname" = "${var.dns_hostname}",
      "sshkey"   = file("ssh_key_id_rsa.pub"),
      "ip"       = cidrhost(var.network_cidr, 10),
      "gateway"  = cidrhost(var.network_cidr, 1)
    }))
  }

  # only create the VM once we have firewall and NAT ready, to avoid potentional confusing connectivity issues
  depends_on = [
    vcd_nsxv_snat.outbound,
    vcd_nsxv_snat.hairpin,
    vcd_nsxv_dnat.ssh,
    vcd_nsxv_dnat.http,
    vcd_nsxv_dnat.https,
    vcd_nsxv_firewall_rule.internal,
    vcd_nsxv_firewall_rule.external,
    vcd_nsxv_firewall_rule.network,
    vcd_nsxv_firewall_rule.ssh,
    vcd_nsxv_firewall_rule.web,
  ]
}
# ======================================================================================================================
