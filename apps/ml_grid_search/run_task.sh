#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXPERIMENT_ENV_FILE="$ROOT_DIR/config/experiment.env"
DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"
BUILD_DIR="$ROOT_DIR/apps/ml_grid_search/build"
PARAMS_FILE="$BUILD_DIR/params.jsonl"
TASK_FILE="$ROOT_DIR/apps/ml_grid_search/task.py"
PYTHON_RUNNER="$ROOT_DIR/apps/python_task_runner/run_task.sh"

MODE="${1:-boinc}"

if [[ -f "$EXPERIMENT_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$EXPERIMENT_ENV_FILE"
  set +a
fi

if [[ -f "$DISTRIBUTED_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$DISTRIBUTED_ENV_FILE"
  set +a
fi

APP_NAME="${APP_NAME:-ml_grid_search}"
PLATFORM="${PLATFORM:-x86_64-pc-linux-gnu}"
EXPERIMENT_WALL_SECONDS="${EXPERIMENT_WALL_SECONDS:-180}"
EXPERIMENT_CORES="${EXPERIMENT_CORES:-12}"
TASK_SECONDS="${TASK_SECONDS:-8}"
TASK_COUNT="${TASK_COUNT:-}"
TASK_DATASET_SIZE="${TASK_DATASET_SIZE:-500}"
TASK_SEED_BASE="${TASK_SEED_BASE:-1000}"
TASK_LAMBDA_GRID="${TASK_LAMBDA_GRID:-0,0.001,0.003,0.01,0.03,0.1,0.3,1,3,10}"

usage() {
  cat <<'USAGE'
Usage:
  apps/ml_grid_search/run_task.sh [boinc|local]

Environment:
  EXPERIMENT_WALL_SECONDS  target experiment duration for automatic task count
  EXPERIMENT_CORES         expected CPU cores for automatic task count
  TASK_SECONDS             target seconds per BOINC workunit
  TASK_COUNT               exact number of workunits, optional
  TASK_DATASET_SIZE        synthetic dataset size
  TASK_SEED_BASE           base seed for generated tasks
  TASK_LAMBDA_GRID         comma-separated lambda grid
USAGE
}

generate_params() {
  mkdir -p "$BUILD_DIR"

  local args=(
    "$ROOT_DIR/apps/ml_grid_search/generate_params.py"
    --out "$PARAMS_FILE"
    --wall-seconds "$EXPERIMENT_WALL_SECONDS"
    --cores "$EXPERIMENT_CORES"
    --task-seconds "$TASK_SECONDS"
    --dataset-size "$TASK_DATASET_SIZE"
    --seed-base "$TASK_SEED_BASE"
    --lambda-grid "$TASK_LAMBDA_GRID"
  )

  if [[ -n "$TASK_COUNT" ]]; then
    args+=(--task-count "$TASK_COUNT")
  fi

  python3 "${args[@]}"
}

run_boinc() {
  generate_params

  export PYTHON_TASK_APP_NAME="${PYTHON_TASK_APP_NAME:-$APP_NAME}"
  export PYTHON_TASK_PLATFORM="${PYTHON_TASK_PLATFORM:-$PLATFORM}"
  export PYTHON_TASK_APP_FRIENDLY_NAME="${PYTHON_TASK_APP_FRIENDLY_NAME:-ML grid search Python}"

  if [[ -n "${PYTHON_TASK_APP_VERSION:-}" ]]; then
    :
  elif [[ -n "${APP_VERSION:-}" && "$APP_VERSION" != "1.04" ]]; then
    export PYTHON_TASK_APP_VERSION="$APP_VERSION"
  else
    if [[ "${APP_VERSION:-}" == "1.04" ]]; then
      echo "Legacy APP_VERSION=1.04 detected; Python runner will auto-select the next BOINC app version."
    fi
    export PYTHON_TASK_APP_VERSION=""
  fi

  "$PYTHON_RUNNER" --task "$TASK_FILE" --params "$PARAMS_FILE" --device cpu
}

run_local() {
  generate_params

  local input_dir="$BUILD_DIR/local_inputs"
  local output_dir="$BUILD_DIR/local_outputs"
  mkdir -p "$input_dir" "$output_dir"

  python3 "$ROOT_DIR/apps/python_task_runner/generate_inputs.py" \
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
    python3 "$ROOT_DIR/apps/python_task_runner/runner.py" \
      --task "$TASK_FILE" \
      --input "$input_file" \
      --output "$output_dir/${name%.json}.output.json" \
      --fail-on-error
  done

  echo "Local outputs: $output_dir"
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
