#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
EXPERIMENT_ENV_FILE="$ROOT_DIR/config/experiment.env"
DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"
MONITORING_DIR="$ROOT_DIR/monitoring"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

cd "$ROOT_DIR"

DEPLOY_CLIENT_AGENTS=1

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-client-agents)
      DEPLOY_CLIENT_AGENTS=0
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./scripts/monitoring_up.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K] [--skip-client-agents]"
      exit 2
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found."
  echo "Run: ./scripts/init_config.sh"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
if [[ -f "$EXPERIMENT_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$EXPERIMENT_ENV_FILE"
fi
if [[ -f "$DISTRIBUTED_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DISTRIBUTED_ENV_FILE"
fi
set +a

if ! docker network inspect server_default >/dev/null 2>&1; then
  echo "ERROR: Docker network server_default not found."
  echo "Run server first:"
  echo "  ./scripts/server_up.sh"
  exit 1
fi

mkdir -p "$MONITORING_DIR"

cat > "$MONITORING_DIR/.env" <<ENVEOF
SERVER_IP=$SERVER_IP
PROJECT_NAME=$PROJECT_NAME
PROJECT_URL=$BOINC_PROJECT_URL
MYSQL_HOST=boinc-mysql
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=root
MYSQL_DATABASE=$PROJECT_NAME
TASK_SECONDS=${TASK_SECONDS:-8}
DISTRIBUTED_TARGET_NRESULTS=${DISTRIBUTED_TARGET_NRESULTS:-1}
DISTRIBUTED_MIN_QUORUM=${DISTRIBUTED_MIN_QUORUM:-1}
DISTRIBUTED_MAX_SUCCESS_RESULTS=${DISTRIBUTED_MAX_SUCCESS_RESULTS:-1}
DISTRIBUTED_MAX_ERROR_RESULTS=${DISTRIBUTED_MAX_ERROR_RESULTS:-3}
DISTRIBUTED_MAX_TOTAL_RESULTS=${DISTRIBUTED_MAX_TOTAL_RESULTS:-3}
ENVEOF

python3 - "$ROOT_DIR" "$MONITORING_DIR/prometheus.yml" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
out_path = Path(sys.argv[2])
inventory = root / "ansible" / "inventory.ini"

hosts = []
inside_group = False

if inventory.exists():
    for raw in inventory.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            inside_group = line == "[boinc_clients]"
            continue
        if not inside_group:
            continue

        parts = line.split()
        if not parts:
            continue

        host = parts[0]
        for part in parts[1:]:
            if part.startswith("ansible_host="):
                host = part.split("=", 1)[1]
                break

        if host and host not in hosts:
            hosts.append(host)

node_targets = [f"{host}:9100" for host in hosts]
cadvisor_targets = [f"{host}:8081" for host in hosts]

def yaml_list(items, indent="          "):
    if not items:
        return indent + "[]\n"
    return "".join(f"{indent}- {item}\n" for item in items)

content = """global:
  scrape_interval: 10s
  evaluation_interval: 10s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - prometheus:9090

  - job_name: boinc
    static_configs:
      - targets:
          - boinc-exporter:9101

  - job_name: cadvisor_server
    static_configs:
      - targets:
          - cadvisor:8080
"""

content += "\n  - job_name: node_exporter_clients\n    static_configs:\n      - targets:\n"
content += yaml_list(node_targets)
content += "\n  - job_name: cadvisor_clients\n    static_configs:\n      - targets:\n"
content += yaml_list(cadvisor_targets)

out_path.write_text(content, encoding="utf-8")

print("Generated Prometheus config:")
print(f"  {out_path.relative_to(root)}")
if hosts:
    print("Client monitoring targets:")
    for host in hosts:
        print(f"  node-exporter: {host}:9100")
        print(f"  cAdvisor:      {host}:8081")
else:
    print("No boinc_clients found in ansible/inventory.ini; only server metrics will be scraped.")
PY

if [[ "$DEPLOY_CLIENT_AGENTS" == "1" && -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  echo
  echo "Refreshing SSH known_hosts for remote clients..."
  awk '
    /^\[/ {next}
    /^[[:space:]]*$/ {next}
    /^[[:space:]]*#/ {next}
    {print $1}
  ' "$ROOT_DIR/ansible/inventory.ini" | while read -r host; do
    if [[ -n "$host" ]]; then
      echo "  removing old SSH host key for $host"
      ssh-keygen -R "$host" >/dev/null 2>&1 || true
    fi
  done

  echo
  echo "Deploying monitoring agents on BOINC clients..."
  ANSIBLE_HOST_KEY_CHECKING=False \
  ./scripts/deploy_monitoring_agents.sh "${ANSIBLE_ARGS[@]}" || true
else
  echo
  echo "Skipping client monitoring agent deployment."
fi

(
  cd "$MONITORING_DIR"
  docker compose up -d --build --force-recreate
)

echo
echo "Monitoring is running:"
echo "  Prometheus: http://$SERVER_IP:9090"
echo "  Grafana:    http://$SERVER_IP:3000"
echo "  Exporter:   http://$SERVER_IP:9101/metrics"
echo "  Loki:       http://$SERVER_IP:3100"
echo
echo "Client agent endpoints are scraped from ansible/inventory.ini:"
echo "  node-exporter: http://CLIENT_IP:9100/metrics"
echo "  cAdvisor:      http://CLIENT_IP:8081/metrics"
echo "  Promtail:      pushes Docker logs to http://$SERVER_IP:3100"
echo
echo "Grafana:"
echo "  Для просмотра dashboard логин не требуется."
echo "  Для администрирования: admin / admin"
echo "  Ошибки и логи: http://$SERVER_IP:3000/d/boinc-errors/boinc-errors"
