#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f config/cluster.yml ]]; then
  echo "ERROR: config/cluster.yml not found."
  echo "Create it first:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  echo "  nano config/cluster.yml"
  exit 1
fi

./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh "$@"

echo
echo "Quickstart completed."
echo "Run experiment:"
echo "  ./scripts/run_experiment.sh $*"
