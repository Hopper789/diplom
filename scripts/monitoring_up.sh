#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
MONITORING_DIR="$ROOT_DIR/monitoring"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found."
  echo "Run: ./scripts/init_config.sh"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if ! docker network inspect server_default >/dev/null 2>&1; then
  echo "ERROR: Docker network server_default not found."
  echo "Run server first:"
  echo "  ./scripts/server_up.sh"
  exit 1
fi

mkdir -p "$MONITORING_DIR"

cat > "$MONITORING_DIR/.env" <<ENVEOF
PROJECT_NAME=$PROJECT_NAME
PROJECT_URL=$BOINC_PROJECT_URL
MYSQL_HOST=boinc-mysql
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=root
MYSQL_DATABASE=$PROJECT_NAME
ENVEOF

(
  cd "$MONITORING_DIR"
  docker compose up -d --build
)

echo
echo "Monitoring is running:"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana:    http://localhost:3000"
echo "  Exporter:   http://localhost:9101/metrics"
echo
echo "Grafana login:"
echo "  admin / admin"
