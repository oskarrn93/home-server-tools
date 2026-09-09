# it-tools

[IT Tools](https://github.com/CorentinTh/it-tools) — a collection of handy online tools for
developers (JSON/base64/UUID/hash/regex/etc.), self-hosted. Static app served by the image's own
nginx, no backend, no data storage.

## Setup

1. Add an A record for `it-tools.oskarrosen.io` → `192.168.1.12` in the UniFi console (see
   `../traefik/README.md`).
2. Start it:
   ```bash
   docker compose up -d
   ```
3. Visit `https://it-tools.oskarrosen.io` — routed through the Tinyauth forward-auth gate
   (`../auth`), since the app itself has no login.

## Notes

- LAN-only (no Route53 record) — see `../traefik/README.md` for the public/LAN-only distinction.
- Pinned to `2024.10.22-7ca5933`, the newest non-`latest`/`nightly` tag published on Docker Hub.
