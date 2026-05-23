#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

if [[ -f "$EXPERIMENT_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$EXPERIMENT_ENV_FILE"
  set +a
fi

APP_NAME="ml_grid_search"
APP_VERSION="${APP_VERSION:-1.04}"
PLATFORM="${PLATFORM:-x86_64-pc-linux-gnu}"
BIN_NAME="${APP_NAME}_${APP_VERSION}_${PLATFORM}"

APP_NAME="${APP_NAME:-ml_grid_search}"
APP_VERSION="${APP_VERSION:-1.04}"
PLATFORM="${PLATFORM:-x86_64-pc-linux-gnu}"

EXPERIMENT_WALL_SECONDS="${EXPERIMENT_WALL_SECONDS:-180}"
EXPERIMENT_CORES="${EXPERIMENT_CORES:-12}"
TASK_SECONDS="${TASK_SECONDS:-8}"
TASK_COUNT="${TASK_COUNT:-}"

TASK_DATASET_SIZE="${TASK_DATASET_SIZE:-500}"
TASK_SEED_BASE="${TASK_SEED_BASE:-1000}"

SRC_CPP="$ROOT_DIR/apps/ml_grid_search/ml_grid_search.cpp"
TPL_IN="$ROOT_DIR/apps/ml_grid_search/templates/ml_grid_search_in"
TPL_OUT="$ROOT_DIR/apps/ml_grid_search/templates/ml_grid_search_out"
BUILD_DIR="$ROOT_DIR/apps/ml_grid_search/build"

MODE="${1:-boinc}"
mkdir -p "$BUILD_DIR"

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

lambda_for_task() {
  python3 - "$1" <<'PY'
import sys
i = int(sys.argv[1])
grid = [0, 0.001, 0.003, 0.01, 0.03, 0.1, 0.3, 1, 3, 10]
print(grid[(i - 1) % len(grid)])
PY
}

run_local() {
  compile_local
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  task_count="$(calc_task_count)"
  echo "Running local synthetic workload: TASK_COUNT=$task_count TASK_SECONDS=$TASK_SECONDS"
  start_ts="$(date +%s)"
  for task_id in $(seq 1 "$task_count"); do
    lambda="$(lambda_for_task "$task_id")"
    seed=$((1000 + task_id))
    cat >"$tmpdir/in" <<EOT
 task_id=$task_id
 lambda=$lambda
 seed=$seed
 n=500
 target_seconds=$TASK_SECONDS
EOT
    "$BUILD_DIR/$BIN_NAME" "$tmpdir/in" "$tmpdir/out" >/dev/null
    tail -n 1 "$tmpdir/out"
  done
  end_ts="$(date +%s)"
  echo "Local run elapsed: $((end_ts - start_ts)) seconds"
}

run_boinc() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
    echo "ERROR: boinc-server container is not running. Run: ./scripts/server_up.sh" >&2
    exit 1
  fi

  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mysql'; then
    echo "ERROR: boinc-mysql container is not running. Run: ./scripts/server_up.sh" >&2
    exit 1
  fi

  task_count="$(calc_task_count)"

  echo "Deploying BOINC app and templates..."
  echo "  PROJECT_NAME=$PROJECT_NAME"
  echo "  APP_NAME=$APP_NAME"
  echo "  APP_VERSION=$APP_VERSION"
  echo "  TASK_COUNT=$task_count"
  echo "  TASK_SECONDS=$TASK_SECONDS"
  echo "  EXPERIMENT_WALL_SECONDS=$EXPERIMENT_WALL_SECONDS"
  echo "  EXPERIMENT_CORES=$EXPERIMENT_CORES"

  docker exec boinc-server bash -lc "mkdir -p '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM' '/project/$PROJECT_NAME/templates' '/project/$PROJECT_NAME/work_inputs'"

  compile_boinc

  docker cp "$TPL_IN" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_in"
  docker cp "$TPL_OUT" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_out"

  echo "Ensuring app is declared in project.xml..."
  docker exec boinc-server bash -lc "
    cd '/project/$PROJECT_NAME'
    if ! grep -q '<name>$APP_NAME</name>' project.xml; then
      python3 - <<'PY'
from pathlib import Path
path = Path('project.xml')
text = path.read_text()
insert = '''
    <app>
        <name>ml_grid_search</name>
        <user_friendly_name>ML grid search</user_friendly_name>
    </app>
'''
text = text.replace('</boinc>', insert + '\n</boinc>')
path.write_text(text)
PY
    fi
  "

  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/xadd"
  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/update_versions --noconfirm"

  echo "Creating many small workunits..."
  run_id="$(date +%s)"

  for task_id in $(seq 1 "$task_count"); do
    lambda="$(lambda_for_task "$task_id")"
    seed=$((TASK_SEED_BASE + task_id))
    task_tag="$(printf '%04d' "$task_id")"
    lambda_tag="${lambda//./p}"
    in_name="grid_${run_id}_${task_tag}_lambda_${lambda_tag}.txt"
    wu_name="grid_${run_id}_${task_tag}_lambda_${lambda_tag}"

    docker exec boinc-server bash -lc "
      cd '/project/$PROJECT_NAME'
      cat > 'work_inputs/$in_name' <<EOT
 task_id=$task_id
 lambda=$lambda
 seed=$seed
 n=$TASK_DATASET_SIZEs
 target_seconds=$TASK_SECONDS
EOT
      ./bin/stage_file_native --copy 'work_inputs/$in_name'
      ./bin/create_work --appname '$APP_NAME' --wu_name '$wu_name' '$in_name'
    "
  done

  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && touch reread_db"

  echo
  echo "Created workunits:"
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" -e "
    SELECT COUNT(*) AS hosts FROM host;
    SELECT COUNT(*) AS workunits FROM workunit;
    SELECT COUNT(*) AS results FROM result;
    SELECT id, name, appid, create_time FROM workunit ORDER BY id DESC LIMIT 10;
  "

  echo
  echo "Watch progress:"
  echo "  ./scripts/status.sh"
  echo "  http://localhost:3000  # Grafana, if monitoring is enabled"
}

case "$MODE" in
  local) run_local ;;
  boinc) run_boinc ;;
  *) echo "Usage: $0 [local|boinc]" >&2; exit 2 ;;
esac
