#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"
DISTRIBUTED_EXAMPLE_FILE="$ROOT_DIR/config/distributed.example.env"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

APP_NAME="${PYTHON_TASK_APP_NAME:-python_task_runner}"
APP_VERSION="${PYTHON_TASK_APP_VERSION:-1.00}"
PLATFORM="${PYTHON_TASK_PLATFORM:-x86_64-pc-linux-gnu}"
BIN_NAME="${APP_NAME}_${APP_VERSION}_${PLATFORM}"

TASK_FILE=""
PARAMS_FILE=""
DEVICE="cpu"
FAIL_ON_ERROR=0

APP_DIR="$ROOT_DIR/apps/python_task_runner"
BUILD_DIR="$APP_DIR/build"
INPUT_DIR="$BUILD_DIR/inputs"
TPL_IN="$BUILD_DIR/${APP_NAME}_in.generated"
TPL_OUT="$APP_DIR/templates/python_task_out"

DISTRIBUTED_TARGET_NRESULTS="${DISTRIBUTED_TARGET_NRESULTS:-1}"
DISTRIBUTED_MIN_QUORUM="${DISTRIBUTED_MIN_QUORUM:-1}"
DISTRIBUTED_MAX_SUCCESS_RESULTS="${DISTRIBUTED_MAX_SUCCESS_RESULTS:-1}"
DISTRIBUTED_MAX_ERROR_RESULTS="${DISTRIBUTED_MAX_ERROR_RESULTS:-3}"
DISTRIBUTED_MAX_TOTAL_RESULTS="${DISTRIBUTED_MAX_TOTAL_RESULTS:-3}"
DISTRIBUTED_DELAY_BOUND="${DISTRIBUTED_DELAY_BOUND:-86400}"
DISTRIBUTED_RSC_MEMORY_BOUND="${DISTRIBUTED_RSC_MEMORY_BOUND:-268435456}"
DISTRIBUTED_RSC_DISK_BOUND="${DISTRIBUTED_RSC_DISK_BOUND:-104857600}"
DISTRIBUTED_RSC_FPOPS_EST="${DISTRIBUTED_RSC_FPOPS_EST:-100000000000.0}"
DISTRIBUTED_RSC_FPOPS_BOUND="${DISTRIBUTED_RSC_FPOPS_BOUND:-10000000000000.0}"

ANSIBLE_EXTRA_ARGS="${ANSIBLE_EXTRA_ARGS:-}"

usage() {
  cat <<'USAGE'
Использование:
  apps/python_task_runner/run_task.sh --task PATH --params PATH [--device cpu|gpu] [--fail-on-error]

Пример:
  apps/python_task_runner/run_task.sh \
    --task apps/python_task_runner/examples/sum_params/user_task.py \
    --params apps/python_task_runner/examples/sum_params/params.jsonl
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      TASK_FILE="${2:-}"
      shift 2
      ;;
    --params)
      PARAMS_FILE="${2:-}"
      shift 2
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --fail-on-error)
      FAIL_ON_ERROR=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Неизвестный аргумент: $1" >&2
      usage
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ -z "$TASK_FILE" || -z "$PARAMS_FILE" ]]; then
  echo "Нужно указать --task и --params." >&2
  usage
  exit 2
fi

if [[ "$DEVICE" != "cpu" && "$DEVICE" != "gpu" ]]; then
  echo "--device должен быть cpu или gpu." >&2
  exit 2
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "Файл задачи не найден: $TASK_FILE" >&2
  exit 1
fi

if [[ ! -f "$PARAMS_FILE" ]]; then
  echo "Файл параметров не найден: $PARAMS_FILE" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Не найден config/generated.env."
  echo "Сначала запусти:"
  echo "  ./scripts/bootstrap_server.sh"
  exit 1
fi

if [[ ! -f "$DISTRIBUTED_ENV_FILE" && -f "$DISTRIBUTED_EXAMPLE_FILE" ]]; then
  echo "Создаётся config/distributed.env из примера."
  cp "$DISTRIBUTED_EXAMPLE_FILE" "$DISTRIBUTED_ENV_FILE"
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
if [[ -f "$DISTRIBUTED_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DISTRIBUTED_ENV_FILE"
fi
set +a

: "${PROJECT_NAME:?PROJECT_NAME пустой}"
: "${BOINC_PROJECT_URL:?BOINC_PROJECT_URL пустой}"
: "${BOINC_CLIENT_RPC_PASSWORD:?BOINC_CLIENT_RPC_PASSWORD пустой}"

if [[ -z "$ANSIBLE_EXTRA_ARGS" && -f "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_EXTRA_ARGS="--vault-password-file $VAULT_PASS_FILE"
fi

mkdir -p "$BUILD_DIR" "$INPUT_DIR"

validate_distributed_config() {
  python3 - <<PY
values = {
    "DISTRIBUTED_TARGET_NRESULTS": "$DISTRIBUTED_TARGET_NRESULTS",
    "DISTRIBUTED_MIN_QUORUM": "$DISTRIBUTED_MIN_QUORUM",
    "DISTRIBUTED_MAX_SUCCESS_RESULTS": "$DISTRIBUTED_MAX_SUCCESS_RESULTS",
    "DISTRIBUTED_MAX_ERROR_RESULTS": "$DISTRIBUTED_MAX_ERROR_RESULTS",
    "DISTRIBUTED_MAX_TOTAL_RESULTS": "$DISTRIBUTED_MAX_TOTAL_RESULTS",
    "DISTRIBUTED_DELAY_BOUND": "$DISTRIBUTED_DELAY_BOUND",
    "DISTRIBUTED_RSC_MEMORY_BOUND": "$DISTRIBUTED_RSC_MEMORY_BOUND",
    "DISTRIBUTED_RSC_DISK_BOUND": "$DISTRIBUTED_RSC_DISK_BOUND",
}

for name, value in values.items():
    parsed = int(value)
    if parsed < 0:
        raise SystemExit(f"{name} должен быть >= 0")

for name, value in {
    "DISTRIBUTED_RSC_FPOPS_EST": "$DISTRIBUTED_RSC_FPOPS_EST",
    "DISTRIBUTED_RSC_FPOPS_BOUND": "$DISTRIBUTED_RSC_FPOPS_BOUND",
}.items():
    parsed = float(value)
    if parsed < 0:
        raise SystemExit(f"{name} должен быть >= 0")

if int("$DISTRIBUTED_MIN_QUORUM") > int("$DISTRIBUTED_TARGET_NRESULTS"):
    raise SystemExit("DISTRIBUTED_MIN_QUORUM должен быть <= DISTRIBUTED_TARGET_NRESULTS")
if int("$DISTRIBUTED_MAX_SUCCESS_RESULTS") < int("$DISTRIBUTED_MIN_QUORUM"):
    raise SystemExit("DISTRIBUTED_MAX_SUCCESS_RESULTS должен быть >= DISTRIBUTED_MIN_QUORUM")
if int("$DISTRIBUTED_MAX_TOTAL_RESULTS") < int("$DISTRIBUTED_TARGET_NRESULTS"):
    raise SystemExit("DISTRIBUTED_MAX_TOTAL_RESULTS должен быть >= DISTRIBUTED_TARGET_NRESULTS")
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
        <open_name>input.json</open_name>
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

ensure_server_running() {
  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
    echo "Контейнер boinc-server не запущен."
    echo "Сначала запусти:"
    echo "  ./scripts/bootstrap_server.sh"
    exit 1
  fi

  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mysql'; then
    echo "Контейнер boinc-mysql не запущен."
    echo "Сначала запусти:"
    echo "  ./scripts/bootstrap_server.sh"
    exit 1
  fi
}

generate_inputs() {
  echo "Генерация input.json-файлов из params.jsonl..."
  python3 "$APP_DIR/generate_inputs.py" \
    --params "$PARAMS_FILE" \
    --out "$INPUT_DIR" \
    --device "$DEVICE"
}

write_launcher() {
  local launcher="$BUILD_DIR/$BIN_NAME"
  local fail_arg=""

  if [[ "$FAIL_ON_ERROR" == "1" ]]; then
    fail_arg=" --fail-on-error"
  fi

  cat > "$launcher" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec python3 "\$SCRIPT_DIR/runner.py" --task "\$SCRIPT_DIR/user_task.py" --input input.json --output output.json$fail_arg
EOF

  chmod +x "$launcher"
}

declare_app_in_project_xml() {
  docker exec boinc-server bash -lc "
    cd '/project/$PROJECT_NAME'
    if ! grep -q '<name>$APP_NAME</name>' project.xml; then
      python3 - <<'PY'
from pathlib import Path

app_name = '$APP_NAME'
friendly_name = 'Python task runner'
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
  echo "Деплой Python task runner в BOINC server..."
  echo "  APP_NAME=$APP_NAME"
  echo "  APP_VERSION=$APP_VERSION"
  echo "  PLATFORM=$PLATFORM"

  generate_input_template
  write_launcher

  docker exec boinc-server bash -lc "
    mkdir -p \
      '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM' \
      '/project/$PROJECT_NAME/templates' \
      '/project/$PROJECT_NAME/work_inputs'
  "

  docker cp "$BUILD_DIR/$BIN_NAME" "boinc-server:/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/$BIN_NAME"
  docker cp "$APP_DIR/runner.py" "boinc-server:/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/runner.py"
  docker cp "$APP_DIR/task_api.py" "boinc-server:/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/task_api.py"
  docker cp "$TASK_FILE" "boinc-server:/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/user_task.py"
  docker cp "$TPL_IN" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_in"
  docker cp "$TPL_OUT" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_out"

  docker exec boinc-server bash -lc "chmod +x '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/$BIN_NAME'"

  declare_app_in_project_xml

  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/xadd"
  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/update_versions --noconfirm"
}

create_workunits() {
  local run_id
  local input_file
  local input_name
  local task_number
  local wu_name

  run_id="$(date +%s)"

  echo "Создание BOINC workunits..."
  for input_file in "$INPUT_DIR"/input_*.json; do
    [[ -e "$input_file" ]] || {
      echo "Не найдены input_*.json в $INPUT_DIR" >&2
      exit 1
    }

    input_name="$(basename "$input_file")"
    task_number="${input_name#input_}"
    task_number="${task_number%.json}"
    wu_name="py_${run_id}_${task_number}"

    docker cp "$input_file" "boinc-server:/project/$PROJECT_NAME/work_inputs/$input_name"
    docker exec boinc-server bash -lc "
      cd '/project/$PROJECT_NAME'
      ./bin/stage_file_native --copy 'work_inputs/$input_name'
      ./bin/create_work --appname '$APP_NAME' --wu_name '$wu_name' '$input_name'
    "
  done

  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && touch reread_db"
}

update_clients() {
  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]] || ! command -v ansible >/dev/null 2>&1; then
    echo "Ansible недоступен или нет inventory; обновление клиентов пропущено."
    return 0
  fi

  echo "Запрос project update на клиентах..."
  # shellcheck disable=SC2086
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b $ANSIBLE_EXTRA_ARGS -m shell -a "
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --project '$BOINC_PROJECT_URL' update
  " || true
}

show_summary() {
  echo
  echo "Краткий статус BOINC server:"
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" -e "
    SELECT COUNT(*) AS workunits FROM workunit;
    SELECT COUNT(*) AS results FROM result;
    SELECT id, name, appid, create_time FROM workunit ORDER BY id DESC LIMIT 10;
  " || true
}

ensure_server_running
generate_inputs
deploy_app_to_server
create_workunits
update_clients
show_summary

echo
echo "Python-задачи отправлены в BOINC."
echo "Проверка:"
echo "  ./scripts/status.sh"
