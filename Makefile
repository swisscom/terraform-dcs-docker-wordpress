.DEFAULT_GOAL := help
SHELL := /bin/bash

# ======================================================================================================================
.PHONY: help
## help: prints this help message
help:
	@echo "Usage:"
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'
# ======================================================================================================================

# ======================================================================================================================
.PHONY: deploy
## deploy: provision all infrastructure, docker and the wordpress deployment
deploy: check-env terraform-init terraform-check terraform-apply

.PHONY: check-env
## check-env: verifies working environment meets all requirements
check-env:
	which terraform
	test -f "ubuntu-22.04-server-cloudimg-amd64.ova" || wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.ova -O ubuntu-22.04-server-cloudimg-amd64.ova
	test -f "ssh_key_id_rsa" || ssh-keygen -t rsa -b 4096 -f "ssh_key_id_rsa" -N ''

.PHONY: terraform-init
## terraform-init: initialize terraform
terraform-init:
	terraform init

.PHONY: terraform-check
## terraform-check: validate and check terraform configuration
terraform-check:
	terraform validate
	terraform plan

.PHONY: terraform-apply
## terraform-apply: apply terraform configuration, provision infrastructure and wordpress deployment
terraform-apply:
	terraform apply -auto-approve

.PHONY: terraform-destroy
## terraform-destroy: delete and cleanup deployment
terraform-destroy:
	terraform destroy
# ======================================================================================================================
