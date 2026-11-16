# CLAUDE.md

Project: Cru AI Gateway (LiteLLM, open source only). **Read [README.md](README.md) first**, then [HANDOFF.md](HANDOFF.md) for the list of pending work. Tick items in HANDOFF.md as you finish them.

## Working rules

- Reply to the user in the language they write in (usually Thai). Write docs, code, and comments in English.
- No em dashes. Plain, simple words.
- **Open source only.** Do not suggest or enable LiteLLM Enterprise features or a license key. Do not use code from LiteLLM's `enterprise/` folder. If a need is Enterprise-only, propose a free workaround.
- **PoC uses free things only** unless the user says otherwise. No paid API calls.
- **Never use floating image tags** (`latest`, `lts`, `main-*`). Pin exact versions. Check release notes and dates before upgrading LiteLLM (it had supply chain attacks in 2026; see README).
- **Secrets:** they live in `poc/.env` only. Never print, log, commit, or paste them in chat. Do not type real provider API keys; Cru staff add those.
- **Do not run `brew install` or change `/opt/homebrew` ownership.** Homebrew belongs to another macOS user. Use Docker containers instead.
- Docker runs through Colima. There is no `docker compose` plugin; scripts use plain `docker run`.
- Machine is an 8 GB M1. Keep local models small (current: Qwen3.5 0.8B Q2_K).
- Verify claims about LiteLLM against the official docs (docs.litellm.ai) for the pinned version, and say what was not verified.

## Keep docs current

When you change the PoC or learn something new, update README.md (Status, Test results, Known issues, Next steps). Big research or plan changes go in `litellm-ai-gateway-study.md` or `implementation-plan.md`.
