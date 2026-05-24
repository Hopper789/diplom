#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== BOINC server bootstrap =="

if [[ ! -f config/cluster.yml ]]; then
  echo "ERROR: config/cluster.yml not found."
  echo "Create it first:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  echo "  nano config/cluster.yml"
  exit 1
fi

chmod +x scripts/*.sh 2>/dev/null || true
chmod +x apps/ml_grid_search/run_task.sh 2>/dev/null || true
chmod +x server/entrypoint.sh 2>/dev/null || true
chmod +x server/scripts/*.sh 2>/dev/null || true

./scripts/init_config.sh
./scripts/server_up.sh
./scripts/create_account_db.sh
./scripts/status.sh || true

echo
echo "Server bootstrap completed."
