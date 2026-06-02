#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

cd "$ROOT_DIR"

build_ansible_args "$@"
if [[ "${#ANSIBLE_REMAINING_ARGS[@]}" -gt 0 ]]; then
  echo "Unknown argument: ${ANSIBLE_REMAINING_ARGS[0]}"
  echo "Usage: ./scripts/deploy_monitoring_agents.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
  exit 2
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
