#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"
BUILD_DIR="$ROOT_DIR/apps/ml_grid_search/build"
PARAMS_FILE="$BUILD_DIR/params.jsonl"
DATASET_FILE="$BUILD_DIR/dataset.csv"
PREPARE_FILE="$ROOT_DIR/apps/ml_grid_search/prepare.py"
MAIN_FILE="$ROOT_DIR/apps/ml_grid_search/main.py"
PYTHON_RUNNER="$ROOT_DIR/apps/python_task_runner/run_task.sh"

MODE="${1:-boinc}"

if [[ -f "$DISTRIBUTED_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$DISTRIBUTED_ENV_FILE"
  set +a
fi

APP_NAME="${APP_NAME:-ml_grid_search}"
PLATFORM="${PLATFORM:-x86_64-pc-linux-gnu}"

usage() {
  cat <<'USAGE'
Usage:
  apps/ml_grid_search/run_task.sh [--debug] [boinc|local]

The workload computes one real ridge-regression point per workunit. The shared
dataset CSV, number of workunits, and task parameters are prepared on the server.
USAGE
}

prepare_task() {
  mkdir -p "$BUILD_DIR"

  local args=(
    "$PREPARE_FILE"
    --main "$MAIN_FILE"
    --out "$PARAMS_FILE"
    --dataset-out "$DATASET_FILE"
  )

  step "Preparing grid-search workunits..."
  quiet_run_all python3 "${args[@]}"
}

read_dataset_open_name() {
  python3 - "$PARAMS_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if line:
            print(json.loads(line).get("dataset_file", "dataset.csv"))
            raise SystemExit(0)

raise SystemExit("params.jsonl is empty")
PY
}

run_boinc() {
  prepare_task
  local dataset_open_name
  dataset_open_name="$(read_dataset_open_name)"

  export PYTHON_TASK_APP_NAME="${PYTHON_TASK_APP_NAME:-$APP_NAME}"
  export PYTHON_TASK_PLATFORM="${PYTHON_TASK_PLATFORM:-$PLATFORM}"
  export PYTHON_TASK_APP_FRIENDLY_NAME="${PYTHON_TASK_APP_FRIENDLY_NAME:-ML grid search Python}"

  if [[ -n "${PYTHON_TASK_APP_VERSION:-}" ]]; then
    :
  elif [[ -n "${APP_VERSION:-}" && "$APP_VERSION" != "1.04" ]]; then
    export PYTHON_TASK_APP_VERSION="$APP_VERSION"
  else
    if [[ "${APP_VERSION:-}" == "1.04" ]]; then
      debug_log "Legacy APP_VERSION=1.04 detected; Python runner will auto-select the next BOINC app version."
    fi
    export PYTHON_TASK_APP_VERSION=""
  fi

  step "Submitting grid-search workunits..."
  quiet_run_all "$PYTHON_RUNNER" \
    --task "$MAIN_FILE" \
    --params "$PARAMS_FILE" \
    --extra-input "$DATASET_FILE:$dataset_open_name" \
    --device cpu \
    --fail-on-error
}

run_local() {
  prepare_task

  local input_dir="$BUILD_DIR/local_inputs"
  local output_dir="$BUILD_DIR/local_outputs"
  mkdir -p "$input_dir" "$output_dir"

  step "Generating local inputs..."
  quiet_run_all python3 "$ROOT_DIR/apps/python_task_runner/generate_inputs.py" \
    --params "$PARAMS_FILE" \
    --out "$input_dir" \
    --device cpu

  for input_file in "$input_dir"/input_*.json; do
    [[ -e "$input_file" ]] || {
      echo "No input_*.json files found in $input_dir" >&2
      exit 1
    }

    local name
    name="$(basename "$input_file")"
    quiet_run_all python3 "$ROOT_DIR/apps/python_task_runner/runner.py" \
      --task "$MAIN_FILE" \
      --input "$input_file" \
      --output "$output_dir/${name%.json}.output.json" \
      --fail-on-error
  done

  step "Local grid-search run completed."
  if debug_enabled; then
    echo "Local outputs: $output_dir"
  fi
}

case "$MODE" in
  boinc)
    run_boinc
    ;;
  local)
    run_local
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    usage
    exit 2
    ;;
esac
