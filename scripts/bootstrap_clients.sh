#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

cd "$ROOT_DIR"

echo "== BOINC clients bootstrap =="
echo

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
      echo "Usage: ./scripts/bootstrap_clients.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 2
      ;;
  esac
done

if [[ "${#ANSIBLE_ARGS[@]}" -eq 0 && -f "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_ARGS+=(--vault-password-file "$VAULT_PASS_FILE")
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

echo "Checking SSH access to clients..."
if ! ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients "${ANSIBLE_ARGS[@]}" -m ping; then
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
echo "Clients bootstrap completed."
echo
echo "Next step:"
echo "  ./scripts/run_experiment.sh"