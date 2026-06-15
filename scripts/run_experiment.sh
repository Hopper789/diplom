#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTO_UPDATE_SECONDS="${BOINC_AUTO_UPDATE_SECONDS:-600}"
AUTO_UPDATE_INTERVAL_SECONDS="${BOINC_AUTO_UPDATE_INTERVAL_SECONDS:-15}"
AUTO_DUMP_RESULTS="${BOINC_AUTO_DUMP_RESULTS:-1}"
STATUS_AFTER_SUBMIT="${BOINC_STATUS_AFTER_SUBMIT:-0}"
SUBMIT_ONLY="${BOINC_SUBMIT_ONLY:-0}"
EXPERIMENT_TASK="user"
USER_TASK_FILE="$ROOT_DIR/apps/user_task_template/user_task.py"
USER_TASK_PARAMS="$ROOT_DIR/apps/user_task_template/params.jsonl"
SIMULATE_FAILURE_RATE="${BOINC_SIMULATE_FAILURE_RATE:-0}"
SIMULATE_FAILURE_SEED="${BOINC_SIMULATE_FAILURE_SEED:-default}"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

cd "$ROOT_DIR"

step "Starting BOINC experiment runner..."

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --submit-only)
      SUBMIT_ONLY=1
      shift
      ;;
    --task)
      if [[ $# -lt 2 ]]; then
        echo "--task requires a value." >&2
        exit 2
      fi
      EXPERIMENT_TASK="$2"
      shift 2
      ;;
    --task=*)
      EXPERIMENT_TASK="${1#*=}"
      shift
      ;;
    --big-det|--big_det|--determinant)
      EXPERIMENT_TASK="determinant"
      shift
      ;;
    --grid-search|--grid_search)
      EXPERIMENT_TASK="grid-search"
      shift
      ;;
    --user-task)
      if [[ $# -lt 2 ]]; then
        echo "--user-task requires a path." >&2
        exit 2
      fi
      USER_TASK_FILE="$2"
      shift 2
      ;;
    --user-params)
      if [[ $# -lt 2 ]]; then
        echo "--user-params requires a path." >&2
        exit 2
      fi
      USER_TASK_PARAMS="$2"
      shift 2
      ;;
    --simulate-failures)
      if [[ $# -lt 2 ]]; then
        echo "--simulate-failures requires a value from 0 to 1." >&2
        exit 2
      fi
      SIMULATE_FAILURE_RATE="$2"
      shift 2
      ;;
    --simulate-failures=*)
      SIMULATE_FAILURE_RATE="${1#*=}"
      shift
      ;;
    --simulate-failure-seed)
      if [[ $# -lt 2 ]]; then
        echo "--simulate-failure-seed requires a value." >&2
        exit 2
      fi
      SIMULATE_FAILURE_SEED="$2"
      shift 2
      ;;
    --simulate-failure-seed=*)
      SIMULATE_FAILURE_SEED="${1#*=}"
      shift
      ;;
    --help|-h)
      cat <<'USAGE'
Usage:
  ./scripts/run_experiment.sh [options]

Options:
  --task user|grid-search|determinant
                           task to submit; default: user
  --user-task PATH          Python file for --task user
  --user-params PATH        params.jsonl for --task user
  --simulate-failures RATE  make roughly RATE of BOINC attempts fail; 0..1
  --simulate-failure-seed SEED
                           deterministic seed for simulated failures
  --submit-only             submit work without client pumping/Grafana dump
  --debug                   show full command output
  --ask-vault-pass, --vault ask Vault password manually
  --vault-password-file F   use custom Vault password file
  --ask-become-pass, -K     ask sudo password
  --help, -h
USAGE
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

ANSIBLE_REMAINING_ARGS=("$@")
if [[ "${#ANSIBLE_REMAINING_ARGS[@]}" -gt 0 ]]; then
  echo "Unknown argument: ${ANSIBLE_REMAINING_ARGS[0]}"
  echo "Usage: ./scripts/run_experiment.sh [--task user|grid-search|determinant] [--submit-only] [--debug]"
  exit 2
fi

if [[ -z "$EXPERIMENT_TASK" ]]; then
  echo "--task cannot be empty." >&2
  exit 2
fi

python3 - <<PY
try:
    rate = float("$SIMULATE_FAILURE_RATE")
except ValueError:
    raise SystemExit("--simulate-failures должен быть числом от 0 до 1")
if not 0 <= rate <= 1:
    raise SystemExit("--simulate-failures должен быть числом от 0 до 1")
PY

if [[ ! -f "$ROOT_DIR/config/generated.env" ]]; then
  echo "ERROR: config/generated.env not found."
  echo "Run first:"
  echo "  ./scripts/prepare_system.sh"
  echo "Then launch the cluster:"
  echo "  ./scripts/launch_cluster.sh --with-monitoring"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/config/generated.env"
set +a
MONITORING_HOST="${SERVER_IP:-localhost}"

if [[ ! -f "$ROOT_DIR/config/distributed.env" && -f "$ROOT_DIR/config/distributed.example.env" ]]; then
  step "Creating distributed config..."
  cp "$ROOT_DIR/config/distributed.example.env" "$ROOT_DIR/config/distributed.env"
fi

if [[ "${#ANSIBLE_ARGS[@]}" -gt 0 ]]; then
  export ANSIBLE_EXTRA_ARGS="${ANSIBLE_ARGS[*]}"
fi

export BOINC_SIMULATE_FAILURE_RATE="$SIMULATE_FAILURE_RATE"
export BOINC_SIMULATE_FAILURE_SEED="$SIMULATE_FAILURE_SEED"

sql_tsv() {
  docker exec boinc-mariadb mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "$1"
}

run_selected_experiment() {
  local task="$EXPERIMENT_TASK"
  case "$task" in
    user|python|python_task|python-task)
      debug_log "Experiment task: user"
      debug_log "Task file: $USER_TASK_FILE"
      debug_log "Params:    $USER_TASK_PARAMS"
      export PYTHON_TASK_APP_NAME="${PYTHON_TASK_APP_NAME:-user_python_task}"
      export PYTHON_TASK_APP_FRIENDLY_NAME="${PYTHON_TASK_APP_FRIENDLY_NAME:-User Python task}"
      quiet_run_all apps/python_task_runner/run_task.sh \
        --task "$USER_TASK_FILE" \
        --params "$USER_TASK_PARAMS" \
        --device cpu
      ;;
    grid-search|grid_search|ml-grid-search|ml_grid_search)
      debug_log "Experiment task: grid-search"
      quiet_run_all apps/ml_grid_search/run_task.sh boinc
      ;;
    determinant|big-det|big_det|big-determinant|big_determinant)
      debug_log "Experiment task: determinant"
      local args=(apps/big_determinant/run_task.sh boinc)
      quiet_run_all "${args[@]}"
      ;;
    *)
      echo "Unknown task: $task" >&2
      echo "Supported tasks:" >&2
      echo "  user         - apps/user_task_template or your --user-task/--user-params" >&2
      echo "  grid-search  - apps/ml_grid_search" >&2
      echo "  determinant  - apps/big_determinant" >&2
      exit 2
      ;;
  esac
}

read_progress() {
  local row
  row="$(sql_tsv "
    SELECT
      COUNT(*),
      COALESCE(SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(unfinished), 0),
      COALESCE(SUM(client_errors), 0),
      COALESCE(SUM(redundant), 0)
    FROM (
      SELECT
        w.id,
        CASE
          WHEN COALESCE(w.canonical_resultid, 0) > 0
            OR COALESCE(SUM(CASE WHEN r.outcome = 1 THEN 1 ELSE 0 END), 0)
               >= GREATEST(COALESCE(NULLIF(w.min_quorum, 0), 1), 1)
          THEN 1 ELSE 0
        END AS completed,
        COALESCE(SUM(CASE WHEN r.outcome = 0 THEN 1 ELSE 0 END), 0) AS unfinished,
        COALESCE(SUM(CASE WHEN r.outcome IN (2, 3, 4, 6) THEN 1 ELSE 0 END), 0) AS client_errors,
        COALESCE(SUM(CASE WHEN r.outcome = 5 THEN 1 ELSE 0 END), 0) AS redundant
      FROM workunit w
      LEFT JOIN result r ON r.workunitid = w.id
      GROUP BY w.id, w.min_quorum, w.canonical_resultid
    ) q;
  " 2>/dev/null || true)"

  IFS=$'\t' read -r WORKUNITS COMPLETED UNFINISHED CLIENT_ERRORS REDUNDANT <<< "$row"
  WORKUNITS="${WORKUNITS:-0}"
  COMPLETED="${COMPLETED:-0}"
  UNFINISHED="${UNFINISHED:-0}"
  CLIENT_ERRORS="${CLIENT_ERRORS:-0}"
  REDUNDANT="${REDUNDANT:-0}"
}

if debug_enabled; then
  echo "Experiment task:"
  echo "  $EXPERIMENT_TASK"
  echo "Simulated failures:"
  echo "  rate=$BOINC_SIMULATE_FAILURE_RATE"
  echo "  seed=$BOINC_SIMULATE_FAILURE_SEED"
  echo
  echo "Distributed computing config:"
  if [[ -f "$ROOT_DIR/config/distributed.env" ]]; then
    grep -v '^#' "$ROOT_DIR/config/distributed.env" | grep -v '^$' || true
  else
    echo "No config/distributed.env found; using defaults from run_task.sh."
  fi
fi

step "Submitting BOINC work..."
export ANSIBLE_HOST_KEY_CHECKING=False
run_selected_experiment

if [[ "$STATUS_AFTER_SUBMIT" == "1" ]]; then
  step "Checking status after submitting work..."
  quiet_run_all ./scripts/status.sh "${ANSIBLE_ARGS[@]}" || true
fi

if [[ "$SUBMIT_ONLY" == "1" ]]; then
  step "Experiment submitted."
  debug_log "Auto-update, Grafana dump, and status check were skipped."
  exit 0
fi

step "Requesting BOINC client updates..."
quiet_run_all ./scripts/pump_clients.sh \
  --max-seconds "$AUTO_UPDATE_SECONDS" \
  --interval-seconds "$AUTO_UPDATE_INTERVAL_SECONDS" \
  --quiet \
  "${ANSIBLE_ARGS[@]}"

if [[ "$AUTO_DUMP_RESULTS" == "1" ]]; then
  if docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana'; then
    read_progress
    if [[ "$CLIENT_ERRORS" -gt 0 || "$WORKUNITS" -eq 0 || "$COMPLETED" -lt "$WORKUNITS" ]]; then
      step "Skipping Grafana dump because computations are not complete."
      debug_log "  workunits=$WORKUNITS completed=$COMPLETED unfinished=$UNFINISHED client_errors=$CLIENT_ERRORS redundant=$REDUNDANT"
      echo "Check the reason with:"
      echo "  ./scripts/diagnose_compute.sh --debug"
      echo "  ./scripts/status.sh --debug"
      echo "After fixing the computation, rerun the experiment, then dump manually if needed:"
      echo "  ./scripts/dump_grafana_results.sh --wait --max-seconds 600"
    else
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
    fi
  else
    echo "Skipping Grafana dump: boinc-grafana is not running."
    echo "Start monitoring to enable graph dumps:"
    echo "  ./scripts/launch_cluster.sh --with-monitoring"
  fi
fi

step "Experiment submitted."
if debug_enabled; then
  echo "Use monitoring or status command to watch progress:"
  echo "  ./scripts/status.sh --debug"
  echo "  http://$MONITORING_HOST:3000"
fi
