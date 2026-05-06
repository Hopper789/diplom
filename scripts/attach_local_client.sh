#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${BOINC_PROJECT_URL:-}" ]]; then
  echo "ERROR: BOINC_PROJECT_URL is empty in config/generated.env" >&2
  exit 1
fi
if [[ -z "${BOINC_ACCOUNT_KEY:-}" ]]; then
  echo "ERROR: BOINC_ACCOUNT_KEY is empty. Run: ./scripts/create_account.sh" >&2
  exit 1
fi
if [[ -z "${BOINC_CLIENT_RPC_PASSWORD:-}" ]]; then
  echo "ERROR: BOINC_CLIENT_RPC_PASSWORD is empty in config/generated.env" >&2
  exit 1
fi

need_start=0
if ! docker ps -a --format '{{.Names}}' | grep -qx 'boinc-client'; then
  need_start=1
elif ! docker ps --format '{{.Names}}' | grep -qx 'boinc-client'; then
  need_start=1
else
  current_pass="$(docker exec boinc-client bash -lc 'cat /var/lib/boinc/gui_rpc_auth.cfg 2>/dev/null || true' | tr -d '\r\n')"
  if [[ -n "$current_pass" && "$current_pass" != "$BOINC_CLIENT_RPC_PASSWORD" ]]; then
    need_start=1
  fi
fi

if [[ "$need_start" -eq 1 ]]; then
  echo "Starting/restarting local boinc-client via docker compose..."
  docker compose up -d --build
fi

echo "Waiting for BOINC GUI RPC to be ready..."
attempts=30
for ((i=1; i<=attempts; i++)); do
  if docker exec boinc-client boinccmd --passwd "$BOINC_CLIENT_RPC_PASSWORD" --get_cc_status >/dev/null 2>&1; then
    break
  fi
  if [[ "$i" -eq "$attempts" ]]; then
    echo "ERROR: boinccmd cannot connect to local client after $attempts attempts." >&2
    docker logs --tail 50 boinc-client || true
    exit 1
  fi
  sleep 1
done

echo "Attaching local boinc-client to project..."
docker exec boinc-client boinccmd --passwd "$BOINC_CLIENT_RPC_PASSWORD" \
  --project_attach "$BOINC_PROJECT_URL" "$BOINC_ACCOUNT_KEY" || true

echo "Project status:"
docker exec boinc-client boinccmd --passwd "$BOINC_CLIENT_RPC_PASSWORD" --get_project_status || true
