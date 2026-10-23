#!/usr/bin/env bash
# Exports the project workflows from the running n8n into n8n/workflows/ (clean, ready to commit).
# Usage: ./scripts/export-workflows.sh
set -euo pipefail
# Git Bash on Windows rewrites paths like /repo/... into C:/...; this keeps them as container paths
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

# file name -> workflow id
declare -A WORKFLOWS=(
  [sms-ai-receptionist]=sM3rT8wQ2kV6nB4x
  [tool-check-availability]=u4zk3B48hPfoFaaa
  [tool-book-appointment]=tCInZXEmBEsGlo9t
  [tool-get-my-appointments]=4e88mmZwNoHCeo16
  [tool-cancel-appointment]=5Iy94ttvJAAoeHMJ
  [tool-reschedule-appointment]=FK9P24mIWJfyvTCV
  [sync-google-calendar]=6j99EaNwCWiWzInA
  [daily-maintenance]=ltnx0Bx5jpnZAskJ
  [tool-search-clinic-documents]=K5dRw9Tn3QxP7mZb
)

for name in "${!WORKFLOWS[@]}"; do
  docker compose exec -T n8n n8n export:workflow --id="${WORKFLOWS[$name]}" --pretty --output="/repo/workflows/$name.json"
done

docker compose exec -T n8n node /repo/scripts/clean-export.js
