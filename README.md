# Cru AI Gateway

One central, open source AI gateway for Cru. Apps, services, and people call it instead of calling AI providers directly. Admins control access, see traffic, and see cost.

Built on [LiteLLM](https://docs.litellm.ai/) (BerriAI), MIT open source core only. (Not "LightLLM", which is a GPU model server.)

## What is in this repo

```
docker-compose.yml         the stack: litellm (gateway) + llama (local models) + postgres
docker-compose.local.yml   local only: publishes the gateway on 127.0.0.1
config.yaml                LiteLLM settings and model list
scripts/chat.sh            test client: send one message with a virtual key, like an app would
.env.example               variable names (copy to .env for a local run)
docs/coolify.md            how to deploy on Coolify
docs/litellm-ai-gateway-study.md   research: features, free vs paid, security
docs/implementation-plan.md        full plan (on hold)
```

| Service | Image (pinned by tag and digest) | Job |
|---|---|---|
| `litellm` | `ghcr.io/berriai/litellm-database:v1.108.8` (LTS, cosign verified) | Gateway. API, Admin UI at `/ui`, metrics at `/metrics/`. The only public service |
| `llama` | `ghcr.io/ggml-org/llama.cpp:server-b12063` (2026-11-03 build) | Runs the local models in router mode. Downloads them on first start and checks sha256 |
| `postgres` | `postgres:16.10-alpine` | Keys, users, teams, spend logs |

### Models

All local, all **1B parameters or less, Q2_K**. One llama.cpp server in **router mode** serves them: a model loads on its first request, and at most 2 stay in memory (the least recently used one is unloaded). The list lives in `MODELS` in `docker-compose.yml` and in `config.yaml`.

| Name to call | Model | Params | File | License |
|---|---|---|---|---|
| `cru-chat` | Qwen3.5 0.8B (name apps should use; later it can point to paid models) | | | |
| `cru-local` | Qwen3.5 0.8B (default local model) | | | |
| `qwen3.5-0.8b` | Qwen3.5 0.8B | 0.77B | 464 MB | Apache 2.0 |
| `qwen3-0.6b` | Qwen3 0.6B | 0.6B | 296 MB | Apache 2.0 |
| `qwen2.5-0.5b` | Qwen2.5 0.5B Instruct | 0.49B | 339 MB | Apache 2.0 |
| `gemma3-1b` | Gemma 3 1B IT | 1.0B | 690 MB | Gemma terms of use |
| `gemma3-270m` | Gemma 3 270M IT | 0.27B | 237 MB | Gemma terms of use |
| `smollm2-360m` | SmolLM2 360M Instruct | 0.36B | 219 MB | Apache 2.0 |

Total download about 2.2 GB. All have a **demo price** so cost and budget features can be tested with free models.

Left out: Llama 3.2 1B (really 1.24B params), LFM2 (its license needs a paid deal above $10M yearly revenue), Granite 4.0 350M (no Q2_K file found).

**Cloud models on the Gemini free tier** (demo only). They need `GEMINI_API_KEY` in `.env` or Coolify, made by Cru staff at [aistudio.google.com](https://aistudio.google.com). Without a key the model returns an error. Groq (free tier, e.g. `groq/openai/gpt-oss-120b`, 30 req/min, 1,000 req/day) was tried and left out for now; it can be added later. Model ids were checked on the official pages on 2026-11-17 (free tier, not deprecated).

| Name to call | Provider | Free tier limits |
|---|---|---|
| `gemini-3.6-flash` | Google Gemini | shown only in AI Studio |
| `gemini-3.5-flash-lite` | Google Gemini | shown only in AI Studio |
| `cru-cloud` | **Fallback demo:** Gemini 3.6 Flash (30 s timeout, no retries), then `cru-local` | |

- **Free tiers may use prompts to train models. Never send real or internal Cru data.**
- Cost for these uses LiteLLM's real price table, so it shows what the call *would* cost on a paid plan.
- The response header `x-litellm-model-group` shows which model really answered (useful in the fallback demo).
- Tested 2026-11-17 with a real key (Thai prompt): `gemini-3.5-flash-lite` 4 s, `gemini-3.6-flash` 7 to 20 s (Google free tier speed varies), both good Thai. Cost rows saved in Postgres per model.
- Fallback tested: with the key removed, `cru-cloud` was answered by `cru-local` in 6 s (`x-litellm-attempted-fallbacks: 1`).
- Slow provider test (2026-11-19, a test server that answers after 45 s in place of Gemini): with the old setting LiteLLM tried it 3 times (router default `num_retries` 2), so `cru-local` answered after **94.7 s**. With `num_retries: 0` it tried once and `cru-local` answered after **30.8 s**.
- Free tier daily limit: `gemini-3.6-flash` allows 20 requests per day per project. On 2026-11-19 it returned 429 "quota exceeded" and `cru-cloud` fell back to `cru-local` in 1 to 2 s.
- `reasoning_effort: minimal` is set for 3.6 Flash. Without it the model spent about 285 of 300 tokens on hidden "thinking" and the answer was cut off.
- Failed Gemini calls (timeouts) were still logged with a small input cost (about $0.00001 each). Keep in mind when reading cost reports.
- `gemini-3.8-flash` is on the free tier too, but on 2026-11-17 it hung for over 2 minutes or returned 503 "high demand", even when called directly. So 3.6 Flash is used.
- Free tier model lists change often. If a model stops working, check the provider's model and deprecation pages and update `config.yaml`.

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
  -d '{"model":"cru-chat","messages":[{"role":"user","content":"hello"}]}'
```

Or with the test client (needs bash, curl, python3; reads `GW_PORT` from `.env`, or set `GW_URL`):

```bash
API_KEY=sk-... ./scripts/chat.sh -m cru-local "Hi, how are you?"
```

It prints the answer, then which model really answered, time, tokens, cost, and fallbacks. `-v` shows the raw JSON, `-t` sets max tokens. The key is passed to curl in a temp file, so it does not show in `ps`.

## Admin tasks (in the Admin UI)

- **People:** Internal Users, invite. Each admin gets their own login (role `proxy_admin`, or `proxy_admin_viewer` for read only). The invite link works once; the person sets a password (12+ chars, upper, lower, number, symbol).
- **Teams:** one per department or product, with budget, allowed models, and limits.
- **Keys:** one key per app or service (service account, tied to a team), and personal keys for people who need direct access. A key is shown only once.
- **Cost:** Usage pages in the UI, the `LiteLLM_SpendLogs` table in Postgres, and Prometheus metrics at `/metrics/` (needs the master key).

**What the logs show:**
- Every refused call is logged in `LiteLLM_SpendLogs` (status `failure`) with the key, team, user, and the reason. The prompt is kept only for rate-limited calls (429), not for "model not allowed" (403) or a blocked key (401). (Tested 2026-11-19 in ../cru-ai-alt.)
- With `store_prompts_in_spend_logs: true` (on now, for the demo), every admin, `proxy_admin_viewer` included, can read every prompt and answer in Logs.

**SSO (not set up):** free only while the whole gateway has 5 or fewer users in total. If it is turned on later, see "Login options" in [the study doc](docs/litellm-ai-gateway-study.md) for `GENERIC_USER_ID_ATTRIBUTE` (use `sub`), group to role, and group to team.

**Turn off the shared `admin` login** once your own admin login works: set `disable_env_credential_login: true` in `config.yaml`, then redeploy. If you get locked out, the master key still works on the API; set it back to `false`.

## Decisions

- **Open source only.** No LiteLLM Enterprise license, no code from LiteLLM's `enterprise/` folder.
- **PoC uses free things only.** Six small local models (all 1B or less, Q2_K) so demos can compare them. Q4_K_M files give better answers if needed.
- **Later:** paid models (GPT, Gemini, Claude, DeepSeek) and bigger local models through the same gateway.
- **Access:** named login per admin; one key per app or service; personal keys for people; teams carry budgets, models, and limits.
- **Privacy:** for the demo, full prompt and response text is saved and shown in Admin UI > Logs (`store_prompts_in_spend_logs: true`, `turn_off_message_logging: false`). Every admin, including `proxy_admin_viewer`, can read it. Logs older than 30 days are deleted (`maximum_spend_logs_retention_period`). Before real use, Cru must decide whether to keep text; set both back to keep only metadata and cost.
- **llama.cpp server instead of Ollama:** its image is about 300 MB vs 3 GB, and it loads the same GGUF file.

Paid-only in LiteLLM (we work around them): SSO once the gateway has more than 5 users **in total** (every user row counts, including email + password admins, so SSO cannot be kept "for a few"; skip SSO or buy Enterprise), audit logs, team/org admins, key rotation, `/global/spend/report`, **tags on keys** (403 in v1.108.8; use key `metadata` instead), tag budgets, secret managers. See section 3.3 of the study doc.

## Security rules (important)

LiteLLM had supply chain attacks in 2026 (bad 1.82.7/1.82.8 in March, 1.107.0 in October, including Docker `latest` tags). So:

- **Pin exact versions and digests.** Never `latest`, `main-latest`, `main-stable`, or `lts`.
- Before upgrading: wait a few days after a release, read the notes, verify the signature, pin the new digest.
- LiteLLM signing key: sha256 of the PEM is `e3fe3e08c44b16407fe0b37c43b4f8b603b3a0f4ee74c29e647bc022d762c2c0` (from their incident post). Verify with:
  `docker run --rm ghcr.io/sigstore/cosign/cosign:v2.4.1 verify --key https://raw.githubusercontent.com/BerriAI/litellm/e82a3c646908ba0a6ee0beddc4310d7a6cac4065/cosign.pub ghcr.io/berriai/litellm-database:v1.108.8`
  Releases from v1.111.0-dev.3 on use keyless cosign instead.
- For llama.cpp, pick a `server-bNNNNN` tag at least a week or two old (they publish many builds a day).
- Secrets live only in `.env` (local, git-ignored) or in Coolify. Never commit, print, or paste them. Real provider keys are entered by Cru staff only.
- Set `SERVICE_PASSWORD_64_SALTKEY` once and never change it (it encrypts data in the DB).

## Test results (2026-11-16/17, Linux x86_64, CPU only)

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

## Known issues

- `PROXY_BASE_URL` must not be empty (LiteLLM then builds broken links); it comes from `SERVICE_URL_LITELLM_4000`, which is required.
- No one-shot init container: plain `docker compose` rejects Coolify's `exclude_from_hc` key, so `llama` downloads its model itself before starting.
- On the 8 GB M1 Mac there is no `docker compose` plugin and Homebrew belongs to another user (do not `brew install`). To run locally there, add the compose plugin binary under `~/.docker/cli-plugins/` (not done yet).
- Port 4000 may be busy on a dev machine; set `GW_PORT` in `.env`.

## Next steps

1. **User:** commit and push, then deploy on Coolify with [docs/coolify.md](docs/coolify.md).
2. After the first Coolify deploy: check domain, healthchecks, the `config.yaml` mount, and that invite links use the public URL. Fix the guide with what we learn.
3. Make your own admin login, then turn off the shared `admin` login.
4. Backups for the Postgres volume; limit `/ui` to Cru IPs or a VPN.
5. Cost dashboard (Grafana on `LiteLLM_SpendLogs` and Prometheus).
6. Optional: add Groq as a second cloud provider (between Gemini and local in the `cru-cloud` fallback).
7. Later, when asked: Phase 0 questions in [docs/implementation-plan.md](docs/implementation-plan.md) (production host, GPU, data rules, logging, size, budgets).
