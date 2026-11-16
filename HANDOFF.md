# Handoff: what is left to do

Written 2026-11-16 at the end of the first working session. That session is being deleted, so everything worth keeping from it is here, in [README.md](README.md), and in the two research/plan docs.

## 1. Where things stand

- Research is done: [litellm-ai-gateway-study.md](litellm-ai-gateway-study.md).
- A full plan exists but is **on hold**: [implementation-plan.md](implementation-plan.md). The user said "don't think that far yet, do a PoC/demo first, use free things".
- PoC scripts are written in `poc/` but the PoC has **never fully started** and **no test has run**.
- Nothing is running now. All containers and background jobs were stopped.

## 2. Pending work, in order

### A. Finish starting the PoC (blocked by a slow download)

- [ ] Run `cd poc && ./up.sh`.
  - Already downloaded: `ghcr.io/berriai/litellm-database:v1.108.8` (1.74 GB), `postgres:16.10-alpine`.
  - **Not downloaded:** `ollama/ollama:0.40.16` (2.9 GB for arm64). The first try ran about 15 minutes and did not finish.
  - Not downloaded: the model `hf.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF:Q2_K` (464 MB). `up.sh` pulls it after Ollama starts.
  - `poc/.env` already exists with random test secrets. `up.sh` will reuse it.
  - Container `cru-postgres` exists (stopped) with volume `cru-pgdata`. `up.sh` restarts it.
- [ ] If the Ollama download is still too slow, switch to the **llama.cpp server** image (much smaller, loads the same GGUF, OpenAI-compatible API). That means:
  - replace the `cru-ollama` block in `up.sh` with a llama.cpp server container (pin an exact tag), and
  - in `config.yaml`, change the model to `openai/<name>` with `api_base: http://<container>:<port>/v1`.
  - Check the llama.cpp server docs for the current image name and flags first. This was not researched yet.

### B. Run and fix the tests

- [ ] Run `cd poc && ./test.sh`. It has **never been run**, so expect small fixes. Things most likely to need a fix:
  - API field names in responses (for example `team_info.spend` in `/team/info`, `key` in `/key/service-account/generate`). Check against the docs for v1.108.8.
  - Budget test timing: it waits 20 s for spend to be saved. LiteLLM writes spend in batches, so it may need longer.
  - Spend SQL joins `LiteLLM_SpendLogs.api_key` to `LiteLLM_VerificationToken.token`. Check that both hold the same hashed form.
  - The viewer test assumes a `proxy_admin_viewer` key is refused on `/key/generate`.
  - Qwen3.5 may spend tokens "thinking". If replies come back empty, raise `max_tokens` or find how to turn thinking off through LiteLLM's `ollama_chat`.
- [ ] Write the real results into README.md under "Test results".

### C. Small checks not done yet

- [ ] **Image signature not verified.** Only the signing key was checked (its PEM sha256 matches the fingerprint in LiteLLM's incident post: `e3fe3e08c44b16407fe0b37c43b4f8b603b3a0f4ee74c29e647bc022d762c2c0`). Run cosign as a container (`ghcr.io/sigstore/cosign/cosign:v2.4.1`, not pulled yet) with the command in the v1.108.8 release notes:
  `cosign verify --key https://raw.githubusercontent.com/BerriAI/litellm/e82a3c646908ba0a6ee0beddc4310d7a6cac4065/cosign.pub ghcr.io/berriai/litellm:v1.108.8`
  (the notes say the same command works for `litellm-database`).
- [ ] Record the image **digests** of all three images in `up.sh` (pin by digest, not only by tag).
- [ ] **Prometheus:** not known if it is free in v1.108.8. Some older docs marked it Enterprise. Check, else use OpenTelemetry.
- [ ] **Tag tracking:** docs are unclear whether basic tag-based spend tracking is free (tag *budgets* are Enterprise). Check in the PoC.

### D. Demo items after tests pass

- [ ] Admin UI walk-through: invite a named admin, log in as them, then set `disable_env_credential_login: true` so the shared `admin` login stops working.
- [ ] Simple cost dashboard (Grafana on the Postgres `LiteLLM_SpendLogs` table).
- [ ] Optional: one free-tier cloud model (for example Gemini free tier) with fallback to local. **Cru staff must put the API key in `poc/.env`**; do not type it for them. Look up the current model ID in Google AI Studio; it was left as a placeholder in `config.yaml`.

### E. Later (only when the user asks)

- [ ] Phase 0 questions in [implementation-plan.md](implementation-plan.md): production host, GPU for local models, direct vs cloud providers, data rules (what must stay local, is DeepSeek OK), logging of prompts, size, budgets.
- [ ] Access-as-code CLI (`tools/cru-gw`), monitoring, hardening, pilot, production.

## 3. Context from the session that is easy to lose

- The user writes in Thai. Replies in Thai, docs in English, no em dashes, simple words.
- The user wrote "LightLLM" but meant **LiteLLM**. LightLLM (ModelTC) is a GPU model server, not a gateway.
- User decisions, in order:
  1. Every admin gets their own user account; tokens are issued per app, service, or user.
  2. **Open source only**, but must be able to route to paid models (GPT, Gemini, Claude, DeepSeek) and to local models.
  3. PoC first, free things only.
  4. Local model around 0.8B, then **Q2 quantization** "so it can run". (Q2_K is 464 MB vs Q4_K_M 579 MB; Q4 is better quality if Q2 answers are too poor.)
- Why v1.108.8: it was the newest **LTS** release (published 2026-11-13). Releases after the October 2026 attack are signed with a new key; v1.111.0-dev.3 and later use keyless cosign.
- Why plain `docker run` instead of Compose, and why Ollama is in Docker: Homebrew on this Mac is owned by another macOS user (`nohrsom`), so `brew install` fails. Do not change that ownership.
- Machine: Apple M1, 8 GB RAM, Docker via Colima (VM set to 8 CPU / 8 GiB).
- Demo prices in `config.yaml` (`input_cost_per_token: 0.000001`, `output_cost_per_token: 0.000002`) are fake. They exist only so budget and cost tests work with a free model.
- Privacy default chosen: `turn_off_message_logging: true` (metadata and cost only).

## 4. Files

| File | What it is |
|---|---|
| [README.md](README.md) | Start here: status, decisions, how to run, gotchas |
| [CLAUDE.md](CLAUDE.md) | Rules for Claude sessions in this folder |
| HANDOFF.md | This file: pending work |
| [litellm-ai-gateway-study.md](litellm-ai-gateway-study.md) | Research, sources |
| [implementation-plan.md](implementation-plan.md) | Full plan (on hold) |
| `poc/up.sh`, `down.sh`, `test.sh`, `config.yaml`, `.env.example` | PoC |
| `poc/.env` | Test secrets (git-ignored, do not print) |
