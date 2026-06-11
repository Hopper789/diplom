#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

MAX_SECONDS=600
INTERVAL_SECONDS=15
QUIET="${BOINC_PUMP_QUIET:-1}"
SERVER_ONLY=0
VERBOSE=0

usage() {
  cat <<'USAGE'
Использование:
  ./scripts/pump_clients.sh [опции]

Что делает:
  Регулярно просит BOINC-клиенты сделать project update, чтобы они забирали
  следующие порции задач без ручного перезапуска bootstrap_clients.sh.

Опции:
  --max-seconds N          Максимальное время работы. По умолчанию: 600.
  --interval-seconds N     Пауза между update. По умолчанию: 15.
  --quiet                  Меньше вывода.
  --verbose                Показывать вывод Ansible update каждый цикл.
  --server-only            Только печатать DB-прогресс, без Ansible update.
  --ask-vault-pass|--vault Передать Ansible --ask-vault-pass.
  --vault-password-file F  Передать Ansible --vault-password-file.
  --ask-become-pass|-K     Передать Ansible --ask-become-pass.
  --debug                  Показать полный вывод команд.
USAGE
}

cd "$ROOT_DIR"

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"
if debug_enabled; then
  QUIET=0
  VERBOSE=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-seconds)
      MAX_SECONDS="${2:-}"
      shift 2
      ;;
    --interval-seconds)
      INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      QUIET=0
      shift
      ;;
    --server-only)
      SERVER_ONLY=1
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

for pair in "MAX_SECONDS:$MAX_SECONDS" "INTERVAL_SECONDS:$INTERVAL_SECONDS"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
    echo "$name must be a positive integer: $value" >&2
    exit 2
  fi
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found." >&2
  echo "Run first:" >&2
  echo "  ./scripts/bootstrap_server.sh" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mariadb'; then
  echo "boinc-mariadb is not running." >&2
  exit 1
fi

sql_tsv() {
  docker exec boinc-mariadb mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "$1"
}

read_progress() {
  local row
  row="$(sql_tsv "
    SELECT
      COUNT(DISTINCT w.id),
      COUNT(DISTINCT CASE WHEN w.canonical_resultid > 0 THEN w.id END),
      COALESCE(SUM(CASE WHEN r.outcome = 0 THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN r.outcome IN (2, 3, 4, 6) THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN r.outcome = 5 THEN 1 ELSE 0 END), 0),
      COUNT(DISTINCT CASE WHEN r.hostid != 0 AND r.outcome = 0 THEN r.hostid END)
    FROM workunit w
    LEFT JOIN result r ON r.workunitid = w.id;
  ")"

  IFS=$'\t' read -r WORKUNITS COMPLETED UNFINISHED CLIENT_ERRORS REDUNDANT ACTIVE_HOSTS <<< "$row"
  WORKUNITS="${WORKUNITS:-0}"
  COMPLETED="${COMPLETED:-0}"
  UNFINISHED="${UNFINISHED:-0}"
  CLIENT_ERRORS="${CLIENT_ERRORS:-0}"
  REDUNDANT="${REDUNDANT:-0}"
  ACTIVE_HOSTS="${ACTIVE_HOSTS:-0}"
}

refresh_server_queue() {
  if docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
    docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && touch reread_db" >/dev/null 2>&1 || true
  fi
}

request_update() {
  if [[ "$SERVER_ONLY" == "1" ]]; then
    return 0
  fi

  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]] || ! command -v ansible >/dev/null 2>&1; then
    if [[ "$QUIET" != "1" ]]; then
      echo "Ansible недоступен или нет inventory; project update не отправлен."
    fi
    return 0
  fi

  local output
  local rc=0

  set +e
  output="$(
    ANSIBLE_HOST_KEY_CHECKING=False \
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
      docker exec boinc-client sh -lc \"cat > /var/lib/boinc/global_prefs_override.xml <<'EOF'
<global_preferences>
  <run_on_batteries>1</run_on_batteries>
  <run_if_user_active>1</run_if_user_active>
  <run_gpu_if_user_active>0</run_gpu_if_user_active>
  <suspend_cpu_usage>0.000000</suspend_cpu_usage>
  <cpu_usage_limit>100.000000</cpu_usage_limit>
  <max_ncpus_pct>100.000000</max_ncpus_pct>
  <work_buf_min_days>0.000000</work_buf_min_days>
  <work_buf_additional_days>0.000000</work_buf_additional_days>
  <disk_max_used_gb>50.000000</disk_max_used_gb>
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
    " 2>&1
  )"
  rc=$?
  set -e

  if [[ "$VERBOSE" == "1" || ( "$rc" -ne 0 && "${DEBUG:-0}" == "1" ) ]]; then
    echo "$output"
  fi

  if [[ "$rc" -ne 0 ]]; then
    echo "WARNING: Ansible project update failed with rc=$rc." >&2
  fi
}

print_diagnostics() {
  echo
  echo "== Auto-update diagnostics =="
  echo "Клиенты не получили назначенных result: active_hosts=0."
  echo

  if docker ps --format '{{.Names}}' | grep -qx 'boinc-mariadb'; then
    echo "== BOINC DB app/version/result states =="
    docker exec boinc-mariadb mariadb -u root -proot -D "$PROJECT_NAME" -e "
      SELECT id, name, user_friendly_name FROM app;
      SELECT av.id, a.name AS app, av.version_num, p.name AS platform
        FROM app_version av
        JOIN app a ON a.id = av.appid
        JOIN platform p ON p.id = av.platformid
       ORDER BY av.id DESC
       LIMIT 20;
      SELECT server_state, outcome, client_state, hostid, COUNT(*) AS results
        FROM result
       GROUP BY server_state, outcome, client_state, hostid
       ORDER BY hostid, server_state, outcome, client_state;
    " || true
    echo
  fi

  if docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
    echo "== Recent scheduler/feeder logs =="
    docker exec boinc-server bash -lc "
      cd '/project/$PROJECT_NAME'
      tail -80 log_*/scheduler.log log_*/feeder.log 2>/dev/null || true
    " || true
    echo
  fi

  if [[ -f "$ROOT_DIR/ansible/inventory.ini" ]] && command -v ansible >/dev/null 2>&1; then
    echo "== Remote client status/messages =="
    ANSIBLE_HOST_KEY_CHECKING=False \
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
      echo '--- project status ---'
      docker exec boinc-client \
        boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
        --get_project_status || true
      echo '--- task summary ---'
      docker exec boinc-client \
        boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
        --get_task_summary || true
      echo '--- recent messages ---'
      docker exec boinc-client \
        boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
        --get_messages 0 | tail -80 || true
      echo '--- preferences override ---'
      docker exec boinc-client \
        sh -lc 'cat /var/lib/boinc/global_prefs_override.xml 2>/dev/null || true'
    " || true
  fi
}

if [[ "$QUIET" != "1" ]]; then
  echo "== BOINC client auto-update =="
  echo "Max seconds:      $MAX_SECONDS"
  echo "Interval seconds: $INTERVAL_SECONDS"
fi

deadline=$((SECONDS + MAX_SECONDS))
last_completed=-1
unchanged_rounds=0
zero_active_rounds=0

refresh_server_queue

while true; do
  read_progress

  if [[ "$QUIET" != "1" ]]; then
    echo "workunits=$WORKUNITS completed=$COMPLETED unfinished=$UNFINISHED client_errors=$CLIENT_ERRORS redundant=$REDUNDANT active_hosts=$ACTIVE_HOSTS"
  fi

  if [[ "$WORKUNITS" -gt 0 && "$UNFINISHED" -eq 0 ]]; then
    [[ "$QUIET" == "1" ]] || echo "Все текущие result-записи завершены."
    exit 0
  fi

  if [[ "$WORKUNITS" -eq 0 ]]; then
    [[ "$QUIET" == "1" ]] || echo "Workunit'ы ещё не созданы; auto-update не нужен."
    exit 0
  fi

  if [[ "$SECONDS" -ge "$deadline" ]]; then
    [[ "$QUIET" == "1" ]] || echo "Auto-update завершён по таймауту."
    exit 0
  fi

  if [[ "$COMPLETED" == "$last_completed" ]]; then
    unchanged_rounds=$((unchanged_rounds + 1))
  else
    unchanged_rounds=0
    last_completed="$COMPLETED"
  fi

  if [[ "$ACTIVE_HOSTS" -eq 0 ]]; then
    zero_active_rounds=$((zero_active_rounds + 1))
  else
    zero_active_rounds=0
  fi

  refresh_server_queue
  request_update

  if [[ "$zero_active_rounds" -ge 4 ]]; then
    if debug_enabled; then
      print_diagnostics
    else
      echo "BOINC clients did not receive work. Run with --debug for diagnostics." >&2
    fi
    exit 1
  fi

  if [[ "$QUIET" != "1" && "$unchanged_rounds" -ge 4 ]]; then
    echo "Прогресс не менялся несколько циклов; продолжаю делать project update до таймаута."
  fi

  sleep "$INTERVAL_SECONDS"
done
