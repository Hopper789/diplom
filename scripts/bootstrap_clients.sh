#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"
# shellcheck source=scripts/lib/inventory.sh
source "$ROOT_DIR/scripts/lib/inventory.sh"

cd "$ROOT_DIR"

echo "== BOINC clients bootstrap =="
echo

build_ansible_args "$@"
if [[ "${#ANSIBLE_REMAINING_ARGS[@]}" -gt 0 ]]; then
  echo "Unknown argument: ${ANSIBLE_REMAINING_ARGS[0]}"
  echo "Usage: ./scripts/bootstrap_clients.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
  exit 2
fi

if [[ ! -f "$ROOT_DIR/config/generated.env" ]]; then
  echo "ERROR: config/generated.env not found."
  echo "Run first:"
  echo "  ./scripts/bootstrap_server.sh"
  exit 1
fi

if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  echo "ERROR: ansible/inventory.ini not found."
  echo "Run first:"
  echo "  ./scripts/init_config.sh"
  exit 1
fi

refresh_client_known_hosts "$ROOT_DIR/ansible/inventory.ini"

echo "Checking SSH access to clients..."
if ! ANSIBLE_HOST_KEY_CHECKING=False \
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients "${ANSIBLE_ARGS[@]}" -m ping; then
  echo
  echo "SSH ping failed."
  echo "You can try copying SSH keys:"
  echo "  ./scripts/copy_ssh_keys.sh"
  echo
  echo "Then rerun:"
  echo "  ./scripts/bootstrap_clients.sh"
  exit 1
fi

echo
echo "Deploying BOINC Docker clients..."
./scripts/deploy_clients.sh "${ANSIBLE_ARGS[@]}"

echo
echo "Clients status:"
./scripts/status.sh "${ANSIBLE_ARGS[@]}" || true

echo
echo "Client runtime check:"
./scripts/check_client_runtime.sh "${ANSIBLE_ARGS[@]}" || true

echo
echo "Clients bootstrap completed."
echo
echo "Next step:"
echo "  ./scripts/run_experiment.sh"
