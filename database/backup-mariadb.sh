#!/usr/bin/env bash
#
# Timestamped backup of the host-installed MariaDB database provisioned by
# ansible/local-databases.yml.
#
# Usage:
#   cd database && ./backup-mariadb.sh
#   (or: make backup-mariadb)
#
# Reads connection details from backup.env (gitignored - copy backup.env.example
# and fill in the real app credentials). Writes timestamped dumps into
# backups/mariadb/<timestamp>/ and keeps only the most recent 7 timestamped runs.
#
# Restore:
#   mysql -h <host> -P <port> -u <user> -p<password> <db> < backups/mariadb/<ts>/mariadb.sql
#
# Alerting: on success, pushes backup_last_success_timestamp_seconds and
# backup_duration_seconds (labeled database="mariadb") to the Prometheus
# Pushgateway (BACKUP_PUSHGATEWAY_URL in backup.env, defaults to
# http://localhost:9092). The DatabaseBackupStale rule in
# server-observability/prometheus-rules/database-alerts.yaml fires if no
# successful push has landed in over 26h - covering both "the dump failed"
# and "the cron job stopped running entirely" in one check, since a failed
# run never reaches the push at all.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/backup.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE - copy backup.env.example to backup.env and fill in credentials." >&2
  exit 1
fi
# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

PUSHGATEWAY_URL="${BACKUP_PUSHGATEWAY_URL:-http://localhost:9092}"
START_TIME="$(date +%s)"

if ! command -v mysqldump >/dev/null 2>&1; then
  echo "mysqldump not found - is the mariadb-client package installed?" >&2
  exit 1
fi
if [[ -z "${MARIADB_USER:-}" ]]; then
  echo "MARIADB_USER not set in $ENV_FILE" >&2
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$SCRIPT_DIR/backups/mariadb"
OUT_DIR="$BACKUP_ROOT/$TIMESTAMP"
mkdir -p "$OUT_DIR"

echo "==> Backing up MariaDB ($MARIADB_DATABASE) to $OUT_DIR"
MYSQL_PWD="$MARIADB_PASSWORD" mysqldump \
  -h "${MARIADB_HOST:-localhost}" \
  -P "${MARIADB_PORT:-3307}" \
  -u "$MARIADB_USER" \
  --single-transaction \
  "$MARIADB_DATABASE" \
  > "$OUT_DIR/mariadb.sql"

echo "==> Pruning old MariaDB backups (keeping last 7)"
mapfile -t OLD_BACKUPS < <(ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | tail -n +8)
for old in "${OLD_BACKUPS[@]:-}"; do
  [[ -n "$old" ]] || continue
  echo "    removing $old"
  rm -rf "$old"
done

echo "==> Done: $OUT_DIR"

END_TIME="$(date +%s)"
cat <<EOF | curl -fsS --max-time 10 --data-binary @- \
  "$PUSHGATEWAY_URL/metrics/job/database_backup/database/mariadb" \
  || echo "    (failed to push metrics to $PUSHGATEWAY_URL)" >&2
# TYPE backup_last_success_timestamp_seconds gauge
backup_last_success_timestamp_seconds $END_TIME
# TYPE backup_duration_seconds gauge
backup_duration_seconds $((END_TIME - START_TIME))
EOF
