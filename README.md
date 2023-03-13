# terraform-vcloud-docker-wordpress
[![Build](https://img.shields.io/github/actions/workflow/status/swisscom/terraform-dcs-docker-wordpress/master.yml?branch=master&label=Build)](https://github.com/swisscom/terraform-dcs-docker-wordpress/actions/workflows/master.yml)
[![License](https://img.shields.io/badge/License-Apache--2.0-lightgrey)](https://github.com/swisscom/terraform-dcs-docker-wordpress/blob/master/LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Docker-blue)](https://www.docker.com/)
[![IaC](https://img.shields.io/badge/IaC-Terraform-purple)](https://www.terraform.io/)

Deploy Wordpress with Docker on vCloud / [Swisscom DCS+](https://dcsguide.scapp.swisscom.com/)

-----

Table of Contents
=================
* [WordPress with Docker](#wordpress-with-docker)
  + [Components](#components)
* [How to deploy](#how-to-deploy)
  + [Configuration](#configuration)
  + [Installation](#installation)

## WordPress with Docker

This Terraform module supports you in deploying a WordPress installation with [Docker](https://www.docker.com/) on [Swisscom DCS+](https://www.swisscom.ch/en/business/enterprise/offer/cloud/cloudservices/dynamic-computing-services.html) infrastructure.

It consists of two different submodules, [infrastructure](/infrastructure/) and [docker](/docker/).

The **infrastructure** module will provision resources on DCS+ and setup a private internal network (10.10.0.0/24 CIDR by default), attach an Edge Gateway with an external public IP, configure NAT and firewall services, setup a virtual machine, attach it to the private network, and then install and configure Docker on it.

The **docker** module will then connect via SSH to the Docker host and deploy a WordPress container, along with MariaDB and Nginx on it. It will also setup automatic TLS certificates using [certbot](https://certbot.eff.org/) and [Let's Encrypt](https://letsencrypt.org/).

The final result is a fully functioning WordPress deployment, having MariaDB as a database backend, accessible via HTTPS and with automatic TLS certificate management.

### Components

| Component | Type | Description |
| --- | --- | --- |
| [WordPress](https://wordpress.org/) | CMS | Content management system, for creating blogs or building websites |
| [MariaDB](https://mariadb.org/) | Database | The "MySQL" database backend for WordPress |
| [Nginx](https://www.nginx.com/) | Webserver | Acts as a reverse proxy in front of WordPress |
| [certbot](https://certbot.eff.org/) | Certificates | Automated TLS certificate management using [Let's Encrypt](https://letsencrypt.org/) |

## How to deploy

### Configuration

### Installation
