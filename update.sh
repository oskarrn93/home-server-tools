#!/usr/bin/env bash
# Pull new images and recreate changed containers.
# Usage: ./update.sh [stack...]   (default: all stacks, in dependency order)
set -euo pipefail

cd "$(dirname "$0")"

ALL_STACKS=(traefik auth ai portainer pgadmin it-tools openspeedtest healthcheck)
STACKS=("${@:-${ALL_STACKS[@]}}")

for stack in "${STACKS[@]}"; do
  [[ -f "$stack/docker-compose.yml" ]] || { echo "unknown stack: $stack" >&2; exit 1; }
  echo "=== $stack"
  (cd "$stack" && docker compose pull -q && docker compose up -d)
done

docker image prune -f >/dev/null

echo "=== not running/healthy:"
docker ps -a --filter status=exited --filter status=restarting --filter health=unhealthy \
  --format '{{.Names}}\t{{.Status}}'
