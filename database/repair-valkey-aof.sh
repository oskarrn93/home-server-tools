#!/usr/bin/env bash
#
# Repair a corrupted Valkey append-only file (AOF) and bring Valkey back up.
#
# Usage:
#   cd database && ./repair-valkey-aof.sh [-y]
#   (or: make valkey-repair-aof)
#
# Symptom this fixes: valkey-server.service is "failed" after an unclean
# shutdown/power loss, and /var/log/valkey/valkey-server.log ends with
#   Bad file format reading the append only file appendonly.aof.<n>.incr.aof
#
# Steps:
#   1. Copies the AOF directory to <dir>/<appenddirname>.bak-<timestamp>.
#   2. Checks every incr file listed in the manifest; stops if all are valid
#      (then the failure is something else - check the log).
#   3. Runs valkey-check-aof --fix on the corrupted (last) incr file, which
#      truncates it at the first broken entry (it shows how many bytes and asks
#      first; -y answers yes). Only writes since the last base snapshot are at
#      risk - and Valkey only holds cache/queue/broker data here (see README.md).
#   4. Clears systemd's restart-limit state and starts valkey-server.
#
# The checker runs on the incr file, not the manifest the error message
# suggests: valkey-check-aof 9.0.4 doesn't recognize the VALKEY magic in the
# RDB base file, so manifest mode always reports the base as corrupt and
# refuses to fix anything.
#
# Re-runs itself with sudo, so you'll be asked for your password once.

# Bash-only (EUID, [[ ]], mapfile); re-exec under bash if started as `sh script`.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

CONF=/etc/valkey/valkey.conf
SERVICE=valkey-server
ASSUME_YES=false

die() {
  echo "$*" >&2
  exit 1
}

case "${1:-}" in
  -y | --yes) ASSUME_YES=true ;;
  "") ;;
  *) die "Usage: $0 [-y]" ;;
esac

if [[ $EUID -ne 0 ]]; then
  exec sudo -- "$(realpath "${BASH_SOURCE[0]}")" "$@"
fi

command -v valkey-check-aof >/dev/null 2>&1 || die "valkey-check-aof not found (package valkey-tools)"
[[ -f "$CONF" ]] || die "Missing $CONF"

# conf_value <key> <default>: last uncommented value of <key> in valkey.conf.
conf_value() {
  local value
  value="$(awk -v key="$1" '$1 == key { v = $2 } END { print v }' "$CONF" | tr -d '"')"
  echo "${value:-$2}"
}

DATA_DIR="$(conf_value dir /var/lib/valkey)"
AOF_DIR="$DATA_DIR/$(conf_value appenddirname appendonlydir)"
MANIFEST="$AOF_DIR/$(conf_value appendfilename appendonly.aof).manifest"

[[ -f "$MANIFEST" ]] || die "No AOF manifest at $MANIFEST - is appendonly enabled?"

if systemctl is-active --quiet "$SERVICE"; then
  echo "$SERVICE is running - nothing to repair."
  exit 0
fi
# A crash-looping unit may still be mid-restart; make sure nothing writes the AOF.
systemctl stop "$SERVICE"

BACKUP_DIR="$AOF_DIR.bak-$(date +%Y%m%d-%H%M%S)"
echo "==> Backing up $AOF_DIR to $BACKUP_DIR"
cp -a "$AOF_DIR" "$BACKUP_DIR"

# Incr files in manifest order ("file <name> seq <n> type i"); only the last
# one can be truncated without dropping the files written after it.
mapfile -t INCR_FILES < <(awk '$1 == "file" && $NF == "i" { print $2 }' "$MANIFEST")
[[ ${#INCR_FILES[@]} -gt 0 ]] || die "No incr files in $MANIFEST - the corruption is elsewhere, see the log."

BAD_FILE=""
for name in "${INCR_FILES[@]}"; do
  echo "==> Checking $name"
  if ! runuser -u valkey -- valkey-check-aof "$AOF_DIR/$name"; then
    BAD_FILE="$name"
    break
  fi
done

if [[ -z "$BAD_FILE" ]]; then
  echo
  echo "The AOF incr files are valid, so they're not why $SERVICE fails. Last log lines:"
  tail -n 20 /var/log/valkey/valkey-server.log
  die "Not repairing. (Backup left at $BACKUP_DIR - remove it if unneeded.)"
fi
[[ "$BAD_FILE" == "${INCR_FILES[-1]}" ]] ||
  die "$BAD_FILE is corrupt but isn't the last incr file - truncating it would drop the later ones. Fix manually; backup at $BACKUP_DIR"

echo
echo "==> Repairing $BAD_FILE (truncates the corrupted tail)"
# Exits non-zero if you answer "n" (or the fix fails), which stops the script.
if $ASSUME_YES; then
  echo y | runuser -u valkey -- valkey-check-aof --fix "$AOF_DIR/$BAD_FILE"
else
  runuser -u valkey -- valkey-check-aof --fix "$AOF_DIR/$BAD_FILE"
fi

echo "==> Starting $SERVICE"
systemctl reset-failed "$SERVICE"
systemctl start "$SERVICE"
systemctl is-active --quiet "$SERVICE" || die "$SERVICE failed to start - see: journalctl -u $SERVICE; tail /var/log/valkey/valkey-server.log"

echo
echo "$SERVICE is running again."
echo "Original AOF kept at $BACKUP_DIR - delete it once everything looks fine:"
echo "  sudo rm -r $BACKUP_DIR"
