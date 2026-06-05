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

mkdir -p "$ROOT_DIR/server/project" "$ROOT_DIR/server/mysql-data"

(
  cd "$ROOT_DIR/server"
  if [[ "${BOINC_SERVER_FORCE_BUILD:-0}" == "1" ]]; then
    COMPOSE_BAKE=false docker compose up -d --build
  elif docker image inspect boinc-server-build >/dev/null 2>&1; then
    COMPOSE_BAKE=false docker compose up -d
  else
    COMPOSE_BAKE=false docker compose up -d --build
  fi
)

echo "Waiting for MariaDB to be ready..."
attempts=30
for ((i=1; i<=attempts; i++)); do
  if docker exec boinc-mysql mariadb -u root -proot -e "SELECT 1" >/dev/null 2>&1; then
    echo "MariaDB is ready."
    break
  fi
  if [[ "$i" -eq "$attempts" ]]; then
    echo "ERROR: MariaDB is not ready after $attempts attempts." >&2
    exit 1
  fi
  sleep 2
done

"$ROOT_DIR/server/scripts/create_project.sh"
"$ROOT_DIR/server/scripts/fix_project_url.sh"

docker restart boinc-server >/dev/null

echo "BOINC server is ready:"
echo "$BOINC_PROJECT_URL"
