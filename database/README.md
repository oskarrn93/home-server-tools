# Local Database Setup

PostgreSQL, MariaDB, and Valkey are installed directly on the host (not in Docker) by the Ansible
playbook in `ansible/`, for easier OS-managed upgrades. Every app database on the server lives on
these shared instances. There is no Docker Compose stack in this directory.

- `ansible/local-databases.yml` - installs/configures the three servers and creates every app
  database, user, and ACL (including Uptime Kuma's MariaDB database and the backup users). See
  `ansible/README.md`.
- `ansible/backup-cron.yml` - schedules the nightly backups below.
- `backup-postgres.sh` / `backup-mariadb.sh` (+ shared `backup-lib.sh`) - the backups themselves.

## Quick start

```bash
cd /home/oskar/github/home-server-tools/database
make ansible-setup        # install collections + run local-databases.yml
make ansible-check        # dry run
make ansible-backup-cron  # install the nightly cron jobs
```

## Connection details

All usernames, passwords, and database names live in `ansible/vars/local-databases.yml`
(gitignored). Apps in Docker reach the servers at `host.docker.internal` (PostgreSQL `5432`,
MariaDB `3306`, Valkey `6379`); the playbook's final task lists which variables go into which app's
env file, without printing the secrets.

## Backups

`backup-postgres.sh` and `backup-mariadb.sh` dump **every** database on their server into
`$BACKUP_ROOT/postgres/<timestamp>/` and `$BACKUP_ROOT/mariadb/<timestamp>/` (this host:
`/mnt/hdd3/Backup/Database`), keeping the most recent 7 runs each:

- PostgreSQL: `globals.sql` (roles/tablespaces, no passwords) plus one custom-format
  `<db>.dump` per database.
- MariaDB: one gzipped `<db>.sql.gz` per database (users/grants are recreated by Ansible).

They run as read-only `backup` users (PostgreSQL `pg_read_all_data`, MariaDB
`SELECT,SHOW VIEW,TRIGGER,LOCK TABLES,EVENT`) whose credentials `local-databases.yml` writes to
`backup.env` (gitignored, mode 0600). Dumps are written owner-only into a hidden `.partial`
directory and only renamed into place once every database dumped, so a failed run never replaces
a good one in the retained set.

They're separate scripts (and cron jobs, 03:00 and 03:10) so one server's failure doesn't block
the other's.

Valkey is intentionally **not** backed up - it only holds cache/queue/broker data (SearXNG's query
cache, Immich's BullMQ job queue, Paperless-ngx's task broker, LiteLLM's response cache).

Backups currently stay on this machine (a separate disk). Copy `$BACKUP_ROOT` off-host too
(e.g. rclone/restic to cloud storage or another machine) to survive losing the server itself.

Run manually:

```bash
cd /home/oskar/github/home-server-tools/database
make backup-postgres
make backup-mariadb
```

### Alerting on failure

On success each script pushes `backup_last_success_timestamp_seconds` and
`backup_duration_seconds` (labeled `database="postgres"`/`"mariadb"`) to `server-observability`'s
Pushgateway (`BACKUP_PUSHGATEWAY_URL`, default `http://localhost:9092`). A failed run never pushes,
so the `DatabaseBackupStale` rule in `server-observability/prometheus-rules/database-alerts.yaml`
(no successful push in 26h) catches both failed dumps and a cron job that stopped running.

### Restoring

- **PostgreSQL** (as a superuser, e.g. `sudo -u postgres`):
  ```bash
  psql -d postgres -f <ts>/globals.sql      # only if the roles are missing
  createdb -O <owner> <db>
  pg_restore -d <db> --no-owner --role=<owner> <ts>/<db>.dump
  ```
- **MariaDB** (as root): `gunzip -c <ts>/<db>.sql.gz | sudo mysql`
