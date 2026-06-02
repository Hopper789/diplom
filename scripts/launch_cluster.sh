#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

WITH_MONITORING=0
RUN_EXPERIMENT=0
SERVER_ONLY=0
CLIENTS_ONLY=0
SKIP_STATUS=0

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/launch_cluster.sh [options]

Options:
  --with-monitoring         start monitoring stack
  --run-experiment          submit and pump the experiment
  --server-only             launch only BOINC server
  --clients-only            launch only BOINC clients
  --skip-status             skip final status check
  --ask-vault-pass, --vault ask Vault password manually
  --vault-password-file F   use custom Vault password file
  --ask-become-pass, -K     ask sudo password
  --help, -h
USAGE
}

check_prepared() {
  local required=(
    "$ROOT_DIR/config/cluster.yml"
    "$ROOT_DIR/config/generated.env"
    "$ROOT_DIR/ansible/inventory.ini"
    "$ROOT_DIR/ansible/group_vars/all/main.yml"
    "$ROOT_DIR/ansible/group_vars/all/vault.yml"
  )

  local path
  for path in "${required[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "System is not prepared."
      echo "Run:"
      echo "  ./scripts/prepare_system.sh"
      exit 1
    fi
  done

  if [[ "${ANSIBLE_VAULT_MODE_SELECTED:-0}" == "0" && ! -f "$ROOT_DIR/ansible/.vault_pass" ]]; then
    echo "System is not prepared."
    echo "Run:"
    echo "  ./scripts/prepare_system.sh"
    exit 1
  fi
}

cd "$ROOT_DIR"

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-monitoring)
      WITH_MONITORING=1
      shift
      ;;
    --run-experiment)
      RUN_EXPERIMENT=1
      shift
      ;;
    --server-only)
      SERVER_ONLY=1
      shift
      ;;
    --clients-only)
      CLIENTS_ONLY=1
      shift
      ;;
    --skip-status)
      SKIP_STATUS=1
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

if [[ "$SERVER_ONLY" == "1" && "$CLIENTS_ONLY" == "1" ]]; then
  echo "ERROR: --server-only and --clients-only cannot be used together." >&2
  exit 2
fi

check_prepared

echo "== Launching BOINC cluster =="
echo

if [[ "$CLIENTS_ONLY" != "1" ]]; then
  ./scripts/bootstrap_server.sh
fi

if [[ "$SERVER_ONLY" != "1" ]]; then
  ./scripts/bootstrap_clients.sh "${ANSIBLE_ARGS[@]}"
fi

if [[ "$WITH_MONITORING" == "1" ]]; then
  monitoring_args=("${ANSIBLE_ARGS[@]}")
  if [[ "$SERVER_ONLY" == "1" ]]; then
    monitoring_args+=(--skip-client-agents)
  fi
  ./scripts/monitoring_up.sh "${monitoring_args[@]}"
fi

if [[ "$RUN_EXPERIMENT" == "1" ]]; then
  ./scripts/run_experiment.sh "${ANSIBLE_ARGS[@]}"
fi

if [[ "$SKIP_STATUS" != "1" ]]; then
  if [[ "$SERVER_ONLY" == "1" ]]; then
    ./scripts/status.sh --server-only "${ANSIBLE_ARGS[@]}"
  else
    ./scripts/status.sh "${ANSIBLE_ARGS[@]}"
  fi
fi

echo
echo "Cluster launch completed."
