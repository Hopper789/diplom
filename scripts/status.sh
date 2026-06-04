#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

SERVER_ONLY=0

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-only)
      SERVER_ONLY=1
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./scripts/status.sh [--server-only] [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 2
      ;;
  esac
done

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

MONITORING_HOST="${SERVER_IP:-localhost}"

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
      SELECT
        outcome,
        CASE outcome
          WHEN 0 THEN 'unfinished'
          WHEN 1 THEN 'success'
          WHEN 2 THEN 'couldnt_send'
          WHEN 3 THEN 'client_error'
          WHEN 4 THEN 'no_reply'
          WHEN 5 THEN 'didnt_need'
          WHEN 6 THEN 'validate_error'
          ELSE 'other'
        END AS outcome_name,
        COUNT(*) AS results
      FROM result
      GROUP BY outcome
      ORDER BY outcome;
      SELECT
        id,
        workunitid,
        outcome,
        client_state,
        hostid,
        LEFT(REPLACE(REPLACE(COALESCE(stderr_out, ''), '\n', ' '), '\r', ' '), 500) AS stderr_preview
      FROM result
      WHERE outcome IN (2, 3, 4, 6) OR LENGTH(COALESCE(stderr_out, '')) > 0
      ORDER BY id DESC
      LIMIT 10;
    " || true
  echo
else
  echo "boinc-mysql is not running."
  echo
fi

if [[ "$SERVER_ONLY" == "1" ]]; then
  echo "Skip remote client checks because --server-only is enabled."
  echo
  exit 0
fi

if [[ -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  if command -v ansible >/dev/null 2>&1; then
    echo "== Ansible ping boinc_clients =="
    ANSIBLE_HOST_KEY_CHECKING=False \
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients "${ANSIBLE_ARGS[@]}" -m ping || true
    echo

    echo "== Docker BOINC clients on remote nodes =="
    ANSIBLE_HOST_KEY_CHECKING=False \
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
      docker ps --filter name=boinc-client
    " || true
    echo

    echo "== Remote BOINC client project status =="
    ANSIBLE_HOST_KEY_CHECKING=False \
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
      docker exec boinc-client \
        boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
        --get_project_status
    " || true
    echo

    echo "== Remote BOINC client task summary =="
    ANSIBLE_HOST_KEY_CHECKING=False \
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
      docker exec boinc-client \
        boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
        --get_task_summary
    " || true
    echo

    echo "== Remote monitoring agents =="
    ANSIBLE_HOST_KEY_CHECKING=False \
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
      docker ps --filter name=boinc-node-exporter --filter name=boinc-client-cadvisor --filter name=boinc-client-promtail
    " || true
    echo
  else
    echo "ansible is not installed; skip remote client checks."
    echo
  fi
else
  echo "ansible/inventory.ini not found; skip remote client checks."
  echo
fi

echo "== Monitoring =="
if docker ps --format '{{.Names}}' | grep -qx 'boinc-prometheus'; then
  echo "Prometheus: http://$MONITORING_HOST:9090"
else
  echo "Prometheus is not running."
fi

if docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana'; then
  echo "Grafana:    http://$MONITORING_HOST:3000"
  echo "Dashboard:  http://$MONITORING_HOST:3000/d/boinc-cluster/boinc-cluster"
  echo "View:       без логина"
  echo "Admin:      admin / admin"
else
  echo "Grafana is not running."
fi

if docker ps --format '{{.Names}}' | grep -qx 'boinc-exporter'; then
  echo "Exporter:   http://$MONITORING_HOST:9101/metrics"
else
  echo "BOINC exporter is not running."
fi

if docker ps --format '{{.Names}}' | grep -qx 'boinc-loki'; then
  echo "Loki:       http://$MONITORING_HOST:3100"
else
  echo "Loki is not running."
fi

if docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana-renderer'; then
  echo "Renderer:   boinc-grafana-renderer is running"
else
  echo "Grafana renderer is not running."
fi

if command -v curl >/dev/null 2>&1; then
  echo
  echo "== Monitoring data checks =="
  if docker ps --format '{{.Names}}' | grep -qx 'boinc-exporter'; then
    if curl -fsS "http://$MONITORING_HOST:9101/metrics" | grep -q '^boinc_db_up'; then
      echo "Exporter metrics: OK"
    else
      echo "Exporter metrics: no boinc_db_up metric"
    fi
  fi

  if docker ps --format '{{.Names}}' | grep -qx 'boinc-prometheus'; then
    if curl -fsS "http://$MONITORING_HOST:9090/api/v1/query?query=boinc_db_up" | grep -q '"status":"success"'; then
      echo "Prometheus query boinc_db_up: OK"
    else
      echo "Prometheus query boinc_db_up: failed"
    fi

    echo "Prometheus targets:"
    curl -fsS "http://$MONITORING_HOST:9090/api/v1/targets?state=active" \
      | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except Exception:
    print("  unable to parse targets response")
    raise SystemExit(0)

for target in payload.get("data", {}).get("activeTargets", []):
    labels = target.get("labels", {})
    job = labels.get("job", "?")
    instance = labels.get("instance", target.get("scrapeUrl", "?"))
    health = target.get("health", "?")
    error = target.get("lastError") or ""
    suffix = f" - {error}" if error else ""
    print(f"  {job} {instance}: {health}{suffix}")
' || true
  fi

  if docker ps --format '{{.Names}}' | grep -qx 'boinc-loki'; then
    if curl -fsS "http://$MONITORING_HOST:3100/ready" | grep -qi 'ready'; then
      echo "Loki ready: OK"
    else
      echo "Loki ready: failed"
    fi
  fi

  if docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana'; then
    if curl -fsS "http://$MONITORING_HOST:3000/api/health" | grep -q '"database":'; then
      echo "Grafana health: OK"
    else
      echo "Grafana health: failed"
    fi

    if curl -fsS -u admin:admin "http://$MONITORING_HOST:3000/api/datasources/uid/prometheus" | grep -q '"uid":"prometheus"'; then
      echo "Grafana datasource prometheus: OK"
    else
      echo "Grafana datasource prometheus: missing"
    fi

    if curl -fsS -u admin:admin "http://$MONITORING_HOST:3000/api/datasources/uid/loki" | grep -q '"uid":"loki"'; then
      echo "Grafana datasource loki: OK"
    else
      echo "Grafana datasource loki: missing"
    fi

    if curl -fsS -u admin:admin "http://$MONITORING_HOST:3000/api/dashboards/uid/boinc-cluster" | grep -q '"uid":"boinc-cluster"'; then
      echo "Grafana dashboard boinc-cluster: OK"
    else
      echo "Grafana dashboard boinc-cluster: missing"
    fi

    if curl -fsS -u admin:admin "http://$MONITORING_HOST:3000/api/dashboards/uid/boinc-errors" | grep -q '"uid":"boinc-errors"'; then
      echo "Grafana dashboard boinc-errors: OK"
    else
      echo "Grafana dashboard boinc-errors: missing"
    fi

    if curl -fsS -u admin:admin \
      "http://$MONITORING_HOST:3000/api/datasources/proxy/uid/prometheus/api/v1/query?query=boinc_db_up" \
      | grep -q '"status":"success"'; then
      echo "Grafana datasource query boinc_db_up: OK"
    else
      echo "Grafana datasource query boinc_db_up: failed"
    fi

    if curl -fsS -u admin:admin \
      "http://$MONITORING_HOST:3000/api/datasources/proxy/uid/loki/loki/api/v1/labels" \
      | grep -q '"status":"success"'; then
      echo "Grafana datasource query loki labels: OK"
    else
      echo "Grafana datasource query loki labels: failed"
    fi

    if docker exec boinc-grafana sh -lc \
      'wget -qO- "http://prometheus:9090/api/v1/query?query=boinc_db_up" | grep -q "\"status\":\"success\""' \
      >/dev/null 2>&1; then
      echo "Grafana container -> Prometheus: OK"
    else
      echo "Grafana container -> Prometheus: failed"
    fi

    if docker exec boinc-grafana sh -lc \
      'wget -qO- "http://loki:3100/ready" | grep -qi "ready"' \
      >/dev/null 2>&1; then
      echo "Grafana container -> Loki: OK"
    else
      echo "Grafana container -> Loki: failed"
    fi

  fi
fi
