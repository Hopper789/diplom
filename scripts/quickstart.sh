#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"
VAULT_FILE="$ROOT_DIR/ansible/group_vars/all/vault.yml"

WITH_MONITORING=0
RUN_EXPERIMENT=0

usage() {
  cat <<'USAGE'
Использование:
  ./scripts/quickstart.sh [--with-monitoring] [--run-experiment]

Варианты:
  ./scripts/quickstart.sh
  ./scripts/quickstart.sh --with-monitoring
  ./scripts/quickstart.sh --run-experiment
  ./scripts/quickstart.sh --with-monitoring --run-experiment
USAGE
}

cd "$ROOT_DIR"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-monitoring)
      WITH_MONITORING=1
      shift
      ;;
    --run-experiment)
      RUN_EXPERIMENT=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ ! -f "$ROOT_DIR/config/cluster.yml" ]]; then
  echo "Не найден config/cluster.yml."
  echo
  echo "Создай его перед запуском:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  echo "  nano config/cluster.yml"
  exit 1
fi

if [[ ! -f "$VAULT_PASS_FILE" || ! -f "$VAULT_FILE" ]]; then
  echo "Не найдены файлы Ansible Vault."
  echo
  echo "Создай их перед запуском:"
  echo "  ./scripts/init_vault.sh"
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  if ! docker ps >/dev/null 2>&1; then
    echo "Docker недоступен текущему пользователю."
    echo "Добавьте пользователя в группу docker: sudo usermod -aG docker \"\$USER\", затем перелогиньтесь"
    exit 1
  fi
fi

echo "== Быстрый запуск BOINC-кластера =="
echo

./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh

if [[ "$WITH_MONITORING" == "1" ]]; then
  ./scripts/monitoring_up.sh
fi

if [[ "$RUN_EXPERIMENT" == "1" ]]; then
  ./scripts/run_experiment.sh
fi

./scripts/status.sh

echo
echo "Быстрый запуск завершён."
