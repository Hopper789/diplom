#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"
AUTO_UPDATE_SECONDS="${BOINC_AUTO_UPDATE_SECONDS:-600}"
AUTO_UPDATE_INTERVAL_SECONDS="${BOINC_AUTO_UPDATE_INTERVAL_SECONDS:-15}"

cd "$ROOT_DIR"

echo "== BOINC experiment runner =="
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
      echo "Usage: ./scripts/run_experiment.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
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

set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/config/generated.env"
set +a
MONITORING_HOST="${SERVER_IP:-localhost}"

if [[ ! -f "$ROOT_DIR/config/experiment.env" && -f "$ROOT_DIR/config/experiment.example.env" ]]; then
  echo "Creating config/experiment.env from example..."
  cp "$ROOT_DIR/config/experiment.example.env" "$ROOT_DIR/config/experiment.env"
fi

if [[ ! -f "$ROOT_DIR/config/distributed.env" && -f "$ROOT_DIR/config/distributed.example.env" ]]; then
  echo "Creating config/distributed.env from example..."
  cp "$ROOT_DIR/config/distributed.example.env" "$ROOT_DIR/config/distributed.env"
fi

if [[ "${#ANSIBLE_ARGS[@]}" -gt 0 ]]; then
  export ANSIBLE_EXTRA_ARGS="${ANSIBLE_ARGS[*]}"
fi

echo "Experiment config:"
if [[ -f "$ROOT_DIR/config/experiment.env" ]]; then
  grep -v '^#' "$ROOT_DIR/config/experiment.env" | grep -v '^$' || true
else
  echo "No config/experiment.env found; using defaults from run_task.sh."
fi

echo
echo "Distributed computing config:"
if [[ -f "$ROOT_DIR/config/distributed.env" ]]; then
  grep -v '^#' "$ROOT_DIR/config/distributed.env" | grep -v '^$' || true
else
  echo "No config/distributed.env found; using defaults from run_task.sh."
fi

echo
echo "Submitting BOINC work..."
export ANSIBLE_HOST_KEY_CHECKING=False
apps/ml_grid_search/run_task.sh boinc

echo
echo "Status after submitting work:"
./scripts/status.sh "${ANSIBLE_ARGS[@]}" || true

echo
echo "Auto-updating BOINC clients so they keep fetching work..."
./scripts/pump_clients.sh \
  --max-seconds "$AUTO_UPDATE_SECONDS" \
  --interval-seconds "$AUTO_UPDATE_INTERVAL_SECONDS" \
  "${ANSIBLE_ARGS[@]}" || true

echo
echo "Experiment submitted."
echo "Use monitoring or status command to watch progress:"
echo "  ./scripts/status.sh"
echo "  http://$MONITORING_HOST:3000"
