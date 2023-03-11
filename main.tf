# ======================================================================================================================
terraform {
  required_providers {
    vcd = {
      source  = "vmware/vcd"
      version = "~> 3.8.2"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
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
  translated_port    = 8080
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
  translated_port    = 8443
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

# ======================================================================================================================
# wait for virtual machine to be ready
resource "time_sleep" "wait_for_vm" {
  create_duration = "150s"
  depends_on      = [vcd_vapp_vm.wordpress]
}
# ======================================================================================================================

# ======================================================================================================================
# create nginx and certbot configuration data
resource "null_resource" "config_data" {
  connection {
    type        = "ssh"
    user        = "wordpress"
    private_key = file("ssh_key_id_rsa")
    host        = data.vcd_edgegateway.edge_gateway.default_external_network_ip
    port        = 2222
    timeout     = "10m"
  }

  provisioner "file" {
    destination = "/tmp/nginx_config.sh"
    content     = <<-EOT
      #!/bin/bash

      # certbot folder structure and fake initial certs for nginx
      mkdir -p "/opt/docker/letsencrypt/live/${var.dns_hostname}" || true
      if [ ! -e "/opt/docker/letsencrypt/live/${var.dns_hostname}/fullchain.pem" ] || [ ! -e "/opt/docker/letsencrypt/live/${var.dns_hostname}/privkey.pem" ]; then
        openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
          -keyout "/opt/docker/letsencrypt/live/${var.dns_hostname}/privkey.pem" \
          -out "/opt/docker/letsencrypt/live/${var.dns_hostname}/fullchain.pem" \
          -subj '/CN=localhost' \
          2>/dev/null
      fi

      # additional nginx configs
      if [ ! -e /opt/docker/letsencrypt/options-ssl-nginx.conf ] || [ ! -e /opt/docker/letsencrypt/ssl-dhparams.pem ]; then
        curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > /opt/docker/letsencrypt/options-ssl-nginx.conf
        curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > /opt/docker/letsencrypt/ssl-dhparams.pem
      fi

      # main nginx config
      mkdir -p /opt/docker/nginx || true
      cat > /opt/docker/nginx/nginx.conf << 'EOF'
      user nginx;
      worker_processes auto;

      error_log  /var/log/nginx/error.log warn;
      pid        /var/run/nginx.pid;

      events {
        worker_connections  1024;
      }

      http {
        server {
          listen 80;
          server_name ${var.dns_hostname};
          server_tokens off;

          location /.well-known/acme-challenge/ {
            root /etc/letsencrypt/www;
          }

          location / {
            return 301 https://$server_name$request_uri;
          }
        }

        server {
          listen 443 ssl;
          server_name ${var.dns_hostname};
          server_tokens off;

          ssl_certificate /etc/letsencrypt/live/${var.dns_hostname}/fullchain.pem;
          ssl_certificate_key /etc/letsencrypt/live/${var.dns_hostname}/privkey.pem;
          include /etc/letsencrypt/options-ssl-nginx.conf;
          ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

          location / {
            proxy_pass          http://wordpress:80;
            proxy_set_header    Host                $http_host;
            proxy_set_header    X-Real-IP           $remote_addr;
            proxy_set_header    X-Forwarded-For     $proxy_add_x_forwarded_for;
          }
        }
      }
      EOF
      EOT
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/nginx_config.sh",
      "sudo /tmp/nginx_config.sh",
    ]
  }

  depends_on = [time_sleep.wait_for_vm]
}
# ======================================================================================================================

# ======================================================================================================================
# configure docker provider
provider "docker" {
  host     = "ssh://wordpress@${var.dns_hostname}:2222"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-i", "ssh_key_id_rsa"]
}

# ======================================================================================================================
# configure docker resources: images, networks, volumes
data "docker_registry_image" "mariadb" {
  name       = "mariadb:10-jammy"
  depends_on = [time_sleep.wait_for_vm]
}

resource "docker_image" "mariadb" {
  name          = data.docker_registry_image.mariadb.name
  pull_triggers = [data.docker_registry_image.mariadb.sha256_digest]
}

data "docker_registry_image" "wordpress" {
  name       = "wordpress:6-apache"
  depends_on = [time_sleep.wait_for_vm]
}

resource "docker_image" "wordpress" {
  name          = data.docker_registry_image.wordpress.name
  pull_triggers = [data.docker_registry_image.wordpress.sha256_digest]
}

data "docker_registry_image" "nginx" {
  name       = "nginx:1.23"
  depends_on = [time_sleep.wait_for_vm]
}

resource "docker_image" "nginx" {
  name          = data.docker_registry_image.nginx.name
  pull_triggers = [data.docker_registry_image.nginx.sha256_digest]
}

resource "docker_volume" "mariadb" {
  name       = "mariadb"
  depends_on = [time_sleep.wait_for_vm]
}

resource "docker_network" "wordpress" {
  name       = "wordpress"
  driver     = "bridge"
  depends_on = [time_sleep.wait_for_vm]
}
# ======================================================================================================================

# ======================================================================================================================
# mariadb container
resource "docker_container" "mariadb" {
  name     = "mariadb"
  image    = docker_image.mariadb.image_id
  command  = ["--default-authentication-plugin=mysql_native_password"]
  hostname = "mariadb"

  restart = "always"
  start   = true

  env = [
    "MYSQL_ROOT_PASSWORD=rootwordpress",
    "MYSQL_DATABASE=wordpress",
    "MYSQL_USER=wordpress",
    "MYSQL_PASSWORD=wordpress"
  ]

  mounts {
    target = "/var/lib/mysql"
    source = docker_volume.mariadb.name
    type   = "volume"
  }

  networks_advanced {
    name = docker_network.wordpress.id
  }
}

# wordpress container
resource "docker_container" "wordpress" {
  name     = "wordpress"
  image    = docker_image.wordpress.image_id
  hostname = "wordpress"

  restart = "always"
  start   = true

  env = [
    "WORDPRESS_DB_HOST=mariadb",
    "WORDPRESS_DB_USER=wordpress",
    "WORDPRESS_DB_PASSWORD=wordpress",
    "WORDPRESS_DB_NAME=wordpress"
  ]

  networks_advanced {
    name = docker_network.wordpress.id
  }

  depends_on = [docker_container.mariadb]
}

# nginx container
resource "docker_container" "nginx" {
  name     = "nginx"
  image    = docker_image.nginx.image_id
  hostname = "nginx"

  restart = "always"
  start   = true

  ports {
    internal = 80
    external = 8080
  }
  ports {
    internal = 443
    external = 8443
  }

  volumes {
    container_path = "/etc/nginx/nginx.conf"
    host_path      = "/opt/docker/nginx/nginx.conf"
    read_only      = true
  }
  volumes {
    container_path = "/etc/letsencrypt/"
    host_path      = "/opt/docker/letsencrypt"
    read_only      = true
  }

  networks_advanced {
    name = docker_network.wordpress.id
  }

  depends_on = [
    docker_container.wordpress,
    null_resource.config_data
  ]
}
# ======================================================================================================================
