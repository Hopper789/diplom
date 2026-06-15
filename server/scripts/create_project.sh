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

project_dir_exists() {
  docker exec boinc-server bash -lc "test -d \"/project/$PROJECT_NAME\""
}

project_db_exists() {
  docker exec boinc-mariadb \
    mariadb -u root -proot -N -B \
    -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='${PROJECT_NAME}'" \
    2>/dev/null | grep -qx "$PROJECT_NAME"
}

if project_dir_exists && project_db_exists; then
  echo "BOINC project already exists: /project/$PROJECT_NAME"
  exit 0
fi

if project_dir_exists && ! project_db_exists; then
  backup_dir="/project/${PROJECT_NAME}.stale.$(date +%Y%m%d_%H%M%S)"
  echo "WARNING: BOINC project directory exists, but database '$PROJECT_NAME' is missing."
  echo "Moving stale project directory to: $backup_dir"
  docker exec boinc-server bash -lc "mv \"/project/$PROJECT_NAME\" \"$backup_dir\""
fi

echo "Creating BOINC project: $PROJECT_NAME"

quiet_run docker exec -i boinc-server bash -lc "yes y | USER=root /opt/boinc/tools/make_project \
  --srcdir /opt/boinc \
  --project_root \"/project/$PROJECT_NAME\" \
  --url_base \"$PROJECT_URL_BASE\" \
  --db_host mariadb \
  --db_user root \
  --db_passwd root \
  \"$PROJECT_NAME\""

echo "BOINC project created: /project/$PROJECT_NAME"

quiet_run docker exec \
  -e PROJECT_NAME="$PROJECT_NAME" \
  boinc-server bash -lc '
python3 - "/project/${PROJECT_NAME}/config.xml" <<'"'"'PY'"'"'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

def set_tag(body: str, tag: str, value: str) -> str:
    pattern = rf"<{tag}>.*?</{tag}>"
    replacement = f"<{tag}>{value}</{tag}>"
    if re.search(pattern, body, flags=re.S):
        return re.sub(pattern, replacement, body, flags=re.S)
    return body.replace("</config>", f"        {replacement}\n    </config>")

text = set_tag(text, "max_wus_to_send", "1")
text = set_tag(text, "min_sendwork_interval", "1")
path.write_text(text, encoding="utf-8")
PY
'
