#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"
# shellcheck source=scripts/lib/inventory.sh
source "$ROOT_DIR/scripts/lib/inventory.sh"

cd "$ROOT_DIR"
SKIP_STATUS=0
SKIP_RUNTIME_CHECK=0

echo "== BOINC clients bootstrap =="
echo

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-status)
      SKIP_STATUS=1
      shift
      ;;
    --skip-runtime-check)
      SKIP_RUNTIME_CHECK=1
      shift
      ;;
    --help|-h)
      echo "Usage: ./scripts/bootstrap_clients.sh [--skip-status] [--skip-runtime-check] [--debug] [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./scripts/bootstrap_clients.sh [--skip-status] [--skip-runtime-check] [--debug] [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 2
      ;;
  esac
done

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
  echo "Check config/cluster.yml: client ip, user and ssh_port."
  echo "You can try copying SSH keys:"
  echo "  ./scripts/prepare_system.sh --copy-ssh-keys"
  echo
  echo "Manual check example:"
  echo "  ssh -p SSH_PORT USER@CLIENT_IP"
  echo
  echo "Then rerun:"
  echo "  ./scripts/bootstrap_clients.sh"
  exit 1
fi

echo
echo "Deploying BOINC Docker clients..."
./scripts/deploy_clients.sh "${ANSIBLE_ARGS[@]}"

if [[ "$SKIP_STATUS" != "1" ]]; then
  echo
  echo "Clients status:"
  ./scripts/status.sh "${ANSIBLE_ARGS[@]}" || true
fi

if [[ "$SKIP_RUNTIME_CHECK" != "1" ]]; then
  echo
  echo "Client runtime check:"
  ./scripts/check_client_runtime.sh "${ANSIBLE_ARGS[@]}" || true
fi

echo
echo "Clients bootstrap completed."
echo
echo "Next step:"
echo "  ./scripts/run_experiment.sh"
