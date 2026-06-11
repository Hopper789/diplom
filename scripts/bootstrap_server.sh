#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

cd "$ROOT_DIR"
SKIP_STATUS=0

usage() {
  cat <<'USAGE'
Использование:
  ./scripts/bootstrap_server.sh [--skip-status]

Скрипт поднимает только локальную серверную часть:
  init_config.sh
  server_up.sh
  create_account_db.sh
  status.sh --server-only

Vault здесь не нужен, потому что удалённые клиенты не управляются.
Добавь --debug, чтобы видеть полный вывод команд.
USAGE
}

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-status)
      SKIP_STATUS=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Примечание: bootstrap_server.sh игнорирует аргумент: $1"
      shift
      ;;
  esac
done

step "Starting BOINC server..."

if [[ ! -f config/cluster.yml ]]; then
  echo "Не найден config/cluster.yml."
  echo "Создай его перед запуском:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  echo "  nano config/cluster.yml"
  exit 1
fi

chmod +x scripts/*.sh 2>/dev/null || true
chmod +x apps/ml_grid_search/run_task.sh 2>/dev/null || true
chmod +x server/entrypoint.sh 2>/dev/null || true
chmod +x server/scripts/*.sh 2>/dev/null || true

step "Generating configuration..."
quiet_run_all ./scripts/init_config.sh
step "Starting server containers..."
quiet_run_all ./scripts/server_up.sh
step "Creating BOINC account..."
quiet_run_all ./scripts/create_account_db.sh

if [[ "$SKIP_STATUS" != "1" ]]; then
  step "Checking server status..."
  quiet_run_all ./scripts/status.sh --server-only || true
fi

echo
step "Серверная часть готова."
echo "Следующий шаг:"
echo "  ./scripts/bootstrap_clients.sh"
