#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
DISTRIBUTED_ENV_FILE="$ROOT_DIR/config/distributed.env"
MONITORING_DIR="$ROOT_DIR/monitoring"
BOINC_EXPORTER_BASE_IMAGE="${BOINC_EXPORTER_BASE_IMAGE:-python:3.12-slim}"
MONITORING_OPTIONAL_PULL_TIMEOUT="${MONITORING_OPTIONAL_PULL_TIMEOUT:-30}"

if [[ -z "${BOINC_EXPORTER_IMAGE:-}" ]]; then
  if command -v sha256sum >/dev/null 2>&1; then
    exporter_hash="$(
      (
        cd "$MONITORING_DIR"
        sha256sum Dockerfile requirements.txt boinc_exporter.py
      ) \
        | sha256sum \
        | awk '{print substr($1, 1, 12)}'
    )"
    BOINC_EXPORTER_IMAGE="monitoring-boinc-exporter:$exporter_hash"
  else
    BOINC_EXPORTER_IMAGE="monitoring-boinc-exporter:latest"
  fi
fi

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"
# shellcheck source=scripts/lib/inventory.sh
source "$ROOT_DIR/scripts/lib/inventory.sh"

cd "$ROOT_DIR"

DEPLOY_CLIENT_AGENTS=1
FORCE_RECREATE=0
START_PROMTAIL=1
START_RENDERER=1

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/monitoring_up.sh [options]

Options:
  --skip-client-agents       do not deploy node-exporter/promtail on BOINC clients
  --skip-promtail            do not start local Promtail log collector
  --skip-renderer            do not start Grafana image renderer
  --force-recreate           force Docker Compose to recreate monitoring containers
  --ask-vault-pass, --vault  ask Vault password manually
  --vault-password-file F    use custom Vault password file
  --ask-become-pass, -K      ask sudo password
  --debug                    show full command output
  --help, -h
USAGE
}

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-client-agents)
      DEPLOY_CLIENT_AGENTS=0
      shift
      ;;
    --skip-promtail)
      START_PROMTAIL=0
      shift
      ;;
    --skip-renderer)
      START_RENDERER=0
      shift
      ;;
    --force-recreate)
      FORCE_RECREATE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
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
if [[ -f "$DISTRIBUTED_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$DISTRIBUTED_ENV_FILE"
fi
set +a

if ! docker image inspect "$BOINC_EXPORTER_IMAGE" >/dev/null 2>&1 \
  && docker image inspect monitoring-boinc-exporter:latest >/dev/null 2>&1; then
  BOINC_EXPORTER_IMAGE="monitoring-boinc-exporter:latest"
fi

if ! docker network inspect server_default >/dev/null 2>&1; then
  echo "ERROR: Docker network server_default not found."
  echo "Run server first:"
  echo "  ./scripts/server_up.sh"
  exit 1
fi

mkdir -p "$MONITORING_DIR"

cat > "$MONITORING_DIR/.env" <<ENVEOF
SERVER_IP=$SERVER_IP
BOINC_EXPORTER_IMAGE=$BOINC_EXPORTER_IMAGE
PROJECT_NAME=$PROJECT_NAME
PROJECT_URL=http://boinc-server/$PROJECT_NAME/
MARIADB_HOST=boinc-mariadb
MARIADB_PORT=3306
MARIADB_USER=root
MARIADB_PASSWORD=root
MARIADB_DATABASE=$PROJECT_NAME
TASK_SECONDS=600
DISTRIBUTED_TARGET_NRESULTS=${DISTRIBUTED_TARGET_NRESULTS:-1}
DISTRIBUTED_MIN_QUORUM=${DISTRIBUTED_MIN_QUORUM:-1}
DISTRIBUTED_MAX_SUCCESS_RESULTS=${DISTRIBUTED_MAX_SUCCESS_RESULTS:-1}
DISTRIBUTED_MAX_ERROR_RESULTS=${DISTRIBUTED_MAX_ERROR_RESULTS:-3}
DISTRIBUTED_MAX_TOTAL_RESULTS=${DISTRIBUTED_MAX_TOTAL_RESULTS:-3}
ENVEOF

retry_command() {
  local attempts="$1"
  local delay_seconds="$2"
  shift 2

  local attempt
  for attempt in $(seq 1 "$attempts"); do
    if "$@"; then
      return 0
    fi

    if [[ "$attempt" -lt "$attempts" ]]; then
      debug_log "Command failed, retrying in ${delay_seconds}s ($attempt/$attempts): $*" >&2
      sleep "$delay_seconds"
    fi
  done

  return 1
}

ensure_boinc_exporter_image() {
  if docker image inspect "$BOINC_EXPORTER_IMAGE" >/dev/null 2>&1; then
    step "Checking BOINC exporter image..."
    return 0
  fi

  step "Building BOINC exporter image..."

  pull_cmd=(docker pull "$BOINC_EXPORTER_BASE_IMAGE")
  if ! debug_enabled; then
    pull_cmd=(quiet_run_all docker pull "$BOINC_EXPORTER_BASE_IMAGE")
  fi

  if ! retry_command 5 20 "${pull_cmd[@]}"; then
    echo
    echo "ERROR: failed to pull BOINC exporter base image: $BOINC_EXPORTER_BASE_IMAGE" >&2
    echo "This is usually a network/DNS/proxy problem reaching Docker Hub from the server, not a BOINC code error." >&2
    echo "Retry later, pre-pull the image, or use a cached tag/local registry, for example:" >&2
    echo "  BOINC_EXPORTER_BASE_IMAGE=python:3 ./scripts/monitoring_up.sh" >&2
    echo "  BOINC_EXPORTER_BASE_IMAGE=registry.local/library/python:3.12-slim ./scripts/monitoring_up.sh" >&2
    exit 1
  fi

  if debug_enabled; then
    retry_command 3 20 \
      docker build \
        --build-arg "PYTHON_BASE_IMAGE=$BOINC_EXPORTER_BASE_IMAGE" \
        -t "$BOINC_EXPORTER_IMAGE" \
        "$MONITORING_DIR"
  else
    retry_command 3 20 \
      docker build -q \
        --build-arg "PYTHON_BASE_IMAGE=$BOINC_EXPORTER_BASE_IMAGE" \
        -t "$BOINC_EXPORTER_IMAGE" \
        "$MONITORING_DIR" >/dev/null 2>&1
  fi
}

optional_compose_up() {
  local service="$1"
  local label="$2"

  if [[ "$MONITORING_OPTIONAL_PULL_TIMEOUT" -lt 1 ]]; then
    MONITORING_OPTIONAL_PULL_TIMEOUT=1
  fi

  step "Starting $label..."
  if debug_enabled; then
    if timeout "$MONITORING_OPTIONAL_PULL_TIMEOUT" \
      env COMPOSE_BAKE=false docker compose up -d "$service"; then
      return 0
    fi
  else
    if timeout "$MONITORING_OPTIONAL_PULL_TIMEOUT" \
      env COMPOSE_BAKE=false COMPOSE_PROGRESS=quiet docker compose up -d "$service" >/dev/null 2>&1; then
      return 0
    fi
  fi

  echo "WARNING: $label was not started within ${MONITORING_OPTIONAL_PULL_TIMEOUT}s." >&2
  echo "Monitoring core is still available. To retry with full output:" >&2
  echo "  ./scripts/monitoring_up.sh --debug" >&2
  return 0
}

step "Generating monitoring configuration..."
python3 - "$ROOT_DIR" "$MONITORING_DIR/prometheus.yml" <<'PY' | quiet_output
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

  - job_name: node_exporter_server
    static_configs:
      - targets:
          - node-exporter:9100

"""

content += "\n  - job_name: node_exporter_clients\n    static_configs:\n      - targets:\n"
content += yaml_list(node_targets)

out_path.write_text(content, encoding="utf-8")

print("Generated Prometheus config:")
print(f"  {out_path.relative_to(root)}")
if hosts:
    print("Client monitoring targets:")
    for host in hosts:
        print(f"  node-exporter: {host}:9100")
else:
    print("No boinc_clients found in ansible/inventory.ini; only server metrics will be scraped.")
PY

if [[ "$DEPLOY_CLIENT_AGENTS" == "1" && -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  refresh_client_known_hosts "$ROOT_DIR/ansible/inventory.ini"

  step "Deploying monitoring agents..."
  ANSIBLE_HOST_KEY_CHECKING=False \
  quiet_run_all ./scripts/deploy_monitoring_agents.sh "${ANSIBLE_ARGS[@]}" || true
else
  step "Skipping client monitoring agent deployment."
fi

ensure_boinc_exporter_image

step "Starting monitoring stack..."
(
  cd "$MONITORING_DIR"
  compose_args=(up -d)
  if [[ "$FORCE_RECREATE" == "1" ]]; then
    compose_args+=(--force-recreate)
  fi
  compose_args+=(boinc-exporter node-exporter prometheus loki grafana)
  compose_run "${compose_args[@]}"

  if [[ "$START_PROMTAIL" == "1" ]]; then
    optional_compose_up promtail "Promtail log collector"
  fi

  if [[ "$START_RENDERER" == "1" ]]; then
    optional_compose_up grafana-renderer "Grafana image renderer"
  fi
)

step "Monitoring is running:"
echo "  Prometheus: http://$SERVER_IP:9090"
echo "  Grafana:    http://$SERVER_IP:3000"
echo "  Exporter:   http://$SERVER_IP:9101/metrics"
echo "  Loki:       http://$SERVER_IP:3100"
if docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana-renderer'; then
  echo "  Renderer:   boinc-grafana-renderer"
else
  echo "  Renderer:   not running; PNG panel dumps are unavailable until it starts"
fi
echo "  Server node-exporter: boinc-node-exporter:9100"
echo
echo "Client agent endpoints are scraped from ansible/inventory.ini:"
echo "  node-exporter: http://CLIENT_IP:9100/metrics"
echo "  Promtail:      pushes Docker logs to http://$SERVER_IP:3100"
echo
echo "Grafana:"
echo "  Для просмотра dashboard логин не требуется."
echo "  Для администрирования: admin / admin"
echo "  Ошибки и логи: http://$SERVER_IP:3000/d/boinc-errors/boinc-errors"
