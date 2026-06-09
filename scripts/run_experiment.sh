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
WORKUNITS=""

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

cd "$ROOT_DIR"

echo "== BOINC experiment runner =="
echo

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
    --big-det|--big_det)
      EXPERIMENT_TASK="big-det"
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
    --workunits|--task-count)
      if [[ $# -lt 2 ]]; then
        echo "--workunits requires a value." >&2
        exit 2
      fi
      WORKUNITS="$2"
      shift 2
      ;;
    --help|-h)
      cat <<'USAGE'
Usage:
  ./scripts/run_experiment.sh [options]

Options:
  --task user|big-det       task to submit; default: user
  --user-task PATH          Python file for --task user
  --user-params PATH        params.jsonl for --task user
  --workunits N             number of big-det workunits
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
  echo "Usage: ./scripts/run_experiment.sh [--task user|big-det] [--submit-only] [--debug]"
  exit 2
fi

if [[ -z "$EXPERIMENT_TASK" ]]; then
  echo "--task cannot be empty." >&2
  exit 2
fi

if [[ -n "$WORKUNITS" ]]; then
  if ! [[ "$WORKUNITS" =~ ^[0-9]+$ ]] || (( WORKUNITS < 1 )); then
    echo "--workunits must be a positive integer." >&2
    exit 2
  fi
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

if [[ ! -f "$ROOT_DIR/config/distributed.env" && -f "$ROOT_DIR/config/distributed.example.env" ]]; then
  echo "Creating config/distributed.env from example..."
  cp "$ROOT_DIR/config/distributed.example.env" "$ROOT_DIR/config/distributed.env"
fi

if [[ "${#ANSIBLE_ARGS[@]}" -gt 0 ]]; then
  export ANSIBLE_EXTRA_ARGS="${ANSIBLE_ARGS[*]}"
fi

sql_tsv() {
  docker exec boinc-mariadb mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "$1"
}

run_selected_experiment() {
  local task="$EXPERIMENT_TASK"
  case "$task" in
    user|python|python_task|python-task)
      echo "Experiment task: user"
      echo "Task file: $USER_TASK_FILE"
      echo "Params:    $USER_TASK_PARAMS"
      export PYTHON_TASK_APP_NAME="${PYTHON_TASK_APP_NAME:-user_python_task}"
      export PYTHON_TASK_APP_FRIENDLY_NAME="${PYTHON_TASK_APP_FRIENDLY_NAME:-User Python task}"
      apps/python_task_runner/run_task.sh \
        --task "$USER_TASK_FILE" \
        --params "$USER_TASK_PARAMS" \
        --device cpu
      ;;
    big-det|big_det|big-determinant|big_determinant)
      echo "Experiment task: big-det"
      local args=(apps/big_determinant/run_task.sh boinc)
      if [[ -n "$WORKUNITS" ]]; then
        args+=(--workunits "$WORKUNITS")
      fi
      "${args[@]}"
      ;;
    *)
      echo "Unknown task: $task" >&2
      echo "Supported: user, big-det" >&2
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

echo "Experiment task:"
echo "  $EXPERIMENT_TASK"
if [[ -n "$WORKUNITS" ]]; then
  echo "  workunits=$WORKUNITS"
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

if [[ "$SUBMIT_ONLY" == "1" ]]; then
  echo "Experiment submitted."
  echo "Auto-update, Grafana dump, and status check were skipped."
  exit 0
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
