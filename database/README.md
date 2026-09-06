# Local Database Setup

This directory contains two ways to manage the local database stack:

- Ansible for installing PostgreSQL, MariaDB, and Valkey directly on the host for easier future upgrades
- Terraform for infrastructure/state management of the Docker-based stack (Uptime Kuma's MariaDB database only, now that Valkey is host-installed) - there is no Docker Compose stack in this directory; PostgreSQL/MariaDB/Valkey themselves are host-installed via the Ansible playbook below

## Quick start

From this directory you can use the bundled Makefile:

```bash
cd /home/oskar/github/home-server-tools/database
make ansible-setup
```

To dry-run the playbook without changing anything:

```bash
cd /home/oskar/github/home-server-tools/database
make ansible-check
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
- create a Valkey ACL user (`searxng`) restricted to db 1, plus per-service users/databases for Immich (db 2), Paperless-ngx (db 3), and LiteLLM (db 4)
- write the Prometheus exporter credential files (`postgres-exporter.env`, `mysqld-exporter.my.cnf`, `redis-exporter.env`) directly into `server-observability`
- print the local connection URLs, including the Grafana credentials to paste into `server-observability/terraform.tfvars`

## Connection details

The Ansible playbook defaults to:

- PostgreSQL: `postgresql://app:changeme@localhost:5432/app`
- MariaDB: `mysql://app:changeme@localhost:3306/app`
- Valkey: `valkey://localhost:6379` (default-user password set via `valkey_root_password`)

## Backups

`backup-postgres.sh` and `backup-mariadb.sh` each dump their respective app database into
timestamped directories under `$BACKUP_ROOT/postgres/` and `$BACKUP_ROOT/mariadb/`
(`BACKUP_ROOT` in `backup.env`, defaults to `./backups` next to the scripts; this host overrides
it to `/mnt/hdd3/Backup/Database`), keeping only the most recent 7 runs per database. They're
separate scripts (and separate cron jobs, see below) so one database's backup failing doesn't
block the other's.

Valkey is intentionally **not** backed up - it only holds cache/queue/broker data for the apps
here (SearXNG's query cache, Immich's BullMQ job queue, Paperless-ngx's task broker, LiteLLM's
response cache), none of which is durable state worth restoring; losing it just means caches
repopulate and in-flight jobs get re-queued.

Setup:

```bash
cd /home/oskar/github/home-server-tools/database
cp backup.env.example backup.env
# edit backup.env with the real app credentials (see "Connection details" above)
```

Run manually:

```bash
cd /home/oskar/github/home-server-tools/database
make backup-postgres
make backup-mariadb
# or: ./backup-postgres.sh / ./backup-mariadb.sh
```

Schedule both with the Ansible playbook (installs one cron job per database, staggered 10
minutes apart):

```bash
cd /home/oskar/github/home-server-tools/database/ansible
ansible-playbook -i inventory.ini backup-cron.yml --ask-become-pass
```

Or by hand via a crontab entry each (`crontab -e`):

```
0 3 * * * /home/oskar/github/home-server-tools/database/backup-postgres.sh >> /home/oskar/github/home-server-tools/database/backup-postgres.log 2>&1
10 3 * * * /home/oskar/github/home-server-tools/database/backup-mariadb.sh >> /home/oskar/github/home-server-tools/database/backup-mariadb.log 2>&1
```

### Alerting on failure

Both scripts act as their own dead-man's-switch via Prometheus Pushgateway: on success, each
pushes `backup_last_success_timestamp_seconds` and `backup_duration_seconds` (labeled
`database="postgres"`/`"mariadb"`) to `server-observability`'s `pushgateway` container
(`BACKUP_PUSHGATEWAY_URL` in `backup.env`, defaults to `http://localhost:9092`). A failed dump
never reaches the push, so the `DatabaseBackupStale` rule in
`server-observability/prometheus-rules/database-alerts.yaml` - which pages if no successful push
has landed in over 26h - catches both "the dump failed" and "the cron job stopped running
entirely" in one check, routed through the same Pushover notification as everything else in
`server-observability`.

No extra setup is needed beyond `BACKUP_PUSHGATEWAY_URL` in `backup.env` (or leaving it at its
default) - the pushgateway container just needs to be up (`docker compose up -d pushgateway` in
`server-observability`).

### Restoring from a dump

- **PostgreSQL**: `PGPASSWORD=<password> psql -h <host> -p <port> -U <user> -d <db> < $BACKUP_ROOT/postgres/<timestamp>/postgres.sql`
- **MariaDB**: `mysql -h <host> -P <port> -u <user> -p<password> <db> < $BACKUP_ROOT/mariadb/<timestamp>/mariadb.sql`

## Notes

- There is no Docker Compose stack in this directory - PostgreSQL, MariaDB, and Valkey are
  installed directly on the host by the Ansible playbook.
- The Terraform setup only manages the Docker-based Uptime Kuma database bootstrap
  (`null_resource.uptime_kuma_database`); Valkey moved to the Ansible/host-installed path
  alongside Postgres and MariaDB.
- The Ansible setup is the preferred local-host approach if the goal is easier future upgrades and direct OS-managed database installs.
- For a real production or long-lived server, prefer host-installed databases and package-managed upgrades over container-managed databases unless you specifically need the isolation benefits of containers.
