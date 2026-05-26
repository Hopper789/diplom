#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALERTS_ENV="$ROOT_DIR/config/alerts.env"
MONITORING_ENV="$ROOT_DIR/monitoring/.env"
COMPOSE_FILE="$ROOT_DIR/monitoring/docker-compose.yml"

cd "$ROOT_DIR"

if [[ ! -f "$ALERTS_ENV" ]]; then
  echo "Не найден config/alerts.env."
  echo
  echo "Создай его перед запуском:"
  echo "  cp config/alerts.example.env config/alerts.env"
  echo "  nano config/alerts.env"
  exit 1
fi

if [[ ! -f "$MONITORING_ENV" ]]; then
  echo "Не найден monitoring/.env."
  echo "Сначала запусти мониторинг:"
  echo "  ./scripts/monitoring_up.sh"
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Не найден monitoring/docker-compose.yml."
  exit 1
fi

mkdir -p "$ROOT_DIR/monitoring/alert-state"

docker compose -f "$COMPOSE_FILE" --profile alerts up -d --build boinc-alerts

echo
echo "Telegram alerts запущены."
echo "Логи:"
echo "  docker logs -f boinc-alerts"
