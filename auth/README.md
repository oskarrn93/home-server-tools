# auth

Self-hosted SSO for 1-3 users: **Pocket ID** (passkey-based OIDC provider, admin UI for users/clients) issuing identity, and **tinyauth** (thin `ForwardAuth` gate) protecting apps that have no login of their own, delegating its own login screen to Pocket ID.

## First-time setup

1. `.env` already exists on this host with a generated `ENCRYPTION_KEY` (gitignored). If recreating from scratch, copy `.env.example` and fill in `ENCRYPTION_KEY` (`openssl rand -base64 32`).
2. Add A records for `oidc.oskarrosen.io` and `auth.oskarrosen.io` → `192.168.1.12` in the UniFi console (see `home-server-tools/traefik/README.md`).
3. Start Pocket ID first and finish its setup wizard in the browser (register your passkey as the first/admin user):
   ```sh
   docker compose up -d pocket-id
   ```
   Visit `https://oidc.oskarrosen.io` and complete setup.
4. In the Pocket ID admin UI, create an OIDC client named `tinyauth`:
   - Callback URL: `https://auth.oskarrosen.io/api/oauth/callback/pocketid`
   - Scopes: `openid email profile groups`
   - Copy the generated Client ID and Client Secret into `.env` as `TINYAUTH_OAUTH_PROVIDERS_POCKETID_CLIENTID` / `_CLIENTSECRET`.
5. Start tinyauth:
   ```sh
   docker compose up -d tinyauth
   ```
6. Visit any gated app (e.g. `https://qbittorrent.oskarrosen.io`) — it should redirect to Pocket ID's passkey login via tinyauth.

## How it's wired to Traefik

- `home-server-tools/traefik/dynamic/tinyauth.yml` defines the `tinyauth` middleware (Traefik file provider) as a `forwardAuth` pointing at `http://tinyauth:3000/api/auth/traefik`. Both containers here join the external `traefik_internal` network, same as Traefik, so the hostname resolves.
- Any router that should be gated gets `traefik.http.routers.<name>.middlewares=tinyauth@file` added to its labels (the `@file` suffix is required since the middleware is defined via the file provider, not Docker labels). Currently applied to `qbittorrent`, `sabnzbd`, `sonarr`, `radarr`, `prowlarr` in `media-services/docker-compose.yml`.
- `TINYAUTH_OAUTH_AUTOREDIRECT=pocketid` skips tinyauth's own login form and sends the browser straight to Pocket ID's passkey login.

## Native OIDC apps

For apps with their own OIDC support (Immich, Mealie, Paperless-ngx, newer Stirling-PDF), point them directly at Pocket ID as the OIDC provider rather than routing through tinyauth — create a separate OIDC client per app in the Pocket ID admin UI (issuer `https://oidc.oskarrosen.io`).

## Adding more forward-auth-gated services

Add `traefik.http.routers.<name>.middlewares=tinyauth@file` to the service's labels. No config change needed here — every Pocket ID user gets access to everything by default (fine for 1-3 users); per-app allow/block lists exist via `TINYAUTH_APPS_<NAME>_USERS_ALLOW` if that's ever needed.

## Notes

- Storage: Pocket ID and tinyauth each use their own database/user on the shared host PostgreSQL instance (provisioned via `home-server-tools/database/ansible/local-databases.yml`, connection strings in `.env` as `DB_CONNECTION_STRING` / `TINYAUTH_DATABASE_PATH`), reached over `host.docker.internal`. The named volumes (`pocketid_data`, `tinyauth_data`) still hold non-DB state (Pocket ID's assets, tinyauth's OIDC keys) — no bind-mounted state to gitignore.
- Adding a user later: invite them from the Pocket ID admin UI; they register their own passkey. No restart needed.
