#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTO_UPDATE_SECONDS="${BOINC_AUTO_UPDATE_SECONDS:-600}"
AUTO_UPDATE_INTERVAL_SECONDS="${BOINC_AUTO_UPDATE_INTERVAL_SECONDS:-15}"
AUTO_DUMP_RESULTS="${BOINC_AUTO_DUMP_RESULTS:-1}"
STATUS_AFTER_SUBMIT="${BOINC_STATUS_AFTER_SUBMIT:-0}"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

cd "$ROOT_DIR"

echo "== BOINC experiment runner =="
echo

build_ansible_args "$@"
if [[ "${#ANSIBLE_REMAINING_ARGS[@]}" -gt 0 ]]; then
  echo "Unknown argument: ${ANSIBLE_REMAINING_ARGS[0]}"
  echo "Usage: ./scripts/run_experiment.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
  exit 2
fi

if [[ ! -f "$ROOT_DIR/config/generated.env" ]]; then
  echo "ERROR: config/generated.env not found."
  echo "Run first:"
  echo "  ./scripts/bootstrap_server.sh"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/config/generated.env"
set +a
MONITORING_HOST="${SERVER_IP:-localhost}"

if [[ ! -f "$ROOT_DIR/config/experiment.env" && -f "$ROOT_DIR/config/experiment.example.env" ]]; then
  echo "Creating config/experiment.env from example..."
  cp "$ROOT_DIR/config/experiment.example.env" "$ROOT_DIR/config/experiment.env"
fi

if [[ ! -f "$ROOT_DIR/config/distributed.env" && -f "$ROOT_DIR/config/distributed.example.env" ]]; then
  echo "Creating config/distributed.env from example..."
  cp "$ROOT_DIR/config/distributed.example.env" "$ROOT_DIR/config/distributed.env"
fi

if [[ "${#ANSIBLE_ARGS[@]}" -gt 0 ]]; then
  export ANSIBLE_EXTRA_ARGS="${ANSIBLE_ARGS[*]}"
fi

sql_tsv() {
  docker exec boinc-mysql mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "$1"
}

run_selected_experiment() {
  local app="${EXPERIMENT_APP:-ml_grid_search}"

  if [[ -n "${EXPERIMENT_TASK_CMD:-}" ]]; then
    echo "Experiment task: custom command"
    echo "Command: $EXPERIMENT_TASK_CMD"
    bash -lc "$EXPERIMENT_TASK_CMD"
    return
  fi

  echo "Experiment task: $app"
  case "$app" in
    ml_grid_search)
      apps/ml_grid_search/run_task.sh boinc
      ;;
    big_determinant)
      apps/big_determinant/run_task.sh boinc
      ;;
    python_task_runner)
      : "${PYTHON_TASK_FILE:?PYTHON_TASK_FILE is required for EXPERIMENT_APP=python_task_runner}"
      : "${PYTHON_TASK_PARAMS:?PYTHON_TASK_PARAMS is required for EXPERIMENT_APP=python_task_runner}"
      apps/python_task_runner/run_task.sh \
        --task "$PYTHON_TASK_FILE" \
        --params "$PYTHON_TASK_PARAMS" \
        --device "${PYTHON_TASK_DEVICE:-cpu}"
      ;;
    *)
      echo "Unknown EXPERIMENT_APP: $app" >&2
      echo "Supported: ml_grid_search, big_determinant, python_task_runner" >&2
      echo "Or set EXPERIMENT_TASK_CMD for a custom command." >&2
      exit 2
      ;;
  esac
}

read_progress() {
  local row
  row="$(sql_tsv "
    SELECT
      COUNT(DISTINCT w.id),
      COUNT(DISTINCT CASE WHEN r.outcome = 1 THEN w.id END),
      COALESCE(SUM(CASE WHEN r.outcome = 0 THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN r.outcome IN (2, 3, 4, 6) THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN r.outcome = 5 THEN 1 ELSE 0 END), 0)
    FROM workunit w
    LEFT JOIN result r ON r.workunitid = w.id;
  " 2>/dev/null || true)"

  IFS=$'\t' read -r WORKUNITS COMPLETED UNFINISHED CLIENT_ERRORS REDUNDANT <<< "$row"
  WORKUNITS="${WORKUNITS:-0}"
  COMPLETED="${COMPLETED:-0}"
  UNFINISHED="${UNFINISHED:-0}"
  CLIENT_ERRORS="${CLIENT_ERRORS:-0}"
  REDUNDANT="${REDUNDANT:-0}"
}

echo "Experiment config:"
if [[ -f "$ROOT_DIR/config/experiment.env" ]]; then
  grep -v '^#' "$ROOT_DIR/config/experiment.env" | grep -v '^$' || true
else
  echo "No config/experiment.env found; using defaults from run_task.sh."
fi

echo
echo "Distributed computing config:"
if [[ -f "$ROOT_DIR/config/distributed.env" ]]; then
  grep -v '^#' "$ROOT_DIR/config/distributed.env" | grep -v '^$' || true
else
  echo "No config/distributed.env found; using defaults from run_task.sh."
fi

echo
echo "Submitting BOINC work..."
export ANSIBLE_HOST_KEY_CHECKING=False
run_selected_experiment

echo
if [[ "$STATUS_AFTER_SUBMIT" == "1" ]]; then
  echo "Status after submitting work:"
  ./scripts/status.sh "${ANSIBLE_ARGS[@]}" || true
  echo
fi

echo
./scripts/pump_clients.sh \
  --max-seconds "$AUTO_UPDATE_SECONDS" \
  --interval-seconds "$AUTO_UPDATE_INTERVAL_SECONDS" \
  --quiet \
  "${ANSIBLE_ARGS[@]}"

echo
if [[ "$AUTO_DUMP_RESULTS" == "1" ]]; then
  if docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana'; then
    read_progress
    if [[ "$CLIENT_ERRORS" -gt 0 || "$WORKUNITS" -eq 0 || "$COMPLETED" -lt "$WORKUNITS" ]]; then
      echo "Skipping Grafana dump because computations are not clean:"
      echo "  workunits=$WORKUNITS completed=$COMPLETED unfinished=$UNFINISHED client_errors=$CLIENT_ERRORS redundant=$REDUNDANT"
      echo "Fix the computation error, rerun the experiment, then dump manually if needed:"
      echo "  ./scripts/dump_grafana_results.sh --wait --max-seconds 600"
    else
      if ./scripts/dump_grafana_results.sh \
        --wait \
        --max-seconds "${BOINC_DUMP_WAIT_SECONDS:-$AUTO_UPDATE_SECONDS}" \
        --interval-seconds "${BOINC_DUMP_INTERVAL_SECONDS:-15}" \
        --quiet; then
        echo "Grafana dump saved."
      else
        echo "WARNING: Grafana dump was skipped or failed. Check computations and monitoring, then run:"
        echo "  ./scripts/dump_grafana_results.sh --wait --max-seconds 600"
      fi
    fi
  else
    echo "Skipping Grafana dump: boinc-grafana is not running."
    echo "Start monitoring to enable graph dumps:"
    echo "  ./scripts/launch_cluster.sh --with-monitoring"
  fi
fi

echo
echo "Experiment submitted."
echo "Use monitoring or status command to watch progress:"
echo "  ./scripts/status.sh"
echo "  http://$MONITORING_HOST:3000"
