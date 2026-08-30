# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this directory.

## What this is

A Docker Compose stack for a local AI/LLM setup: Ollama (model runtime), SearXNG (private search, used as a web-search backend), Open WebUI (chat UI), and n8n plus its sandbox service (workflow automation with an AI code-execution sandbox). Previously part of the sibling `media-services` repo, moved here since it isn't media-specific. Almost everything is configuration (`docker-compose.yml`, `.env` files, YAML) rather than application code.

## Commands

No Makefile — plain `docker compose` v2 CLI, run from this directory:

```sh
docker compose up -d          # start/update the stack
docker compose up -d <service># start/recreate one service
docker compose logs -f <service>
docker compose config         # validate compose file
```

There's no linter or test suite; validate compose changes with `docker compose config`.

## Architecture

- **ollama**: model runtime, no web UI, HTTP API on `11434`. `ollama/Modelfile` is bind-mounted in.
- **searxng**: search backend, `settings.yml` bind-mounted read-only, healthcheck at `/healthz`. Used by both Open WebUI (`WEB_SEARCH_ENGINE=searxng`) and n8n's AI sandbox (`N8N_INSTANCE_AI_SEARXNG_URL`).
- **openwebui**: chat frontend, depends on `ollama` and `searxng` being healthy.
- **n8n**: depends on `ollama`, `searxng`, and `n8n-sandbox-api` being healthy. Wires its own AI sandbox provider to `n8n-sandbox-api` and its default LLM to Ollama via an OpenAI-compatible endpoint (`N8N_INSTANCE_AI_MODEL_URL: http://ollama:11434/v1`). Also configured to export OTEL traces to `host.docker.internal:4318` (the `otel-collector` in the sibling `server-observability` stack).
- **n8n-sandbox-tls-init / n8n-sandbox-api / n8n-sandbox-runner-1**: mTLS-secured sandbox execution service for n8n's AI code nodes. `n8n-sandbox-tls-init` bootstraps certs into the `n8n_sandbox_tls` volume before the API/runner start (`service_completed_successfully` dependency); the runner is `privileged` (Docker-in-Docker) to execute sandboxed code. `n8n-sandbox-api` has **no published host port** — it's internal-only, reachable from other containers on the `ai_default` network but not from the LAN/browser.
- **Traefik**: `searxng`, `openwebui`, and `n8n` are dual-homed on `default` and the external `traefik_internal` network with `traefik.*` labels for a `*.local.oskarrosen.io` route (`web` entrypoint); `openwebui` and `n8n` additionally get a public `*.oskarrosen.io` route (TLS via `lets_encrypt`, `web_secure` entrypoint) since they're meant to be reachable off-LAN. `searxng` stays local-only. Traefik itself runs elsewhere (sibling stack) — `traefik_internal` is `external: true`.
- **Monitoring/dashboard (external to this repo)**: Uptime Kuma and Homepage run in the sibling `server-observability` and `media-services` repos respectively, not here. Uptime Kuma reaches this stack's containers by joining the external `ai_default` network (declared in `server-observability/docker-compose.yaml`).

## Adding a new service

When adding a new service to `docker-compose.yml` here:

1. **Uptime Kuma monitor**: add an entry to the `ai_service_monitors` map in `server-observability/main.tf` (merged into `locals.monitor_targets`), pointing at the container's health/readiness endpoint over the `ai_default` network (e.g. `http://<service>:<port>/healthz`). Run `terraform apply` in `server-observability/` afterward. Skip only if the service has no HTTP endpoint to poll.
2. **Homepage link**: add an entry under the `AI` group in `media-services/homepage/config/services.yaml`, with `href: http://192.168.1.12:<port>` (only if a host port is published — internal-only services like `n8n-sandbox-api` get a monitor but no link), a short `description`, and an `icon:` (check [homepage's icon list](https://github.com/homarr-labs/dashboard-icons) before guessing). No restart needed — Homepage reads this file live.
3. **Prometheus scrape target**: if the service exposes a Prometheus-format `/metrics` endpoint, add a `scrape_configs` job for it in `server-observability/prometheus.yaml`, targeting `<service>:<port>`. As of this writing Prometheus is *not* on `ai_default` (only Uptime Kuma is) — the first time this is needed, also add `ai_default` to the `prometheus` service's `networks:` in `server-observability/docker-compose.yaml` so container names resolve, then `docker compose up -d prometheus`. `n8n` already exports OTLP metrics via `N8N_OTEL_ENABLED`/`N8N_OTEL_EXPORTER_OTLP_ENDPOINT`, covered by the existing `otel-collector` scrape job — don't double-add it. Skip if the service has no metrics endpoint and no OTLP export.
4. **Grafana dashboard**: if you added a scrape target, also add a dashboard JSON to `server-observability/grafana/dashboards/` and a matching `data "local_file"`/`resource "grafana_dashboard"` block in `server-observability/main.tf`, then `terraform apply`.

All four of these live in sibling repos, not here — cross-repo edits are expected for this checklist. See `server-observability/.claude/CLAUDE.md` for the full detail on steps 3–4.

## Secrets and untracked files

Every service with credentials has a `<service>.env` (or `.env`) file referenced via `env_file:`, gitignored, with a committed `.env.example` sibling listing the same keys blanked out (`n8n.env`, `n8n-sandbox.env`, `openwebui.env`, `searxng.env`, `.env`). When adding a new service that needs secrets, add both the real file and its `.example` counterpart.

Never print, log, or write the contents of any non-`.example` `*.env` file to files or command output.
