#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Использование:
  ./scripts/bootstrap_server.sh

Скрипт поднимает только локальную серверную часть:
  init_config.sh
  server_up.sh
  create_account_db.sh
  status.sh --server-only

Vault здесь не нужен, потому что удалённые клиенты не управляются.
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  echo "Примечание: bootstrap_server.sh игнорирует аргументы Ansible, потому что выполняет только серверные шаги."
  echo "Для полного запуска используй ./scripts/launch_cluster.sh или ./scripts/bootstrap_clients.sh вручную."
  echo
fi

echo "== Запуск BOINC server =="

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

./scripts/init_config.sh
./scripts/server_up.sh
./scripts/create_account_db.sh
./scripts/status.sh --server-only || true

echo
echo "Серверная часть готова."
echo "Следующий шаг:"
echo "  ./scripts/bootstrap_clients.sh"
