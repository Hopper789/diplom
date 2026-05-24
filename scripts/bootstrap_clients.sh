#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== BOINC clients bootstrap =="

if [[ ! -f config/generated.env ]]; then
  echo "ERROR: config/generated.env not found. Run ./scripts/bootstrap_server.sh first."
  exit 1
fi

if [[ ! -f ansible/inventory.ini ]]; then
  echo "ERROR: ansible/inventory.ini not found. Run ./scripts/init_config.sh first."
  exit 1
fi

ANSIBLE_HOST_KEY_CHECKING=False ansible -i ansible/inventory.ini boinc_clients -m ping
./scripts/deploy_clients.sh "$@"
./scripts/status.sh || true

echo
echo "Clients bootstrap completed."
