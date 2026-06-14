#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

WITH_MONITORING=0
RUN_EXPERIMENT=0
SUBMIT_ONLY=0
SERVER_ONLY=0
CLIENTS_ONLY=0
SKIP_STATUS=0
EXPERIMENT_ARGS=()
STATUS_TIMEOUT_SECONDS="${STATUS_TIMEOUT_SECONDS:-90}"
AUTO_UPDATE_SECONDS="${BOINC_AUTO_UPDATE_SECONDS:-600}"
AUTO_UPDATE_INTERVAL_SECONDS="${BOINC_AUTO_UPDATE_INTERVAL_SECONDS:-15}"
AUTO_DUMP_RESULTS="${BOINC_AUTO_DUMP_RESULTS:-1}"
EXPERIMENT_SUBMITTED_BEFORE_CLIENTS=0

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/launch_cluster.sh [options]

Options:
  --with-monitoring         start monitoring stack
  --run-experiment          submit and pump the experiment
  --task user|grid-search|determinant
                           task for --run-experiment; default: user
  --user-task PATH          Python file for --task user
  --user-params PATH        params.jsonl for --task user
  --submit-only             with --run-experiment, submit work without auto-update/status wait
  --server-only             launch only BOINC server
  --clients-only            launch only BOINC clients
  --skip-status             skip final status check
  --ask-vault-pass, --vault ask Vault password manually
  --vault-password-file F   use custom Vault password file
  --ask-become-pass, -K     ask sudo password
  --debug                   show full command output
  --help, -h
USAGE
}

check_prepared() {
  local required=(
    "$ROOT_DIR/config/cluster.yml"
    "$ROOT_DIR/config/generated.env"
    "$ROOT_DIR/ansible/inventory.ini"
    "$ROOT_DIR/ansible/group_vars/all/main.yml"
    "$ROOT_DIR/ansible/group_vars/all/vault.yml"
  )

  local path
  for path in "${required[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "System is not prepared."
      echo "Run:"
      echo "  ./scripts/prepare_system.sh"
      exit 1
    fi
  done

  if [[ "${ANSIBLE_VAULT_MODE_SELECTED:-0}" == "0" && ! -f "$ROOT_DIR/ansible/.vault_pass" ]]; then
    echo "System is not prepared."
    echo "Run:"
    echo "  ./scripts/prepare_system.sh"
    exit 1
  fi
}

check_boinc_account_ready() {
  local account_key=""

  if [[ -f "$ROOT_DIR/config/generated.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/config/generated.env"
    account_key="${BOINC_ACCOUNT_KEY:-}"
  fi

  if [[ -z "$account_key" ]]; then
    echo "BOINC account key is missing."
    echo
    echo "Run the server stage first:"
    echo "  ./scripts/launch_cluster.sh --server-only"
    echo
    echo "Then run clients:"
    echo "  ./scripts/launch_cluster.sh --clients-only"
    echo
    echo "Or run the full launch:"
    echo "  ./scripts/launch_cluster.sh --with-monitoring"
    exit 1
  fi
}

cd "$ROOT_DIR"

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

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
    --submit-only)
      SUBMIT_ONLY=1
      shift
      ;;
    --server-only)
      SERVER_ONLY=1
      shift
      ;;
    --clients-only)
      CLIENTS_ONLY=1
      shift
      ;;
    --skip-status)
      SKIP_STATUS=1
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

if [[ "$SERVER_ONLY" == "1" && "$CLIENTS_ONLY" == "1" ]]; then
  echo "ERROR: --server-only and --clients-only cannot be used together." >&2
  exit 2
fi

check_prepared

step "Launching BOINC cluster..."

if [[ "$CLIENTS_ONLY" != "1" ]]; then
  step "Starting BOINC server..."
  quiet_run_all ./scripts/bootstrap_server.sh --skip-status
fi

if [[ "$RUN_EXPERIMENT" == "1" && "$SERVER_ONLY" != "1" && "$CLIENTS_ONLY" != "1" ]]; then
  experiment_args=("${ANSIBLE_ARGS[@]}")
  experiment_args+=("${EXPERIMENT_ARGS[@]}")
  experiment_args+=(--submit-only)
  step "Preparing experiment work before clients start..."
  quiet_run_all env BOINC_SKIP_CLIENT_UPDATE=1 ./scripts/run_experiment.sh "${experiment_args[@]}"
  EXPERIMENT_SUBMITTED_BEFORE_CLIENTS=1
fi

if [[ "$SERVER_ONLY" != "1" ]]; then
  check_boinc_account_ready
  step "Starting BOINC clients..."
  quiet_run_all ./scripts/bootstrap_clients.sh --skip-status --skip-runtime-check "${ANSIBLE_ARGS[@]}"
fi

if [[ "$WITH_MONITORING" == "1" ]]; then
  monitoring_args=("${ANSIBLE_ARGS[@]}")
  if [[ "$SERVER_ONLY" == "1" ]]; then
    monitoring_args+=(--skip-client-agents)
  fi
  step "Starting monitoring..."
  quiet_run_all ./scripts/monitoring_up.sh "${monitoring_args[@]}"
fi

if [[ "$RUN_EXPERIMENT" == "1" && "$EXPERIMENT_SUBMITTED_BEFORE_CLIENTS" != "1" ]]; then
  experiment_args=("${ANSIBLE_ARGS[@]}")
  experiment_args+=("${EXPERIMENT_ARGS[@]}")
  if [[ "$SUBMIT_ONLY" == "1" ]]; then
    experiment_args+=(--submit-only)
  fi
  step "Submitting experiment..."
  quiet_run_all ./scripts/run_experiment.sh "${experiment_args[@]}"
elif [[ "$RUN_EXPERIMENT" == "1" && "$SUBMIT_ONLY" != "1" ]]; then
  step "Requesting BOINC client updates..."
  quiet_run_all ./scripts/pump_clients.sh \
    --max-seconds "$AUTO_UPDATE_SECONDS" \
    --interval-seconds "$AUTO_UPDATE_INTERVAL_SECONDS" \
    --quiet \
    "${ANSIBLE_ARGS[@]}"

  if [[ "$AUTO_DUMP_RESULTS" == "1" ]]; then
    if docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana'; then
      step "Dumping Grafana results..."
      if quiet_run_all ./scripts/dump_grafana_results.sh \
        --wait \
        --max-seconds "${BOINC_DUMP_WAIT_SECONDS:-$AUTO_UPDATE_SECONDS}" \
        --interval-seconds "${BOINC_DUMP_INTERVAL_SECONDS:-15}" \
        --quiet; then
        step "Grafana dump saved."
      else
        echo "WARNING: Grafana dump was skipped or failed. Check computations and monitoring, then run:"
        echo "  ./scripts/dump_grafana_results.sh --wait --max-seconds 600"
      fi
    else
      debug_log "Skipping Grafana dump: boinc-grafana is not running."
    fi
  fi
fi

if [[ "$SKIP_STATUS" != "1" ]]; then
  step "Checking cluster status..."
  if [[ "$SERVER_ONLY" == "1" ]]; then
    if ! quiet_run_all timeout "${STATUS_TIMEOUT_SECONDS}s" ./scripts/status.sh --server-only "${ANSIBLE_ARGS[@]}"; then
      echo "WARNING: status check failed or timed out. Run manually:"
      echo "  ./scripts/status.sh --server-only --debug"
    fi
  else
    if ! quiet_run_all timeout "${STATUS_TIMEOUT_SECONDS}s" ./scripts/status.sh "${ANSIBLE_ARGS[@]}"; then
      echo "WARNING: status check failed or timed out. Run manually:"
      echo "  ./scripts/status.sh --debug"
    fi
  fi
fi

echo
step "Cluster launch completed."
