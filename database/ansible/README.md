# Ansible: local database setup

Installs and configures PostgreSQL, MariaDB, and Valkey directly on this host, and wires up
monitoring for them in the sibling `server-observability` repo.

This directory also has `host-tuning.yml`, a small playbook for miscellaneous host-level
kernel/sysctl tuning unrelated to the databases (see below).

## Prerequisites

```bash
sudo apt-get update
sudo apt-get install -y ansible
ansible-galaxy collection install community.postgresql community.mysql community.general ansible.posix
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
  (`docker_gateway_ip`, `172.17.0.1`).
- Creates the app database/user for PostgreSQL and MariaDB, and sets root passwords.
- Creates a dedicated PostgreSQL database/user for Immich (`immich_db`/`immich_user`), with the
  `vchord` and `earthdistance` extensions enabled in that database, and a Valkey ACL user for
  Immich (`valkey_immich_user`) that the app selects its own db index into (`valkey_immich_db`) -
  Valkey ACL has no per-database restriction, so this isolation is by convention, not enforcement.
- Creates read-only monitoring users for Prometheus (`postgres_exporter`, `mysqld_exporter`,
  a Valkey ACL user) and `grafana` users (Postgres: `pg_read_all_data`; MariaDB: global `SELECT`)
  used by the dashboards/data sources in `server-observability`.
- Creates the Valkey ACL user for SearXNG (`searxng`, using db 1 the same way).
- Configures a Valkey `aclfile` (`/etc/valkey/users.acl`) so ACL users created above survive a
  Valkey restart/reboot instead of only living in memory.
- Writes `uptime-kuma.env` and the Prometheus exporter credential files
  (`postgres-exporter.env`, `mysqld-exporter.my.cnf`, `redis-exporter.env`) directly into
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

## Host tuning (`host-tuning.yml`)

Miscellaneous host kernel/sysctl tuning that isn't specific to the databases above. Currently:

- Raises `fs.inotify.max_user_watches` (to 1048576) and `fs.inotify.max_user_instances` (to 512)
  via `/etc/sysctl.d/99-inotify.conf`, applied immediately. The default watch limit (65536) is too
  low for Immich's library watcher on large photo libraries, which otherwise logs repeated
  `ENOSPC: System limit for number of file watchers reached` errors. This is a host kernel limit
  shared with all containers (inotify isn't namespaced), so it's fixed here rather than in
  `server-observability` or the Immich container config.

Run it the same way as the database playbook:

```bash
cd /home/oskar/github/home-server-tools/database/ansible
ansible-playbook host-tuning.yml --ask-become-pass
```
