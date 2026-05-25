#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

cd "$ROOT_DIR"

if [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  echo "ERROR: Do not run this script with sudo."
  echo
  echo "Run as your normal user:"
  echo "  ./scripts/clean_runtime.sh"
  echo
  echo "Reason:"
  echo "  Ansible uses your user's SSH keys to connect to client nodes."
  echo "  If you run this script with sudo, Ansible runs as root and cannot use your SSH keys."
  exit 1
fi

ANSIBLE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ask-vault-pass|--vault)
      ANSIBLE_ARGS+=(--ask-vault-pass)
      shift
      ;;
    --vault-password-file)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --vault-password-file requires a path."
        exit 2
      fi
      ANSIBLE_ARGS+=(--vault-password-file "$2")
      shift 2
      ;;
    --ask-become-pass|-K)
      ANSIBLE_ARGS+=(--ask-become-pass)
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: ./scripts/clean_runtime.sh [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]"
      exit 2
      ;;
  esac
done

if [[ "${#ANSIBLE_ARGS[@]}" -eq 0 && -f "$VAULT_PASS_FILE" ]]; then
  ANSIBLE_ARGS+=(--vault-password-file "$VAULT_PASS_FILE")
fi

echo "Cleaning BOINC runtime data..."
echo

echo "Stopping and cleaning remote BOINC clients..."
if [[ -f "$ROOT_DIR/ansible/inventory.ini" ]] && command -v ansible >/dev/null 2>&1; then
  echo "Refreshing SSH known_hosts for remote clients..."

  awk '
    /^\[/ {next}
    /^[[:space:]]*$/ {next}
    /^[[:space:]]*#/ {next}
    {print $1}
  ' "$ROOT_DIR/ansible/inventory.ini" | while read -r host; do
    if [[ -n "$host" ]]; then
      echo "  removing old SSH host key for $host"
      ssh-keygen -R "$host" >/dev/null 2>&1 || true
    fi
  done

  echo "Cleaning remote BOINC client state..."

  ANSIBLE_HOST_KEY_CHECKING=False \
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a '
    docker rm -f boinc-client 2>/dev/null || true
    rm -rf /opt/boinc-client/data

    systemctl stop boinc-client 2>/dev/null || true
    systemctl disable boinc-client 2>/dev/null || true
    pkill -9 boinc 2>/dev/null || true

    rm -rf /var/lib/boinc-client
    rm -rf /var/lib/boinc
    rm -rf /etc/boinc-client
  ' || true
else
  echo "Skip remote client cleanup: ansible/inventory.ini not found or ansible is not installed."
fi

echo
echo "Stopping monitoring stack..."
if [[ -f "$ROOT_DIR/monitoring/docker-compose.yml" ]]; then
  (
    cd "$ROOT_DIR/monitoring"
    docker compose down -v --remove-orphans || true
  )
fi

echo
echo "Stopping BOINC server stack..."
if [[ -f "$ROOT_DIR/server/docker-compose.yml" ]]; then
  (
    cd "$ROOT_DIR/server"
    docker compose down -v --remove-orphans || true
  )
fi

echo
echo "Removing server runtime directories..."
remove_runtime_dir() {
  local path="$1"

  if [[ -e "$path" ]]; then
    if rm -rf "$path" 2>/dev/null; then
      return 0
    fi

    echo "  Need sudo to remove root-owned path: $path"
    sudo rm -rf "$path"
  fi
}

remove_runtime_dir "$ROOT_DIR/server/project"
remove_runtime_dir "$ROOT_DIR/server/mysql-data"

mkdir -p "$ROOT_DIR/server/project"

echo
echo "Removing dangling BOINC server containers if any..."
docker rm -f boinc-server boinc-mysql 2>/dev/null || true

echo
echo "Removing generated runtime configs..."
rm -f "$ROOT_DIR/config/generated.env"
rm -f "$ROOT_DIR/ansible/inventory.ini"
rm -f "$ROOT_DIR/ansible/group_vars/all.yml"
rm -f "$ROOT_DIR/ansible/group_vars/all/main.yml"
rm -f "$ROOT_DIR/monitoring/.env"

echo
echo "Runtime cleanup completed."
echo
echo "Next steps:"
echo "  ./scripts/init_config.sh"
echo "  ./scripts/server_up.sh"
echo "  ./scripts/create_account_db.sh"
echo "  ./scripts/deploy_clients.sh"