#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "== BOINC clients bootstrap =="
echo

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

ASK_BECOME_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --ask-become-pass|-K)
      ASK_BECOME_ARGS+=(--ask-become-pass)
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./scripts/bootstrap_clients.sh [--ask-become-pass]"
      exit 2
      ;;
  esac
done

echo "Checking SSH access to clients..."
if ! ansible -i ansible/inventory.ini boinc_clients -m ping; then
  echo
  echo "SSH ping failed."
  echo "You can try copying SSH keys:"
  echo "  ./scripts/copy_ssh_keys.sh"
  echo
  echo "Then rerun:"
  echo "  ./scripts/bootstrap_clients.sh ${ASK_BECOME_ARGS[*]:-}"
  exit 1
fi

echo
echo "Deploying BOINC Docker clients..."
./scripts/deploy_clients.sh "${ASK_BECOME_ARGS[@]}"

echo
echo "Clients status:"
./scripts/status.sh || true

echo
echo "Clients bootstrap completed."
echo
echo "Next step:"
if [[ "${#ASK_BECOME_ARGS[@]}" -gt 0 ]]; then
  echo "  ./scripts/run_experiment.sh --ask-become-pass"
else
  echo "  ./scripts/run_experiment.sh"
fi
