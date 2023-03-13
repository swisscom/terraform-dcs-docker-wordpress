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
  + [Requirements](#requirements)
    - [DCS+ resources](#dcs-resources)
      * [Virtual Data Center](#virtual-data-center)
      * [Edge Gateway](#edge-gateway)
      * [API User](#api-user)
    - [Local CLI tools](#local-cli-tools)
  + [Configuration](#configuration)
  + [Installation](#installation)

## WordPress with Docker

This Terraform module supports you in deploying a WordPress installation with [Docker](https://www.docker.com/) on [Swisscom DCS+](https://www.swisscom.ch/en/business/enterprise/offer/cloud/cloudservices/dynamic-computing-services.html) infrastructure.

It consists of two different submodules, [infrastructure](/infrastructure/) and [docker](/docker/).

The **infrastructure** module will provision resources on DCS+ and setup a private internal network (10.10.0.0/24 CIDR by default), attach an Edge Gateway with an external public IP, configure NAT and firewall services, setup a virtual machine, attach it to the private network, and then install and configure Docker on it.

The **docker** module will then connect via SSH to the Docker host and deploy a WordPress container, along with MariaDB and Nginx on it. It will also setup automatic TLS certificates using certbot and Let's Encrypt.

The final result is a fully functioning WordPress deployment, having MariaDB as a database backend, accessible via HTTPS and with automatic TLS certificate management.

### Components

| Component | Type | Description |
| --- | --- | --- |
| [WordPress](https://wordpress.org/) | CMS | Content management system, for creating blogs or building websites |
| [MariaDB](https://mariadb.org/) | Database | The "MySQL" database backend for WordPress |
| [Nginx](https://www.nginx.com/) | Webserver | Acts as a reverse proxy in front of WordPress |
| [certbot](https://certbot.eff.org/) | Certificates | Automated TLS certificate management using [Let's Encrypt](https://letsencrypt.org/) |

## How to deploy

### Requirements

To use this Terraform module you will need to have a valid account / contract number on [Swisscom DCS+](https://dcsguide.scapp.swisscom.com/).

Configure your contract number (PRO-number) in `terraform.tfvars -> vcd_org`.

#### DCS+ resources

For deploying WordPress with Docker on DCS+ you will need to manually create the following resources first before you can proceed:
- a Virtual Data Center (also called Dynamic Data Center / DDC on DCS+)
- an Edge Gateway with Internet in your VDC/DDC
- an API User

#### Virtual Data Center

Login to the DCS+ management portal and go to [Catalog](https://portal.swisscomcloud.com/catalog/). From there you can order a new **Dynamic Data Center**. Pick the appropriate *"Service Level"* you want.

See the official DCS+ documentation on [Dynamic Data Center](https://dcsguide.scapp.swisscom.com/ug3/dcs_portal.html#dynamic-data-center) for more information.

Configure the name of your newly created DDC in `terraform.tfvars -> vcd_vdc`.

#### Edge Gateway

Login to the DCS+ management portal and go to [My Items](https://portal.swisscomcloud.com/my-items/) view. From here click on the right hand side on *"Actions"* and then select **Create Internet Access** for your *Dynamic Data Center*. Make sure to check the box *"Edge Gateway"* and then fill out all the other values. For *"IP Range Size"* you can select the smallest value available, this Terraform module will only need one public IP for external connectivity. On *"Edge Gateway Configuration"* it is important that you select the **Large** configuration option to create an Edge Gateway with an advanced feature set, otherwise it might be missing some features and not function correctly!

See the official DCS+ documentation on [Create Internet Access](https://dcsguide.scapp.swisscom.com/ug3/dcs_portal.html#internet-access) for more information.

Configure the name of this Edge Gateway in `terraform.tfvars -> vcd_edgegateway`.

> **Note**: Also have a look in the vCloud Director web UI and check what the external/public IP assigned to this newly created Edge Gateway is by going to its **Configuration -> Gateway Interfaces** page and looking for the **Primary IP**. You will need this IP to set up a DNS *A* record with it.

#### API User

Login to the DCS+ management portal and go to [Catalog](https://portal.swisscomcloud.com/catalog/). From there you can order a new **vCloudDirector API User**. Make sure to leave *"Read only user?"* unchecked, otherwise your new API user will not be able to do anything!

See the official DCS+ documentation on [Cloud Director API Users](https://dcsguide.scapp.swisscom.com/ug3/dcs_portal.html#cloud-director-api-user) for more information.

Configure the new API username and password in `terraform.tfvars` at `vcd_api_username` and `vcd_api_password`.
Make sure you also set the API URL at `vcd_api_url`. Check out the official DCS+ documentation on how to determine the API URL value, see [Cloud Director API - API access methods](https://dcsguide.scapp.swisscom.com/ug3/vcloud_director.html#api-access-methods).

#### Local CLI tools

For deploying this Terraform module you will need to have all the following CLI tools installed on your machine:
- [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- [curl](https://curl.se/)
- [git](https://git-scm.com/)

This module has so far only been tested running under Linux and MacOSX. Your experience with Windows tooling may vary.

### Configuration



### Installation
