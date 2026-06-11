#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

CLUSTER_CONFIG="$ROOT_DIR/config/cluster.yml"
ENV_FILE="$ROOT_DIR/config/generated.env"
ANSIBLE_INVENTORY="$ROOT_DIR/ansible/inventory.ini"
ANSIBLE_GROUP_VARS_DIR="$ROOT_DIR/ansible/group_vars/all"
ANSIBLE_GROUP_VARS="$ANSIBLE_GROUP_VARS_DIR/main.yml"
MONITORING_ENV="$ROOT_DIR/monitoring/.env"

if [[ ! -f "$CLUSTER_CONFIG" ]]; then
  echo "ERROR: config/cluster.yml not found. Create it with:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  echo "  nano config/cluster.yml"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required."
  exit 1
fi

step "Generating configuration files..."
python3 - "$ROOT_DIR" "$CLUSTER_CONFIG" "$ENV_FILE" "$ANSIBLE_INVENTORY" "$ANSIBLE_GROUP_VARS" "$MONITORING_ENV" <<'PY' | quiet_output
import sys
import secrets
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install it with:")
    print("  sudo apt install -y python3-yaml")
    sys.exit(1)

root = Path(sys.argv[1])
cluster_path = Path(sys.argv[2])
env_path = Path(sys.argv[3])
inventory_path = Path(sys.argv[4])
group_vars_path = Path(sys.argv[5])
monitoring_env_path = Path(sys.argv[6])

with cluster_path.open("r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f) or {}

def get_nested(data, *keys, default=None):
    cur = data
    for key in keys:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur

project_name = (
    get_nested(cfg, "project", "name")
    or cfg.get("project_name")
    or "my_project"
)

project_port = str(
    get_nested(cfg, "project", "port")
    or cfg.get("project_port")
    or 8080
)

server_ip = (
    get_nested(cfg, "server", "ip")
    or cfg.get("server_ip")
    or "127.0.0.1"
)

project_url_base = f"http://{server_ip}:{project_port}"
boinc_project_url = f"{project_url_base}/{project_name}/"

account_cfg = cfg.get("account") or cfg.get("boinc_account") or {}

account_email = (
    account_cfg.get("email")
    or cfg.get("boinc_account_email")
    or "nodes@local.test"
)

account_name = (
    account_cfg.get("name")
    or account_cfg.get("username")
    or cfg.get("boinc_account_name")
    or "nodes"
)

account_password = (
    account_cfg.get("password")
    or cfg.get("boinc_account_password")
    or "manual"
)

rpc_password = (
    get_nested(cfg, "boinc", "client_rpc_password")
    or get_nested(cfg, "boinc", "rpc_password")
    or cfg.get("boinc_client_rpc_password")
)

if not rpc_password or str(rpc_password).lower() == "auto":
    rpc_password = secrets.token_urlsafe(24)

clients = cfg.get("clients") or get_nested(cfg, "cluster", "clients") or []
default_client_user = (
    get_nested(cfg, "clients_defaults", "username")
    or get_nested(cfg, "clients_defaults", "user")
)
default_client_port = (
    get_nested(cfg, "clients_defaults", "port")
    or get_nested(cfg, "clients_defaults", "ssh_port")
    or get_nested(cfg, "clients_defaults", "ansible_port")
    or get_nested(cfg, "ssh", "port")
    or cfg.get("ssh_port")
    or cfg.get("default_ssh_port")
)

env_path.parent.mkdir(parents=True, exist_ok=True)
inventory_path.parent.mkdir(parents=True, exist_ok=True)
group_vars_path.parent.mkdir(parents=True, exist_ok=True)
monitoring_env_path.parent.mkdir(parents=True, exist_ok=True)

def quote_env(value: str) -> str:
    value = str(value)
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'

env_text = f"""PROJECT_NAME={quote_env(project_name)}
PROJECT_PORT={quote_env(project_port)}
SERVER_IP={quote_env(server_ip)}
PROJECT_URL_BASE={quote_env(project_url_base)}
BOINC_PROJECT_URL={quote_env(boinc_project_url)}

BOINC_CLIENT_RPC_PASSWORD={quote_env(rpc_password)}
BOINC_ACCOUNT_EMAIL={quote_env(account_email)}
BOINC_ACCOUNT_PASSWORD={quote_env(account_password)}
BOINC_ACCOUNT_NAME={quote_env(account_name)}
BOINC_ACCOUNT_KEY=""
"""

env_path.write_text(env_text, encoding="utf-8")

inventory_lines = ["[boinc_clients]\n"]

for item in clients:
    if isinstance(item, str):
        host = item
        user = default_client_user
        port = default_client_port
    elif isinstance(item, dict):
        host = item.get("ip") or item.get("host") or item.get("hostname") or item.get("ansible_host")
        user = item.get("username") or item.get("user") or item.get("ansible_user") or default_client_user
        port = item.get("port") or item.get("ssh_port") or item.get("ansible_port") or default_client_port
    else:
        continue

    if not host:
        continue

    parts = [str(host)]

    if user:
        parts.append(f"ansible_user={user}")

    if port:
        parts.append(f"ansible_port={port}")

    inventory_lines.append(" ".join(parts) + "\n")

inventory_path.write_text("".join(inventory_lines), encoding="utf-8")

group_vars_text = f"""project_name: "{project_name}"
project_port: "{project_port}"
server_ip: "{server_ip}"
boinc_project_url: "{boinc_project_url}"
boinc_client_rpc_password: "{rpc_password}"
boinc_account_key: ""
"""

group_vars_path.write_text(group_vars_text, encoding="utf-8")

monitoring_env_text = f"""PROJECT_NAME={project_name}
PROJECT_PORT={project_port}
SERVER_IP={server_ip}
PROJECT_URL_BASE={project_url_base}
BOINC_PROJECT_URL={boinc_project_url}
"""

monitoring_env_path.write_text(monitoring_env_text, encoding="utf-8")

print("Generated:")
print(f"  {env_path.relative_to(root)}")
print(f"  {inventory_path.relative_to(root)}")
print(f"  {group_vars_path.relative_to(root)}")
print(f"  {monitoring_env_path.relative_to(root)}")
PY
