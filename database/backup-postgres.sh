#!/usr/bin/env bash
#
# Nightly backup of every database on the host-installed PostgreSQL instance
# provisioned by ansible/local-databases.yml (Immich, Paperless-ngx, Mealie,
# Seerr, LiteLLM, Pocket ID, tinyauth, ...).
#
# Usage:
#   cd database && ./backup-postgres.sh
#   (or: make backup-postgres)
#
# Connects as the read-only backup role (pg_read_all_data) from backup.env,
# which ansible/local-databases.yml writes. Each run produces
# $BACKUP_ROOT/postgres/<timestamp>/ containing:
#   globals.sql   roles and tablespaces (without passwords)
#   <db>.dump     one custom-format (compressed) dump per database
# and keeps the most recent 7 runs. See backup-lib.sh for atomicity/alerting.
#
# Restore one database (as a superuser, e.g. postgres):
#   psql -d postgres -f <ts>/globals.sql            # only if roles are missing
#   createdb -O <owner> <db>
#   pg_restore -d <db> --no-owner --role=<owner> <ts>/<db>.dump

source "$(dirname "${BASH_SOURCE[0]}")/backup-lib.sh"

load_backup_env
require_cmds pg_dump pg_dumpall psql curl
require_vars POSTGRES_USER POSTGRES_PASSWORD

export PGHOST="${POSTGRES_HOST:-localhost}"
export PGPORT="${POSTGRES_PORT:-5432}"
export PGUSER="$POSTGRES_USER"
export PGPASSWORD="$POSTGRES_PASSWORD"

mapfile -t DATABASES < <(psql -XAt -d postgres \
  -c "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY 1")
[[ ${#DATABASES[@]} -gt 0 ]] || die "Could not list PostgreSQL databases as $PGUSER@$PGHOST:$PGPORT"

begin_backup postgres

pg_dumpall --globals-only --no-role-passwords -f "$WORK_DIR/globals.sql"
for db in "${DATABASES[@]}"; do
  echo "    $db"
  pg_dump -d "$db" -F c -f "$WORK_DIR/$db.dump"
done

finish_backup postgres
