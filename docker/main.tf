# ======================================================================================================================
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
  required_version = ">= 1.2.0"
}

# configure docker provider
provider "docker" {
  host     = "ssh://wordpress@${var.dns_hostname}:2222"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-i", "../ssh_key_id_rsa"]
}
# ======================================================================================================================

# ======================================================================================================================
# create nginx and certbot configuration data
resource "null_resource" "config_data" {
  # triggers = {
  #   always_run = "${timestamp()}"
  # }

  connection {
    type        = "ssh"
    user        = "wordpress"
    private_key = file("../ssh_key_id_rsa")
    host        = var.dns_hostname
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
            proxy_set_header    Host                  $http_host;
            proxy_set_header    X-Real-IP             $remote_addr;
            proxy_set_header    X-Forwarded-For       $proxy_add_x_forwarded_for;
            proxy_set_header    X-Forwarded-Proto     $scheme;
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
}
# ======================================================================================================================

# ======================================================================================================================
# configure docker resources: images, networks, volumes
data "docker_registry_image" "mariadb" {
  name       = var.docker_image_mariadb
  depends_on = [null_resource.config_data]
}

resource "docker_image" "mariadb" {
  name          = data.docker_registry_image.mariadb.name
  pull_triggers = [data.docker_registry_image.mariadb.sha256_digest]
}

data "docker_registry_image" "wordpress" {
  name       = var.docker_image_wordpress
  depends_on = [null_resource.config_data]
}

resource "docker_image" "wordpress" {
  name          = data.docker_registry_image.wordpress.name
  pull_triggers = [data.docker_registry_image.wordpress.sha256_digest]
}

data "docker_registry_image" "nginx" {
  name       = var.docker_image_nginx
  depends_on = [null_resource.config_data]
}

resource "docker_image" "nginx" {
  name          = data.docker_registry_image.nginx.name
  pull_triggers = [data.docker_registry_image.nginx.sha256_digest]
}

resource "docker_volume" "mariadb" {
  name       = "mariadb"
  depends_on = [null_resource.config_data]
}

resource "docker_network" "wordpress" {
  name       = "wordpress"
  driver     = "bridge"
  depends_on = [null_resource.config_data]
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

# ======================================================================================================================
# configure certbot to manage letsencrypt certificates
resource "null_resource" "certbot" {
  # triggers = {
  #   always_run = "${timestamp()}"
  # }

  connection {
    type        = "ssh"
    user        = "wordpress"
    private_key = file("../ssh_key_id_rsa")
    host        = var.dns_hostname
    port        = 2222
    timeout     = "10m"
  }

  provisioner "file" {
    destination = "/tmp/certbot.sh"
    content     = <<-EOT
      #!/bin/bash

      # certbot data does not yet exist?
      if [ ! -e "/opt/docker/letsencrypt/www" ]; then
        rm -rf /opt/docker/letsencrypt/live/* || true
        rm -rf /opt/docker/letsencrypt/archive/* || true
        rm -rf /opt/docker/letsencrypt/renewal/* || true

        mkdir /opt/docker/letsencrypt/www || true
        certbot certonly --webroot \
          -w /opt/docker/letsencrypt/www \
          -d "${var.dns_hostname}" \
          --config-dir /opt/docker/letsencrypt \
          --server "${var.lets_encrypt_server}" \
          --rsa-key-size 4096 \
          --register-unsafely-without-email \
          --agree-tos \
          --force-renewal
      fi

      mkdir -p /opt/docker || true
      cat > /opt/docker/cert_renewal.sh << 'EOF'
      #!/bin/bash

      certbot renew --config-dir /opt/docker/letsencrypt && docker restart nginx
      EOF
      chmod +x /opt/docker/cert_renewal.sh

      crontab << EOF
      15 3 * * * /opt/docker/cert_renewal.sh >/dev/null 2>&1
      EOF

      docker restart nginx
      EOT
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/certbot.sh",
      "sudo /tmp/certbot.sh",
    ]
  }

  depends_on = [docker_container.nginx]
}
# ======================================================================================================================
