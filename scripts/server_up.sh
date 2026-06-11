#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

mkdir -p "$ROOT_DIR/server/project" "$ROOT_DIR/server/mariadb-data"

(
  cd "$ROOT_DIR/server"
  if [[ "${BOINC_SERVER_FORCE_BUILD:-0}" == "1" ]]; then
    compose_run up -d --build
  elif docker image inspect boinc-server-build >/dev/null 2>&1; then
    compose_run up -d
  else
    compose_run up -d --build
  fi
)

step "Waiting for MariaDB..."
attempts=30
for ((i=1; i<=attempts; i++)); do
  if docker exec boinc-mariadb mariadb -u root -proot -e "SELECT 1" >/dev/null 2>&1; then
    step "MariaDB is ready."
    break
  fi
  if [[ "$i" -eq "$attempts" ]]; then
    echo "ERROR: MariaDB is not ready after $attempts attempts." >&2
    exit 1
  fi
  sleep 2
done

step "Creating BOINC project..."
quiet_run_all "$ROOT_DIR/server/scripts/create_project.sh"
step "Updating BOINC project URL..."
quiet_run_all "$ROOT_DIR/server/scripts/fix_project_url.sh"

quiet_run docker restart boinc-server

step "BOINC server is ready."
debug_enabled && echo "$BOINC_PROJECT_URL"
