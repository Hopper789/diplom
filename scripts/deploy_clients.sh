#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
INVENTORY="$ROOT_DIR/ansible/inventory.ini"
PLAYBOOK="$ROOT_DIR/ansible/install_boinc_clients.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh"
  exit 1
fi

source "$ENV_FILE"

if [[ -z "${BOINC_ACCOUNT_KEY:-}" ]]; then
  echo "ERROR: BOINC_ACCOUNT_KEY is empty. Run: ./scripts/create_account_db.sh"
  exit 1
fi

ansible-playbook \
  -i "$INVENTORY" \
  "$PLAYBOOK" \
  "$@"