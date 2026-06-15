#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

WITH_MONITORING=0
RUN_EXPERIMENT=0
INSTALL_LOCAL=0
COPY_SSH_KEYS=0
SKIP_PREPARE=0
SKIP_LAUNCH=0
SKIP_STATUS=0
ASK_BECOME_PASS=0
EXPERIMENT_ARGS=()

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/quickstart.sh [options]

Options:
  --with-monitoring     start monitoring during launch
  --run-experiment      submit the experiment during launch
  --task user|grid-search|determinant
                       task for --run-experiment; default: user
  --user-task PATH      Python file for --task user
  --user-params PATH    params.jsonl for --task user
  --simulate-failures RATE
                       make roughly RATE of BOINC attempts fail; 0..1
  --simulate-failure-seed SEED
                       deterministic seed for simulated failures
  --simulate-failure-after-seconds SECONDS
                       burn CPU for SECONDS before simulated failure
  --install-local       install local control-machine dependencies during preparation
  --copy-ssh-keys       copy SSH keys to clients during preparation
  --skip-prepare        run only launch_cluster.sh
  --skip-launch         run only prepare_system.sh
  --skip-status         skip final launch status check
  --ask-become-pass, -K ask sudo password for Ansible steps
  --debug              show full command output
  --help, -h

Examples:
  ./scripts/quickstart.sh
  ./scripts/quickstart.sh --with-monitoring
  ./scripts/quickstart.sh --with-monitoring --run-experiment --task determinant
  ./scripts/quickstart.sh --with-monitoring --run-experiment --task determinant --simulate-failures 0.25 --simulate-failure-after-seconds 60
  ./scripts/quickstart.sh --with-monitoring --run-experiment --task grid-search

Default experiment task is the user task template in apps/user_task_template.
USAGE
}

cd "$ROOT_DIR"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-monitoring)
      WITH_MONITORING=1
      shift
      ;;
    --run-experiment)
      RUN_EXPERIMENT=1
      shift
      ;;
    --task)
      if [[ $# -lt 2 ]]; then
        echo "--task requires a value." >&2
        exit 2
      fi
      EXPERIMENT_ARGS+=(--task "$2")
      shift 2
      ;;
    --task=*)
      EXPERIMENT_ARGS+=("$1")
      shift
      ;;
    --big-det|--big_det|--determinant)
      EXPERIMENT_ARGS+=(--task determinant)
      shift
      ;;
    --grid-search|--grid_search)
      EXPERIMENT_ARGS+=(--task grid-search)
      shift
      ;;
    --user-task)
      if [[ $# -lt 2 ]]; then
        echo "--user-task requires a path." >&2
        exit 2
      fi
      EXPERIMENT_ARGS+=(--user-task "$2")
      shift 2
      ;;
    --user-params)
      if [[ $# -lt 2 ]]; then
        echo "--user-params requires a path." >&2
        exit 2
      fi
      EXPERIMENT_ARGS+=(--user-params "$2")
      shift 2
      ;;
    --simulate-failures)
      if [[ $# -lt 2 ]]; then
        echo "--simulate-failures requires a value from 0 to 1." >&2
        exit 2
      fi
      EXPERIMENT_ARGS+=(--simulate-failures "$2")
      shift 2
      ;;
    --simulate-failures=*)
      EXPERIMENT_ARGS+=("$1")
      shift
      ;;
    --simulate-failure-seed)
      if [[ $# -lt 2 ]]; then
        echo "--simulate-failure-seed requires a value." >&2
        exit 2
      fi
      EXPERIMENT_ARGS+=(--simulate-failure-seed "$2")
      shift 2
      ;;
    --simulate-failure-seed=*)
      EXPERIMENT_ARGS+=("$1")
      shift
      ;;
    --simulate-failure-after-seconds)
      if [[ $# -lt 2 ]]; then
        echo "--simulate-failure-after-seconds requires a value >= 0." >&2
        exit 2
      fi
      EXPERIMENT_ARGS+=(--simulate-failure-after-seconds "$2")
      shift 2
      ;;
    --simulate-failure-after-seconds=*)
      EXPERIMENT_ARGS+=("$1")
      shift
      ;;
    --install-local)
      INSTALL_LOCAL=1
      shift
      ;;
    --copy-ssh-keys)
      COPY_SSH_KEYS=1
      shift
      ;;
    --skip-prepare)
      SKIP_PREPARE=1
      shift
      ;;
    --skip-launch)
      SKIP_LAUNCH=1
      shift
      ;;
    --skip-status)
      SKIP_STATUS=1
      shift
      ;;
    --ask-become-pass|-K)
      ASK_BECOME_PASS=1
      shift
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

if [[ "$SKIP_PREPARE" == "1" && "$SKIP_LAUNCH" == "1" ]]; then
  echo "ERROR: --skip-prepare and --skip-launch cannot be used together." >&2
  exit 2
fi

prepare_args=()
launch_args=()

if [[ "$INSTALL_LOCAL" == "1" ]]; then
  prepare_args+=(--install-local)
fi

if [[ "$COPY_SSH_KEYS" == "1" ]]; then
  prepare_args+=(--copy-ssh-keys)
fi

if [[ "$WITH_MONITORING" == "1" ]]; then
  launch_args+=(--with-monitoring)
fi

if [[ "$RUN_EXPERIMENT" == "1" ]]; then
  launch_args+=(--run-experiment)
  launch_args+=("${EXPERIMENT_ARGS[@]}")
  launch_args+=(--submit-only)
  launch_args+=(--skip-status)
fi

if [[ "$SKIP_STATUS" == "1" ]]; then
  launch_args+=(--skip-status)
fi

if [[ "$ASK_BECOME_PASS" == "1" ]]; then
  prepare_args+=(--ask-become-pass)
  launch_args+=(--ask-become-pass)
fi

step "Starting BOINC cluster quickstart..."

if [[ "$SKIP_PREPARE" != "1" ]]; then
  step "Preparing system..."
  quiet_run_all ./scripts/prepare_system.sh "${prepare_args[@]}"
fi

if [[ "$SKIP_LAUNCH" != "1" ]]; then
  step "Launching cluster..."
  quiet_run_all ./scripts/launch_cluster.sh "${launch_args[@]}"
fi

echo
step "Quickstart completed."
