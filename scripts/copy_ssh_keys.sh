#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_FILE="${CLUSTER_FILE:-$ROOT_DIR/config/cluster.yml}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

if [[ ! -f "$CLUSTER_FILE" ]]; then
  echo "ERROR: cluster config not found: $CLUSTER_FILE"
  echo "Create it first:"
  echo "  cp config/cluster.example.yml config/cluster.yml"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required"
  exit 1
fi

if ! python3 - <<'PY' >/dev/null 2>&1
import yaml
PY
then
  echo "ERROR: PyYAML is required"
  echo "Install it with:"
  echo "  sudo apt install -y python3-yaml"
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key not found: $SSH_KEY"
  step "Generating SSH key..."
  quiet_run_all ssh-keygen -t ed25519 -f "$SSH_KEY" -N ""
fi

PUB_KEY="${SSH_KEY}.pub"

if [[ ! -f "$PUB_KEY" ]]; then
  echo "ERROR: public key not found: $PUB_KEY"
  exit 1
fi

if ! command -v ssh-copy-id >/dev/null 2>&1; then
  echo "ERROR: ssh-copy-id is required"
  echo "Install it with:"
  echo "  sudo apt install -y openssh-client"
  exit 1
fi

NODES="$(
python3 - "$CLUSTER_FILE" <<'PY'
import sys
import yaml

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f) or {}

def get_nested(data, *keys, default=None):
    cur = data
    for key in keys:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur

clients = cfg.get("clients") or get_nested(cfg, "cluster", "clients") or []
default_user = (
    get_nested(cfg, "clients_defaults", "username")
    or get_nested(cfg, "clients_defaults", "user")
)
default_port = (
    get_nested(cfg, "clients_defaults", "port")
    or get_nested(cfg, "clients_defaults", "ssh_port")
    or get_nested(cfg, "clients_defaults", "ansible_port")
    or get_nested(cfg, "ssh", "port")
    or cfg.get("ssh_port")
    or cfg.get("default_ssh_port")
)

for client in clients:
    if isinstance(client, str):
        name = ""
        ip = client
        user = default_user
        port = default_port
    elif isinstance(client, dict):
        name = client.get("name", "")
        ip = client.get("ip") or client.get("host") or client.get("hostname") or client.get("ansible_host")
        user = client.get("user") or client.get("username") or client.get("ansible_user") or default_user
        port = client.get("port") or client.get("ssh_port") or client.get("ansible_port") or default_port
    else:
        continue

    if not ip or not user:
        continue

    print(f"{name}|{user}|{ip}|{port or ''}")
PY
)"

if [[ -z "$NODES" ]]; then
  echo "No clients found in $CLUSTER_FILE"
  echo
  echo "Expected format:"
  echo "clients:"
  echo "  - name: laptop"
  echo "    ip: 192.168.1.189"
  echo "    user: hopper"
  echo "    port: 2222"
  exit 1
fi

step "Copying SSH public key to clients..."

while IFS="|" read -r NAME USER IP PORT; do
  [[ -z "$USER" || -z "$IP" ]] && continue

  LABEL="$IP"
  if [[ -n "$NAME" ]]; then
    LABEL="$NAME ($IP)"
  fi
  if [[ -n "$PORT" ]]; then
    LABEL="$LABEL:$PORT"
  fi

  step "Establishing SSH connection..."
  debug_log "==> $LABEL as $USER"

  SSH_COPY_ID_ARGS=(
    -i "$PUB_KEY"
    -o StrictHostKeyChecking=accept-new
  )
  if [[ -n "$PORT" ]]; then
    SSH_COPY_ID_ARGS+=(-p "$PORT")
  fi

  if debug_enabled; then
    ssh-copy-id \
      "${SSH_COPY_ID_ARGS[@]}" \
      "$USER@$IP"
  else
    ssh-copy-id \
      "${SSH_COPY_ID_ARGS[@]}" \
      "$USER@$IP" >/dev/null
  fi
done <<< "$NODES"

step "SSH keys copied."
