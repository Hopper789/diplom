#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

cd "$ROOT_DIR"

build_ansible_args "$@"
if [[ "${#ANSIBLE_REMAINING_ARGS[@]}" -gt 0 ]]; then
  echo "Unknown argument: ${ANSIBLE_REMAINING_ARGS[0]}"
  echo "Usage: ./scripts/deploy_clients.sh [--debug] [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
  exit 2
fi

if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  echo "ERROR: ansible/inventory.ini not found."
  echo "Run:"
  echo "  ./scripts/init_config.sh"
  exit 1
fi

if [[ ! -f "$ROOT_DIR/ansible/group_vars/all/main.yml" ]]; then
  echo "ERROR: Ansible group vars not found."
  echo "Expected:"
  echo "  ansible/group_vars/all/main.yml"
  echo
  echo "Run:"
  echo "  ./scripts/init_config.sh"
  echo "  ./scripts/create_account_db.sh"
  exit 1
fi

step "Deploying BOINC clients..."
ANSIBLE_HOST_KEY_CHECKING=False \
quiet_run_all ansible-playbook \
  -i "$ROOT_DIR/ansible/inventory.ini" \
  "$ROOT_DIR/ansible/install_boinc_clients.yml" \
  "${ANSIBLE_ARGS[@]}"
