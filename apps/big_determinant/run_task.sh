#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"
BUILD_DIR="$ROOT_DIR/apps/big_determinant/build"
PARAMS_FILE="$BUILD_DIR/params.jsonl"
PREPARE_FILE="$ROOT_DIR/apps/big_determinant/prepare.py"
MAIN_FILE="$ROOT_DIR/apps/big_determinant/main.py"
PYTHON_RUNNER="$ROOT_DIR/apps/python_task_runner/run_task.sh"

MODE="boinc"
TASK_COUNT=""
SEED_BASE=10000

if [[ -f "$DISTRIBUTED_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$DISTRIBUTED_ENV_FILE"
  set +a
fi

APP_NAME="${DETERMINANT_APP_NAME:-big_determinant}"
PLATFORM="${PLATFORM:-x86_64-pc-linux-gnu}"

usage() {
  cat <<'USAGE'
Usage:
  apps/big_determinant/run_task.sh [--debug] [boinc|local] [--workunits N]

Options:
  --workunits N            number of fixed 10-minute BOINC workunits

The benchmark ignores computation config: matrix size, repeat count, and
runtime are fixed in apps/big_determinant/main.py.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    boinc|local)
      MODE="$1"
      shift
      ;;
    --workunits|--task-count)
      if [[ $# -lt 2 ]]; then
        echo "--workunits requires a value." >&2
        exit 2
      fi
      TASK_COUNT="$2"
      shift 2
      ;;
    --help|-h|help)
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

if [[ -n "$TASK_COUNT" ]]; then
  if ! [[ "$TASK_COUNT" =~ ^[0-9]+$ ]] || (( TASK_COUNT < 1 )); then
    echo "--workunits must be a positive integer." >&2
    exit 2
  fi
fi

default_workunits() {
  python3 - "$ROOT_DIR/ansible/inventory.ini" <<'PY'
import sys
from pathlib import Path

inventory = Path(sys.argv[1])
count = 0
inside = False

if inventory.exists():
    for raw in inventory.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            inside = line == "[boinc_clients]"
            continue
        if inside:
            count += 1

print(max(1, count))
PY
}

prepare_task() {
  mkdir -p "$BUILD_DIR"

  local count="$TASK_COUNT"
  if [[ -z "$count" ]]; then
    count="$(default_workunits)"
  fi

  local args=(
    "$PREPARE_FILE"
    --main "$MAIN_FILE"
    --out "$PARAMS_FILE"
    --task-count "$count"
    --seed-base "$SEED_BASE"
  )

  python3 "${args[@]}"
}

run_boinc() {
  prepare_task

  export PYTHON_TASK_APP_NAME="${PYTHON_TASK_APP_NAME:-$APP_NAME}"
  export PYTHON_TASK_PLATFORM="${PYTHON_TASK_PLATFORM:-$PLATFORM}"
  export PYTHON_TASK_APP_FRIENDLY_NAME="${PYTHON_TASK_APP_FRIENDLY_NAME:-Big determinant CPU}"
  export PYTHON_TASK_APP_VERSION="${DETERMINANT_APP_VERSION:-${PYTHON_TASK_APP_VERSION:-}}"

  "$PYTHON_RUNNER" --task "$MAIN_FILE" --params "$PARAMS_FILE" --device cpu --fail-on-error
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
