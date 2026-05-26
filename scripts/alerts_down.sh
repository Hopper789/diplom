#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/monitoring/docker-compose.yml"

cd "$ROOT_DIR"

if [[ -f "$COMPOSE_FILE" ]]; then
  docker compose -f "$COMPOSE_FILE" --profile alerts stop boinc-alerts 2>/dev/null || true
  docker compose -f "$COMPOSE_FILE" --profile alerts rm -f boinc-alerts 2>/dev/null || true
else
  docker rm -f boinc-alerts 2>/dev/null || true
fi

echo "Telegram alerts остановлены."
