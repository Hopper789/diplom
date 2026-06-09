#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

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

quiet_run docker exec \
  -e PROJECT_NAME="$PROJECT_NAME" \
  -e PROJECT_URL_BASE="$PROJECT_URL_BASE" \
  boinc-server bash -lc '
set -euo pipefail

PROJECT_DIR="/project/${PROJECT_NAME}"

FILES=(
  "${PROJECT_DIR}/html/user/schedulers.txt"
  "${PROJECT_DIR}/config.xml"
  "${PROJECT_DIR}/project.xml"
  "${PROJECT_DIR}/gui_urls.xml"
)

# Replace common/known host variants + any IPv4:PORT with PROJECT_URL_BASE.
URL_REGEX="http://(localhost|172\\.17\\.0\\.1|host\\.docker\\.internal|([0-9]{1,3}\\.){3}[0-9]{1,3})(:[0-9]+)?"

for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then
    sed -E -i "s#${URL_REGEX}#${PROJECT_URL_BASE}#g" "$f"
  fi
done

apachectl graceful || apachectl restart || true

echo "Current URLs (after replacement):"
EXISTING_FILES=()
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] && EXISTING_FILES+=("$f")
done
if (( ${#EXISTING_FILES[@]} > 0 )); then
  grep -R -n "http://" "${EXISTING_FILES[@]}" || true
fi
'
