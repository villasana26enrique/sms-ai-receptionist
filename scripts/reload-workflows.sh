#!/usr/bin/env bash
# Imports every workflow in n8n/workflows/ (filling in values from .env) and publishes them all again,
# then restarts n8n. Importing unpublishes a workflow, so never import one without running this whole script
# (a scheduled workflow left unpublished simply stops running, without any error).
# Usage: ./scripts/reload-workflows.sh
set -euo pipefail
# Git Bash on Windows rewrites paths like /repo/... into C:/...; this keeps them as container paths
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-.env}"
set -a; source "$ENV_FILE"; set +a
docker() { if [ "$1" = compose ]; then shift; command docker compose --env-file "$ENV_FILE" "$@"; else command docker "$@"; fi; }

# The Twilio Auth Token goes into the signature check of the SMS workflow; the export puts the placeholder back
docker compose exec -T -e GOOGLE_CALENDAR_ID -e RAG_SEARCH_URL -e N8N_WEBHOOK_URL -e TWILIO_AUTH_TOKEN \
  n8n node /repo/scripts/prepare-import.js
docker compose exec -T n8n sh -c 'n8n import:workflow --separate --input=/tmp/workflows-to-import; status=$?; rm -rf /tmp/workflows-to-import; exit $status'

# Sub-workflows first, so the agent's tools exist when the agent is published
for id in u4zk3B48hPfoFaaa tCInZXEmBEsGlo9t 4e88mmZwNoHCeo16 5Iy94ttvJAAoeHMJ FK9P24mIWJfyvTCV K5dRw9Tn3QxP7mZb \
          sM3rT8wQ2kV6nB4x 6j99EaNwCWiWzInA ltnx0Bx5jpnZAskJ; do
  docker compose exec -T n8n n8n publish:workflow --id="$id"
done

# Published workflows are loaded at startup
docker compose restart n8n
