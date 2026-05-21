#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLUSTER_YML="$ROOT_DIR/config/cluster.yml"
GENERATED_ENV="$ROOT_DIR/config/generated.env"
ANSIBLE_INVENTORY="$ROOT_DIR/ansible/inventory.ini"
ANSIBLE_GROUP_VARS="$ROOT_DIR/ansible/group_vars/all.yml"

if [[ ! -f "$CLUSTER_YML" ]]; then
  echo "ERROR: config/cluster.yml not found. Create it with:" >&2
  echo "  cp config/cluster.example.yml config/cluster.yml" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/config" "$ROOT_DIR/ansible/group_vars"

python3 - "$CLUSTER_YML" "$GENERATED_ENV" "$ANSIBLE_INVENTORY" "$ANSIBLE_GROUP_VARS" <<'PY'
import os
import re
import secrets
import sys

cluster_yml, generated_env, ansible_inventory, ansible_group_vars = sys.argv[1:5]

try:
    import yaml  # type: ignore
except Exception:
    print("ERROR: PyYAML is required. Install it with: pip install pyyaml", file=sys.stderr)
    raise SystemExit(1)


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def ensure_str(value, path: str) -> str:
    if value is None:
        die(f"Missing required key: {path}")
    if isinstance(value, (int, float)):
        return str(value)
    if not isinstance(value, str):
        die(f"Expected string at {path}, got {type(value).__name__}")
    return value


def load_yaml(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        die("config/cluster.yml must be a YAML mapping/object")
    return data


def read_existing_env(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    env = {}
    line_re = re.compile(r'^([A-Z0-9_]+)=(.*)$')
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            raw = raw.strip()
            if not raw or raw.startswith("#"):
                continue
            m = line_re.match(raw)
            if not m:
                continue
            key, val = m.group(1), m.group(2)
            if len(val) >= 2 and ((val[0] == val[-1] == '"') or (val[0] == val[-1] == "'")):
                val = val[1:-1]
            env[key] = val
    return env


def random_token() -> str:
    # URL-safe, no spaces, good for passwords/keys.
    return secrets.token_urlsafe(24)


cfg = load_yaml(cluster_yml)
existing = read_existing_env(generated_env)

project = cfg.get("project") or {}
server = cfg.get("server") or {}
boinc = cfg.get("boinc") or {}
clients = cfg.get("clients") or []

if not isinstance(project, dict):
    die("project must be a mapping")
if not isinstance(server, dict):
    die("server must be a mapping")
if not isinstance(boinc, dict):
    die("boinc must be a mapping")
if not isinstance(clients, list):
    die("clients must be a list")

project_name = ensure_str(project.get("name"), "project.name")
project_port = ensure_str(project.get("port"), "project.port")

server_ip = ensure_str(server.get("ip"), "server.ip")
server_user = ensure_str(server.get("user"), "server.user")

account_name = ensure_str(boinc.get("account_name"), "boinc.account_name")
rpc_password_cfg = ensure_str(boinc.get("rpc_password"), "boinc.rpc_password")
account_email_cfg = ensure_str(boinc.get("account_email"), "boinc.account_email")
account_password_cfg = ensure_str(boinc.get("account_password"), "boinc.account_password")

project_url_base = f"http://{server_ip}:{project_port}"
boinc_project_url = f"{project_url_base}/{project_name}/"

rpc_password = (
    existing.get("BOINC_CLIENT_RPC_PASSWORD")
    if rpc_password_cfg == "auto"
    else rpc_password_cfg
)
if rpc_password_cfg == "auto" and not rpc_password:
    rpc_password = random_token()

account_password = (
    existing.get("BOINC_ACCOUNT_PASSWORD")
    if account_password_cfg == "auto"
    else account_password_cfg
)
if account_password_cfg == "auto" and not account_password:
    account_password = random_token()

account_email = (
    existing.get("BOINC_ACCOUNT_EMAIL")
    if account_email_cfg == "auto"
    else account_email_cfg
)
if account_email_cfg == "auto" and not account_email:
    account_email = f"{account_name}@mail.ru"

account_key = existing.get("BOINC_ACCOUNT_KEY", "")

lines = [
    f'PROJECT_NAME="{project_name}"',
    f'PROJECT_PORT="{project_port}"',
    f'SERVER_IP="{server_ip}"',
    f'PROJECT_URL_BASE="{project_url_base}"',
    f'BOINC_PROJECT_URL="{boinc_project_url}"',
    "",
    f'BOINC_CLIENT_RPC_PASSWORD="{rpc_password}"',
    f'BOINC_ACCOUNT_EMAIL="{account_email}"',
    f'BOINC_ACCOUNT_PASSWORD="{account_password}"',
    f'BOINC_ACCOUNT_NAME="{account_name}"',
    f'BOINC_ACCOUNT_KEY="{account_key}"',
    "",
]
with open(generated_env, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

inv = []
inv.append("[boinc_server]")
inv.append(f"{server_ip} ansible_user={server_user}")
inv.append("")
inv.append("[boinc_clients]")
for idx, c in enumerate(clients):
    if not isinstance(c, dict):
        die(f"clients[{idx}] must be a mapping")
    ip = ensure_str(c.get("ip"), f"clients[{idx}].ip")
    user = ensure_str(c.get("user"), f"clients[{idx}].user")
    inv.append(f"{ip} ansible_user={user}")
inv.append("")
with open(ansible_inventory, "w", encoding="utf-8") as f:
    f.write("\n".join(inv))

group_vars = [
    f'project_name: "{project_name}"',
    f'project_port: "{project_port}"',
    f'server_ip: "{server_ip}"',
    f'boinc_project_url: "{boinc_project_url}"',
    f'boinc_client_rpc_password: "{rpc_password}"',
    f'boinc_account_key: "{account_key}"',
    "",
]
with open(ansible_group_vars, "w", encoding="utf-8") as f:
    f.write("\n".join(group_vars))

print("Generated:")
print("  config/generated.env")
print("  ansible/inventory.ini")
print("  ansible/group_vars/all.yml")
PY
