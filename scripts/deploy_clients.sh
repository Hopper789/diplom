#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
INVENTORY="$ROOT_DIR/ansible/inventory.ini"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh" >&2
  exit 1
fi
if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: ansible/inventory.ini not found. Run: ./scripts/init_config.sh" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${BOINC_ACCOUNT_KEY:-}" ]]; then
  echo "ERROR: BOINC_ACCOUNT_KEY is empty. Run: ./scripts/create_account.sh" >&2
  exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook is not installed." >&2
  echo "Install it, for example:" >&2
  echo "  sudo apt update && sudo apt install -y ansible" >&2
  echo "or:" >&2
  echo "  pip3 install ansible" >&2
  exit 1
fi

ansible-playbook -i "$INVENTORY" "$ROOT_DIR/ansible/install_boinc_clients.yml"
