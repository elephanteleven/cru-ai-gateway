# Cru AI Gateway

One central, open source AI gateway for Cru. Every app, service, and person that needs AI calls it, instead of calling AI providers directly. It lets admins control access, monitor traffic, and see cost.

Built on [LiteLLM](https://docs.litellm.ai/) (BerriAI), MIT open source core only.

> Note: this is **LiteLLM**, not **LightLLM**. LightLLM (ModelTC) is a model serving engine for GPUs, not a gateway.

**Picking this up? Read [HANDOFF.md](HANDOFF.md) for everything still pending.**

## Status (2026-11-16)

| Item | State |
|---|---|
| Study of LiteLLM | Done: [litellm-ai-gateway-study.md](litellm-ai-gateway-study.md) |
| Full implementation plan | Draft: [implementation-plan.md](implementation-plan.md) (on hold, PoC first) |
| PoC scripts | Written in [poc/](poc/) |
| PoC running | **Paused.** LiteLLM and Postgres images are pulled. The Ollama image (2.9 GB) did not finish downloading, so the model and gateway never started. All jobs and containers were stopped on 2026-11-16. |
| PoC tests | Not run yet. See "Test results" below |

**To resume:** `cd poc && ./up.sh` (it pulls the Ollama image and the model, then starts the gateway; `.env` already exists), then `./test.sh`. Plan for a long first pull on a slow network, or switch to the llama.cpp server image (see Known issues).

## Decisions made

- **Open source only.** No LiteLLM Enterprise license. Never use or copy code from the `enterprise/` folder of the LiteLLM repo (different license).
- **PoC uses free things only.** One small local model, no paid API keys.
- **Local model for PoC:** Qwen3.5 0.8B, **Q2_K** quantization (464 MB GGUF from `hf.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF`). Chosen to run light on an 8 GB M1 Mac. Q4_K_M (579 MB) is the better-quality option if needed.
- **Later (not now):** route to paid models (GPT, Gemini, Claude, DeepSeek) and to bigger local models through the same gateway.
- **Access model:**
  - Every admin gets a named account (email + password, free). Roles: `proxy_admin`, `proxy_admin_viewer`, `internal_user`.
  - Each app or service gets a **service account key** tied to a team (not to a person).
  - Each person who needs direct access gets a **personal key**.
  - Teams = departments or products. Budgets, allowed models, and rate limits are set per team and per key.
- **Privacy default:** log metadata and cost only, not prompt or response text (`turn_off_message_logging: true`).

## Things that are paid-only in LiteLLM (so we work around them)

SSO beyond 5 users, audit logs, team/org admins, one-click key rotation, `/global/spend/report`, tag budgets, per-model budgets per key, secret manager integration. Workarounds are in section 3.3 of the study doc. In short: email/password logins, access managed as code in git (git history = audit log), Grafana dashboards on the Postgres spend tables.

## Security rules (important)

LiteLLM had two supply chain attacks in 2026 (malicious 1.82.7/1.82.8 in March, 1.107.0 in October, including Docker `latest` tags). So:

- **Pin exact versions.** Never use `latest`, `main-latest`, `main-stable`, or `lts` tags.
- Before upgrading, wait a few days after a release, read the release notes, and verify the signature.
- LiteLLM signing key fingerprint (sha256 of the PEM, from their incident post): `e3fe3e08c44b16407fe0b37c43b4f8b603b3a0f4ee74c29e647bc022d762c2c0`. We checked the `cosign.pub` linked from the v1.108.8 release and it matches. Releases from v1.111.0-dev.3 on use keyless cosign instead.
- Secrets live only in `poc/.env` (git-ignored, chmod 600). Never commit, print, or paste them. Real provider API keys are entered by Cru staff only.

## PoC: how to run

Needs Docker. This Mac uses **Colima** (`colima start` if Docker is not running).

```bash
cd poc
./up.sh        # first run creates .env with random test secrets, pulls images and the model
./test.sh      # runs 9 checks (keys, limits, budget, block, roles, spend)
./down.sh      # stop (data kept)
./down.sh --wipe   # stop and delete containers, volumes, network
```

- Gateway API: http://127.0.0.1:4000 (OpenAI-compatible, use any OpenAI SDK with `base_url` set to this)
- Admin UI: http://127.0.0.1:4000/ui (login from `poc/.env`: `UI_USERNAME` / `UI_PASSWORD`)
- Ports are bound to 127.0.0.1 only.

Containers (all on Docker network `cru-ai-poc`):

| Container | Image (pinned) | Job |
|---|---|---|
| `cru-postgres` | `postgres:16.10-alpine` | Keys, users, teams, spend logs. Volume `cru-pgdata` |
| `cru-ollama` | `ollama/ollama:0.40.16` | Runs the local model (CPU in Docker). Volume `cru-ollama` |
| `cru-litellm` | `ghcr.io/berriai/litellm-database:v1.108.8` (LTS) | The gateway. Mounts `poc/config.yaml` |

Model names apps call (in `poc/config.yaml`):

- `cru-chat`: the name apps should use. Today it is the local model. Later it can point to paid models with fallback to local.
- `cru-local`: the local model directly.

Both have a **demo price** (not a real cost) so cost tracking and budgets can be tested with a free model.

### Example call

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer <a virtual key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"cru-chat","messages":[{"role":"user","content":"hello"}]}'
```

### What test.sh checks

1. Gateway health
2. Chat through the gateway to the local model
3. Team + service account key, key limited to `cru-local` only
4. Personal key for a user (90 day expiry)
5. Rate limit (`rpm_limit=1` gives 429 on the 2nd call)
6. Budget (tiny `max_budget` blocks the key after spend is saved)
7. Blocking a key
8. `proxy_admin_viewer` cannot issue keys
9. Spend saved in Postgres, shown by key and model

It creates demo teams, users, and keys with a time-based suffix, so it can be re-run.

## Test results

_Not run yet._ (Fill in after the first `./test.sh` run.) The script itself has not been run, so expect small fixes on the first run.

## Known issues and gotchas on this Mac

- **Homebrew is owned by another macOS user** (`nohrsom`), so `brew install` fails with permission denied. Do not change its ownership. That is why everything runs in Docker and there is no native Ollama or `docker compose` plugin. `up.sh` uses plain `docker run`.
- Mac is an **M1 with 8 GB RAM**. Keep models small. Ollama in Docker runs on CPU only (no Metal GPU), so replies are slow.
- The Ollama Docker image for arm64 is **2.9 GB** and the first pull is slow. If that is a problem, a lighter option is the llama.cpp server image, which can load the same GGUF file and also speaks the OpenAI API.
- Qwen3.5 may "think" before answering. Tests use `max_tokens: 40` to keep calls short.
- `cosign` is not installed locally. To verify image signatures, run it as a container (`ghcr.io/sigstore/cosign/cosign:v2.4.1`) with the command from the LiteLLM release notes.

## Next steps

1. Get the PoC running and record `./test.sh` results above.
2. Open the Admin UI and check: create an admin user by invite, then turn off the shared bootstrap login (`disable_env_credential_login: true`).
3. Check whether Prometheus metrics are free in v1.108.8. If not, use OpenTelemetry.
4. Simple cost dashboard (Grafana on Postgres `LiteLLM_SpendLogs`).
5. Optional: add one free-tier cloud model (e.g. Gemini free tier) with fallback to local. Cru staff put the key in `poc/.env`.
6. Then go back to [implementation-plan.md](implementation-plan.md) Phase 0 questions (production host, GPU, data rules, logging, size, budgets).

## File map

```
cru-ai/
  README.md                        this file (start here)
  CLAUDE.md                        rules for Claude sessions working here
  HANDOFF.md                       pending work checklist and session context
  litellm-ai-gateway-study.md      research: features, free vs paid, security, alternatives
  implementation-plan.md           full plan, phases 0-6, open questions
  dev.sh                           starts Claude Code for this folder
  poc/
    config.yaml                    LiteLLM models, settings
    up.sh / down.sh                start / stop the stack
    test.sh                        PoC checks
    .env.example                   secret names (real .env is git-ignored)
```
