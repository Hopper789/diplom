#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTO_UPDATE_SECONDS="${BOINC_AUTO_UPDATE_SECONDS:-600}"
AUTO_UPDATE_INTERVAL_SECONDS="${BOINC_AUTO_UPDATE_INTERVAL_SECONDS:-15}"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

cd "$ROOT_DIR"

echo "== BOINC experiment runner =="
echo

build_ansible_args "$@"
if [[ "${#ANSIBLE_REMAINING_ARGS[@]}" -gt 0 ]]; then
  echo "Unknown argument: ${ANSIBLE_REMAINING_ARGS[0]}"
  echo "Usage: ./scripts/run_experiment.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
  exit 2
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
  "${ANSIBLE_ARGS[@]}"

echo
echo "Experiment submitted."
echo "Use monitoring or status command to watch progress:"
echo "  ./scripts/status.sh"
echo "  http://$MONITORING_HOST:3000"
