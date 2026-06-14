#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

COPY_SSH_KEYS=0
SKIP_MONITORING=0
SKIP_PUMP=0
RESET_CLIENT_STATE=0
PUMP_SECONDS="${BOINC_ADD_NODES_PUMP_SECONDS:-180}"
PUMP_INTERVAL_SECONDS="${BOINC_ADD_NODES_PUMP_INTERVAL_SECONDS:-15}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/add_nodes.sh [options]

Edit config/cluster.yml first, then run this script. It regenerates Ansible
inventory, prepares/deploys BOINC clients, refreshes monitoring targets, and
asks clients to fetch available work.

Options:
  --copy-ssh-keys          copy local SSH public key before deploying
  --reset-client-state     reset BOINC client state on all configured clients
  --skip-monitoring        do not refresh monitoring agents/targets
  --skip-pump              do not request BOINC client updates after deploy
  --pump-seconds N         max pump time; default: 180
  --pump-interval N        pump interval; default: 15
  --ask-vault-pass, --vault ask Vault password manually
  --vault-password-file F  use custom Vault password file
  --ask-become-pass, -K    ask sudo password
  --debug                  show full command output
  --help, -h
USAGE
}

cd "$ROOT_DIR"

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy-ssh-keys)
      COPY_SSH_KEYS=1
      shift
      ;;
    --reset-client-state)
      RESET_CLIENT_STATE=1
      shift
      ;;
    --skip-monitoring)
      SKIP_MONITORING=1
      shift
      ;;
    --skip-pump)
      SKIP_PUMP=1
      shift
      ;;
    --pump-seconds)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --pump-seconds requires a value." >&2
        exit 2
      fi
      PUMP_SECONDS="$2"
      shift 2
      ;;
    --pump-interval)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --pump-interval requires a value." >&2
        exit 2
      fi
      PUMP_INTERVAL_SECONDS="$2"
      shift 2
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

for pair in "PUMP_SECONDS:$PUMP_SECONDS" "PUMP_INTERVAL_SECONDS:$PUMP_INTERVAL_SECONDS"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
    echo "ERROR: $name must be a positive integer: $value" >&2
    exit 2
  fi
done

step "Adding BOINC client nodes..."

prepare_args=("${ANSIBLE_ARGS[@]}")
if [[ "$COPY_SSH_KEYS" == "1" ]]; then
  prepare_args+=(--copy-ssh-keys)
fi

step "Regenerating configuration and preparing client nodes..."
quiet_run_all ./scripts/prepare_system.sh "${prepare_args[@]}"

bootstrap_args=("${ANSIBLE_ARGS[@]}" --skip-status)
if [[ "$RESET_CLIENT_STATE" == "1" ]]; then
  bootstrap_args+=(--reset-client-state)
fi

if [[ "$RESET_CLIENT_STATE" == "1" ]]; then
  step "Deploying BOINC clients..."
  quiet_run_all ./scripts/bootstrap_clients.sh "${bootstrap_args[@]}"

  if [[ "$SKIP_MONITORING" != "1" ]]; then
    step "Refreshing monitoring targets..."
    quiet_run_all ./scripts/monitoring_up.sh "${ANSIBLE_ARGS[@]}"
  fi
else
  launch_args=("${ANSIBLE_ARGS[@]}" --clients-only --skip-status)
  if [[ "$SKIP_MONITORING" != "1" ]]; then
    launch_args+=(--with-monitoring)
  fi

  step "Deploying clients through launch_cluster.sh..."
  quiet_run_all ./scripts/launch_cluster.sh "${launch_args[@]}"
fi

if [[ "$SKIP_PUMP" != "1" ]]; then
  step "Requesting available BOINC work..."
  quiet_run_all ./scripts/pump_clients.sh \
    --max-seconds "$PUMP_SECONDS" \
    --interval-seconds "$PUMP_INTERVAL_SECONDS" \
    --quiet \
    "${ANSIBLE_ARGS[@]}"
fi

echo
step "Node update completed."
echo "Check:"
echo "  ./scripts/status.sh"
