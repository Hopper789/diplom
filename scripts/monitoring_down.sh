#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

cd "$ROOT_DIR"

STOP_CLIENT_AGENTS=0

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-client-agents|--agents)
      STOP_CLIENT_AGENTS=1
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./scripts/monitoring_down.sh [--with-client-agents|--agents] [--debug] [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 2
      ;;
  esac
done

if [[ -f "$ROOT_DIR/monitoring/docker-compose.yml" ]]; then
  (
    cd "$ROOT_DIR/monitoring"
    compose_run down -v --remove-orphans
  )
else
  echo "Monitoring compose file not found."
fi

if [[ "$STOP_CLIENT_AGENTS" == "1" ]]; then
  if [[ -f "$ROOT_DIR/ansible/inventory.ini" ]] && command -v ansible >/dev/null 2>&1; then
    echo "Stopping monitoring agents on BOINC clients..."
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a '
      docker rm -f boinc-node-exporter boinc-client-cadvisor boinc-client-promtail 2>/dev/null || true
      rm -rf /opt/boinc-monitoring
    ' || true
  else
    echo "Skip client agent cleanup: ansible/inventory.ini not found or ansible is not installed."
  fi
fi

echo "Monitoring stopped."
