# Deploy the Cru AI Gateway on Coolify

Uses [docker-compose.yml](../docker-compose.yml) at the repo root. Tested locally with `docker compose` on 2026-11-17. **Not yet tested on a real Coolify server.** The Coolify parts follow the Coolify docs ([Docker Compose](https://coolify.io/docs/knowledge-base/docker/compose), [environment variables](https://coolify.io/docs/knowledge-base/environment-variables)).

## Server size

Measured: about 650 MB RAM for litellm + postgres. No local models (all models are on OpenRouter). Plan for **at least 1.5 GB free RAM, 1 to 2 CPUs, and 5 GB disk** (litellm image about 1.7 GB, the database grows with traffic).

## Steps

1. **Push the repo** to GitHub.
2. In Coolify: **New Resource**, pick the repository (GitHub App for a private repo), build pack **Docker Compose**.
   - **Base Directory:** `/`
   - **Docker Compose Location:** `/docker-compose.yml`
3. **General > Build pipeline:** turn on **Preserve repository during deployment**. `litellm` mounts `./config.yaml` from the repo. Without it, Docker makes an empty folder instead and LiteLLM fails to start.
4. **Domain:** give the `litellm` service a domain with port 4000, for example `https://ai.example.org:4000`. The `:4000` only tells Coolify's proxy which container port to use; users call `https://ai.example.org`. Do not add `ports:`.
5. **Environment variables:**
   - `LITELLM_MASTER_KEY`: **you set this.** It must start with `sk-`. Make one on your computer with `echo "sk-$(openssl rand -hex 32)"` and keep it in your password manager. It is the super-admin key for the API.
   - `SERVICE_PASSWORD_POSTGRES`, `SERVICE_PASSWORD_UI`, `SERVICE_PASSWORD_64_SALTKEY`: Coolify makes these. Never change `SERVICE_PASSWORD_64_SALTKEY` after the first start.
   - `UI_USERNAME`: defaults to `admin`.
   - `SERVICE_URL_LITELLM` and `SERVICE_URL_LITELLM_4000`: come from the domain. `PROXY_BASE_URL` uses `SERVICE_URL_LITELLM` (no port); Coolify v4.7.6 adds `:4000` to the `_4000` one.
   - `OPENROUTER_API_KEY`: needed for every model. Cru staff paste it here. Empty: the gateway starts, but every model call fails.
   - Ignore `COMPOSE_FILE` / `GW_PORT`; they are for local runs only.
6. **Deploy.** The first start pulls the images. Both services should become healthy.
7. **Check:** open `https://<your domain>/ui` and log in with `admin` and the `SERVICE_PASSWORD_UI` value from Coolify.

## After the first deploy

1. In the Admin UI, invite yourself under **Internal Users** with role `proxy_admin`. Open the link, set a password, log in with your email.
2. Turn off the shared `admin` login: in `config.yaml` set `disable_env_credential_login: true`, push, redeploy. If you get locked out, the master key still works on the API; set it back to `false` and redeploy.
3. Make teams and keys in the Admin UI.

## Security notes

- Once a domain is set, the Admin UI and API are on the public internet. Consider limiting `/ui` to Cru IPs or a VPN (not set up yet).
- Only `litellm` is reachable from outside.
- Coolify at https://cru.engineer hosts other projects: only touch the cru-ai-gateway resource.
- To upgrade, follow the [security rules in the README](../README.md#security-rules-important).
- Backups: back up the `pgdata` volume (for example a nightly `pg_dump`). Not set up yet. Whether Coolify's built-in database backups cover a Postgres inside a compose app was not checked.
