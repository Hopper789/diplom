#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
ANSIBLE_GROUP_VARS="$ROOT_DIR/ansible/group_vars/all.yml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found. Run: ./scripts/init_config.sh"
  exit 1
fi

if [[ ! -f "$ANSIBLE_GROUP_VARS" ]]; then
  echo "ERROR: ansible/group_vars/all.yml not found. Run: ./scripts/init_config.sh"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${PROJECT_NAME:?PROJECT_NAME is empty}"
: "${BOINC_PROJECT_URL:?BOINC_PROJECT_URL is empty}"
: "${BOINC_ACCOUNT_EMAIL:?BOINC_ACCOUNT_EMAIL is empty}"

echo "Looking for BOINC account in database..."
echo "Project: $PROJECT_NAME"
echo "Email:   $BOINC_ACCOUNT_EMAIL"

if ! docker ps --format '{{.Names}}' | grep -q '^boinc-mysql$'; then
  echo "ERROR: boinc-mysql container is not running."
  echo "Run: ./scripts/server_up.sh"
  exit 1
fi

ACCOUNT_KEY="$(
  docker exec boinc-mysql \
    mariadb -u root -proot "$PROJECT_NAME" -N -B \
    -e "SELECT authenticator FROM user WHERE email_addr='${BOINC_ACCOUNT_EMAIL}' LIMIT 1;" \
    2>/dev/null || true
)"

if [[ -z "$ACCOUNT_KEY" ]]; then
  echo
  echo "Account was not found in BOINC database."
  echo
  echo "Open the BOINC website and create user manually:"
  echo "  $BOINC_PROJECT_URL"
  echo
  echo "Use these values:"
  echo "  email: ${BOINC_ACCOUNT_EMAIL}"
  echo "  name:  ${BOINC_ACCOUNT_NAME:-nodes}"
  echo
  echo "After creating the user, run again:"
  echo "  ./scripts/create_account.sh"
  echo
  exit 1
fi

echo "Found BOINC_ACCOUNT_KEY:"
echo "$ACCOUNT_KEY"

python3 - "$ENV_FILE" "$ANSIBLE_GROUP_VARS" "$ACCOUNT_KEY" <<'PY'
import sys

env_path, vars_path, key = sys.argv[1:4]

def update_env(path):
    lines = []
    replaced = False

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith("BOINC_ACCOUNT_KEY="):
                lines.append(f'BOINC_ACCOUNT_KEY="{key}"\n')
                replaced = True
            else:
                lines.append(line)

    if not replaced:
        lines.append(f'\nBOINC_ACCOUNT_KEY="{key}"\n')

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)

def update_group_vars(path):
    lines = []
    replaced = False

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("boinc_account_key:"):
                lines.append(f'boinc_account_key: "{key}"\n')
                replaced = True
            else:
                lines.append(line)

    if not replaced:
        lines.append(f'\nboinc_account_key: "{key}"\n')

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)

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