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
      echo "Usage: ./scripts/deploy_clients.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 2
      ;;
  esac
done

if [[ "${#ANSIBLE_ARGS[@]}" -eq 0 && -f "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_ARGS+=(--vault-password-file "$VAULT_PASS_FILE")
fi

if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  echo "ERROR: ansible/inventory.ini not found."
  echo "Run:"
  echo "  ./scripts/init_config.sh"
  exit 1
fi

if [[ ! -f "$ROOT_DIR/ansible/group_vars/all/main.yml" && ! -f "$ROOT_DIR/ansible/group_vars/all.yml" ]]; then
  echo "ERROR: Ansible group vars not found."
  echo "Expected one of:"
  echo "  ansible/group_vars/all/main.yml"
  echo "  ansible/group_vars/all.yml"
  echo
  echo "Run:"
  echo "  ./scripts/init_config.sh"
  echo "  ./scripts/create_account_db.sh"
  exit 1
fi

ansible-playbook \
  -i "$ROOT_DIR/ansible/inventory.ini" \
  "$ROOT_DIR/ansible/install_boinc_clients.yml" \
  "${ANSIBLE_ARGS[@]}"