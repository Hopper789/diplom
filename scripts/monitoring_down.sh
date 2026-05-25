#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

cd "$ROOT_DIR"

ANSIBLE_ARGS=()
STOP_CLIENT_AGENTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-client-agents|--agents)
      STOP_CLIENT_AGENTS=1
      shift
      ;;
    --ask-vault-pass|--vault)
      ANSIBLE_ARGS+=(--ask-vault-pass)
      shift
      ;;
    --vault-password-file)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --vault-password-file requires a path."
        exit 2
      fi
      ANSIBLE_ARGS+=(--vault-password-file "$2")
      shift 2
      ;;
    --ask-become-pass|-K)
      ANSIBLE_ARGS+=(--ask-become-pass)
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./scripts/monitoring_down.sh [--with-client-agents|--agents] [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 2
      ;;
  esac
done

if [[ "${#ANSIBLE_ARGS[@]}" -eq 0 && -f "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_ARGS+=(--vault-password-file "$VAULT_PASS_FILE")
fi

if [[ -f "$ROOT_DIR/monitoring/docker-compose.yml" ]]; then
  (
    cd "$ROOT_DIR/monitoring"
    docker compose down -v --remove-orphans
  )
else
  echo "Monitoring compose file not found."
fi

if [[ "$STOP_CLIENT_AGENTS" == "1" ]]; then
  if [[ -f "$ROOT_DIR/ansible/inventory.ini" ]] && command -v ansible >/dev/null 2>&1; then
    echo "Stopping monitoring agents on BOINC clients..."
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a '
      docker rm -f boinc-node-exporter boinc-client-cadvisor 2>/dev/null || true
      rm -rf /opt/boinc-monitoring
    ' || true
  else
    echo "Skip client agent cleanup: ansible/inventory.ini not found or ansible is not installed."
  fi
fi

echo "Monitoring stopped."
