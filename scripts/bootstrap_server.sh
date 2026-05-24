#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./scripts/bootstrap_server.sh

Bootstraps only the local BOINC server stack:
  init_config.sh
  server_up.sh
  create_account_db.sh
  status.sh --server-only

Vault is not needed here because this script does not manage remote clients.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  echo "NOTE: bootstrap_server.sh ignores remote Ansible options because it runs server-only steps."
  echo "      Use ./scripts/bootstrap_clients.sh --ask-vault-pass for clients."
  echo
fi

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
./scripts/status.sh --server-only || true

echo
echo "Server bootstrap completed."
echo "Next step:"
echo "  ./scripts/bootstrap_clients.sh --ask-vault-pass"
