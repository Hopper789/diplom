#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
INVENTORY_FILE="$ROOT_DIR/ansible/inventory.ini"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/check_client_runtime.sh [options]

Checks BOINC client nodes:
  - Ansible SSH access
  - Docker availability
  - boinc-client container
  - Python runtime inside boinc-client
  - numpy and numba inside boinc-client
  - BOINC RPC project status, if config/generated.env exists

Options:
  --ask-vault-pass, --vault ask Vault password manually
  --vault-password-file F   use custom Vault password file
  --ask-become-pass, -K     ask sudo password
  --help, -h
USAGE
}

cd "$ROOT_DIR"

build_ansible_args "$@"
if [[ "${#ANSIBLE_REMAINING_ARGS[@]}" -gt 0 ]]; then
  case "${ANSIBLE_REMAINING_ARGS[0]}" in
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: ${ANSIBLE_REMAINING_ARGS[0]}" >&2
      usage
      exit 2
      ;;
  esac
fi

if [[ ! -f "$INVENTORY_FILE" ]]; then
  echo "ERROR: ansible/inventory.ini not found."
  echo "Run:"
  echo "  ./scripts/prepare_system.sh"
  exit 1
fi

if ! command -v ansible >/dev/null 2>&1; then
  echo "ERROR: ansible is not installed."
  echo "Run:"
  echo "  ./scripts/prepare_system.sh --install-local"
  exit 1
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ENV_FILE"
  set +a
fi

project_url_q="$(printf "%q" "${BOINC_PROJECT_URL:-}")"
rpc_password_q="$(printf "%q" "${BOINC_CLIENT_RPC_PASSWORD:-}")"

echo "== Checking BOINC client runtime =="
echo

echo "Ansible ping:"
ANSIBLE_HOST_KEY_CHECKING=False \
  ansible -i "$INVENTORY_FILE" boinc_clients "${ANSIBLE_ARGS[@]}" -m ping

echo
echo "Docker and Python runtime inside boinc-client:"
ANSIBLE_HOST_KEY_CHECKING=False \
  ansible -i "$INVENTORY_FILE" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
    set -e

    docker version >/dev/null
    echo 'docker: OK'

    if ! docker ps --format '{{.Names}}' | grep -qx boinc-client; then
      echo 'boinc-client container: MISSING'
      exit 1
    fi
    echo 'boinc-client container: OK'

    docker exec boinc-client python3 -c '
import sys
import numpy
import numba

print(\"python=\" + sys.version.split()[0])
print(\"numpy=\" + numpy.__version__)
print(\"numba=\" + numba.__version__)
'

    BOINC_PROJECT_URL=$project_url_q
    BOINC_CLIENT_RPC_PASSWORD=$rpc_password_q
    if [ -n \"\$BOINC_PROJECT_URL\" ] && [ -n \"\$BOINC_CLIENT_RPC_PASSWORD\" ]; then
      docker exec boinc-client \
        boinccmd --passwd \"\$BOINC_CLIENT_RPC_PASSWORD\" \
        --get_project_status >/dev/null
      echo 'boinc rpc: OK'
    else
      echo 'boinc rpc: skipped; config/generated.env is missing or incomplete'
    fi
  "

echo
echo "Client runtime check completed."
