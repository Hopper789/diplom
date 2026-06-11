#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/config/generated.env}"
ANSIBLE_GROUP_VARS="$ROOT_DIR/ansible/group_vars/all/main.yml"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run:"
  echo "  ./scripts/init_config.sh"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

PROJECT_NAME="${PROJECT_NAME:?PROJECT_NAME is empty}"

EMAIL="${EMAIL:-${BOINC_ACCOUNT_EMAIL:-}}"
USERNAME="${USERNAME:-${BOINC_ACCOUNT_NAME:-}}"
PASSWORD="${PASSWORD:-${BOINC_ACCOUNT_PASSWORD:-}}"

if [[ -z "$EMAIL" ]]; then
  echo "ERROR: EMAIL is empty. Set EMAIL or BOINC_ACCOUNT_EMAIL."
  exit 1
fi

if [[ -z "$USERNAME" ]]; then
  echo "ERROR: USERNAME is empty. Set USERNAME or BOINC_ACCOUNT_NAME."
  exit 1
fi

if [[ -z "$PASSWORD" || "$PASSWORD" == "manual" ]]; then
  PASSWORD="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(18))
PY
)"
  debug_enabled && echo "Generated account password: $PASSWORD"
fi

if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mariadb'; then
  echo "ERROR: boinc-mariadb container is not running."
  echo "Run:"
  echo "  ./scripts/server_up.sh"
  exit 1
fi

sql_escape() {
  python3 - "$1" <<'PY'
import sys
s = sys.argv[1]
s = s.replace("\\", "\\\\").replace("'", "\\'")
print(s)
PY
}

EMAIL_SQL="$(sql_escape "$EMAIL")"
USERNAME_SQL="$(sql_escape "$USERNAME")"

step "Creating or looking up BOINC account..."
debug_enabled && echo "Project:  $PROJECT_NAME"
debug_enabled && echo "Email:    $EMAIL"
debug_enabled && echo "Username: $USERNAME"

EXISTING_ROW="$(
  docker exec boinc-mariadb \
    mariadb -u root -proot "$PROJECT_NAME" -N -B \
    -e "SELECT id, email_addr, name, authenticator FROM user WHERE email_addr='${EMAIL_SQL}' OR name='${USERNAME_SQL}' LIMIT 1;" \
    2>/dev/null || true
)"

if [[ -n "$EXISTING_ROW" ]]; then
  USER_ID="$(echo "$EXISTING_ROW" | awk -F '\t' '{print $1}')"
  FOUND_EMAIL="$(echo "$EXISTING_ROW" | awk -F '\t' '{print $2}')"
  FOUND_NAME="$(echo "$EXISTING_ROW" | awk -F '\t' '{print $3}')"
  ACCOUNT_KEY="$(echo "$EXISTING_ROW" | awk -F '\t' '{print $4}')"

  step "BOINC account exists."
  debug_enabled && echo "User ID: $USER_ID"
  debug_enabled && echo "Email:   $FOUND_EMAIL"
  debug_enabled && echo "Name:    $FOUND_NAME"
else
  step "Creating BOINC account..."

  AUTHENTICATOR="$(
    python3 - "$EMAIL" "$USERNAME" <<'PY'
import hashlib
import secrets
import sys
import time

email = sys.argv[1]
username = sys.argv[2]
raw = f"{email}:{username}:{time.time()}:{secrets.token_hex(32)}"
print(hashlib.md5(raw.encode()).hexdigest())
PY
  )"

  PASSWD_HASH="$(
    python3 - "$EMAIL" "$PASSWORD" <<'PY'
import hashlib
import sys

email = sys.argv[1].lower()
password = sys.argv[2]
print(hashlib.md5((password + email).encode()).hexdigest())
PY
  )"

  AUTHENTICATOR_SQL="$(sql_escape "$AUTHENTICATOR")"
  PASSWD_HASH_SQL="$(sql_escape "$PASSWD_HASH")"

  quiet_run_all docker exec boinc-mariadb \
    mariadb -u root -proot "$PROJECT_NAME" \
    -e "
INSERT INTO user (
  create_time,
  email_addr,
  name,
  authenticator,
  passwd_hash,

  total_credit,
  expavg_credit,
  expavg_time,

  teamid,
  venue,
  country,
  postal_code,
  url,

  send_email,
  show_hosts,
  posts,

  seti_id,
  seti_nresults,
  seti_last_result_time,
  seti_total_cpu,

  has_profile,
  cross_project_id,
  email_validated,
  donated,

  project_prefs
)
VALUES (
  UNIX_TIMESTAMP(),
  '${EMAIL_SQL}',
  '${USERNAME_SQL}',
  '${AUTHENTICATOR_SQL}',
  '${PASSWD_HASH_SQL}',

  0,
  0,
  UNIX_TIMESTAMP(),

  0,
  '',
  'International',
  '',
  '',

  1,
  1,
  0,

  0,
  0,
  0,
  0,

  0,
  '',
  0,
  0,

  ''
);
"

  USER_ID="$(
    docker exec boinc-mariadb \
      mariadb -u root -proot "$PROJECT_NAME" -N -B \
      -e "SELECT id FROM user WHERE email_addr='${EMAIL_SQL}' LIMIT 1;" 2>/dev/null
  )"

  ACCOUNT_KEY="$AUTHENTICATOR"

  step "BOINC account created."
  debug_enabled && echo "User ID: $USER_ID"
fi

debug_enabled && echo
debug_enabled && echo "BOINC_ACCOUNT_KEY:"
debug_enabled && echo "$ACCOUNT_KEY"

step "Writing BOINC account configuration..."
quiet_run_all python3 - "$ENV_FILE" "$ANSIBLE_GROUP_VARS" "$ACCOUNT_KEY" "$PASSWORD" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
vars_path = Path(sys.argv[2])
account_key = sys.argv[3]
account_password = sys.argv[4]

def upsert_env(path: Path, key: str, value: str):
    path.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    if path.exists():
        lines = path.read_text(encoding="utf-8").splitlines(True)

    out = []
    replaced = False

    for line in lines:
        if line.startswith(key + "="):
            out.append(f'{key}="{value}"\n')
            replaced = True
        else:
            out.append(line)

    if not replaced:
        out.append(f'{key}="{value}"\n')

    path.write_text("".join(out), encoding="utf-8")

def upsert_yaml(path: Path, key: str, value: str):
    path.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    if path.exists():
        lines = path.read_text(encoding="utf-8").splitlines(True)

    out = []
    replaced = False

    for line in lines:
        if line.strip().startswith(key + ":"):
            out.append(f'{key}: "{value}"\n')
            replaced = True
        else:
            out.append(line)

    if not replaced:
        out.append(f'{key}: "{value}"\n')

    path.write_text("".join(out), encoding="utf-8")

upsert_env(env_path, "BOINC_ACCOUNT_KEY", account_key)
upsert_env(env_path, "BOINC_ACCOUNT_PASSWORD", account_password)

upsert_yaml(vars_path, "boinc_account_key", account_key)
PY

step "BOINC account configuration updated."
if debug_enabled; then
  echo
  echo "Updated:"
  echo "  $ENV_FILE"
  echo "  $ANSIBLE_GROUP_VARS"
  echo
  echo "Check:"
  echo "  grep BOINC_ACCOUNT_KEY config/generated.env"
  echo "  grep boinc_account_key ansible/group_vars/all/main.yml"
  echo
  echo "Database:"
  echo "  docker exec -it boinc-mariadb mariadb -u root -proot $PROJECT_NAME -e \"SELECT id, email_addr, name, authenticator FROM user;\""
fi
