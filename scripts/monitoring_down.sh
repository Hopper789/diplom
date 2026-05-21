#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$ROOT_DIR/monitoring/docker-compose.yml" ]]; then
  echo "Monitoring compose file not found."
  exit 0
fi

(
  cd "$ROOT_DIR/monitoring"
  docker compose down -v --remove-orphans
)

echo "Monitoring stopped."
