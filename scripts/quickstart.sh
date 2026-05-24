#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

ASK_BECOME_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --ask-become-pass|-K)
      ASK_BECOME_ARGS+=(--ask-become-pass)
      ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./scripts/quickstart.sh [--ask-become-pass]"
      exit 2
      ;;
  esac
done

if [[ ! -f "$ROOT_DIR/config/cluster.yml" ]]; then
  echo "ERROR: config/cluster.yml not found."
  echo
  echo "Create it first:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  echo "  nano config/cluster.yml"
  exit 1
fi

./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh "${ASK_BECOME_ARGS[@]}"

echo
echo "Quickstart completed."
echo
echo "To run experiment:"
if [[ "${#ASK_BECOME_ARGS[@]}" -gt 0 ]]; then
  echo "  ./scripts/run_experiment.sh --ask-become-pass"
else
  echo "  ./scripts/run_experiment.sh"
fi
