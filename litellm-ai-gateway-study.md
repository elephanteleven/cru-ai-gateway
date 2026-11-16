# LiteLLM as Cru's AI Gateway: Study Notes

Date: 2026-11-16
Status: first study, not yet tested hands-on

## 0. Name check: LiteLLM vs LightLLM

These are two different projects.

| | LiteLLM (BerriAI) | LightLLM (ModelTC) |
|---|---|---|
| What it is | AI gateway / proxy in front of 100+ LLM providers | Engine that runs open models on your own GPUs |
| Fits the Cru goal? | Yes. Keys, cost, logs, routing | No. It serves models, it does not govern traffic |
| License | MIT core + paid Enterprise key | Apache-2.0 |

The goal (one central entry point, control, monitoring, cost) matches **LiteLLM**. LightLLM only matters later if Cru wants to host its own open models on GPUs. Then LiteLLM would sit in front of it like any other provider.

## Decisions so far

- **Open source only.** Use the LiteLLM MIT core, with no Enterprise license key. Do not use or change code in the `enterprise/` folder (it has a different license).
- **Paid models through the gateway:** OpenAI (GPT), Google Gemini, Anthropic Claude, DeepSeek.
- **Local models through the same gateway:** e.g. Ollama or vLLM, or any OpenAI-compatible server.
- Named user per admin, service account keys per app/service, personal keys per user (see 3.1).

## 1. What Cru wants

1. One central service that every app (internal tools, custom apps, services) calls for AI.
2. Control: who can use which models, with limits.
3. Monitor AI traffic.
4. See cost, split by team / app / user.

## 2. How LiteLLM fits

```
 Apps / services / custom tools
        |  (OpenAI-style API, one virtual key per app or team)
        v
 +---------------------------+      +-------------+
 |  LiteLLM Proxy (gateway)  |----->|  Postgres   |  keys, teams, spend logs
 |  - auth (virtual keys)    |      +-------------+
 |  - budgets / rate limits  |      +-------------+
 |  - routing / fallbacks    |----->|  Redis      |  shared limits across replicas
 |  - guardrails             |      +-------------+
 |  - cost per request       |----->  Langfuse / Datadog / OTel / Prometheus
 +---------------------------+
        |  real provider keys live only here
        v
 OpenAI, Anthropic, Azure OpenAI, Bedrock, Vertex, Gemini, self-hosted models ...
```

Key idea: apps never see real provider keys. They get a LiteLLM "virtual key". Cru can turn a key off, cap its budget, or limit its models at any time.

## 3. Features vs Cru needs (from official docs)

| Need | LiteLLM feature | Free (OSS) or paid |
|---|---|---|
| Single entry point | OpenAI-compatible API for 100+ providers, Admin UI | Free |
| Per-app access | Virtual keys with team, model list, budget, rate limits | Free |
| Cost per request | Cost from model price map, returned in `x-litellm-response-cost`, saved in `LiteLLM_SpendLogs` | Free |
| Cost by key / user / team / model | Spend logs and daily activity views | Free |
| Cost by tag (e.g. project, department) | Tags on request, key, or team | Basic tracking appears free; tag **budgets** are Enterprise. Verify. |
| Spend reports (`/global/spend/report`) | Group by team, etc. | Enterprise |
| Budgets and rate limits | Per key / team / user | Basic: free. Advanced (per-model per key, temp increase, soft-budget email): Enterprise |
| Reliability | Load balancing, retries, fallbacks across providers | Free |
| Monitoring | Prometheus, Langfuse, Datadog, OpenTelemetry, etc. | Free (team-based logging is Enterprise) |
| Guardrails / PII | Custom guardrails, Presidio PII masking | Free. Per-key/team guardrails and many built-in moderation plugins: Enterprise |
| MCP gateway | Central MCP tool access | Free |
| Staff login to Admin UI | SSO | Free up to 5 users, then Enterprise |
| Who did what | Audit logs | Enterprise |
| Org / team admins | RBAC | Enterprise |
| Secrets | AWS / Azure / GCP / Vault secret managers, key rotation | Enterprise |

Enterprise pricing is not public ("based on usage", contact sales, 30-day free trial). Third-party sites quote about $250/month (basic) to about $30k/year, but these numbers are **not verified**.

## 3.1 Access model: admin users and tokens

Requirement from Cru:
- Every team member who runs this service gets their own user account.
- Tokens (keys) are issued per app, per service, or per user who needs AI.

How LiteLLM does it (from the official docs, checked 2026-11-16):

**A. Admin accounts (people who run the gateway)**

| Role | Can do | Free or paid |
|---|---|---|
| `proxy_admin` | Full control: teams, users, keys, settings | Free |
| `proxy_admin_viewer` | Log in and see all keys and spend, cannot change anything | Free |
| `internal_user` | Log in, manage own keys (if team allows), see own spend | Free |
| `team_admin` | Manage one team and its members/keys | Enterprise |
| `org_admin` | Manage one organization | Enterprise |

Login options:
- **Email + password (free):** invite each admin from the Admin UI ("Invite User") or `POST /user/new`. They set their own password from the invite link. Password policy: 12+ chars with mixed types. Brute force lockout is built in.
- **SSO (Google / Microsoft / Okta / OIDC):** free up to 5 users, then needs Enterprise.
- **Shared bootstrap login** (`UI_USERNAME` / `UI_PASSWORD` or master key): only for first setup. Turn it off after with `disable_env_credential_login: true` so every admin must use a named account.

**B. Tokens for apps, services, and users**

| Who uses it | Key type | Notes |
|---|---|---|
| App or backend service | **Service account key** (`/key/service-account/generate`, needs `team_id`) | Not tied to a person, so it keeps working when staff leave. Free. |
| A person (developer, staff) | **Personal virtual key** (`/key/generate` with `user_id`, optional `team_id`) | Spend is tracked to that person. Free. |

Each key can have: allowed models, budget + reset period, TPM/RPM limits, expiry (`duration`), and metadata/tags. Keys can be blocked or unblocked at once (free). Regenerate and scheduled auto-rotation of keys is Enterprise.

**C. Suggested setup for Cru**

1. One **team** per department or product. Teams are the top boundary in the free version.
2. Each app or service gets a **service account key** in its team, with only the models it needs and a monthly budget.
3. Staff who need direct access get a **personal key** under their team.
4. Admins get named accounts: 1 to 2 `proxy_admin`, the rest `proxy_admin_viewer` or `internal_user`.
5. Keep the master key in a secret manager. Only use it for break-glass.
6. Set an expiry on personal keys (for example 90 days).

**What forces Enterprise for this requirement:**
- More than 5 people logging in with SSO (email + password stays free).
- Delegating management to team admins instead of central proxy admins.
- An audit log of which admin made which change. Important for an org service, so plan for it.
- One-click key rotation (without it, rotate by creating a new key, then blocking or deleting the old one).

Sources: [access control](https://docs.litellm.ai/docs/proxy/access_control), [Admin UI](https://docs.litellm.ai/docs/proxy/ui), [SSO](https://docs.litellm.ai/docs/proxy/admin_ui_sso), [virtual keys](https://docs.litellm.ai/docs/proxy/virtual_keys), [service accounts](https://docs.litellm.ai/docs/proxy/service_accounts), [budgets](https://docs.litellm.ai/docs/proxy/users).

## 3.2 Providers and local models (all free in OSS)

| Target | How LiteLLM routes it (config prefix) |
|---|---|
| OpenAI GPT | `openai/` |
| Google Gemini | `gemini/` (AI Studio) or `vertex_ai/` (Google Cloud) |
| Anthropic Claude | `anthropic/` (also `bedrock/` or `vertex_ai/` if bought via a cloud) |
| DeepSeek | `deepseek/` |
| Local: Ollama | `ollama_chat/` + local `api_base` |
| Local: vLLM | `hosted_vllm/` + `api_base` |
| Local: any OpenAI-compatible server | `openai/` + custom `api_base` |

Apps call one model name (e.g. `cru-chat`). The gateway decides if it goes to a paid API or a local model, and can fall back from one to the other. Local models can be given a $0 or custom price so cost reports stay complete.

Sources: [providers](https://docs.litellm.ai/docs/providers), [Ollama](https://docs.litellm.ai/docs/providers/ollama), [vLLM](https://docs.litellm.ai/docs/providers/vllm), [config](https://docs.litellm.ai/docs/proxy/configs).

## 3.3 Gaps from going open source only, and workarounds

| Missing in OSS | Workaround |
|---|---|
| SSO for more than 5 users | Use email + password accounts for admins (free). Keep SSO for at most 5. |
| Audit log of admin actions | Keep admins few. Manage teams/keys through a script or GitOps repo so changes are in git history. Ship proxy logs to central logging. |
| Team admin / org admin | Only central `proxy_admin`s create teams and keys. Use a request process (ticket/form). |
| One-click key rotation | Create a new key, update the app, then block and delete the old key. |
| `/global/spend/report`, tag budgets, per-model budget per key | Build cost dashboards from the `LiteLLM_SpendLogs` table in Postgres and from Prometheus metrics (Grafana / Metabase). Use team and key budgets (free) instead. |
| Built-in moderation plugins, per-key guardrails | Use free custom guardrails and Presidio PII masking. |
| Secret manager integration | Inject provider keys as environment variables from the platform (e.g. Kubernetes secrets, Docker secrets). |

## 4. Big risk: supply chain security

LiteLLM holds every provider key Cru has, so a bad release is very costly. It has been hit twice in 2026:

- **Mar 24, 2026:** bad PyPI versions 1.82.7 and 1.82.8 (credential stealer), live about 40 minutes. Cause: compromised Trivy scanner in their CI leaked the PyPI token.
- **Oct 21, 2026:** bad `1.107.0` on PyPI and on Docker Hub / GHCR, including the `latest`, `main-latest`, `main-stable` tags, live for about 2 to 3 hours. Cause (their own record): an admin key leaked to a public repo in May led to stolen GitHub tokens, and attackers published from a lookalike fork. The private enterprise registry was not affected.

What they changed: rotated the signing key (Oct 23), and since v1.111.0-dev.3 releases use keyless cosign signing.

**What this means for Cru (must-do if we adopt it):**

1. Never use `latest` or floating tags. Pin an exact version and the image digest.
2. Verify the image signature (cosign) before deploy.
3. Wait a few days before taking a new release. Do not auto-update.
4. Keep provider keys in a secret manager, give the gateway only the access it needs, and limit its outbound network to the provider endpoints.
5. Have a key rotation runbook ready (provider keys, master key, DB password).

## 5. Other options to compare

From vendor blogs, so treat as leads, not facts:

- **Bifrost** (Go, Apache-2.0): pitched as faster, fewer features gated.
- **Kong AI Gateway**: good if Cru already uses Kong. Advanced AI proxy needs a paid license.
- **Envoy AI Gateway, Higress, WSO2 AI Gateway**: Envoy-based options.
- **Portkey**: open gateway is MIT, but reports say Palo Alto Networks bought it in May 2026 and the OSS repo has slowed. Check before relying on it.
- **Cloud native** (Azure API Management AI gateway, AWS Bedrock, etc.): less to run if Cru is on one cloud.

## 6. Suggested next steps

1. Confirm needs: which providers, rough monthly volume, how many teams/apps, does Cru need SSO for more than 5 admins, audit logs, and cost by department.
2. Run a small proof of concept: LiteLLM (pinned version) + Postgres + Redis in Docker, 2 providers, 2 test teams, Prometheus + Grafana dashboard. Check that cost numbers match provider bills.
3. Decide free vs Enterprise based on the gaps (SSO, audit logs, RBAC, spend reports). Ask LiteLLM sales for a quote and the 30-day trial.
4. Do a quick side-by-side PoC with one alternative (e.g. Bifrost or Kong) using the same test.
5. Write the security plan from section 4 before any production use.

## Sources

Official:
- LiteLLM Enterprise: https://docs.litellm.ai/docs/enterprise
- LiteLLM Proxy: https://docs.litellm.ai/docs/simple_proxy
- Cost tracking: https://docs.litellm.ai/docs/proxy/cost_tracking
- Oct 2026 incident: https://docs.litellm.ai/blog/security-incident-oct-21-2026
- Oct 2026 attack chain: https://docs.litellm.ai/blog/security-incident-oct-21-2026-attack-chain
- Mar 2026 incident: https://docs.litellm.ai/blog/security-update-march-2026
- LightLLM: https://github.com/ModelTC/lightllm

Third party:
- Datadog Security Labs on the compromise: https://securitylabs.datadoghq.com/articles/litellm-compromised-pypi-docker/
- JFrog on 1.107.0: https://research.jfrog.com/post/litellm-hijacked-again/
- JFrog on March: https://research.jfrog.com/post/litellm-compromised-teampcp/
- TrueFoundry LiteLLM pricing guide (unverified prices): https://www.truefoundry.com/blog/litellm-pricing-guide
- Alternatives roundup (vendor blog): https://getmaxim.ai/articles/top-litellm-alternatives-in-2026/
