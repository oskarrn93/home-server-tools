# Local Database Setup

This directory contains three ways to manage the local database stack:

- Docker Compose for a local containerized stack
- Terraform for infrastructure/state management of the Docker-based stack (Uptime Kuma's MariaDB database only, now that Valkey is host-installed)
- Ansible for installing PostgreSQL, MariaDB, and Valkey directly on the host for easier future upgrades

## Quick start

From this directory you can use the bundled Makefile:

```bash
cd /home/oskar/github/home-server-tools/database
make docker-up
```

To reset the Docker stack completely and start over from scratch:

```bash
cd /home/oskar/github/home-server-tools/database
make docker-restart
```

## Docker Compose

Start the local Docker stack:

```bash
docker compose up -d
```

Stop it without deleting data:

```bash
docker compose down
```

Delete the containers and persisted volumes and recreate the stack from scratch:

```bash
docker compose down --volumes --remove-orphans
docker compose up -d
```

## Terraform

Install `tfenv` and pin Terraform to `1.16.0`:

```bash
git clone --depth=1 https://github.com/tfutils/tfenv.git ~/.tfenv
export PATH="$HOME/.tfenv/bin:$PATH"
# add to shell startup if desired
# echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
# echo 'eval "$(tfenv init -)"' >> ~/.bashrc
# source ~/.bashrc

tfenv install 1.16.0
tfenv use 1.16.0
terraform version
```

Then in this directory:

```bash
cd /home/oskar/github/home-server-tools/database/terraform
terraform init
terraform plan
terraform apply
```

Useful Makefile targets:

```bash
cd /home/oskar/github/home-server-tools/database
make terraform-init
make terraform-plan
make terraform-apply
make terraform-destroy
```

## Ansible

Install Ansible on Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install -y ansible
ansible-galaxy collection install community.postgresql community.mysql
```

Then run the local database playbook:

```bash
cd /home/oskar/github/home-server-tools/database/ansible
ansible-playbook -i inventory.ini local-databases.yml --ask-become-pass
```

If your account has passwordless sudo configured, you can also run:

```bash
sudo ansible-playbook -i inventory.ini local-databases.yml
```

Useful Makefile targets:

```bash
cd /home/oskar/github/home-server-tools/database
make ansible-setup
make ansible-check
```

This playbook will:

- install PostgreSQL, MariaDB, and Valkey
- start and enable the system services
- create the app database and users
- open PostgreSQL (5432), MariaDB (3306), and Valkey (6379) to the Docker bridge network (`docker_network` in `ansible/vars/local-databases.yml`) via bind-address/listen_addresses changes and UFW rules, so containers in `server-observability` can reach them at the Docker gateway IP
- create dedicated read-only `*_exporter` users/ACLs (Prometheus postgres_exporter/mysqld_exporter/redis_exporter) and `grafana` users (Postgres: `pg_read_all_data`; MariaDB: global `SELECT`) for the server-observability dashboards
- create a Valkey ACL user (`searxng`) restricted to db 1
- write the Prometheus exporter credential files (`postgres-exporter.env`, `mysqld-exporter.my.cnf`, `redis-exporter.env`) directly into `server-observability`
- print the local connection URLs, including the Grafana credentials to paste into `server-observability/terraform.tfvars`

## Connection details

The Ansible playbook defaults to:

- PostgreSQL: `postgresql://app:changeme@localhost:5432/app`
- MariaDB: `mysql://app:changeme@localhost:3307/app`
- Valkey: `valkey://localhost:6379` (default-user password set via `valkey_root_password`)

## Notes

- The Docker Compose stack in this repo is a good option for quick local testing and isolated services.
- The Terraform setup now only manages the Docker-based Uptime Kuma database bootstrap (`null_resource.uptime_kuma_database`); Valkey moved to the Ansible/host-installed path alongside Postgres and MariaDB.
- The Ansible setup is the preferred local-host approach if the goal is easier future upgrades and direct OS-managed database installs.
- MariaDB defaults to host port 3307 because a local service is already using 3306 on this machine.
- For a real production or long-lived server, prefer host-installed databases and package-managed upgrades over container-managed databases unless you specifically need the isolation benefits of containers.
