#!/usr/bin/env bash
# Send one chat message through the gateway, like an app would.
#
#   API_KEY=sk-... ./scripts/chat.sh -m cru-local "Hi, how are you?"
#
# Options:
#   -m MODEL   model name to call (default: cru-chat)
#   -t N       max tokens in the answer (default: 300)
#   -v         also print the raw JSON response
# Env:
#   API_KEY    virtual key (required). Never put it in a file in this repo.
#   GW_URL     gateway URL (default: http://127.0.0.1:<GW_PORT from .env, else 4000>)
# Needs: bash, curl, python3.
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

model=cru-chat max_tokens=300 verbose=0
while getopts "m:t:vh" opt; do
  case $opt in
    m) model=$OPTARG ;;
    t) max_tokens=$OPTARG ;;
    v) verbose=1 ;;
    h) usage 0 ;;
    *) usage 2 ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "error: no message given" >&2; usage 2; }
message="$*"

[ -n "${API_KEY:-}" ] || { echo "error: set API_KEY (a virtual key from the Admin UI)" >&2; exit 2; }

if [ -z "${GW_URL:-}" ]; then
  port=$(sed -n 's/^GW_PORT=//p' "$(dirname "$0")/../.env" 2>/dev/null | tail -1)
  GW_URL="http://127.0.0.1:${port:-4000}"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Build the JSON body safely (any quotes or Thai text in the message are fine).
python3 -I -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"max_tokens":int(sys.argv[2]),"messages":[{"role":"user","content":sys.argv[3]}]}))' \
  "$model" "$max_tokens" "$message" > "$tmp/body.json"

# The key goes in a header file, not on the curl command line (so it does not show in `ps`).
printf 'Authorization: Bearer %s\n' "$API_KEY" > "$tmp/auth"

start=$(date +%s.%N)
code=$(curl -sS -o "$tmp/resp.json" -D "$tmp/headers" -w '%{http_code}' \
  -H @"$tmp/auth" -H 'Content-Type: application/json' \
  --data-binary @"$tmp/body.json" "$GW_URL/v1/chat/completions") || { echo "error: cannot reach $GW_URL" >&2; exit 1; }
end=$(date +%s.%N)

python3 -I - "$tmp/resp.json" "$tmp/headers" "$code" "$start" "$end" "$model" "$verbose" <<'PY'
import json, sys
resp_path, hdr_path, code, start, end, asked, verbose = sys.argv[1:]
hdrs = {}
for line in open(hdr_path, encoding="utf-8", errors="replace"):
    if ":" in line:
        k, v = line.split(":", 1)
        hdrs[k.strip().lower()] = v.strip()
raw = open(resp_path, encoding="utf-8", errors="replace").read()
try:
    data = json.loads(raw)
except ValueError:
    data = None
secs = float(end) - float(start)

if code != "200":
    msg = raw
    if isinstance(data, dict) and isinstance(data.get("error"), dict):
        msg = data["error"].get("message", raw)
    print(f"HTTP {code}: {msg}", file=sys.stderr)
    sys.exit(1)

choice = data["choices"][0]
print(choice["message"].get("content") or "(empty answer)", flush=True)
usage = data.get("usage") or {}
info = [
    f"model: {asked} -> {hdrs.get('x-litellm-model-group', '?')} ({data.get('model', '?')})",
    f"time: {secs:.1f}s",
    f"tokens: {usage.get('prompt_tokens', '?')} in / {usage.get('completion_tokens', '?')} out",
    f"cost: ${float(hdrs.get('x-litellm-response-cost') or 0):.6f}",
    f"finish: {choice.get('finish_reason')}",
]
if hdrs.get("x-litellm-attempted-fallbacks", "0") not in ("0", ""):
    info.append(f"fallbacks: {hdrs['x-litellm-attempted-fallbacks']}")
for k in ("x-ratelimit-remaining-requests", "x-ratelimit-remaining-tokens"):
    if k in hdrs:
        info.append(f"{k[12:]}: {hdrs[k]}")
print("\n--- " + " | ".join(info), file=sys.stderr)
if verbose == "1":
    print(json.dumps(data, indent=2, ensure_ascii=False), file=sys.stderr)
PY
