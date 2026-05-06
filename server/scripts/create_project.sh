#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

ENV_FILE="$ROOT_DIR/config/generated.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
  echo "ERROR: boinc-server container is not running. Run: ./scripts/server_up.sh" >&2
  exit 1
fi

if docker exec boinc-server bash -lc "test -d \"/project/$PROJECT_NAME\""; then
  echo "BOINC project already exists: /project/$PROJECT_NAME"
  exit 0
fi

echo "Creating BOINC project: $PROJECT_NAME"

docker exec -i boinc-server bash -lc "yes y | USER=root /opt/boinc/tools/make_project \
  --srcdir /opt/boinc \
  --project_root \"/project/$PROJECT_NAME\" \
  --url_base \"$PROJECT_URL_BASE\" \
  --db_host mysql \
  --db_user root \
  --db_passwd root \
  \"$PROJECT_NAME\""

echo "BOINC project created: /project/$PROJECT_NAME"
