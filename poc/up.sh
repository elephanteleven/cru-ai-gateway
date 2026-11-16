#!/usr/bin/env bash
# Start the Cru AI Gateway PoC: Postgres + Ollama (local model) + LiteLLM.
# Everything runs in Docker. Ports are bound to 127.0.0.1 only.
set -euo pipefail
cd "$(dirname "$0")"

# Pinned versions. Never use "latest".
LITELLM_IMAGE="ghcr.io/berriai/litellm-database:v1.108.8"   # LTS
OLLAMA_IMAGE="ollama/ollama:0.40.16"
POSTGRES_IMAGE="postgres:16.10-alpine"
LOCAL_MODEL="hf.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF:Q2_K"   # 464 MB. Q4_K_M is 579 MB, better quality.
NET="cru-ai-poc"

# Create .env with random test secrets on first run. Values are never printed.
if [ ! -f .env ]; then
  rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }
  cat > .env <<EOF
LITELLM_MASTER_KEY=sk-$(rand 32)
UI_USERNAME=admin
UI_PASSWORD=$(rand 20)
POSTGRES_PASSWORD=$(rand 24)
EOF
  chmod 600 .env
  echo "Created .env with new test secrets."
fi
set -a; source .env; set +a

docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null

start() { # name, docker run args...
  local name=$1; shift
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    docker start "$name" >/dev/null
  else
    docker run -d --name "$name" --network "$NET" --restart unless-stopped "$@" >/dev/null
  fi
  echo "started $name"
}

start cru-postgres \
  -e POSTGRES_USER=litellm -e POSTGRES_DB=litellm -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -v cru-pgdata:/var/lib/postgresql/data \
  "$POSTGRES_IMAGE"

start cru-ollama \
  -v cru-ollama:/root/.ollama \
  -p 127.0.0.1:11434:11434 \
  "$OLLAMA_IMAGE"

echo "Pulling local model $LOCAL_MODEL (first time takes a while)..."
until docker exec cru-ollama ollama list >/dev/null 2>&1; do sleep 1; done
docker exec cru-ollama ollama pull "$LOCAL_MODEL" >/dev/null
echo "model ready"

start cru-litellm \
  -e LITELLM_MASTER_KEY -e UI_USERNAME -e UI_PASSWORD \
  -e DATABASE_URL="postgresql://litellm:${POSTGRES_PASSWORD}@cru-postgres:5432/litellm" \
  -v "$PWD/config.yaml:/app/config.yaml:ro" \
  -p 127.0.0.1:4000:4000 \
  "$LITELLM_IMAGE" --config /app/config.yaml --port 4000

echo -n "Waiting for gateway"
until curl -sf http://127.0.0.1:4000/health/liveliness >/dev/null; do echo -n "."; sleep 2; done
echo
echo "Gateway:  http://127.0.0.1:4000"
echo "Admin UI: http://127.0.0.1:4000/ui  (user/password in poc/.env)"
