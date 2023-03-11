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
.PHONY: all
## all: provision all infrastructure, docker and the entire wordpress deployment
all: infrastructure docker

.PHONY: destroy
## destroy: delete and cleanup all deployments and infrastructure
destroy: docker-destroy infrastructure-destroy

.PHONY: check-env
## check-env: verifies working environment meets all requirements
check-env:
	which terraform
	test -f "infrastructure/ubuntu-22.04-server-cloudimg-amd64.ova" || wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.ova -O "infrastructure/ubuntu-22.04-server-cloudimg-amd64.ova"
	test -f "ssh_key_id_rsa" || ssh-keygen -t rsa -b 4096 -f "ssh_key_id_rsa" -N ''
	ssh-add "ssh_key_id_rsa"
# ======================================================================================================================

# ======================================================================================================================
.PHONY: infrastructure
## infrastructure: provision all infrastructure
infrastructure: check-env infrastructure-init infrastructure-apply

.PHONY: infrastructure-init
## infrastructure-init: initialize terraform
infrastructure-init:
	cd infrastructure && terraform init -var-file=../terraform.tfvars

.PHONY: infrastructure-check
## infrastructure-check: validate and check terraform configuration
infrastructure-check:
	cd infrastructure && terraform validate
	cd infrastructure && terraform plan -var-file=../terraform.tfvars

.PHONY: infrastructure-apply
## infrastructure-apply: apply terraform configuration and provision infrastructure
infrastructure-apply:
	cd infrastructure && terraform apply -auto-approve -var-file=../terraform.tfvars

.PHONY: infrastructure-destroy
## infrastructure-destroy: delete and cleanup infrastructure
infrastructure-destroy:
	cd infrastructure && terraform destroy -var-file=../terraform.tfvars
# ======================================================================================================================

# ======================================================================================================================
.PHONY: docker
## docker: provision docker and all of wordpress
docker: check-env docker-init docker-apply

.PHONY: docker-init
## docker-init: initialize terraform
docker-init:
	cd docker && terraform init -var-file=../terraform.tfvars

.PHONY: docker-check
## docker-check: validate and check terraform configuration
docker-check:
	cd docker && terraform validate
	cd docker && terraform plan -var-file=../terraform.tfvars

.PHONY: docker-apply
## docker-apply: apply terraform configuration, provision docker and wordpress deployment
docker-apply:
	cd docker && terraform apply -auto-approve -var-file=../terraform.tfvars

.PHONY: docker-destroy
## docker-destroy: delete and cleanup deployment
docker-destroy:
	cd docker && terraform destroy -var-file=../terraform.tfvars
# ======================================================================================================================
