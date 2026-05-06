#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

APP_NAME="ml_grid_search"
APP_VERSION="1.03"
PLATFORM="x86_64-pc-linux-gnu"
BIN_NAME="${APP_NAME}_${APP_VERSION}_${PLATFORM}"

SRC_CPP="$ROOT_DIR/apps/ml_grid_search/ml_grid_search.cpp"
TPL_IN="$ROOT_DIR/apps/ml_grid_search/templates/ml_grid_search_in"
TPL_OUT="$ROOT_DIR/apps/ml_grid_search/templates/ml_grid_search_out"
BUILD_DIR="$ROOT_DIR/apps/ml_grid_search/build"

MODE="${1:-boinc}"

mkdir -p "$BUILD_DIR"

compile() {
  echo "Building $BIN_NAME..."
  g++ -O2 -std=c++17 -o "$BUILD_DIR/$BIN_NAME" "$SRC_CPP"
}

compile_boinc() {
  echo "Building $BIN_NAME inside boinc-server (with BOINC API)..."
  docker cp "$SRC_CPP" "boinc-server:/tmp/${APP_NAME}.cpp"
  docker exec boinc-server bash -lc "g++ -O2 -std=c++17 \
    -I/opt/boinc -I/opt/boinc/api -I/opt/boinc/lib \
    -L/opt/boinc/api -L/opt/boinc/lib \
    -o \"/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/$BIN_NAME\" /tmp/${APP_NAME}.cpp \
    -lboinc_api -lboinc -pthread"
}

run_local() {
  compile
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  best_lambda=""
  best_mse=""

  for lambda in 0 0.01 0.1 1 10; do
    cat >"$tmpdir/in" <<EOF
lambda=$lambda
seed=42
n=50
EOF
    "$BUILD_DIR/$BIN_NAME" "$tmpdir/in" "$tmpdir/out" >/dev/null 2>&1 || true
    mse="$(python3 - <<PY
import json
print(json.load(open("$tmpdir/out"))["mse"])
PY
)"
    echo "lambda=$lambda mse=$mse"
    if [[ -z "$best_mse" ]]; then
      best_mse="$mse"
      best_lambda="$lambda"
      continue
    fi
    if python3 - <<PY
import sys
sys.exit(0 if float("$mse") < float("$best_mse") else 1)
PY
    then
      best_mse="$mse"
      best_lambda="$lambda"
    fi
  done

  echo "Best: lambda=$best_lambda mse=$best_mse"
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
  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-client'; then
    echo "ERROR: boinc-client container is not running. Run: docker compose up -d --build" >&2
    exit 1
  fi

  echo "Deploying app + templates into BOINC project..."
  docker exec boinc-server bash -lc "mkdir -p \"/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM\" \"/project/$PROJECT_NAME/templates\" \"/project/$PROJECT_NAME/work_inputs\""
  compile_boinc

  docker cp "$TPL_IN" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_in"
  docker cp "$TPL_OUT" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_out"

  # Ensure the app is declared in project.xml (so bin/xadd can add it to DB)
  docker exec boinc-server bash -lc "cd \"/project/$PROJECT_NAME\" && if ! grep -q \"<name>${APP_NAME}</name>\" project.xml; then sed -i \"s#</boinc>#    <app>\\\\n        <name>${APP_NAME}</name>\\\\n        <user_friendly_name>ML grid search</user_friendly_name>\\\\n    </app>\\\\n</boinc>#\" project.xml; fi"

  docker exec boinc-server bash -lc "cd \"/project/$PROJECT_NAME\" && ./bin/xadd"
  docker exec boinc-server bash -lc "cd \"/project/$PROJECT_NAME\" && ./bin/update_versions --noconfirm"

  echo "Creating workunits..."
  # Make a small grid; each WU evaluates one lambda value.
  run_id="$(date +%s)"
  for lambda in 0 0.01 0.1 1 10; do
    lambda_tag="${lambda//./p}"
    in_name="grid_lambda_${lambda_tag}_${run_id}.txt"
    docker exec boinc-server bash -lc "cd \"/project/$PROJECT_NAME\" && printf 'lambda=%s\\nseed=42\\nn=50\\n' \"$lambda\" > \"work_inputs/$in_name\""
    docker exec boinc-server bash -lc "cd \"/project/$PROJECT_NAME\" && ./bin/stage_file_native --copy \"work_inputs/$in_name\""
    docker exec boinc-server bash -lc "cd \"/project/$PROJECT_NAME\" && ./bin/create_work --appname \"$APP_NAME\" --wu_name \"grid_${lambda_tag}_${run_id}\" \"$in_name\""
  done

  docker exec boinc-server bash -lc "cd \"/project/$PROJECT_NAME\" && touch reread_db"

  echo "Triggering client update..."
  docker exec boinc-client boinccmd --passwd "$BOINC_CLIENT_RPC_PASSWORD" --project "$BOINC_PROJECT_URL" update || true

  echo "Client task summary:"
  docker exec boinc-client boinccmd --passwd "$BOINC_CLIENT_RPC_PASSWORD" --get_task_summary || true

  echo "Server-side host/workunit counts:"
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" -e "SELECT COUNT(*) AS hosts FROM host; SELECT COUNT(*) AS wus FROM workunit; SELECT COUNT(*) AS results FROM result;" || true
}

case "$MODE" in
  local)
    run_local
    ;;
  boinc)
    run_boinc
    ;;
  *)
    echo "Usage: $0 [local|boinc]" >&2
    exit 2
    ;;
esac
