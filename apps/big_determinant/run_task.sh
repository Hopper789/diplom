#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

EXPERIMENT_ENV_FILE="$ROOT_DIR/config/experiment.env"
DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"
BUILD_DIR="$ROOT_DIR/apps/big_determinant/build"
PARAMS_FILE="$BUILD_DIR/params.jsonl"
PREPARE_FILE="$ROOT_DIR/apps/big_determinant/prepare.py"
MAIN_FILE="$ROOT_DIR/apps/big_determinant/main.py"
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

APP_NAME="${DETERMINANT_APP_NAME:-big_determinant}"
PLATFORM="${PLATFORM:-x86_64-pc-linux-gnu}"
EXPERIMENT_WALL_SECONDS="${DETERMINANT_WALL_SECONDS:-${EXPERIMENT_WALL_SECONDS:-1800}}"
EXPERIMENT_CORES="${EXPERIMENT_CORES:-1}"
TASK_SECONDS="${DETERMINANT_TASK_SECONDS:-600}"
TASK_COUNT="${DETERMINANT_TASK_COUNT:-${TASK_COUNT:-}}"
TASK_MATRIX_SIZE="${DETERMINANT_MATRIX_SIZE:-1200}"
TASK_SEED_BASE="${DETERMINANT_SEED_BASE:-10000}"
TASK_DIAGONAL_BOOST="${DETERMINANT_DIAGONAL_BOOST:-}"
TASK_MAX_REPEATS="${DETERMINANT_MAX_REPEATS:-0}"

usage() {
  cat <<'USAGE'
Usage:
  apps/big_determinant/run_task.sh [--debug] [boinc|local]

Environment:
  EXPERIMENT_WALL_SECONDS  target wall-clock duration for automatic task count
  EXPERIMENT_CORES         expected CPU slots for automatic task count
  DETERMINANT_TASK_SECONDS target seconds per BOINC workunit, default 600
  DETERMINANT_TASK_COUNT   exact number of workunits, optional
  DETERMINANT_MATRIX_SIZE  generated square matrix size, default 1200
  DETERMINANT_SEED_BASE    base seed for generated matrices
  DETERMINANT_DIAGONAL_BOOST value added to the matrix diagonal, optional
  DETERMINANT_MAX_REPEATS  exact determinant repeats per workunit; 0 means run until DETERMINANT_TASK_SECONDS
USAGE
}

prepare_task() {
  mkdir -p "$BUILD_DIR"

  local args=(
    "$PREPARE_FILE"
    --main "$MAIN_FILE"
    --out "$PARAMS_FILE"
    --wall-seconds "$EXPERIMENT_WALL_SECONDS"
    --cores "$EXPERIMENT_CORES"
    --task-seconds "$TASK_SECONDS"
    --matrix-size "$TASK_MATRIX_SIZE"
    --seed-base "$TASK_SEED_BASE"
    --max-repeats "$TASK_MAX_REPEATS"
  )

  if [[ -n "$TASK_COUNT" ]]; then
    args+=(--task-count "$TASK_COUNT")
  fi

  if [[ -n "$TASK_DIAGONAL_BOOST" ]]; then
    args+=(--diagonal-boost "$TASK_DIAGONAL_BOOST")
  fi

  python3 "${args[@]}"
}

run_boinc() {
  prepare_task

  export PYTHON_TASK_APP_NAME="${PYTHON_TASK_APP_NAME:-$APP_NAME}"
  export PYTHON_TASK_PLATFORM="${PYTHON_TASK_PLATFORM:-$PLATFORM}"
  export PYTHON_TASK_APP_FRIENDLY_NAME="${PYTHON_TASK_APP_FRIENDLY_NAME:-Big determinant CPU}"
  export PYTHON_TASK_APP_VERSION="${DETERMINANT_APP_VERSION:-${PYTHON_TASK_APP_VERSION:-}}"

  "$PYTHON_RUNNER" --task "$MAIN_FILE" --params "$PARAMS_FILE" --device cpu
}

run_local() {
  prepare_task

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
      --task "$MAIN_FILE" \
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
