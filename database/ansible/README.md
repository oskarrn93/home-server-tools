# Ansible: local database setup

Installs and configures PostgreSQL, MariaDB, and Valkey directly on this host, and wires up
monitoring for them in the sibling `server-observability` repo.

## Prerequisites

```bash
sudo apt-get update
sudo apt-get install -y ansible
ansible-galaxy collection install community.postgresql community.mysql community.general
```

## Run it

From this directory:

```bash
cd /home/oskar/github/home-server-tools/database/ansible
ansible-playbook -i inventory.ini local-databases.yml --ask-become-pass
```

You'll be prompted for your sudo password interactively (`become: true` is required for package
installs, service management, and editing files under `/etc`). If your account has passwordless
sudo configured, you can instead run:

```bash
sudo ansible-playbook -i inventory.ini local-databases.yml
```

This must be run in a real interactive terminal — it can't be driven non-interactively (e.g. by
an agent without a TTY), since `--ask-become-pass` needs a password typed at the prompt.

## What it does

- Installs `postgresql`, `mariadb-server`, `valkey-server` (+ client/tools packages) and enables
  their systemd services.
- Opens PostgreSQL (5432), MariaDB (3306), and Valkey (6379) to the Docker bridge network
  (`docker_network` in `vars/local-databases.yml`) via bind-address/listen_addresses changes and
  UFW rules, so containers in `server-observability` can reach them at the Docker gateway IP
  (`docker_gateway_ip`, `172.17.0.1`).
- Creates the app database/user for PostgreSQL and MariaDB, and sets root passwords.
- Creates read-only monitoring users for Prometheus (`postgres_exporter`, `mysqld_exporter`,
  a Valkey ACL user) and `grafana` users (Postgres: `pg_read_all_data`; MariaDB: global `SELECT`)
  used by the dashboards/data sources in `server-observability`.
- Creates the Valkey ACL user for SearXNG (`searxng`, restricted to db 1).
- Writes `uptime-kuma.env` and the three Prometheus exporter env files
  (`postgres-exporter.env`, `mysqld-exporter.env`, `redis-exporter.env`) directly into
  `server-observability`.
- Prints connection URLs at the end, including the Grafana credentials to paste into
  `server-observability/terraform.tfvars` (`postgres_grafana_user`/`password`,
  `mariadb_grafana_user`/`password`).

## Config

All variables (passwords, usernames, ports, file paths) live in `vars/local-databases.yml`.
That file contains plaintext secrets — never commit changes that print or log its contents.

## After running

In `server-observability`:

```bash
docker compose up -d postgres_exporter mysqld_exporter redis_exporter prometheus
terraform plan
terraform apply
```
