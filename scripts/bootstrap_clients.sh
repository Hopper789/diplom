#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./scripts/bootstrap_clients.sh [OPTIONS]

Options passed to Ansible:
  --ask-vault-pass, --vault  Ask Ansible Vault password
  --vault-password-file FILE Use Vault password file
  --vault-id ID             Use Ansible Vault ID
  --ask-become-pass, -K      Ask sudo password for remote clients

Examples:
  ./scripts/bootstrap_clients.sh --ask-vault-pass
  ./scripts/bootstrap_clients.sh --vault-password-file ~/.vault_pass.txt
USAGE
}

ANSIBLE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ask-vault-pass|--vault)
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
    --ask-become-pass|-K)
      ANSIBLE_ARGS+=(--ask-become-pass)
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -n "${ANSIBLE_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_FROM_ENV=(${ANSIBLE_EXTRA_ARGS})
  ANSIBLE_ARGS+=("${EXTRA_FROM_ENV[@]}")
fi

echo "== BOINC clients bootstrap =="

if [[ ! -f config/generated.env ]]; then
  echo "ERROR: config/generated.env not found. Run ./scripts/bootstrap_server.sh first."
  exit 1
fi

if [[ ! -f ansible/inventory.ini ]]; then
  echo "ERROR: ansible/inventory.ini not found. Run ./scripts/init_config.sh first."
  exit 1
fi

ANSIBLE_HOST_KEY_CHECKING=False \
  ansible -i ansible/inventory.ini boinc_clients "${ANSIBLE_ARGS[@]}" -m ping

./scripts/deploy_clients.sh "${ANSIBLE_ARGS[@]}"
./scripts/status.sh "${ANSIBLE_ARGS[@]}" || true

echo
echo "Clients bootstrap completed."
echo "Next step:"
echo "  ./scripts/run_experiment.sh ${ANSIBLE_ARGS[*]:-}"
