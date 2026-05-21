#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found."
  echo "Run: ./scripts/init_config.sh"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

echo "== Docker containers =="
docker ps --filter name=boinc || true
docker ps --filter name=monitoring || true
echo

if docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
  echo "== BOINC server daemons (project: $PROJECT_NAME) =="
  docker exec boinc-server bash -lc "cd \"/project/$PROJECT_NAME\" && ./bin/status" || true
  echo
else
  echo "boinc-server is not running."
  echo
fi

if docker ps --format '{{.Names}}' | grep -qx 'boinc-mysql'; then
  echo "== MariaDB users =="
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" \
    -e "SELECT id, email_addr FROM user;" || true
  echo

  echo "== MariaDB hosts =="
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" \
    -e "SELECT id, userid, domain_name, os_name, create_time FROM host;" || true
  echo

  echo "== MariaDB workunits/results summary =="
  docker exec boinc-mysql mariadb -u root -proot -D "$PROJECT_NAME" \
    -e "SELECT COUNT(*) AS workunits FROM workunit; SELECT COUNT(*) AS results FROM result;" || true
  echo
else
  echo "boinc-mysql is not running."
  echo
fi

if [[ -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  if command -v ansible >/dev/null 2>&1; then
    echo "== Ansible ping boinc_clients =="
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -m ping || true
    echo
  else
    echo "== Ansible ping boinc_clients =="
    echo "ansible is not installed; skip"
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
