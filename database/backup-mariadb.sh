#!/usr/bin/env bash
#
# Nightly backup of every database on the host-installed MariaDB instance
# provisioned by ansible/local-databases.yml (Uptime Kuma's kuma, app, ...).
#
# Usage:
#   cd database && ./backup-mariadb.sh
#   (or: make backup-mariadb)
#
# Connects as the read-only backup user from backup.env, which
# ansible/local-databases.yml writes. Each run produces
# $BACKUP_ROOT/mariadb/<timestamp>/ containing:
#   <db>.sql.gz    one gzipped dump per database (with CREATE DATABASE)
# and keeps the most recent 7 runs. See backup-lib.sh for atomicity/alerting.
# Users/grants aren't dumped - ansible/local-databases.yml recreates them.
#
# Restore one database (as root):
#   gunzip -c <ts>/<db>.sql.gz | mysql

source "$(dirname "${BASH_SOURCE[0]}")/backup-lib.sh"

load_backup_env
require_cmds mysql mysqldump gzip curl
require_vars MARIADB_USER MARIADB_PASSWORD

export MYSQL_PWD="$MARIADB_PASSWORD"
CONN=(-h "${MARIADB_HOST:-localhost}" -P "${MARIADB_PORT:-3306}" -u "$MARIADB_USER" --skip-ssl-verify-server-cert)

mapfile -t DATABASES < <(mysql "${CONN[@]}" -NBe "SHOW DATABASES" \
  | grep -vxE 'information_schema|performance_schema|sys|mysql')
[[ ${#DATABASES[@]} -gt 0 ]] || die "Could not list MariaDB databases as $MARIADB_USER"

begin_backup mariadb

for db in "${DATABASES[@]}"; do
  echo "    $db"
  mysqldump "${CONN[@]}" \
    --single-transaction --routines --events --triggers --no-tablespaces \
    --databases "$db" \
    | gzip > "$WORK_DIR/$db.sql.gz"
done

finish_backup mariadb
