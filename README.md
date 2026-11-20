# Cru AI Gateway

One central, open source AI gateway for Cru. Apps, services, and people call it instead of calling AI providers directly. Admins control access, see traffic, and see cost.

Built on [LiteLLM](https://docs.litellm.ai/) (BerriAI), MIT open source core only. (Not "LightLLM", which is a GPU model server.)

## What is in this repo

```
docker-compose.yml         the stack: litellm (gateway) + postgres
docker-compose.local.yml   local only: publishes the gateway on 127.0.0.1
config.yaml                LiteLLM settings and model list
scripts/chat.sh            test client: send one message with a virtual key, like an app would
.env.example               variable names (copy to .env for a local run)
docs/coolify.md            how to deploy on Coolify
docs/litellm-ai-gateway-study.md   research: features, free vs paid, security
docs/implementation-plan.md        full plan (on hold)
docs/litellm-test-results.md       API, logs, and SSO test results (2026-11-19/20)
docs/screenshots/                  Admin UI screenshots from those tests
```

| Service | Image (pinned by tag and digest) | Job |
|---|---|---|
| `litellm` | `ghcr.io/berriai/litellm-database:v1.108.8` (LTS, cosign verified) | Gateway. API, Admin UI at `/ui`, metrics at `/metrics/`. The only public service |
| `postgres` | `postgres:16.10-alpine` | Keys, users, teams, spend logs |

### Models

**Every model goes through [OpenRouter](https://openrouter.ai). No local models are deployed** (user decision, 2026-11-20). One key, `OPENROUTER_API_KEY`, in `.env` or Coolify, entered by Cru staff. OpenRouter charges for every call (except `openrouter/free`); set a credit limit on the key in OpenRouter and budgets on teams in LiteLLM.

The name to call is the **OpenRouter model id**, for example `anthropic/claude-fable-5.2`. There are no alias names. The full list (38 models) with notes is in `config.yaml`; ids and prices were read from the OpenRouter models API on 2026-11-20.

| Group | Models, best first | Ranked by |
|---|---|---|
| Frontier (10) | `anthropic/claude-fable-5.2`, `openai/gpt-6.2-astra`, `google/gemini-4-neon`, `google/gemini-4-carbon`, `anthropic/claude-opus-5.5`, `openai/gpt-6.2-sol`, `anthropic/claude-sonnet-5.5`, `google/gemini-4-hydrogen`, `openai/gpt-6.1-terra`, `google/gemini-4-argon` | [Artificial Analysis](https://artificialanalysis.ai/leaderboards/models) Intelligence Index v5.0.1 |
| Open weights (10) | `moonshotai/kimi-k3.1-pro`, `deepseek/deepseek-v4.1-flash-1017`, `tencent/hy4-preview`, `inclusionai/ling-3.1-flash`, `moonshotai/kimi-k3`, `z-ai/glm-5.3`, `xiaomi/mimo-v2.6-pro`, `xiaomi/mimo-v2.6-flash`, `stepfun/step-5-preview`, `deepseek/deepseek-v4-pro` | [BenchLM open-source](https://benchlm.ai/best/open-source) (2026-11-19). Skipped: Qwen3.8 Max (no open weights on OpenRouter), Ornith-1.5-397B (not on OpenRouter) |
| Small, fit one GPU of 96 GB or less (10) | `qwen/qwen3.8-27b`, `meta/muse-glimmer-30b`, `qwen/qwen3.6-27b`, `google/gemma-4-31b-it`, `microsoft/phi-4`, `qwen/qwen3.5-27b`, `qwen/qwen3.6-35b-a3b`, `google/gemma-4-26b-a4b-it`, `z-ai/glm-4.7-flash`, `qwen/qwen3.5-35b-a3b` | BenchLM. Rule used: 80B params or less (fits 96 GB at 8-bit). Sizes from model names, not checked against model cards. Skipped: not on OpenRouter, or failed the model check below |
| Routers, like Jev (8) | `openrouter/fusion`, `openrouter/auto`, `typesafe/jev-router`, `nvidia/switchyard`, `openrouter/pareto-code`, `openrouter/auto-code`, `openrouter/auto-beta`, `openrouter/free` | No benchmark ranks routers; order is our judgment. OpenRouter has only these 8 routers, not 10 |

- **Cost:** LiteLLM v1.108.8 does not know prices for most of these models, so `config.yaml` sets `input_cost_per_token` / `output_cost_per_token` from OpenRouter's list. Routers have no price in `config.yaml`, but LiteLLM still showed the same cost as OpenRouter for them in the test below. Models with several providers can cost a bit more or less than the `config.yaml` price, because OpenRouter picks the provider per call.
- **Rankings change often.** Re-check the boards and the OpenRouter list before a demo.
- The model answer comes from the provider OpenRouter picks. Prompts go to OpenRouter and that provider: never send real or internal Cru data in the demo.

## Run it

**On Coolify:** follow [docs/coolify.md](docs/coolify.md).

**On your own machine:**

```bash
cp .env.example .env      # then fill in the values (commands are in the file)
docker compose up -d --wait
docker compose down       # stop, data kept (add -v to delete data and the model)
```

- Gateway: `http://127.0.0.1:<GW_PORT>` (OpenAI-compatible: use any OpenAI SDK with `base_url` set to it)
- Admin UI: `http://127.0.0.1:<GW_PORT>/ui`, user `admin`, password = `SERVICE_PASSWORD_UI` in `.env`

Example call:

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer <a virtual key>" -H "Content-Type: application/json" \
  -d '{"model":"deepseek/deepseek-v4.1-flash-1017","messages":[{"role":"user","content":"hello"}]}'
```

Or with the test client (needs bash, curl, python3; reads `GW_PORT` from `.env`, or set `GW_URL`):

```bash
API_KEY=sk-... ./scripts/chat.sh -m openrouter/auto "Hi, how are you?"
```

It prints the answer, then which model really answered, time, tokens, cost, and fallbacks. `-v` shows the raw JSON, `-t` sets max tokens. The key is passed to curl in a temp file, so it does not show in `ps`.

## Admin tasks (in the Admin UI)

- **People:** Internal Users, invite. Each admin gets their own login (role `proxy_admin`, or `proxy_admin_viewer` for read only). The invite link works once; the person sets a password (12+ chars, upper, lower, number, symbol).
- **Teams:** one per department or product, with budget, allowed models, and limits.
- **Keys:** one key per app or service (service account, tied to a team), and personal keys for people who need direct access. A key is shown only once.
- **Cost:** Usage pages in the UI, the `LiteLLM_SpendLogs` table in Postgres, and Prometheus metrics at `/metrics/` (needs the master key).

**What the logs show:**
- Every refused call is logged in `LiteLLM_SpendLogs` (status `failure`) with the key, team, user, and the reason. The prompt is kept only for rate-limited calls (429), not for "model not allowed" (403) or a blocked key (401). (Tested 2026-11-19.)
- With `store_prompts_in_spend_logs: true` (on now, for the demo), every admin, `proxy_admin_viewer` included, can read every prompt and answer in Logs.

**SSO (not set up):** free only while the whole gateway has 5 or fewer users in total. If it is turned on later, see "Login options" in [the study doc](docs/litellm-ai-gateway-study.md) for `GENERIC_USER_ID_ATTRIBUTE` (use `sub`), group to role, and group to team.

**More test facts** (2026-11-19/20, see [docs/litellm-test-results.md](docs/litellm-test-results.md)):
- **Offboarding:** disabling a person in Okta stops new SSO logins, but their API keys keep working. An admin must block or delete their keys by hand. SCIM (automatic offboarding) is Enterprise only.
- **Team keys for users:** an `internal_user` can make personal keys. To make a key inside their team, an admin must allow `/key/generate` once per team (`/team/permissions_update`).
- **SSO settings gotcha:** `PATCH /update/sso_settings` with only some fields saves nulls for the rest, and DB values override env, so SSO silently falls back to password login. Always send the full set.

**Turn off the shared `admin` login** once your own admin login works: set `disable_env_credential_login: true` in `config.yaml`, then redeploy. If you get locked out, the master key still works on the API; set it back to `false`.

## Decisions

- **Open source only.** No LiteLLM Enterprise license, no code from LiteLLM's `enterprise/` folder.
- **Models from OpenRouter only (2026-11-20).** Paid models are fine for the demo (user decision). No local LLM service is deployed. Earlier the PoC used six tiny local models (llama.cpp) and the Gemini free tier; see Test results.
- **Access:** named login per admin; one key per app or service; personal keys for people; teams carry budgets, models, and limits.
- **Privacy:** for the demo, full prompt and response text is saved and shown in Admin UI > Logs (`store_prompts_in_spend_logs: true`, `turn_off_message_logging: false`). Every admin, including `proxy_admin_viewer`, can read it. Logs older than 30 days are deleted (`maximum_spend_logs_retention_period`). Before real use, Cru must decide whether to keep text; set both back to keep only metadata and cost.

Paid-only in LiteLLM (we work around them): SSO once the gateway has more than 5 users **in total** (every user row counts, including email + password admins, so SSO cannot be kept "for a few"; skip SSO or buy Enterprise), audit logs, team/org admins, key rotation, `/global/spend/report`, **tags on keys** (403 in v1.108.8; use key `metadata` instead), tag budgets, secret managers. See section 3.3 of the study doc.

## Security rules (important)

LiteLLM had supply chain attacks in 2026 (bad 1.82.7/1.82.8 in March, 1.107.0 in October, including Docker `latest` tags). So:

- **Pin exact versions and digests.** Never `latest`, `main-latest`, `main-stable`, or `lts`.
- Before upgrading: wait a few days after a release, read the notes, verify the signature, pin the new digest.
- LiteLLM signing key: sha256 of the PEM is `e3fe3e08c44b16407fe0b37c43b4f8b603b3a0f4ee74c29e647bc022d762c2c0` (from their incident post). Verify with:
  `docker run --rm ghcr.io/sigstore/cosign/cosign:v2.4.1 verify --key https://raw.githubusercontent.com/BerriAI/litellm/e82a3c646908ba0a6ee0beddc4310d7a6cac4065/cosign.pub ghcr.io/berriai/litellm-database:v1.108.8`
  Releases from v1.111.0-dev.3 on use keyless cosign instead.
- Secrets live only in `.env` (local, git-ignored) or in Coolify. Never commit, print, or paste them. Real provider keys are entered by Cru staff only.
- Set `SERVICE_PASSWORD_64_SALTKEY` once and never change it (it encrypts data in the DB).

## Test results (2026-11-16/17, Linux x86_64, CPU only)

These were run with the old setup (local llama.cpp models, Gemini free tier). The gateway features (keys, teams, limits, logs) do not depend on the models.

All 13 checks passed, first with `docker run`, then with this compose file. (The test script was removed later to keep the repo small.)

| Check | Result |
|---|---|
| Health, chat to the local model | OK, 0.2 to 1.3 s for a short reply |
| Team + app key limited to `cru-local` | OK, `cru-chat` refused with 403 |
| Personal key, 90 day expiry | OK |
| `rpm_limit=1` | 2nd call gets 429 |
| Tiny `max_budget` | Next call gets 422 `budget_exceeded` (one call can go over before the block) |
| Blocked key | 401 |
| `proxy_admin_viewer` making a key | 403 |
| Spend saved in Postgres by key and model | OK. Refused calls are logged too, with 0 cost |
| Invite link, set password, log in as named admin | OK. Link works once |
| `disable_env_credential_login: true` | Shared login 401, named admin 200, master key still works on the API |
| Prometheus | Free, works with `callbacks: ["prometheus"]` |
| Restart | Data and model kept, no second download |

Memory: about 600 MB (litellm) + 30 MB (postgres) + llama (250 MB with one model, 500 MB with two loaded).

Six-model check (2026-11-17), through the gateway, first call includes loading the model:

| Model | "Capital of Thailand?" | Short Thai self-intro |
|---|---|---|
| qwen3.5-0.8b | correct, 1.6 s | broken Thai |
| qwen3-0.6b | correct, 1.3 s | broken Thai |
| qwen2.5-0.5b | Bangkok, but wrong extra fact | broken Thai |
| gemma3-1b | correct, 1.8 s | **good Thai** |
| gemma3-270m | correct, 1.0 s | **good Thai** (short) |
| smollm2-360m | correct, 0.9 s | nonsense |

All are fine for showing the gateway, not for real use.

## OpenRouter model check (2026-11-20, local, real key)

One call per model through the gateway ("Reply with one word: OK", `max_tokens` 300). Whole run cost about $0.012 (OpenRouter `usage.cost`).

- **35 of 38 answered** "OK" in 0.7 to 8 s.
- Cost in LiteLLM (`x-litellm-response-cost`) matched OpenRouter's `usage.cost` exactly for 24 of the 35. The rest were off by a little (example: `z-ai/glm-5.3` $0.00007 in LiteLLM vs $0.00016 in OpenRouter) because the provider OpenRouter picked charged a different price than the one in `config.yaml`. Use the OpenRouter bill as the real number.
- Failed:

| Model | Error | Why |
|---|---|---|
| `prism-ml/ternary-bonsai-2-27b` | 404 | Its only provider does not meet the OpenRouter account's zero data retention (ZDR) setting. Kept that setting on. |
| `liquid/lfm-2.5-24b-a2b` | 504 after ~78 s, twice | Its only provider (Liquid) timed out. |
| `openrouter/free` | 429 once | Free models are rate limited. OK on retry. |

The two broken small models were replaced by the next ones on BenchLM that fit: `z-ai/glm-4.7-flash` (#64, 30B A3B) and `qwen/qwen3.5-35b-a3b` (#71, 35B A3B). Both answered on 2 of 2 calls, cost matched OpenRouter. Notes: one `glm-4.7-flash` call took 54 s (the other 3 s), and one `qwen3.5-35b-a3b` call came back with empty text because the model spent the 300 tokens on thinking; give these models a higher `max_tokens`.

## Known issues

- `PROXY_BASE_URL` must not be empty (LiteLLM then builds broken links); it comes from `SERVICE_URL_LITELLM_4000`, which is required.
- On the 8 GB M1 Mac there is no `docker compose` plugin and Homebrew belongs to another user (do not `brew install`). To run locally there, add the compose plugin binary under `~/.docker/cli-plugins/` (not done yet).
- Port 4000 may be busy on a dev machine; set `GW_PORT` in `.env`.

## Next steps

1. Deploy on Coolify (https://cru.engineer) with [docs/coolify.md](docs/coolify.md). Touch only the cru-ai-gateway resource there, never other projects.
2. After the first Coolify deploy: check domain, healthchecks, the `config.yaml` mount, and that invite links use the public URL. Fix the guide with what we learn.
3. Make your own admin login, then turn off the shared `admin` login.
4. Backups for the Postgres volume; limit `/ui` to Cru IPs or a VPN.
5. Cost dashboard (Grafana on `LiteLLM_SpendLogs` and Prometheus).
6. Later, when asked: Phase 0 questions in [docs/implementation-plan.md](docs/implementation-plan.md) (production host, GPU, data rules, logging, size, budgets).
