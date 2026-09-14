SHELL := /bin/bash

ANS_DIR := ansible

.PHONY: ansible-setup ansible-check ansible-backup-cron backup-postgres backup-mariadb

ansible-setup:
	cd $(ANS_DIR) && ansible-galaxy collection install community.postgresql community.mysql community.general
	cd $(ANS_DIR) && ansible-playbook -i inventory.ini local-databases.yml --ask-become-pass

ansible-check:
	cd $(ANS_DIR) && ansible-playbook -i inventory.ini local-databases.yml --check --ask-become-pass

ansible-backup-cron:
	cd $(ANS_DIR) && ansible-playbook -i inventory.ini backup-cron.yml --ask-become-pass

backup-postgres:
	./backup-postgres.sh

backup-mariadb:
	./backup-mariadb.sh
