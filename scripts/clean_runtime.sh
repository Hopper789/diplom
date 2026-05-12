#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PROJECT_NAME="${PROJECT_NAME:-my_project}"

if [[ -f "$ROOT_DIR/config/generated.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT_DIR/config/generated.env"
  set +a
fi

PROJECT_NAME="${PROJECT_NAME:-my_project}"

echo "Cleaning BOINC runtime data..."
echo "Project name: $PROJECT_NAME"
echo

echo "Stopping/removing local BOINC client..."
docker rm -f boinc-client 2>/dev/null || true

echo "Removing local BOINC client data..."
rm -rf "$ROOT_DIR/boinc-data"

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

echo
echo "Runtime cleanup completed."
echo
echo "Next steps:"
echo "  ./scripts/init_config.sh"
echo "  ./scripts/server_up.sh"