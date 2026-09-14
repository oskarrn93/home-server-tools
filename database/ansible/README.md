# Ansible: local database setup

Installs and configures PostgreSQL, MariaDB, and Valkey directly on this host, and wires up
monitoring for them in the sibling `server-observability` repo.

This directory also has `backup-cron.yml`, which schedules `../backup-postgres.sh` and `../backup-mariadb.sh` via
cron - see `../README.md`'s "Backups" section. (Host kernel tuning moved to `../../host/`.)

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
- Installs `pgvector` and [VectorChord](https://github.com/tensorchord/VectorChord)
  (`vectorchord_version` in `vars/local-databases.yml`) for PostgreSQL and preloads `vchord` via
  `shared_preload_libraries`, since Immich requires it for embeddings search.
- Opens PostgreSQL (5432), MariaDB (3306), and Valkey (6379) to the Docker bridge network
  (`docker_network` in `vars/local-databases.yml`) via bind-address/listen_addresses changes and
  UFW rules, so containers in `server-observability` can reach them at the Docker gateway IP
  (`docker_gateway_ip`, `172.17.0.1`). The servers listen on all interfaces, so the playbook
  refuses to run unless `ufw status` reports active - it deliberately doesn't enable UFW itself,
  since that could cut off SSH or other host services.
- Creates the generic `app` database/user for PostgreSQL (`CREATEDB`, not superuser) and
  MariaDB, and sets root passwords.
- Creates one PostgreSQL database + owner role per app (`postgres_app_databases` in the playbook:
  Immich, Mealie, Paperless-ngx, LiteLLM, Seerr, Pocket ID, tinyauth), with the `vchord` and
  `earthdistance` extensions enabled in Immich's database.
- Creates Uptime Kuma's MariaDB database/user (`uptime_kuma_db_*`, formerly a separate Terraform
  stack) and writes `uptime-kuma.env` into `server-observability`.
- Creates Valkey ACL users (`valkey_acl_users`: SearXNG, Immich, Paperless-ngx, LiteLLM, and the
  Prometheus exporter) that each app selects its own db index into - Valkey ACL has no
  per-database restriction, so that isolation is by convention, not enforcement.
- Creates read-only `backup` users (PostgreSQL `pg_read_all_data`; MariaDB
  `SELECT,SHOW VIEW,TRIGGER,LOCK TABLES,EVENT`, socket-only) and writes `../backup.env` (0600)
  for the nightly backup scripts.
- Creates read-only monitoring users for Prometheus (`postgres_exporter`, `mysqld_exporter`,
  a Valkey ACL user) and `grafana` users (Postgres: `pg_read_all_data`; MariaDB: global `SELECT`)
  used by the dashboards/data sources in `server-observability`.
- Creates a personal PostgreSQL superuser for Oskar (`postgres_admin_user`, default `oskar`) with
  `CREATEDB,SUPERUSER`, used to log into pgAdmin (`home-server-tools/pgadmin`) and see/administer
  every database on the instance.
- Configures a Valkey `aclfile` (`/etc/valkey/users.acl`) so ACL users created above survive a
  Valkey restart/reboot instead of only living in memory.
- Writes the Prometheus exporter credential files (`postgres-exporter.env`,
  `mysqld-exporter.my.cnf`, `redis-exporter.env`) directly into `server-observability`.
- Ends by listing which `vars/local-databases.yml` variables go into which app's env file (e.g.
  the Grafana credentials for `server-observability/terraform.tfvars`) - variable names only,
  never the secret values.

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

## Backup scheduling (`backup-cron.yml`)

Installs one cron job per database (`../backup-postgres.sh` at 03:00, `../backup-mariadb.sh` at
03:10, staggered so they don't contend for I/O at the same instant) for the `oskar` user.
Requires `../backup.env` to already exist (written by `local-databases.yml`) - this playbook only
schedules the scripts.
Valkey has no backup job - see `../README.md`'s "Backups" section for why.

Run it the same way as the database playbook:

```bash
cd /home/oskar/github/home-server-tools/database/ansible
ansible-playbook -i inventory.ini backup-cron.yml --ask-become-pass
```
