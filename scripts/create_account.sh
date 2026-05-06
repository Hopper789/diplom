#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"
ANSIBLE_GROUP_VARS="$ROOT_DIR/ansible/group_vars/all.yml"

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

if [[ -n "${BOINC_ACCOUNT_KEY:-}" ]]; then
  echo "BOINC_ACCOUNT_KEY already set."
  exit 0
fi

if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mysql'; then
  echo "ERROR: boinc-mysql container is not running. Run: ./scripts/server_up.sh" >&2
  exit 1
fi

db_exists="$(
  docker exec boinc-mysql mariadb -u root -proot -N -B \
    -e "SHOW DATABASES LIKE '${PROJECT_NAME}';" 2>/dev/null || true
)"
if [[ -z "$db_exists" ]]; then
  echo "ERROR: MariaDB database '${PROJECT_NAME}' not found. Ensure the project is created (./scripts/server_up.sh)." >&2
  exit 1
fi

echo "Looking up BOINC account key in MariaDB for: $BOINC_ACCOUNT_EMAIL"

authenticator="$(
  docker exec boinc-mysql mariadb -u root -proot -N -B -D "$PROJECT_NAME" \
    -e "SELECT authenticator FROM user WHERE email_addr='${BOINC_ACCOUNT_EMAIL}' LIMIT 1;" 2>/dev/null || true
)"

if [[ -z "$authenticator" ]]; then
  echo "Account not found."
  echo "Open $BOINC_PROJECT_URL and create user:"
  echo "email: $BOINC_ACCOUNT_EMAIL"
  echo "password: $BOINC_ACCOUNT_PASSWORD"
  echo "Then run scripts/create_account.sh again."
  exit 0
fi

python3 - "$ENV_FILE" "$ANSIBLE_GROUP_VARS" "$authenticator" <<'PY'
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

def update_vars(path: str) -> None:
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
update_vars(vars_path)
PY

echo "BOINC_ACCOUNT_KEY updated in:"
echo "  config/generated.env"
echo "  ansible/group_vars/all.yml"
