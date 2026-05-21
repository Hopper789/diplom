#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Cleaning BOINC runtime data..."
echo

echo "Stopping monitoring stack..."
if [[ -f "$ROOT_DIR/monitoring/docker-compose.yml" ]]; then
  (
    cd "$ROOT_DIR/monitoring"
    docker compose down -v --remove-orphans || true
  )
fi

echo "Stopping BOINC server stack..."
if [[ -f "$ROOT_DIR/server/docker-compose.yml" ]]; then
  (
    cd "$ROOT_DIR/server"
    docker compose down -v --remove-orphans || true
  )
fi

echo "Removing server runtime directories..."
rm -rf "$ROOT_DIR/server/project"
rm -rf "$ROOT_DIR/server/mysql-data"
mkdir -p "$ROOT_DIR/server/project"

echo "Removing dangling BOINC containers if any..."
docker rm -f boinc-server boinc-mysql 2>/dev/null || true

echo "Removing generated runtime configs..."
rm -f "$ROOT_DIR/config/generated.env"
rm -f "$ROOT_DIR/ansible/inventory.ini"
rm -f "$ROOT_DIR/ansible/group_vars/all.yml"
rm -f "$ROOT_DIR/monitoring/.env"

echo
echo "Runtime cleanup completed."
echo
echo "Next steps:"
echo "  ./scripts/init_config.sh"
echo "  ./scripts/server_up.sh"
