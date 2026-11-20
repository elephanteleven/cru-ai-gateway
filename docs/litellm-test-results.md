# LiteLLM test results: API, logs, SSO (2026-11-19/20)

LiteLLM v1.108.8 OSS, same `config.yaml` as this repo, Linux x86_64 (8 CPU, 31 GB, CPU only), same llama.cpp
models.
Okta was replaced by a local Keycloak with the same kind of `groups` claim. **Not tested with a real Okta org.**
Screenshots: `docs/screenshots/litellm-*.png`.

Source: test scripts, Keycloak setup, and raw results are in https://github.com/elephanteleven/cru-ai-alt.

| | LiteLLM |
|---|---|
| Version tested | v1.108.8 (LTS) |
| License | MIT core + paid `enterprise/` |
| Community (2026-11-19) | 63.5k stars, ~1,950 contributors |
| Language / image | Python / 1.73 GB |

## 1. API checks

Result: **24 pass, 1 fail** (the 5-user SSO cap, S7 below), 0 skipped.

| ID | Check | Result |
|---|---|---|
| 1.1-1.3 | health, admin needs login, chat needs key | PASS |
| 2.1-2.2 | chat, all 9 model names | PASS |
| 3.1 | team with $5/month budget | PASS |
| 3.2 | app (service account) key | PASS (owned by the team) |
| 3.3-3.5 | app key: allowed model only | PASS |
| 4.1-4.2 | personal key, 90 day expiry, works | PASS |
| 5.1 | 1 request/minute -> 429 | PASS |
| 6.1 | tiny budget refused | PASS (lets one call go over first) |
| 7.1 | block key | PASS |
| 8.1 | read-only admin cannot create keys | PASS |
| 9.1 | spend by team, key, model | PASS |
| 9.2 | refused calls in logs | 5 of 5 |
| 10.1 | `cru-cloud` fallback | PASS |
| 11.1 | Prometheus | PASS (needs the master key) |
| 12.1 | team and user, user in team | PASS |
| 12.2 | team key vs user key | PASS (a team key has no user) |
| 12.3 | logs say team or user | PASS |
| 12.4 | admin reads prompt + answer | PASS |
| 12.5 | refused calls logged with who + prompt | **FAIL**: who + reason yes, prompt only for 429 |
| 13.1 | restart keeps data | PASS |

### Who used it, and what is in the logs

Each prompt was tagged so its row in `LiteLLM_SpendLogs` (Admin UI > Logs) could be found.

| Call | What is logged |
|---|---|
| team key, OK | team, no user, prompt + answer |
| user key, OK | user + team, prompt + answer |
| model not allowed (403) | key, team, reason; no prompt |
| blocked key (401) | key, user, reason; no prompt |
| rate limited (429) | key, team, prompt |

- Prompts are stored only with `store_prompts_in_spend_logs: true` (off by default, on in this repo for the demo).
  One switch for the whole gateway. Every admin, `proxy_admin_viewer` included, can read every prompt and answer.
- Log retention seen: 30 days (`maximum_spend_logs_retention_period`).

## 2. SSO checks (Keycloak as Okta, generic OIDC)

Settings used: `GENERIC_CLIENT_ID`, `GENERIC_CLIENT_SECRET`, `GENERIC_*` endpoints, `GENERIC_USER_ID_ATTRIBUTE`,
`GENERIC_ROLE_MAPPINGS_*`, `STORE_MODEL_IN_DB=True`.

| ID | Result | Details |
|---|---|---|
| S1 | PASS | Generic OIDC login works; user created on first login (user_id = `preferred_username`). |
| S2 | PASS (free) | Group -> role with `GENERIC_ROLE_MAPPINGS_*`: ai-admins = `proxy_admin`, ai-viewers = `proxy_admin_viewer`, team-marketing = `internal_user`. A user with no group would get `internal_user_viewer` (not seen, S7 blocked it first). |
| S3 | PASS (free) | Group -> team with SSO setting `team_mappings.team_ids_jwt_field = groups`: the user was added to team `team-marketing` on login. The team must exist with `team_id` = the Okta group name. Needs `STORE_MODEL_IN_DB=True`. |
| S4 | Mixed | Role: an admin changed a user to `proxy_admin_viewer`; on the next login the group mapping set it back (Okta wins on roles). Teams added by hand were kept after re-login. |
| S5 | PASS | An SSO `internal_user` made a personal key and it worked. A key inside their team needed the admin to allow `/key/generate` once per team (`/team/permissions_update`). The user could not create teams or users (401). |
| S6 | PASS | `disable_env_credential_login: true` turns off the shared admin login. The master key on the API is the break-glass path. |
| S7 | **FAIL (paid)** | Free SSO stops for **everyone** once the DB has more than 5 users in total (`count_billable_users` counts all users, not only SSO users). With 6 users, `/sso/key/generate` returned 403 "You must be a LiteLLM Enterprise user to use SSO for more than 5 users", also for an admin. Screenshot: `litellm-sso-over-5-users.png`. |
| S8 | Docs | Okta works through the generic OIDC settings (`https://<org>.okta.com/oauth2/default/v1/...`). Not tested with a real Okta org. |

Gotchas:
- `PATCH /update/sso_settings` with only `team_mappings` saved nulls for the client settings, and DB values override
  env values, so SSO silently fell back to the password page. Always send the full set (client id/secret,
  endpoints, `proxy_base_url`).
- LiteLLM rejects emails on reserved domains (`.test`). Use something like `@cru.example.com` for test users.

### Identity: what ties an SSO login to a user

- `LiteLLM_UserTable.user_id` = the claim named by `GENERIC_USER_ID_ATTRIBUTE` (default `preferred_username`).
  Also `sso_user_id` and `user_email`. The IdP's `sub` is not used unless you set the attribute to `sub`.
- With the default, a person deleted and re-created in Okta (new `sub`, same username) stays the same user, but a
  renamed username makes a new user. Set `GENERIC_USER_ID_ATTRIBUTE=sub` to key on the Okta user id instead
  (stable across renames, but a re-created user becomes a new user).

### Offboarding: a person disabled in the IdP

- Their API key **still works**. An admin must block or delete the person's keys and account in LiteLLM by hand.
- New SSO login is refused by the IdP (here it was also blocked by S7).
- SCIM (automatic offboarding) exists but is Enterprise only (`premium_user_check` on the SCIM router).

## 3. Speed and size

100 warm calls, `gemma3-270m`, `max_tokens: 1`, two rounds.

| | p50 | p90 | p99 | Gateway RAM (idle) | DB RAM |
|---|---|---|---|---|---|
| Direct to llama (no gateway) | 21 ms | 23 ms | 25-27 ms | | |
| Through LiteLLM | 36 ms | 38-40 ms | 45-58 ms | ~710 MB | ~41 MB |

The gateway adds about 15 ms, small next to a real model call (seconds).

## 4. Gemini 30 s timeout on `cru-cloud`

A test-only server stood in for Gemini (only the address changed for the test).

| Upstream answers after | Result |
|---|---|
| 45 s (too slow) | Old config: cut at 30 s, **but tried 3 times** (router default `num_retries` 2), then `cru-local`: **95 s**. With `num_retries: 0`: one try, **30.8 s** |
| 20 s (in time) | Gemini answer in 20.0 s |

Fix in `config.yaml`: `num_retries: 0` on `cru-cloud`.

## 5. What this means for Cru (opinion, not a test result)

- LiteLLM covers keys, teams, budgets, limits, logs, and fallback for free, and its free SSO does the Okta part
  well (group -> role and group -> team).
- But free SSO **stops for everyone once more than 5 users exist** (all users, not only SSO users). So:
  1. LiteLLM free with at most 5 user accounts (the AI team) and team or service account keys for everyone else,
     no Okta login for other staff, or
  2. LiteLLM Enterprise (paid; ask for a quote) if Okta login is needed for more people.

## Not verified

- A real Okta org (only Keycloak): groups claim setup, https issuer, Okta app assignment.
- Load and multi-instance setups.
- An open browser session after the person is disabled in the IdP.
