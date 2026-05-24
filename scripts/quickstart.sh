#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./scripts/quickstart.sh [OPTIONS]

Options passed to client Ansible steps:
  --ask-vault-pass, --vault  Ask Ansible Vault password
  --vault-password-file FILE Use Vault password file
  --vault-id ID             Use Ansible Vault ID
  --ask-become-pass, -K      Ask sudo password for remote clients

Examples:
  ./scripts/quickstart.sh --ask-vault-pass
  ./scripts/quickstart.sh --vault-password-file ~/.vault_pass.txt
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

if [[ ! -f config/cluster.yml ]]; then
  echo "ERROR: config/cluster.yml not found."
  echo "Create it first:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  echo "  nano config/cluster.yml"
  exit 1
fi

./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh "${ANSIBLE_ARGS[@]}"

echo
echo "Quickstart completed."
echo "Run experiment:"
echo "  ./scripts/run_experiment.sh ${ANSIBLE_ARGS[*]:-}"
