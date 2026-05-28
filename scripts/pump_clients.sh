#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

MAX_SECONDS=600
INTERVAL_SECONDS=15
QUIET=0
SERVER_ONLY=0
ANSIBLE_ARGS=()

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
  --server-only            Только печатать DB-прогресс, без Ansible update.
  --ask-vault-pass|--vault Передать Ansible --ask-vault-pass.
  --vault-password-file F  Передать Ansible --vault-password-file.
  --ask-become-pass|-K     Передать Ansible --ask-become-pass.
USAGE
}

cd "$ROOT_DIR"

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
    --server-only)
      SERVER_ONLY=1
      shift
      ;;
    --ask-vault-pass|--vault)
      ANSIBLE_ARGS+=(--ask-vault-pass)
      shift
      ;;
    --vault-password-file)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --vault-password-file requires a path." >&2
        exit 2
      fi
      ANSIBLE_ARGS+=(--vault-password-file "$2")
      shift 2
      ;;
    --ask-become-pass|-K)
      ANSIBLE_ARGS+=(--ask-become-pass)
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

if [[ "${#ANSIBLE_ARGS[@]}" -eq 0 && -f "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_ARGS+=(--vault-password-file "$VAULT_PASS_FILE")
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mysql'; then
  echo "boinc-mysql is not running." >&2
  exit 1
fi

sql_tsv() {
  docker exec boinc-mysql mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "$1"
}

read_progress() {
  local row
  row="$(sql_tsv "
    SELECT
      COUNT(DISTINCT w.id),
      COUNT(DISTINCT CASE WHEN r.outcome = 1 THEN w.id END),
      SUM(CASE WHEN r.outcome = 0 THEN 1 ELSE 0 END),
      SUM(CASE WHEN r.outcome NOT IN (0, 1) THEN 1 ELSE 0 END),
      COUNT(DISTINCT CASE WHEN r.hostid != 0 THEN r.hostid END)
    FROM workunit w
    LEFT JOIN result r ON r.workunitid = w.id;
  ")"

  IFS=$'\t' read -r WORKUNITS COMPLETED UNFINISHED ERRORS ACTIVE_HOSTS <<< "$row"
  WORKUNITS="${WORKUNITS:-0}"
  COMPLETED="${COMPLETED:-0}"
  UNFINISHED="${UNFINISHED:-0}"
  ERRORS="${ERRORS:-0}"
  ACTIVE_HOSTS="${ACTIVE_HOSTS:-0}"
}

request_update() {
  if [[ "$SERVER_ONLY" == "1" ]]; then
    return 0
  fi

  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]] || ! command -v ansible >/dev/null 2>&1; then
    return 0
  fi

  ANSIBLE_HOST_KEY_CHECKING=False \
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --read_global_prefs_override || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --set_run_mode always || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --project '$BOINC_PROJECT_URL' update
  " >/dev/null 2>&1 || true
}

if [[ "$QUIET" != "1" ]]; then
  echo "== BOINC client auto-update =="
  echo "Max seconds:      $MAX_SECONDS"
  echo "Interval seconds: $INTERVAL_SECONDS"
fi

deadline=$((SECONDS + MAX_SECONDS))
last_completed=-1
unchanged_rounds=0

while true; do
  read_progress

  if [[ "$QUIET" != "1" ]]; then
    echo "workunits=$WORKUNITS completed=$COMPLETED unfinished=$UNFINISHED errors=$ERRORS active_hosts=$ACTIVE_HOSTS"
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

  request_update

  if [[ "$QUIET" != "1" && "$unchanged_rounds" -ge 4 ]]; then
    echo "Прогресс не менялся несколько циклов; продолжаю делать project update до таймаута."
  fi

  sleep "$INTERVAL_SECONDS"
done
