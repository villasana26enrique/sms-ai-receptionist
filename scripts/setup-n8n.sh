#!/usr/bin/env bash
# Sets up a fresh n8n with everything this project needs: credentials (from .env), workflows and publishing.
# Usage: docker compose up -d && ./scripts/setup-n8n.sh
# Only manual step left: open the "Google Calendar account" credential in n8n and click "Sign in with Google".
set -euo pipefail
# Git Bash on Windows rewrites paths like /repo/... into C:/...; this keeps them as container paths
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

# ENV_FILE / COMPOSE_PROJECT_NAME allow targeting another environment (e.g. a throwaway test stack)
ENV_FILE="${ENV_FILE:-.env}"
set -a; source "$ENV_FILE"; set +a
docker() { if [ "$1" = compose ]; then shift; command docker compose --env-file "$ENV_FILE" "$@"; else command docker "$@"; fi; }

# Secrets go to this one command only; they are never stored in the n8n container's environment
docker compose exec -T \
  -e POSTGRES_DB -e POSTGRES_USER -e POSTGRES_PASSWORD \
  -e TWILIO_ACCOUNT_SID -e TWILIO_AUTH_TOKEN \
  -e GEMINI_API_KEY -e GOOGLE_OAUTH_CLIENT_ID -e GOOGLE_OAUTH_CLIENT_SECRET -e RAG_SEARCH_API_KEY \
  n8n sh -c 'node /repo/scripts/build-credentials.js \
    && n8n import:credentials --input=/tmp/credentials-to-import.json \
    ; rm -f /tmp/credentials-to-import.json'

ENV_FILE="$ENV_FILE" ./scripts/reload-workflows.sh
echo "Done. Last step: in n8n, open the 'Google Calendar account' credential and click 'Sign in with Google'."
