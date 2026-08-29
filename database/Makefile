SHELL := /bin/bash

TF_DIR := terraform
ANS_DIR := ansible

.PHONY: docker-up docker-restart terraform-init terraform-plan terraform-apply terraform-destroy ansible-setup ansible-check

docker-up:
	docker compose up -d

docker-restart:
	docker compose down --volumes --remove-orphans
	docker compose up -d

terraform-init:
	cd $(TF_DIR) && terraform init

terraform-plan:
	cd $(TF_DIR) && terraform plan

terraform-apply:
	cd $(TF_DIR) && terraform apply

terraform-destroy:
	cd $(TF_DIR) && terraform destroy

ansible-setup:
	cd $(ANS_DIR) && ansible-galaxy collection install community.postgresql community.mysql community.general
	cd $(ANS_DIR) && ansible-playbook -i inventory.ini local-databases.yml

ansible-check:
	cd $(ANS_DIR) && ansible-playbook -i inventory.ini local-databases.yml --check
