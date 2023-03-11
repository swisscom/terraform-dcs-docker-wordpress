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
  lb_enabled              = true
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

  depends_on = [vcd_vapp.wordpress, vcd_catalog.catalog]
}
# ======================================================================================================================

