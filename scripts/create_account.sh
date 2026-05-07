#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
ANSIBLE_GROUP_VARS="$ROOT_DIR/ansible/group_vars/all.yml"

FORCE="${FORCE:-0}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh" >&2
  exit 1
fi

if [[ ! -f "$ANSIBLE_GROUP_VARS" ]]; then
  echo "ERROR: ansible/group_vars/all.yml not found. Run: ./scripts/init_config.sh" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${PROJECT_NAME:?ERROR: PROJECT_NAME is empty}"
: "${BOINC_PROJECT_URL:?ERROR: BOINC_PROJECT_URL is empty}"
: "${BOINC_ACCOUNT_EMAIL:?ERROR: BOINC_ACCOUNT_EMAIL is empty}"
: "${BOINC_ACCOUNT_PASSWORD:?ERROR: BOINC_ACCOUNT_PASSWORD is empty}"
: "${BOINC_ACCOUNT_NAME:?ERROR: BOINC_ACCOUNT_NAME is empty}"

if [[ -n "${BOINC_ACCOUNT_KEY:-}" && "$FORCE" != "1" ]]; then
  echo "BOINC_ACCOUNT_KEY already set:"
  echo "$BOINC_ACCOUNT_KEY"
  echo
  echo "Use FORCE=1 ./scripts/create_account.sh to recreate/refresh it."
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required. Install it with: sudo apt install curl" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required." >&2
  exit 1
fi

PROJECT_URL="${BOINC_PROJECT_URL%/}/"
CREATE_ACCOUNT_URL="${PROJECT_URL}create_account.php"

echo "Creating or looking up BOINC account via web RPC..."
echo "Project URL: $PROJECT_URL"
echo "Account URL: $CREATE_ACCOUNT_URL"
echo "Email: $BOINC_ACCOUNT_EMAIL"
echo "Name: $BOINC_ACCOUNT_NAME"

PASSWD_HASH="$(
  python3 - "$BOINC_ACCOUNT_PASSWORD" "$BOINC_ACCOUNT_EMAIL" <<'PY'
import hashlib
import sys

password = sys.argv[1]
email = sys.argv[2].lower()
print(hashlib.md5((password + email).encode("utf-8")).hexdigest())
PY
)"

RESPONSE="$(
  curl -fsS \
    --data-urlencode "email_addr=${BOINC_ACCOUNT_EMAIL}" \
    --data-urlencode "passwd_hash=${PASSWD_HASH}" \
    --data-urlencode "user_name=${BOINC_ACCOUNT_NAME}" \
    "$CREATE_ACCOUNT_URL" || true
)"

echo "$RESPONSE"

ACCOUNT_KEY="$(
  python3 - <<'PY' "$RESPONSE"
import re
import sys
text = sys.argv[1]
m = re.search(r"<authenticator>([^<]+)</authenticator>", text)
if m:
    print(m.group(1).strip())
PY
)"

if [[ -z "$ACCOUNT_KEY" ]]; then
  ERROR_NUM="$(
    python3 - <<'PY' "$RESPONSE"
import re
import sys
text = sys.argv[1]
m = re.search(r"<error_num>([^<]+)</error_num>", text)
if m:
    print(m.group(1).strip())
PY
  )"

  echo
  echo "ERROR: could not get authenticator from create_account.php response."

  if [[ -n "$ERROR_NUM" ]]; then
    echo "BOINC error_num: $ERROR_NUM"
  fi

  echo
  echo "Check that:"
  echo "1. BOINC server is running:"
  echo "   docker ps"
  echo
  echo "2. Project URL is reachable:"
  echo "   curl -I ${PROJECT_URL}"
  echo
  echo "3. BOINC project URL is not localhost for external clients:"
  echo "   grep BOINC_PROJECT_URL config/generated.env"
  echo
  echo "4. Account creation is not disabled in project config."
  exit 1
fi

echo
echo "BOINC account key received:"
echo "$ACCOUNT_KEY"

python3 - "$ENV_FILE" "$ANSIBLE_GROUP_VARS" "$ACCOUNT_KEY" <<'PY'
import sys

env_path, vars_path, key = sys.argv[1:4]

def update_env(path: str) -> None:
    out = []
    replaced = False

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("BOINC_ACCOUNT_KEY="):
                out.append(f'BOINC_ACCOUNT_KEY="{key}"\n')
                replaced = True
            else:
                out.append(line)

    if not replaced:
        out.append(f'\nBOINC_ACCOUNT_KEY="{key}"\n')

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out)

def update_group_vars(path: str) -> None:
    out = []
    replaced = False

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("boinc_account_key:"):
                out.append(f'boinc_account_key: "{key}"\n')
                replaced = True
            else:
                out.append(line)

    if not replaced:
        out.append(f'\nboinc_account_key: "{key}"\n')

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(out)

update_env(env_path)
update_group_vars(vars_path)
PY

echo
echo "Updated:"
echo "  config/generated.env"
echo "  ansible/group_vars/all.yml"

echo
echo "Check:"
echo "  grep BOINC_ACCOUNT_KEY config/generated.env"
echo "  grep boinc_account_key ansible/group_vars/all.yml"