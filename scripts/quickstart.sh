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

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/quickstart.sh [options]

Options:
  --with-monitoring     start monitoring during launch
  --run-experiment      submit the experiment during launch
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
  ./scripts/quickstart.sh --with-monitoring --run-experiment

Experiment task is selected in config/experiment.env via EXPERIMENT_APP.
Use ./scripts/run_experiment.sh when you want to submit, auto-update clients, and wait.
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

echo "== BOINC cluster quickstart =="
echo

if [[ "$SKIP_PREPARE" != "1" ]]; then
  ./scripts/prepare_system.sh "${prepare_args[@]}"
fi

if [[ "$SKIP_LAUNCH" != "1" ]]; then
  ./scripts/launch_cluster.sh "${launch_args[@]}"
fi

echo
echo "Quickstart completed."
