# Cru AI Gateway: Implementation Plan

Date: 2026-11-16
Based on: [litellm-ai-gateway-study.md](litellm-ai-gateway-study.md)
Status: draft for review

## Goal

One open source AI gateway (LiteLLM, MIT core only) that:

1. Is the only way Cru apps, services, and people reach AI models.
2. Routes to paid models (GPT, Gemini, Claude, DeepSeek) and to local models.
3. Gives each admin a named account, and each app/service/user its own key.
4. Tracks traffic and cost by team, app, user, and model.

## Ground rules

- Open source only. No Enterprise license, no code from the `enterprise/` folder.
- Pin exact versions and image digests. Never use `latest`.
- Real provider API keys are entered by Cru staff only, into `.env` / secret store. I will not type them in, and they never go into git.
- Everything that can be config or code lives in git, so git history acts as our audit trail.

## Proposed repo layout

```
cru-ai-gateway/
  docker-compose.yml        # gateway + postgres + redis + monitoring + local model
  .env.example              # names of secrets, no values
  litellm/config.yaml       # models, routing, fallbacks, prices
  access/                   # access as code
    teams.yaml              # teams, budgets, allowed models
    admins.yaml             # admin users and roles
    service-accounts.yaml   # app/service keys per team
    users.yaml              # personal keys
  tools/cru-gw/             # small Python CLI that applies access/*.yaml via LiteLLM API
  monitoring/
    grafana/dashboards/     # cost + traffic dashboards
    prometheus.yml
  docs/
    onboarding-app.md       # how an app team gets and uses a key
    admin-runbook.md        # issue / block / rotate keys, upgrades, incidents
  tests/                    # smoke tests and cost check scripts
```

## Phases

### Phase 0. Confirm inputs (before any build)

Questions for Cru (see "Open questions" below). Output: filled answers, target host decided.

### Phase 1. Local proof of concept

Build on this Mac with Docker Compose:

- LiteLLM proxy (pinned version + digest, signature checked with cosign)
- Postgres (keys, users, spend logs)
- Redis (shared rate limits and cache)
- Ollama with one small local model (for the local model path)
- `config.yaml` with one model each from OpenAI, Gemini, Anthropic, DeepSeek, plus the Ollama model
- Model aliases apps will use, e.g. `cru-chat`, `cru-fast`, `cru-local`, with fallback (paid model down → other provider or local)

Checks:
- [ ] Each provider answers through the gateway (curl + OpenAI Python SDK)
- [ ] Fallback works when one provider key is broken on purpose
- [ ] Cost per request shows up in `LiteLLM_SpendLogs` and in the response header
- [ ] Cost for a known test batch is close to what the provider console shows
- [ ] Local model calls are logged with $0 (or our set price)

Needs from Cru: test API keys for each provider with low spend limits, entered by Cru staff into `.env`.

### Phase 2. Users, teams, and keys

- Turn off shared bootstrap login (`disable_env_credential_login: true`) after first admin is created.
- Create named admin accounts (email + password). Free SSO only works while the whole gateway has 5 or fewer users in total (every user counts, any login type); otherwise skip SSO or buy Enterprise.
- Roles: 1 to 2 `proxy_admin`, others `proxy_admin_viewer` or `internal_user`.
- Write `tools/cru-gw`, a small Python CLI that reads `access/*.yaml` and calls the LiteLLM API:
  - `plan` shows what will change, `apply` makes the change
  - creates teams with budgets and allowed models
  - creates service account keys (per app/service) and personal keys (per user)
  - sets key expiry, TPM/RPM limits, metadata labels (key `tags` are Enterprise-only in v1.108.8)
  - rotates a key: create new, hand over, block old, delete later
  - new keys are shown once to the admin, never written to git
- Changes go through pull requests, so we know who changed what and when (replaces the paid audit log).

Checks:
- [ ] A service key cannot call models outside its allow list
- [ ] A key stops working when its budget is used up
- [ ] Rate limit returns 429 when exceeded
- [ ] Blocked key is rejected right away
- [ ] Viewer admin cannot create keys

### Phase 3. Monitoring and cost dashboards

- Grafana dashboards built from Postgres spend logs:
  - cost per day by team, app (key), user, model, provider
  - requests, tokens, errors, latency
  - top spenders, budget used vs budget left
- Traffic and health metrics: Prometheus. Checked in the PoC on 2026-11-16: free in v1.108.8 (no license needed).
- Alerts (Grafana): team over 80% of budget, error rate spike, provider down.
- Decide what prompt/response content is logged. Default: log metadata and cost only, not full prompts, for privacy.

### Phase 4. Security hardening

- TLS in front of the gateway (reverse proxy), gateway not open to the internet unless needed
- Outbound network limited to provider endpoints and the local model host
- Provider keys and master key in the platform secret store, master key used only for break-glass
- Postgres backups and a restore test
- Upgrade process: watch releases, wait a few days, check signature and digest, test in staging, then upgrade
- Incident runbook: how to rotate every provider key, master key, and DB password fast
- Basic PII guardrail with Presidio (free) if needed

### Phase 5. Pilot

- Pick 1 to 2 internal apps or teams
- Write `docs/onboarding-app.md`: get a key, set `base_url` to the gateway, pick a model alias
- Run 2 to 4 weeks, compare gateway cost vs provider bills, collect feedback

### Phase 6. Production

- Deploy on the target host (decided in Phase 0): 2+ gateway replicas, managed or backed-up Postgres, Redis
- Move pilot apps, then open to other teams
- Hand over runbooks to the admin team

## Open questions for Cru

1. **Where will it run in production?** Our own server / VM, Kubernetes, or a cloud (Azure, AWS, GCP)?
2. **Local models:** which models, and is there a GPU server? (Ollama is fine for PoC; vLLM is better for real load on GPUs.)
3. **Providers:** direct accounts (OpenAI, Google AI Studio, Anthropic, DeepSeek) or through a cloud (Azure OpenAI, Vertex, Bedrock)?
4. **Data rules:** any data that must never go to an outside provider (only to local models)? Can DeepSeek be used for all data?
5. **Logging:** may we store prompts and responses, or only metadata and cost?
6. **Size:** about how many admins, teams, apps, and users at start?
7. **Budgets:** how should budgets be set, per team per month?

## What I will do vs what Cru does

| I will | Cru staff will |
|---|---|
| Write compose files, config, CLI, dashboards, tests, docs | Answer open questions |
| Run the PoC locally and report real test results | Create provider accounts and test API keys, put them in `.env` |
| Propose security settings and runbooks | Approve production host and network rules |
| | Review and approve each phase before the next |

## First step after approval

Phase 1: create the repo layout, `docker-compose.yml`, `config.yaml`, and `.env.example`, start the stack with the local Ollama model only (no paid keys needed), then add paid providers once Cru puts test keys in `.env`.
