#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/config/generated.env}"
ANSIBLE_GROUP_VARS="${ANSIBLE_GROUP_VARS:-$ROOT_DIR/ansible/group_vars/all.yml}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh"
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
  echo "Generated account password: $PASSWORD"
fi

if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mysql'; then
  echo "ERROR: boinc-mysql container is not running."
  echo "Run: ./scripts/server_up.sh"
  exit 1
fi

echo "Creating or looking up BOINC account directly in MariaDB..."
echo "Project:  $PROJECT_NAME"
echo "Email:    $EMAIL"
echo "Username: $USERNAME"

EXISTING_ROW="$(
  docker exec boinc-mysql \
    mariadb -u root -proot "$PROJECT_NAME" -N -B \
    -e "SELECT id, authenticator FROM user WHERE email_addr='${EMAIL}' LIMIT 1;" \
    2>/dev/null || true
)"

if [[ -n "$EXISTING_ROW" ]]; then
  USER_ID="$(echo "$EXISTING_ROW" | awk '{print $1}')"
  ACCOUNT_KEY="$(echo "$EXISTING_ROW" | awk '{print $2}')"
  echo "Account already exists."
  echo "User ID: $USER_ID"
else
  echo "Account does not exist. Creating..."

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

  docker exec boinc-mysql \
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
  '${EMAIL}',
  '${USERNAME}',
  '${AUTHENTICATOR}',
  '${PASSWD_HASH}',

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
    docker exec boinc-mysql \
      mariadb -u root -proot "$PROJECT_NAME" -N -B \
      -e "SELECT id FROM user WHERE email_addr='${EMAIL}' LIMIT 1;"
  )"

  ACCOUNT_KEY="$AUTHENTICATOR"

  echo "Created account."
  echo "User ID: $USER_ID"
fi

echo
echo "BOINC_ACCOUNT_KEY:"
echo "$ACCOUNT_KEY"

python3 - "$ENV_FILE" "$ANSIBLE_GROUP_VARS" "$ACCOUNT_KEY" "$PASSWORD" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
vars_path = Path(sys.argv[2])
key = sys.argv[3]
password = sys.argv[4]

def upsert_env(path: Path, key_name: str, value: str):
    path.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    if path.exists():
        lines = path.read_text(encoding="utf-8").splitlines(True)

    out = []
    replaced = False

    for line in lines:
        if line.startswith(key_name + "="):
            out.append(f'{key_name}="{value}"\n')
            replaced = True
        else:
            out.append(line)

    if not replaced:
        out.append(f'{key_name}="{value}"\n')

    path.write_text("".join(out), encoding="utf-8")

def upsert_yaml_key(path: Path, key_name: str, value: str):
    path.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    if path.exists():
        lines = path.read_text(encoding="utf-8").splitlines(True)

    out = []
    replaced = False

    for line in lines:
        if line.strip().startswith(key_name + ":"):
            out.append(f'{key_name}: "{value}"\n')
            replaced = True
        else:
            out.append(line)

    if not replaced:
        out.append(f'\n{key_name}: "{value}"\n')

    path.write_text("".join(out), encoding="utf-8")

upsert_env(env_path, "BOINC_ACCOUNT_KEY", key)
upsert_env(env_path, "BOINC_ACCOUNT_PASSWORD", password)
upsert_yaml_key(vars_path, "boinc_account_key", key)
PY

echo
echo "Updated:"
echo "  $ENV_FILE"
echo "  $ANSIBLE_GROUP_VARS"

echo
echo "Check:"
echo "  grep BOINC_ACCOUNT_KEY config/generated.env"
echo "  grep boinc_account_key ansible/group_vars/all.yml"
echo
echo "Database:"
echo "  docker exec -it boinc-mysql mariadb -u root -proot $PROJECT_NAME -e \"SELECT id, email_addr, name, authenticator FROM user;\""