# CLAUDE.md

Project: Cru AI Gateway (LiteLLM, open source only). **Read [README.md](README.md) first.** Its "Next steps" list is the pending work; update it as you finish items.

## Working rules

- Reply to the user in the language they write in (usually Thai). Write docs, code, and comments in English.
- No em dashes. Plain, simple words.
- **Open source only.** Do not suggest or enable LiteLLM Enterprise features or a license key. Do not use code from LiteLLM's `enterprise/` folder. If a need is Enterprise-only, propose a free workaround.
- **Paid OpenRouter calls are allowed for the demo** (user, 2026-11-20). Keep test calls small.
- **Never use floating image tags** (`latest`, `lts`, `main-*`). Pin exact versions. Check release notes and dates before upgrading LiteLLM (it had supply chain attacks in 2026; see README).
- **Secrets:** they live in `.env` (local, git-ignored) or in Coolify only. Never print, log, commit, or paste them in chat. Do not type real provider API keys; Cru staff add those.
- **Do not run `brew install` or change `/opt/homebrew` ownership.** Homebrew belongs to another macOS user. Use Docker containers instead.
- Two machines so far: an 8 GB M1 Mac (Docker through Colima, no `docker compose` plugin) and a Linux x86_64 box (native Docker with compose, port 4000 taken, so `GW_PORT=4400`). Deploy target is **Coolify** via the root `docker-compose.yml`. Check `uname -m` first.
- Keep the repo small: no helper scripts that repeat what `docker compose` or the Admin UI already do (user asked for a clean setup on 2026-11-17). Exception the user asked for: `scripts/chat.sh`, a test client that calls the gateway like an app.
- Do not `git commit` until the user says so.
- **No local LLM service is deployed** (user rule, 2026-11-20). Every model goes through OpenRouter; the name to call is the OpenRouter model id, no alias names. The list is in README "Models" and `config.yaml`. Paid models are OK for the demo (user said money is not a problem). On Linux, leave the unrelated `ab-development-*` containers alone.
- **Coolify at https://cru.engineer:** only touch the cru-ai-gateway resource. Never change or delete other projects.
- Verify claims about LiteLLM against the official docs (docs.litellm.ai) for the pinned version, and say what was not verified.

## Keep docs current

When you change the PoC or learn something new, update README.md (Test results, Known issues, Next steps) and `docs/coolify.md` if deploy changes. Big research or plan changes go in `docs/litellm-ai-gateway-study.md` or `docs/implementation-plan.md`.
