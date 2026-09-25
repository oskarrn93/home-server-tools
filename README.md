# home-server-tools

Infrastructure-as-config for the home server (`192.168.1.12`): Docker Compose stacks behind a
shared Traefik, host-installed databases managed by Ansible, and Terraform for app-level config
(OIDC clients, Ollama models). Each directory is deployed independently with
`docker compose up -d` from inside it.

| Directory | What it is |
|---|---|
| [`traefik/`](traefik/README.md) | Reverse proxy, Let's Encrypt wildcard cert, fail2ban/rate-limit/`lan-only` middlewares, and the public vs LAN-only hostname list |
| [`auth/`](auth/README.md) | Pocket ID (passkey OIDC provider) + tinyauth (forward-auth gate); `terraform/` manages the OIDC clients |
| [`ai/`](ai/.claude/CLAUDE.md) | Ollama, LiteLLM, Open WebUI, SearXNG; `terraform/` manages models |
| [`database/`](database/README.md) | Ansible for host PostgreSQL/MariaDB/Valkey and every app database; nightly backup scripts |
| [`pgadmin/`](pgadmin/README.md) | pgAdmin for the host PostgreSQL, Pocket ID login |
| `portainer/` | Portainer CE + agent |
| [`it-tools/`](it-tools/README.md) | IT Tools, behind tinyauth |
| `openspeedtest/` | OpenSpeedTest |
| `healthcheck/` | Tiny Go "OK" endpoint |
| [`host/`](host/README.md) | Host kernel/sysctl tuning playbook |

Monitoring (Prometheus, Grafana, Uptime Kuma) lives in the sibling `server-observability` repo and
the media apps in `media-services`.

## Conventions

- Secrets live in gitignored `*.env` / `.env` / `*.tfvars` files (mode `0600`) next to a committed
  `.example` counterpart.
- Services are exposed through Traefik only - no published host ports - and LAN-only routers list
  `lan-only@file` first. See `traefik/README.md` before adding a hostname.

## Updating images

Image tags are pinned and bumped by Dependabot PRs. After merging one, on the server:

```bash
git pull
./update.sh          # all stacks, in dependency order
./update.sh ai auth  # or only specific stacks
```

The script pulls, recreates only containers whose image changed, prunes old images, and lists any
container that is not running or healthy.
