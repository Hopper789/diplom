#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

cd "$ROOT_DIR"

ANSIBLE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ask-vault-pass|--vault)
      ANSIBLE_ARGS+=(--ask-vault-pass)
      shift
      ;;
    --vault-password-file)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --vault-password-file requires a path."
        exit 2
      fi
      ANSIBLE_ARGS+=(--vault-password-file "$2")
      shift 2
      ;;
    --ask-become-pass|-K)
      ANSIBLE_ARGS+=(--ask-become-pass)
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./scripts/deploy_monitoring_agents.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 2
      ;;
  esac
done

if [[ "${#ANSIBLE_ARGS[@]}" -eq 0 && -f "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_ARGS+=(--vault-password-file "$VAULT_PASS_FILE")
fi

if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  echo "ERROR: ansible/inventory.ini not found."
  echo "Run: ./scripts/init_config.sh"
  exit 1
fi

ansible-playbook \
  -i "$ROOT_DIR/ansible/inventory.ini" \
  "$ROOT_DIR/ansible/install_monitoring_agents.yml" \
  "${ANSIBLE_ARGS[@]}"
