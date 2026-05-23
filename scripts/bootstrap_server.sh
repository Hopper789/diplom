#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "== BOINC server bootstrap =="
echo

if [[ ! -f "$ROOT_DIR/config/cluster.yml" ]]; then
  echo "ERROR: config/cluster.yml not found."
  echo
  echo "Create it first:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  echo "  nano config/cluster.yml"
  exit 1
fi

echo "Making scripts executable..."
chmod +x "$ROOT_DIR"/scripts/*.sh 2>/dev/null || true
chmod +x "$ROOT_DIR"/apps/ml_grid_search/run_task.sh 2>/dev/null || true
chmod +x "$ROOT_DIR"/server/entrypoint.sh 2>/dev/null || true
chmod +x "$ROOT_DIR"/server/scripts/*.sh 2>/dev/null || true

echo
echo "Generating runtime config..."
./scripts/init_config.sh

echo
echo "Starting BOINC server..."
./scripts/server_up.sh

echo
echo "Creating or looking up BOINC account..."
./scripts/create_account_db.sh

echo
echo "Server status:"
./scripts/status.sh || true

echo
echo "Server bootstrap completed."
echo
echo "Next step:"
echo "  ./scripts/bootstrap_clients.sh --ask-become-pass"
