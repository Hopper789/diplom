#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "== BOINC experiment runner =="
echo

ASK_BECOME=0

for arg in "$@"; do
  case "$arg" in
    --ask-become-pass|-K)
      ASK_BECOME=1
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./scripts/run_experiment.sh [--ask-become-pass]"
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

if [[ ! -f "$ROOT_DIR/config/experiment.env" && -f "$ROOT_DIR/config/experiment.example.env" ]]; then
  echo "Creating config/experiment.env from example..."
  cp "$ROOT_DIR/config/experiment.example.env" "$ROOT_DIR/config/experiment.env"
fi

if [[ "$ASK_BECOME" == "1" ]]; then
  export ANSIBLE_EXTRA_ARGS="--ask-become-pass"
fi

echo "Experiment config:"
if [[ -f "$ROOT_DIR/config/experiment.env" ]]; then
  grep -v '^#' "$ROOT_DIR/config/experiment.env" | grep -v '^$' || true
else
  echo "No config/experiment.env found; using defaults from run_task.sh."
fi

echo
echo "Submitting BOINC work..."
apps/ml_grid_search/run_task.sh boinc

echo
echo "Status after submitting work:"
./scripts/status.sh || true

echo
echo "Experiment submitted."
echo "Use monitoring or status command to watch progress:"
echo "  ./scripts/status.sh"
echo "  http://localhost:3000"

