#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"
DISTRIBUTED_EXAMPLE_FILE="$ROOT_DIR/config/distributed.example.env"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

APP_NAME="${PYTHON_TASK_APP_NAME:-python_task_runner}"
APP_VERSION="${PYTHON_TASK_APP_VERSION:-}"
APP_FRIENDLY_NAME="${PYTHON_TASK_APP_FRIENDLY_NAME:-Python task runner}"
PLATFORM="${PYTHON_TASK_PLATFORM:-x86_64-pc-linux-gnu}"
APP_VERSION_NUM=""
BIN_NAME=""

TASK_FILE=""
PARAMS_FILE=""
DEVICE="cpu"
FAIL_ON_ERROR=0

APP_DIR="$ROOT_DIR/apps/python_task_runner"
BUILD_DIR="$APP_DIR/build"
INPUT_DIR="$BUILD_DIR/inputs"
TPL_IN="$BUILD_DIR/${APP_NAME}_in.generated"
TPL_OUT="$APP_DIR/templates/python_task_out"
VERSION_XML="$BUILD_DIR/version.xml"

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

version_to_num() {
  python3 - "$1" <<'PY'
import decimal
import sys

value = decimal.Decimal(sys.argv[1])
if value <= 0:
    raise SystemExit("Версия приложения должна быть положительным числом")

print(int(value * 100))
PY
}

format_version_num() {
  python3 - "$1" <<'PY'
import sys

value = int(sys.argv[1])
if value < 1:
    value = 100

print(f"{value // 100}.{value % 100:02d}")
PY
}

resolve_app_version() {
  if [[ -n "$APP_VERSION" ]]; then
    APP_VERSION_NUM="$(version_to_num "$APP_VERSION")"
  else
    local next_version_num
    next_version_num="$(
      docker exec boinc-mysql mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "
        SELECT COALESCE(MAX(av.version_num), 99) + 1
          FROM app_version av
          JOIN app a ON a.id = av.appid
          JOIN platform p ON p.id = av.platformid
         WHERE a.name = '$APP_NAME'
           AND p.name = '$PLATFORM';
      " 2>/dev/null | tail -1
    )"

    if ! [[ "$next_version_num" =~ ^[0-9]+$ ]]; then
      next_version_num=100
    fi

    APP_VERSION="$(format_version_num "$next_version_num")"
    APP_VERSION_NUM="$next_version_num"
  fi

  BIN_NAME="${APP_NAME}_${APP_VERSION}_${PLATFORM}"
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
set -uo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"

resolve_output_files() {
  if [[ ! -f init_data.xml ]]; then
    return 1
  fi

  python3 - <<'PY'
from pathlib import Path
import re

path = Path("init_data.xml")
if not path.exists():
    raise SystemExit(1)

text = path.read_text(encoding="utf-8", errors="replace")
seen = set()

for block in re.findall(r"<file_ref>.*?</file_ref>", text, flags=re.S):
    open_name = re.search(r"<open_name>(.*?)</open_name>", block, flags=re.S)
    file_name = re.search(r"<file_name>(.*?)</file_name>", block, flags=re.S)

    if not open_name or not file_name:
        continue
    if open_name.group(1).strip() != "output.json":
        continue

    name = file_name.group(1).strip()
    if name and name != "output.json" and name not in seen:
        seen.add(name)
        print(name)
PY
}

copy_output_to_boinc_files() {
  if [[ ! -f output.json ]]; then
    echo "ERROR: runner exited successfully but output.json is missing" >&2
    return 1
  fi

  local copied=0
  local boinc_output
  while IFS= read -r boinc_output; do
    [[ -n "\$boinc_output" ]] || continue
    if [[ "\$boinc_output" != "output.json" ]]; then
      cp output.json "\$boinc_output"
      copied=1
    fi
  done < <(resolve_output_files || true)

  if [[ "\$copied" -eq 0 ]]; then
    echo "ERROR: no BOINC physical output filename found in init_data.xml" >&2
    return 1
  fi
}

python3 "\$SCRIPT_DIR/runner.py" --task "\$SCRIPT_DIR/user_task.py" --input input.json --output output.json$fail_arg
status="\$?"
if [[ "\$status" -eq 0 ]]; then
  if copy_output_to_boinc_files; then
    printf '0\n' > boinc_finish_called
  else
    status=1
  fi
fi
exit "\$status"
EOF

  chmod +x "$launcher"
}

write_version_xml() {
  cat > "$VERSION_XML" <<EOF
<version>
  <file>
    <physical_name>$BIN_NAME</physical_name>
    <main_program/>
  </file>
  <file>
    <physical_name>runner.py</physical_name>
  </file>
  <file>
    <physical_name>task_api.py</physical_name>
  </file>
  <file>
    <physical_name>user_task.py</physical_name>
  </file>
</version>
EOF
}

declare_app_in_project_xml() {
  docker exec boinc-server bash -lc "
    cd '/project/$PROJECT_NAME'
    if ! grep -q '<name>$APP_NAME</name>' project.xml; then
      python3 - <<'PY'
from pathlib import Path

app_name = '$APP_NAME'
friendly_name = '$APP_FRIENDLY_NAME'
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
  write_version_xml

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
  docker cp "$VERSION_XML" "boinc-server:/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/version.xml"
  docker cp "$TPL_IN" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_in"
  docker cp "$TPL_OUT" "boinc-server:/project/$PROJECT_NAME/templates/${APP_NAME}_out"

  docker exec boinc-server bash -lc "
    chmod +x '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/$BIN_NAME'
    chmod 0644 \
      '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/runner.py' \
      '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/task_api.py' \
      '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/user_task.py' \
      '/project/$PROJECT_NAME/apps/$APP_NAME/$APP_VERSION/$PLATFORM/version.xml'
  "

  declare_app_in_project_xml

  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/xadd"
  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/update_versions --noconfirm"
}

assert_app_version_registered() {
  local registered

  registered="$(
    docker exec boinc-mysql mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "
      SELECT COUNT(*)
        FROM app_version av
        JOIN app a ON a.id = av.appid
        JOIN platform p ON p.id = av.platformid
       WHERE a.name = '$APP_NAME'
         AND p.name = '$PLATFORM'
         AND av.version_num = $APP_VERSION_NUM;
    " 2>/dev/null | tail -1
  )"

  if [[ "${registered:-0}" -lt 1 ]]; then
    echo "BOINC не зарегистрировал app_version для $APP_NAME $APP_VERSION $PLATFORM." >&2
    echo "Workunit'ы не создаются, потому что клиенты не смогут получить задачи." >&2
    exit 1
  fi
}

create_workunits() {
  local run_id
  local input_file
  local input_name
  local task_number
  local wu_name

  run_id="${PYTHON_TASK_RUN_ID:-$(date +%s)_$$}"

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

restart_project_daemons() {
  echo "Перезапуск BOINC daemons, чтобы сервер перечитал очередь задач..."
  docker exec boinc-server bash -lc "
    cd '/project/$PROJECT_NAME'
    ./bin/stop || true
    sleep 2
    ./bin/start || true
    touch reread_db
  "
}

update_clients() {
  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]] || ! command -v ansible >/dev/null 2>&1; then
    echo "Ansible недоступен или нет inventory; обновление клиентов пропущено."
    return 0
  fi

  echo "Запрос project update на клиентах..."
  # shellcheck disable=SC2086
  ANSIBLE_HOST_KEY_CHECKING=False \
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b $ANSIBLE_EXTRA_ARGS -m shell -a "
    docker exec boinc-client sh -lc \"cat > /var/lib/boinc/global_prefs_override.xml <<'EOF'
<global_preferences>
  <run_on_batteries>1</run_on_batteries>
  <run_if_user_active>1</run_if_user_active>
  <run_gpu_if_user_active>0</run_gpu_if_user_active>
  <suspend_cpu_usage>0.000000</suspend_cpu_usage>
  <cpu_usage_limit>100.000000</cpu_usage_limit>
  <max_ncpus_pct>100.000000</max_ncpus_pct>
  <work_buf_min_days>0.010000</work_buf_min_days>
  <work_buf_additional_days>0.010000</work_buf_additional_days>
  <disk_max_used_gb>20.000000</disk_max_used_gb>
  <disk_interval>60.000000</disk_interval>
</global_preferences>
EOF\"
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --read_global_prefs_override || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --set_run_mode always || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --set_network_mode always || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --project '$BOINC_PROJECT_URL' allowmorework || true
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
resolve_app_version
generate_inputs
deploy_app_to_server
assert_app_version_registered
create_workunits
restart_project_daemons
update_clients
sleep 10
update_clients
show_summary

echo
echo "Python-задачи отправлены в BOINC."
echo "Проверка:"
echo "  ./scripts/status.sh"
