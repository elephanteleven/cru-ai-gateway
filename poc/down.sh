#!/usr/bin/env bash
# Stop the PoC. Data (keys, spend logs, model) is kept in Docker volumes.
# Use "./down.sh --wipe" to also delete containers, volumes, and the network.
set -uo pipefail
docker stop cru-litellm cru-ollama cru-postgres >/dev/null 2>&1
echo "stopped"
if [ "${1:-}" = "--wipe" ]; then
  docker rm cru-litellm cru-ollama cru-postgres >/dev/null 2>&1
  docker volume rm cru-pgdata cru-ollama >/dev/null 2>&1
  docker network rm cru-ai-poc >/dev/null 2>&1
  echo "wiped containers, volumes, network"
fi
