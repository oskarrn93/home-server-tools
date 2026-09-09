# pgadmin

[pgAdmin 4](https://www.pgadmin.org/) for browsing/administering every database on the shared
host PostgreSQL instance (`database/ansible`), with Pocket ID as an OIDC login provider (see
`../auth/README.md` for how Pocket ID itself is set up).

## First-time setup

1. Create the `oskar` PostgreSQL superuser if you haven't already (this is what pgAdmin logs into
   Postgres with - full read/write/admin on every database):
   ```bash
   cd ../database/ansible
   ansible-playbook -i inventory.ini local-databases.yml --ask-become-pass
   ```
   This creates/updates the role from `postgres_admin_user`/`postgres_admin_password` in
   `vars/local-databases.yml` (gitignored - holds the real password).
2. Add an A record for `pgadmin.oskarrosen.io` → `192.168.1.12` in the UniFi console (see
   `../traefik/README.md`).
3. `cp .env.example .env` and set `PGADMIN_DEFAULT_PASSWORD`. Internal-auth login is disabled in
   the UI (`config_local.py`, `AUTHENTICATION_SOURCES = ["oauth2"]` only) - this account still
   exists and owns the shared server definition (see below), but there's no login form to use it
   with. Any value works here; just don't leave it unset (`openssl rand -base64 24`).
4. In the Pocket ID admin UI (`https://oidc.oskarrosen.io`), create an OIDC client named
   `pgadmin`:
   - Callback URL: `https://pgadmin.oskarrosen.io/oauth2/authorize`
   - Scopes: `openid email profile`
   - Enable PKCE on the client - `config_local.py` already sets `OAUTH2_CHALLENGE_METHOD=S256` /
     `OAUTH2_RESPONSE_TYPE=code` on the pgAdmin side, so it works alongside the client secret.
   - Copy the generated Client ID and Client Secret into `.env` as `OAUTH2_CLIENT_ID` /
     `OAUTH2_CLIENT_SECRET`.
5. Start pgAdmin:
   ```bash
   docker compose up -d
   ```
6. Visit `https://pgadmin.oskarrosen.io` and click "Pocket ID" to log in via passkey - it's the
   only login option shown.
7. A server called **Home Server (host PostgreSQL)** is pre-loaded and shared with every pgAdmin
   user (`servers.json`, `"Shared": true`, connecting to `host.docker.internal:5432` as `oskar`) -
   click it, enter the `oskar` password from `postgres_admin_password` in
   `database/ansible/vars/local-databases.yml`, and optionally check "Save Password" so it's
   remembered (each user's saved password is their own - sharing the server definition doesn't
   share credentials). Every database on the instance (app databases for Immich, Mealie,
   Paperless-ngx, LiteLLM, Seerr, Pocket ID, tinyauth, etc.) is visible underneath it since `oskar`
   is a superuser.

## How it's wired up

- `config_local.py` is mounted read-only into the container at `/pgadmin4/config_local.py` and
  configures `OAUTH2_CONFIG` to point at Pocket ID's OIDC discovery document
  (`https://oidc.oskarrosen.io/.well-known/openid-configuration`). pgAdmin only reads OAuth2
  provider config from this list, not from individual `PGADMIN_CONFIG_OAUTH2_*` env vars, hence
  the mounted file rather than `.env` entries.
- `servers.json` is mounted read-only at `/pgadmin4/servers.json` and declares the host Postgres
  connection. `PGADMIN_REPLACE_SERVERS_ON_STARTUP=True` (in `docker-compose.yml`) makes pgAdmin
  re-sync from this file on every container start (not just the first) - restart the container to
  pick up edits, no need to touch anything by hand in the UI or wipe `pgadmin_data`.
- The server is loaded under the internal-auth admin user (`PGADMIN_DEFAULT_EMAIL`), which is a
  *separate* pgAdmin account from whichever user Pocket ID/OAuth2 auto-creates on first login, even
  when they share the same email - pgAdmin distinguishes accounts by `(email, auth_source)`. A
  server without `"Shared": true` is only visible to the account it was loaded under, which is why
  it's marked shared here: any user (OAuth2 or internal) can then see and connect to it, entering
  their own password independently.
- Traefik routes `pgadmin.oskarrosen.io` to the container on the external `traefik_internal`
  network, same pattern as every other app here (see `../auth/docker-compose.yml`).
- Postgres itself already listens on the Docker bridge network and accepts password auth from it
  (`database/ansible/local-databases.yml`), which is how pgAdmin reaches
  `host.docker.internal:5432` from inside its container.
- Monitored in Uptime Kuma (`server-observability`, `pgadmin_service_monitors` in `main.tf`) via
  `http://pgadmin:80/login` (the root path 302-redirects there) - reached over the external
  `pgadmin_default` network, which `server-observability/docker-compose.yaml` joins the same way
  it joins `auth_default`/`ai_default`/etc.

## Notes

- Internal-auth login is disabled (`AUTHENTICATION_SOURCES = ["oauth2"]` in `config_local.py`) -
  Pocket ID is the only way into the UI. If Pocket ID ever breaks, recovery means editing that
  file back to `["oauth2", "internal"]` and restarting the container, not something fixable from
  the pgAdmin UI itself.
- The `oskar` PostgreSQL role is a full superuser (`CREATEDB,SUPERUSER`), separate from the
  generic `postgres` superuser (`postgres_root_user`) and from the app-specific service accounts -
  it exists so there's a superuser tied to a named person for interactive/admin use via pgAdmin.
- `pgadmin_data` (named volume) holds pgAdmin's own config database - the OAuth2 login mapping,
  saved server passwords (if you opt in), query history, etc. Not backed up; losing it just means
  redoing the one-time setup above.
