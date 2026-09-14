# shellcheck shell=bash
#
# Shared helpers for backup-postgres.sh and backup-mariadb.sh - sourced, not run.
#
# Each run dumps into a hidden "<root>/<kind>/.<timestamp>.partial" directory
# and only renames it to "<root>/<kind>/<timestamp>" once every dump succeeded,
# so a failed or killed run never counts toward the retained set (and gets
# cleaned up by the EXIT trap, or by the next run if it was SIGKILLed).
#
# Alerting: on success, pushes backup_last_success_timestamp_seconds and
# backup_duration_seconds (labeled database="<kind>") to the Prometheus
# Pushgateway (BACKUP_PUSHGATEWAY_URL, defaults to http://localhost:9092). The
# DatabaseBackupStale rule in
# server-observability/prometheus-rules/database-alerts.yaml fires if no
# successful push has landed in over 26h - covering both "the dump failed" and
# "the cron job stopped running entirely", since a failed run never pushes.

set -euo pipefail
# Dumps contain every app's data and password hashes - owner-only.
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_RUNS=7

die() {
  echo "$*" >&2
  exit 1
}

load_backup_env() {
  local env_file="$SCRIPT_DIR/backup.env"
  [[ -f "$env_file" ]] || die "Missing $env_file - run ansible/local-databases.yml (writes it) or copy backup.env.example."
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

require_cmds() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "$cmd not found"
  done
}

require_vars() {
  local var
  for var in "$@"; do
    [[ -n "${!var:-}" ]] || die "$var not set in backup.env"
  done
}

# begin_backup <kind>: sets KIND_ROOT, OUT_DIR and WORK_DIR (dump into WORK_DIR).
begin_backup() {
  local kind="$1"
  START_TIME="$(date +%s)"
  KIND_ROOT="${BACKUP_ROOT:-$SCRIPT_DIR/backups}/$kind"
  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  OUT_DIR="$KIND_ROOT/$timestamp"
  WORK_DIR="$KIND_ROOT/.$timestamp.partial"

  mkdir -p "$KIND_ROOT"
  rm -rf "$KIND_ROOT"/.*.partial
  mkdir "$WORK_DIR"
  trap 'rm -rf "$WORK_DIR"' EXIT
  echo "==> Backing up $kind to $OUT_DIR"
}

# finish_backup <kind>: publishes WORK_DIR, prunes old runs, pushes metrics.
finish_backup() {
  local kind="$1"
  mv "$WORK_DIR" "$OUT_DIR"
  trap - EXIT

  echo "==> Pruning old $kind backups (keeping last $KEEP_RUNS)"
  local old_runs old
  # shellcheck disable=SC2012  # timestamped dir names only
  mapfile -t old_runs < <(ls -1dt "$KIND_ROOT"/*/ 2>/dev/null | tail -n +$((KEEP_RUNS + 1)))
  for old in "${old_runs[@]}"; do
    echo "    removing $old"
    rm -rf "$old"
  done

  echo "==> Done: $OUT_DIR ($(du -sh "$OUT_DIR" | cut -f1))"

  local pushgateway_url="${BACKUP_PUSHGATEWAY_URL:-http://localhost:9092}"
  local end_time
  end_time="$(date +%s)"
  cat <<EOF | curl -fsS --max-time 10 --data-binary @- \
    "$pushgateway_url/metrics/job/database_backup/database/$kind" \
    || echo "    (failed to push metrics to $pushgateway_url)" >&2
# TYPE backup_last_success_timestamp_seconds gauge
backup_last_success_timestamp_seconds $end_time
# TYPE backup_duration_seconds gauge
backup_duration_seconds $((end_time - START_TIME))
EOF
}
