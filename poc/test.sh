#!/usr/bin/env bash
# PoC checks for the Cru AI Gateway. Keys are kept in variables and never printed.
# Run after ./up.sh. Creates demo teams/users/keys with a run id so it can be re-run.
set -uo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a
GW=http://127.0.0.1:4000
MK="$LITELLM_MASTER_KEY"
RUN=$(date +%H%M%S)
PASS=0; FAIL=0

ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1  ($2)"; FAIL=$((FAIL+1)); }
api()  { # method path key [json] -> body, sets CODE
  local out; out=$(curl -s -w '\n%{http_code}' -X "$1" "$GW$2" -H "Authorization: Bearer $3" -H 'Content-Type: application/json' ${4:+-d "$4"})
  CODE=${out##*$'\n'}; BODY=${out%$'\n'*}
}
jget() { python3 -c "import sys,json;d=json.loads(sys.argv[1]);print(eval(sys.argv[2]))" "$BODY" "$1" 2>/dev/null; }
chat() { # key model
  api POST /v1/chat/completions "$1" "{\"model\":\"$2\",\"max_tokens\":40,\"messages\":[{\"role\":\"user\",\"content\":\"Say hi to Cru in one short sentence.\"}]}"
}

echo "== 1. Gateway health"
api GET /health/liveliness "$MK"; [ "$CODE" = 200 ] && ok "gateway is up" || bad "gateway is up" "$CODE"

echo "== 2. Chat through the gateway (local model)"
START=$(python3 -c 'import time;print(time.time())')
chat "$MK" cru-chat
SECS=$(python3 -c "import time;print(round(time.time()-$START,1))")
if [ "$CODE" = 200 ]; then
  ok "cru-chat answered in ${SECS}s: $(jget "repr((d['choices'][0]['message'].get('content') or '')[:80])")"
  echo "        tokens: $(jget "d['usage']")"
else bad "cru-chat answered" "$CODE $(echo "$BODY" | head -c 200)"; fi

echo "== 3. Team + service account key for an app (only cru-local allowed)"
api POST /team/new "$MK" "{\"team_alias\":\"demo-team-$RUN\",\"max_budget\":5,\"budget_duration\":\"30d\",\"models\":[\"cru-chat\",\"cru-local\"]}"
TEAM=$(jget "d['team_id']")
[ -n "$TEAM" ] && ok "team created" || bad "team created" "$CODE $(echo "$BODY" | head -c 200)"
api POST /key/service-account/generate "$MK" "{\"team_id\":\"$TEAM\",\"key_alias\":\"demo-app-$RUN\",\"models\":[\"cru-local\"],\"metadata\":{\"service_account_id\":\"demo-app-$RUN\"},\"tags\":[\"app:demo\"]}"
APPKEY=$(jget "d['key']")
[ -n "$APPKEY" ] && ok "service account key issued" || bad "service account key issued" "$CODE $(echo "$BODY" | head -c 200)"
chat "$APPKEY" cru-local;  [ "$CODE" = 200 ] && ok "app key can call cru-local" || bad "app key can call cru-local" "$CODE"
chat "$APPKEY" cru-chat;   [ "$CODE" != 200 ] && ok "app key blocked from cru-chat (HTTP $CODE)" || bad "app key blocked from cru-chat" "$CODE"

echo "== 4. Personal key for a user"
api POST /user/new "$MK" "{\"user_email\":\"demo-user-$RUN@example.com\",\"user_role\":\"internal_user\",\"teams\":[\"$TEAM\"]}"
USERID=$(jget "d['user_id']")
api POST /key/generate "$MK" "{\"user_id\":\"$USERID\",\"team_id\":\"$TEAM\",\"key_alias\":\"demo-user-$RUN\",\"duration\":\"90d\"}"
USERKEY=$(jget "d['key']")
[ -n "$USERKEY" ] && ok "personal key issued (90 day expiry)" || bad "personal key issued" "$CODE $(echo "$BODY" | head -c 200)"
chat "$USERKEY" cru-chat; [ "$CODE" = 200 ] && ok "user key can call cru-chat" || bad "user key can call cru-chat" "$CODE"

echo "== 5. Rate limit (rpm_limit=1)"
api POST /key/generate "$MK" "{\"team_id\":\"$TEAM\",\"key_alias\":\"demo-rpm-$RUN\",\"rpm_limit\":1}"
RPMKEY=$(jget "d['key']")
chat "$RPMKEY" cru-chat; C1=$CODE
chat "$RPMKEY" cru-chat; C2=$CODE
[ "$C1" = 200 ] && [ "$C2" = 429 ] && ok "2nd call in same minute rejected (429)" || bad "rate limit" "first=$C1 second=$C2"

echo "== 6. Budget (max_budget tiny, demo price)"
api POST /key/generate "$MK" "{\"team_id\":\"$TEAM\",\"key_alias\":\"demo-budget-$RUN\",\"max_budget\":0.00001}"
BKEY=$(jget "d['key']")
chat "$BKEY" cru-chat; C1=$CODE
echo "        waiting 20s for spend to be saved..."; sleep 20
chat "$BKEY" cru-chat; C2=$CODE
[ "$C1" = 200 ] && [ "$C2" != 200 ] && ok "over-budget key rejected (HTTP $C2)" || bad "budget" "first=$C1 second=$C2"

echo "== 7. Block a key"
api POST /key/block "$MK" "{\"key\":\"$USERKEY\"}"
chat "$USERKEY" cru-chat; [ "$CODE" != 200 ] && ok "blocked key rejected (HTTP $CODE)" || bad "blocked key rejected" "$CODE"

echo "== 8. Viewer admin cannot issue keys"
api POST /user/new "$MK" "{\"user_email\":\"demo-viewer-$RUN@example.com\",\"user_role\":\"proxy_admin_viewer\"}"
VID=$(jget "d['user_id']")
api POST /key/generate "$MK" "{\"user_id\":\"$VID\",\"key_alias\":\"demo-viewer-$RUN\"}"
VKEY=$(jget "d['key']")
api POST /key/generate "$VKEY" "{\"key_alias\":\"should-fail-$RUN\"}"
[ "$CODE" != 200 ] && ok "viewer blocked from /key/generate (HTTP $CODE)" || bad "viewer blocked from /key/generate" "$CODE"

echo "== 9. Spend tracking"
echo "        waiting 15s for spend to be saved..."; sleep 15
api GET "/team/info?team_id=$TEAM" "$MK"
echo "        team spend: \$$(jget "d['team_info']['spend']")"
docker exec cru-postgres psql -U litellm -d litellm -At -F ' | ' -c \
  "select coalesce(k.key_alias,'(master)') as key, s.model_group, count(*) as calls, sum(s.prompt_tokens) as in_tok, sum(s.completion_tokens) as out_tok, round(sum(s.spend)::numeric,6) as spend
   from \"LiteLLM_SpendLogs\" s left join \"LiteLLM_VerificationToken\" k on k.token = s.api_key
   group by 1,2 order by 1" 2>&1 | sed 's/^/        /'
N=$(docker exec cru-postgres psql -U litellm -d litellm -At -c "select count(*) from \"LiteLLM_SpendLogs\" where team_id='$TEAM'")
[ "${N:-0}" -gt 0 ] && ok "spend rows saved for team ($N)" || bad "spend rows saved for team" "$N"

echo
echo "Result: $PASS passed, $FAIL failed"
