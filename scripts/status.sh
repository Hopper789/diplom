#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

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

ANSIBLE_EXTRA_ARGS="${ANSIBLE_EXTRA_ARGS:-}"

echo "== Docker containers on server =="
docker ps --filter name=boinc || true
docker ps --filter name=monitoring || true
echo

if docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
  echo "== BOINC server daemons (project: $PROJECT_NAME) =="
  docker exec boinc-server bash -lc "cd '/project/$PROJECT_NAME' && ./bin/status" || true
  echo
else
  echo "boinc-server is not running."
  echo
fi

if docker ps --format '{{.Names}}' | grep -qx 'boinc-mysql'; then
  echo "== MariaDB users =="
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" \
    -e "SELECT id, email_addr, name, authenticator FROM user;" || true
  echo

  echo "== MariaDB hosts =="
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" \
    -e "SELECT id, userid, domain_name, os_name, create_time FROM host;" || true
  echo

  echo "== MariaDB workunits/results summary =="
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" \
    -e "
      SELECT COUNT(*) AS workunits FROM workunit;
      SELECT COUNT(*) AS results FROM result;
      SELECT id, name, appid, create_time FROM workunit ORDER BY id DESC LIMIT 10;
      SELECT id, workunitid, server_state, outcome, client_state, hostid FROM result ORDER BY id DESC LIMIT 10;
    " || true
  echo
else
  echo "boinc-mysql is not running."
  echo
fi

if [[ -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  if command -v ansible >/dev/null 2>&1; then
    echo "== Ansible ping boinc_clients =="
    # shellcheck disable=SC2086
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients $ANSIBLE_EXTRA_ARGS -m ping || true
    echo

    echo "== Docker BOINC clients on remote nodes =="
    # shellcheck disable=SC2086
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b $ANSIBLE_EXTRA_ARGS -m shell -a "
      docker ps --filter name=boinc-client
    " || true
    echo

    echo "== Remote BOINC client project status =="
    # shellcheck disable=SC2086
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b $ANSIBLE_EXTRA_ARGS -m shell -a "
      docker exec boinc-client \
        boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
        --get_project_status
    " || true
    echo

    echo "== Remote BOINC client task summary =="
    # shellcheck disable=SC2086
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b $ANSIBLE_EXTRA_ARGS -m shell -a "
      docker exec boinc-client \
        boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
        --get_task_summary
    " || true
    echo
  else
    echo "ansible is not installed; skip remote client checks."
    echo
  fi
fi

echo "== Monitoring =="
if docker ps --format '{{.Names}}' | grep -qx 'boinc-prometheus'; then
  echo "Prometheus: http://localhost:9090"
else
  echo "Prometheus is not running."
fi

if docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana'; then
  echo "Grafana:    http://localhost:3000"
  echo "Login:      admin / admin"
else
  echo "Grafana is not running."
fi

if docker ps --format '{{.Names}}' | grep -qx 'boinc-exporter'; then
  echo "Exporter:   http://localhost:9101/metrics"
else
  echo "BOINC exporter is not running."
fi