#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
INVENTORY="$ROOT_DIR/ansible/inventory.ini"
PLAYBOOK="$ROOT_DIR/ansible/install_boinc_clients.yml"

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy_clients.sh [ANSIBLE OPTIONS]

Common options:
  --ask-become-pass, -K       Ask sudo password for remote clients
  --ask-vault-pass            Ask Ansible Vault password
  --vault                     Shortcut for --ask-vault-pass
  --vault-password-file FILE  Use Vault password file

Examples:
  ./scripts/deploy_clients.sh --ask-become-pass
  ./scripts/deploy_clients.sh --ask-vault-pass
  ./scripts/deploy_clients.sh --vault
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh"
  exit 1
fi

if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: ansible/inventory.ini not found. Run: ./scripts/init_config.sh"
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

if [[ -z "${BOINC_ACCOUNT_KEY:-}" ]]; then
  echo "ERROR: BOINC_ACCOUNT_KEY is empty. Run: ./scripts/create_account_db.sh"
  exit 1
fi

ANSIBLE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault)
      ANSIBLE_ARGS+=(--ask-vault-pass)
      shift
      ;;
    --vault-password-file|--vault-id)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: $1 requires an argument" >&2
        exit 2
      fi
      ANSIBLE_ARGS+=("$1" "$2")
      shift 2
      ;;
    *)
      ANSIBLE_ARGS+=("$1")
      shift
      ;;
  esac
done

ansible-playbook \
  -i "$INVENTORY" \
  "$PLAYBOOK" \
  "${ANSIBLE_ARGS[@]}"
