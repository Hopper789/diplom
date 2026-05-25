#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
EXPERIMENT_ENV_FILE="$ROOT_DIR/config/experiment.env"
DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"

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
APP_VERSION="${APP_VERSION:-1.04}"
PLATFORM="${PLATFORM:-x86_64-pc-linux-gnu}"
BIN_NAME="${APP_NAME}_${APP_VERSION}_${PLATFORM}"

SRC_CPP="$ROOT_DIR/apps/ml_grid_search/ml_grid_search.cpp"
TPL_IN_BASE="$ROOT_DIR/apps/ml_grid_search/templates/ml_grid_search_in"
TPL_OUT="$ROOT_DIR/apps/ml_grid_search/templates/ml_grid_search_out"
BUILD_DIR="$ROOT_DIR/apps/ml_grid_search/build"
TPL_IN="$BUILD_DIR/${APP_NAME}_in.generated"

MODE="${1:-boinc}"

EXPERIMENT_WALL_SECONDS="${EXPERIMENT_WALL_SECONDS:-180}"
EXPERIMENT_CORES="${EXPERIMENT_CORES:-12}"
TASK_SECONDS="${TASK_SECONDS:-8}"
TASK_COUNT="${TASK_COUNT:-}"
TASK_DATASET_SIZE="${TASK_DATASET_SIZE:-500}"
TASK_SEED_BASE="${TASK_SEED_BASE:-1000}"

# BOINC workunit scheduling and replication parameters.
# Defaults match the baseline configuration: one result per workunit, no replication.
DISTRIBUTED_TARGET_NRESULTS="${DISTRIBUTED_TARGET_NRESULTS:-1}"
DISTRIBUTED_MIN_QUORUM="${DISTRIBUTED_MIN_QUORUM:-1}"
DISTRIBUTED_MAX_SUCCESS_RESULTS="${DISTRIBUTED_MAX_SUCCESS_RESULTS:-1}"
DISTRIBUTED_MAX_ERROR_RESULTS="${DISTRIBUTED_MAX_ERROR_RESULTS:-3}"
DISTRIBUTED_MAX_TOTAL_RESULTS="${DISTRIBUTED_MAX_TOTAL_RESULTS:-3}"
DISTRIBUTED_DELAY_BOUND="${DISTRIBUTED_DELAY_BOUND:-86400}"
DISTRIBUTED_RSC_FPOPS_EST="${DISTRIBUTED_RSC_FPOPS_EST:-100000000000.0}"
DISTRIBUTED_RSC_FPOPS_BOUND="${DISTRIBUTED_RSC_FPOPS_BOUND:-10000000000000.0}"
DISTRIBUTED_RSC_MEMORY_BOUND="${DISTRIBUTED_RSC_MEMORY_BOUND:-268435456}"
DISTRIBUTED_RSC_DISK_BOUND="${DISTRIBUTED_RSC_DISK_BOUND:-104857600}"

ANSIBLE_EXTRA_ARGS="${ANSIBLE_EXTRA_ARGS:-}"

mkdir -p "$BUILD_DIR"

require_generated_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: config/generated.env not found."
    echo "Run:"
    echo "  ./scripts/init_config.sh"
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  : "${PROJECT_NAME:?PROJECT_NAME is empty}"
  : "${BOINC_PROJECT_URL:?BOINC_PROJECT_URL is empty}"
  : "${BOINC_CLIENT_RPC_PASSWORD:?BOINC_CLIENT_RPC_PASSWORD is empty}"
}

calc_task_count() {
  if [[ -n "$TASK_COUNT" ]]; then
    echo "$TASK_COUNT"
    return
  fi

  python3 - "$EXPERIMENT_WALL_SECONDS" "$EXPERIMENT_CORES" "$TASK_SECONDS" <<'PY'
import math
import sys

wall = float(sys.argv[1])
cores = max(1, int(float(sys.argv[2])))
task_seconds = max(1.0, float(sys.argv[3]))

print(max(1, math.ceil(wall * cores / task_seconds)))
PY
}

compile_local() {
  echo "Building $BIN_NAME locally..."
  g++ -O2 -std=c++17 -o "$BUILD_DIR/$BIN_NAME" "$SRC_CPP"
}

compile_boinc() {
  echo "Building $BIN_NAME inside boinc-server with BOINC API..."

  docker cp "$SRC_CPP" "boinc-server:/tmp/${APP_NAME}.cpp"

  docker exec boinc-server bash -lc "
    mkdir -p '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM'
    g++ -O2 -std=c++17 \
      -I/opt/boinc -I/opt/boinc/api -I/opt/boinc/lib \
      -L/opt/boinc/api -L/opt/boinc/lib \
      -o '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/$BIN_NAME' \
      '/tmp/${APP_NAME}.cpp' \
      -lboinc_api -lboinc -pthread
  "
}

ensure_server_running() {
  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
    echo "ERROR: boinc-server container is not running."
    echo "Run:"
    echo "  ./scripts/server_up.sh"
    exit 1
  fi

  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mysql'; then
    echo "ERROR: boinc-mysql container is not running."
    echo "Run:"
    echo "  ./scripts/server_up.sh"
    exit 1
  fi
}

validate_distributed_config() {
  python3 - <<PY
import sys

ints = {
    "DISTRIBUTED_TARGET_NRESULTS": "$DISTRIBUTED_TARGET_NRESULTS",
    "DISTRIBUTED_MIN_QUORUM": "$DISTRIBUTED_MIN_QUORUM",
    "DISTRIBUTED_MAX_SUCCESS_RESULTS": "$DISTRIBUTED_MAX_SUCCESS_RESULTS",
    "DISTRIBUTED_MAX_ERROR_RESULTS": "$DISTRIBUTED_MAX_ERROR_RESULTS",
    "DISTRIBUTED_MAX_TOTAL_RESULTS": "$DISTRIBUTED_MAX_TOTAL_RESULTS",
    "DISTRIBUTED_DELAY_BOUND": "$DISTRIBUTED_DELAY_BOUND",
    "DISTRIBUTED_RSC_MEMORY_BOUND": "$DISTRIBUTED_RSC_MEMORY_BOUND",
    "DISTRIBUTED_RSC_DISK_BOUND": "$DISTRIBUTED_RSC_DISK_BOUND",
}

for name, value in ints.items():
    try:
        parsed = int(value)
    except ValueError:
        print(f"ERROR: {name} must be an integer, got: {value}")
        sys.exit(1)
    if parsed < 0:
        print(f"ERROR: {name} must be >= 0, got: {value}")
        sys.exit(1)

floats = {
    "DISTRIBUTED_RSC_FPOPS_EST": "$DISTRIBUTED_RSC_FPOPS_EST",
    "DISTRIBUTED_RSC_FPOPS_BOUND": "$DISTRIBUTED_RSC_FPOPS_BOUND",
}

for name, value in floats.items():
    try:
        parsed = float(value)
    except ValueError:
        print(f"ERROR: {name} must be a number, got: {value}")
        sys.exit(1)
    if parsed < 0:
        print(f"ERROR: {name} must be >= 0, got: {value}")
        sys.exit(1)

if int("$DISTRIBUTED_MIN_QUORUM") > int("$DISTRIBUTED_TARGET_NRESULTS"):
    print("ERROR: DISTRIBUTED_MIN_QUORUM must be <= DISTRIBUTED_TARGET_NRESULTS")
    sys.exit(1)

if int("$DISTRIBUTED_MAX_SUCCESS_RESULTS") < int("$DISTRIBUTED_MIN_QUORUM"):
    print("ERROR: DISTRIBUTED_MAX_SUCCESS_RESULTS must be >= DISTRIBUTED_MIN_QUORUM")
    sys.exit(1)

if int("$DISTRIBUTED_MAX_TOTAL_RESULTS") < int("$DISTRIBUTED_TARGET_NRESULTS"):
    print("ERROR: DISTRIBUTED_MAX_TOTAL_RESULTS must be >= DISTRIBUTED_TARGET_NRESULTS")
    sys.exit(1)
PY
}

generate_input_template() {
  validate_distributed_config

  cat > "$TPL_IN" <<TEMPLATE_EOF
<file_info>
    <number>0</number>
</file_info>

<workunit>
    <file_ref>
        <file_number>0</file_number>
        <open_name>in</open_name>
    </file_ref>

    <rsc_fpops_est>$DISTRIBUTED_RSC_FPOPS_EST</rsc_fpops_est>
    <rsc_fpops_bound>$DISTRIBUTED_RSC_FPOPS_BOUND</rsc_fpops_bound>
    <rsc_memory_bound>$DISTRIBUTED_RSC_MEMORY_BOUND</rsc_memory_bound>
    <rsc_disk_bound>$DISTRIBUTED_RSC_DISK_BOUND</rsc_disk_bound>

    <delay_bound>$DISTRIBUTED_DELAY_BOUND</delay_bound>
    <min_quorum>$DISTRIBUTED_MIN_QUORUM</min_quorum>
    <target_nresults>$DISTRIBUTED_TARGET_NRESULTS</target_nresults>
    <max_error_results>$DISTRIBUTED_MAX_ERROR_RESULTS</max_error_results>
    <max_total_results>$DISTRIBUTED_MAX_TOTAL_RESULTS</max_total_results>
    <max_success_results>$DISTRIBUTED_MAX_SUCCESS_RESULTS</max_success_results>
</workunit>
TEMPLATE_EOF
}

ensure_templates() {
  if [[ ! -f "$TPL_IN_BASE" ]]; then
    echo "ERROR: input template reference not found: $TPL_IN_BASE"
    exit 1
  fi

  if [[ ! -f "$TPL_OUT" ]]; then
    echo "ERROR: output template not found: $TPL_OUT"
    exit 1
  fi

  generate_input_template
}

declare_app_in_project_xml() {
  echo "Ensuring app is declared in project.xml..."

  docker exec boinc-server bash -lc "
    cd '/project/$PROJECT_NAME'

    if ! grep -q '<name>$APP_NAME</name>' project.xml; then
      python3 - <<'PY'
from pathlib import Path

app_name = '$APP_NAME'
friendly_name = 'ML grid search'

path = Path('project.xml')
text = path.read_text()

insert = f'''
    <app>
        <name>{app_name}</name>
        <user_friendly_name>{friendly_name}</user_friendly_name>
    </app>
'''

if f'<name>{app_name}</name>' not in text:
    text = text.replace('</boinc>', insert + '\\n</boinc>')

path.write_text(text)
PY
    fi
  "
}

deploy_app_to_server() {
  echo "Deploying BOINC app and templates..."
  echo "  PROJECT_NAME=$PROJECT_NAME"
  echo "  APP_NAME=$APP_NAME"
  echo "  APP_VERSION=$APP_VERSION"
  echo "  PLATFORM=$PLATFORM"

  docker exec boinc-server bash -lc "
    mkdir -p \
      '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM' \
      '/project/$PROJECT_NAME/templates' \
      '/project/$PROJECT_NAME/work_inputs'
  "

  compile_boinc

  docker cp "$TPL_IN" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_in"
  docker cp "$TPL_OUT" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_out"

  declare_app_in_project_xml

  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/xadd"
  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/update_versions --noconfirm"
}

create_workunits() {
  local task_count
  task_count="$(calc_task_count)"

  echo "Creating workunits..."
  echo "  TASK_COUNT=$task_count"
  echo "  TASK_SECONDS=$TASK_SECONDS"
  echo "  TASK_DATASET_SIZE=$TASK_DATASET_SIZE"
  echo "  TASK_SEED_BASE=$TASK_SEED_BASE"
  echo "  EXPERIMENT_WALL_SECONDS=$EXPERIMENT_WALL_SECONDS"
  echo "  EXPERIMENT_CORES=$EXPERIMENT_CORES"
  echo "  DISTRIBUTED_TARGET_NRESULTS=$DISTRIBUTED_TARGET_NRESULTS"
  echo "  DISTRIBUTED_MIN_QUORUM=$DISTRIBUTED_MIN_QUORUM"
  echo "  DISTRIBUTED_MAX_SUCCESS_RESULTS=$DISTRIBUTED_MAX_SUCCESS_RESULTS"
  echo "  DISTRIBUTED_MAX_TOTAL_RESULTS=$DISTRIBUTED_MAX_TOTAL_RESULTS"

  local run_id
  run_id="$(date +%s)"

  for task_id in $(seq 1 "$task_count"); do
    lambda="$(
      python3 - "$task_id" <<'PY'
import sys
i = int(sys.argv[1])
grid = [0, 0.001, 0.003, 0.01, 0.03, 0.1, 0.3, 1, 3, 10]
print(grid[(i - 1) % len(grid)])
PY
    )"

    seed=$((TASK_SEED_BASE + task_id))
    task_tag="$(printf '%04d' "$task_id")"
    lambda_tag="${lambda//./p}"
    in_name="grid_${run_id}_${task_tag}_lambda_${lambda_tag}.txt"
    wu_name="grid_${run_id}_${task_tag}_lambda_${lambda_tag}"

    docker exec boinc-server bash -lc "
      cd '/project/$PROJECT_NAME'

      cat > 'work_inputs/$in_name' <<EOF
task_id=$task_id
lambda=$lambda
seed=$seed
n=$TASK_DATASET_SIZE
target_seconds=$TASK_SECONDS
EOF

      ./bin/stage_file_native --copy 'work_inputs/$in_name'
      ./bin/create_work --appname '$APP_NAME' --wu_name '$wu_name' '$in_name'
    "
  done

  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && touch reread_db"
}

update_real_clients() {
  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
    echo "ansible/inventory.ini not found; skip client update."
    return 0
  fi

  if ! command -v ansible >/dev/null 2>&1; then
    echo "ansible is not installed; skip client update."
    return 0
  fi

  echo
  echo "Requesting project update on real BOINC clients..."
  echo "Ansible options are taken from ANSIBLE_EXTRA_ARGS."
  echo "If ansible/.vault_pass exists, wrapper scripts pass it automatically."
  echo

  # shellcheck disable=SC2086
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b $ANSIBLE_EXTRA_ARGS -m shell -a "
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --project '$BOINC_PROJECT_URL' update
  " || true
}

show_server_summary() {
  echo
  echo "Server DB summary:"
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" -e "
    SELECT COUNT(*) AS hosts FROM host;
    SELECT COUNT(*) AS workunits FROM workunit;
    SELECT COUNT(*) AS results FROM result;
    SELECT id, name, appid, create_time FROM workunit ORDER BY id DESC LIMIT 10;
    SELECT id, workunitid, server_state, outcome, client_state, hostid FROM result ORDER BY id DESC LIMIT 10;
  "
}

show_client_summary() {
  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
    return 0
  fi

  if ! command -v ansible >/dev/null 2>&1; then
    return 0
  fi

  echo
  echo "Client task summary:"

  # shellcheck disable=SC2086
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b $ANSIBLE_EXTRA_ARGS -m shell -a "
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --get_task_summary
  " || true

  echo
  echo "Client project status:"

  # shellcheck disable=SC2086
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b $ANSIBLE_EXTRA_ARGS -m shell -a "
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --get_project_status
  " || true
}

run_boinc() {
  require_generated_env
  ensure_server_running
  ensure_templates

  deploy_app_to_server
  create_workunits
  update_real_clients
  show_server_summary
  show_client_summary

  echo
  echo "Experiment submitted."
  echo "Watch progress:"
  echo "  ./scripts/status.sh"
  echo "  http://localhost:3000  # Grafana, if monitoring is enabled"
}

run_local() {
  compile_local

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  task_count="$(calc_task_count)"

  echo "Running local synthetic workload:"
  echo "  TASK_COUNT=$task_count"
  echo "  TASK_SECONDS=$TASK_SECONDS"

  start_ts="$(date +%s)"

  for task_id in $(seq 1 "$task_count"); do
    lambda="$(
      python3 - "$task_id" <<'PY'
import sys
i = int(sys.argv[1])
grid = [0, 0.001, 0.003, 0.01, 0.03, 0.1, 0.3, 1, 3, 10]
print(grid[(i - 1) % len(grid)])
PY
    )"

    seed=$((TASK_SEED_BASE + task_id))

    cat >"$tmpdir/in" <<EOF
task_id=$task_id
lambda=$lambda
seed=$seed
n=$TASK_DATASET_SIZE
target_seconds=$TASK_SECONDS
EOF

    "$BUILD_DIR/$BIN_NAME" "$tmpdir/in" "$tmpdir/out" >/dev/null
    tail -n 1 "$tmpdir/out"
  done

  end_ts="$(date +%s)"
  echo "Local run elapsed: $((end_ts - start_ts)) seconds"
}

case "$MODE" in
  boinc)
    run_boinc
    ;;
  local)
    run_local
    ;;
  *)
    echo "Usage: $0 [boinc|local]" >&2
    exit 2
    ;;
esac