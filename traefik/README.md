# Traefik domains

All services are reachable at a single `*.oskarrosen.io` hostname namespace — there is no separate `.local.` subdomain. The same hostname resolves differently depending on where the client is:

- **LAN clients**: the UniFi console at `192.168.1.1` acts as the local DNS server and resolves every `*.oskarrosen.io` name to `192.168.1.12` (this host).
- **Off-LAN clients**: only a subset of names additionally have a public record in AWS Route53, pointing at the public IP/target that reaches this host. Everything else has no public record and simply won't resolve outside the LAN.

Every router — public and LAN-only alike — is declared on both `web` and `web_secure` (`entrypoints=web,web_secure`) with `tls=true` / `tls.certresolver=lets_encrypt`, so all hostnames get the same real Let's Encrypt wildcard cert (`*.oskarrosen.io`, via the `route53` DNS challenge) and work whether a client connects over plain HTTP or HTTPS. This matters because most modern browsers try HTTPS first for typed URLs regardless of what a link says — a LAN-only host with no `web_secure` router would 404 for those clients even though plain `http://` worked. There is no entrypoint-level HTTP→HTTPS redirect (removing one is what motivated always dual-registering routers instead): a global redirect on `web` would send LAN-only hosts to `web_secure` before their own router could even match.

Public vs. LAN-only is purely a DNS-resolution distinction (see tables below) — it has no effect on Traefik's router config anymore.

## Public (also defined in Route53)

| Domain | Service | Repo |
|---|---|---|
| `seerr.oskarrosen.io` | Seerr (media requests) | `media-services` |
| `n8n.oskarrosen.io` | n8n | `home-server-tools/ai` |
| `www.oskarrosen.io` | healthcheck | `home-server-tools/healthcheck` |

## LAN-only (defined only in UniFi's local DNS, resolves to 192.168.1.12)

| Domain | Service | Repo |
|---|---|---|
| `traefik.oskarrosen.io` | Traefik dashboard | `home-server-tools/traefik` |
| `homepage.oskarrosen.io` | Homepage | `media-services` |
| `openwebui.oskarrosen.io` | Open WebUI | `home-server-tools/ai` |
| `portainer.oskarrosen.io` | Portainer | `home-server-tools/portainer` |
| `searxng.oskarrosen.io` | SearXNG | `home-server-tools/ai` |
| `sonarr.oskarrosen.io` | Sonarr | `media-services` |
| `radarr.oskarrosen.io` | Radarr | `media-services` |
| `prowlarr.oskarrosen.io` | Prowlarr | `media-services` |
| `nzbhydra2.oskarrosen.io` | NZBHydra2 | `media-services` |
| `readarr.oskarrosen.io` | Readarr | `media-services` |
| `bazarr.oskarrosen.io` | Bazarr | `media-services` |
| `calibre.oskarrosen.io` | Calibre (desktop) | `media-services` |
| `calibre-content.oskarrosen.io` | Calibre (content server) | `media-services` |
| `tautulli.oskarrosen.io` | Tautulli | `media-services` |
| `flaresolverr.oskarrosen.io` | FlareSolverr | `media-services` |
| `plex.oskarrosen.io` | Plex | `media-services` |
| `dispatcharr.oskarrosen.io` | Dispatcharr | `media-services` |
| `stirling-pdf.oskarrosen.io` | Stirling PDF | `media-services` |
| `immich.oskarrosen.io` | Immich | `media-services` |
| `mealie.oskarrosen.io` | Mealie | `media-services` |
| `paperless.oskarrosen.io` | Paperless-ngx | `media-services` |
| `paperless-ai.oskarrosen.io` | Paperless-ai | `media-services` |
| `qbittorrent.oskarrosen.io` | qBittorrent | `media-services` |
| `sabnzbd.oskarrosen.io` | SABnzbd | `media-services` |
| `litellm.oskarrosen.io` | LiteLLM | `home-server-tools/ai` |
| `openspeedtest.oskarrosen.io` | OpenSpeedTest | `home-server-tools/openspeedtest` |
| `healthcheck.oskarrosen.io` | healthcheck | `home-server-tools/healthcheck` |

## Adding a new domain

1. Add the paired `traefik.*` labels to the service in its `docker-compose.yml` (see `media-services/.claude/CLAUDE.md` or `home-server-tools/ai/.claude/CLAUDE.md` for the label pattern) — always `entrypoints=web,web_secure` with `tls=true` / `tls.certresolver=lets_encrypt`, regardless of whether the host is public or LAN-only.
2. Add an A record for the new hostname in the UniFi console pointing at `192.168.1.12` so LAN clients can resolve it.
3. If the service should also be reachable off-LAN, add a matching Route53 record pointing at the public target, and move the entry from the LAN-only table above to the public one.
