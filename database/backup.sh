#!/usr/bin/env bash
#
# Simple timestamped backup for the host-installed PostgreSQL, MariaDB, and
# Valkey databases provisioned by ansible/local-databases.yml.
#
# Usage:
#   cd database && ./backup.sh
#   (or: make backup)
#
# Reads connection details from backup.env (gitignored - copy backup.env.example
# and fill in the real app credentials). Writes timestamped dumps into
# backups/<timestamp>/ and keeps only the most recent 7 timestamped runs.
#
# Restore:
#   PostgreSQL: PGPASSWORD=... psql -h <host> -p <port> -U <user> -d <db> < backups/<ts>/postgres.sql
#   MariaDB:    mysql -h <host> -P <port> -u <user> -p<password> <db> < backups/<ts>/mariadb.sql
#   Valkey:     stop valkey-server, copy backups/<ts>/valkey.rdb over the configured
#               `dir`/`dbfilename` (see `valkey-cli CONFIG GET dir` / `CONFIG GET dbfilename`
#               on the live server), then start valkey-server again.

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

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$SCRIPT_DIR/backups"
OUT_DIR="$BACKUP_ROOT/$TIMESTAMP"
mkdir -p "$OUT_DIR"

echo "==> Backing up to $OUT_DIR"

if command -v pg_dump >/dev/null 2>&1 && [[ -n "${POSTGRES_USER:-}" ]]; then
  echo "--> PostgreSQL ($POSTGRES_DB)"
  PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
    -h "${POSTGRES_HOST:-localhost}" \
    -p "${POSTGRES_PORT:-5432}" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -F p \
    -f "$OUT_DIR/postgres.sql"
else
  echo "--> Skipping PostgreSQL (pg_dump not found or POSTGRES_USER unset)"
fi

if command -v mysqldump >/dev/null 2>&1 && [[ -n "${MARIADB_USER:-}" ]]; then
  echo "--> MariaDB ($MARIADB_DATABASE)"
  MYSQL_PWD="$MARIADB_PASSWORD" mysqldump \
    -h "${MARIADB_HOST:-localhost}" \
    -P "${MARIADB_PORT:-3307}" \
    -u "$MARIADB_USER" \
    --single-transaction \
    "$MARIADB_DATABASE" \
    > "$OUT_DIR/mariadb.sql"
else
  echo "--> Skipping MariaDB (mysqldump not found or MARIADB_USER unset)"
fi

if command -v valkey-cli >/dev/null 2>&1 && [[ -n "${VALKEY_HOST:-}" ]]; then
  echo "--> Valkey (SAVE + copy RDB)"
  VALKEY_CLI=(valkey-cli --no-auth-warning -h "${VALKEY_HOST:-localhost}" -p "${VALKEY_PORT:-6379}")
  if [[ -n "${VALKEY_PASSWORD:-}" ]]; then
    VALKEY_CLI+=(-a "$VALKEY_PASSWORD")
  fi
  "${VALKEY_CLI[@]}" SAVE >/dev/null
  RDB_DIR="$("${VALKEY_CLI[@]}" CONFIG GET dir | tail -n1)"
  RDB_FILE="$("${VALKEY_CLI[@]}" CONFIG GET dbfilename | tail -n1)"
  if [[ -n "$RDB_DIR" && -n "$RDB_FILE" && -f "$RDB_DIR/$RDB_FILE" ]]; then
    # Requires read access to the Valkey data directory (e.g. run as root/valkey,
    # or via sudo) - copy fails silently skipped otherwise.
    cp "$RDB_DIR/$RDB_FILE" "$OUT_DIR/valkey.rdb" 2>/dev/null \
      || echo "    (could not read $RDB_DIR/$RDB_FILE - run with sufficient privileges to copy it)"
  else
    echo "    (could not determine Valkey RDB path via CONFIG GET)"
  fi
else
  echo "--> Skipping Valkey (valkey-cli not found or VALKEY_HOST unset)"
fi

echo "==> Pruning old backups (keeping last 7)"
mapfile -t OLD_BACKUPS < <(ls -1dt "$BACKUP_ROOT"/*/ 2>/dev/null | tail -n +8)
for old in "${OLD_BACKUPS[@]:-}"; do
  [[ -n "$old" ]] || continue
  echo "    removing $old"
  rm -rf "$old"
done

echo "==> Done: $OUT_DIR"
