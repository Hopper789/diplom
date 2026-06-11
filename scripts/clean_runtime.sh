#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

SERVER_ONLY=0
CLIENTS_ONLY=0
PURGE_CLIENTS=0

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/clean_runtime.sh [options]

Default:
  clean server runtime and reset BOINC tasks on clients, keeping boinc-client installed.

Options:
  --server-only              clean only server and monitoring runtime
  --clients-only             clean only client BOINC tasks
  --purge-clients            fully remove boinc-client from client nodes
  --remove-clients           alias for --purge-clients
  --ask-vault-pass, --vault  ask Vault password manually
  --vault-password-file F    use custom Vault password file
  --ask-become-pass, -K      ask sudo password
  --debug                    show full command output
  --help, -h
USAGE
}

check_not_sudo() {
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
}

remove_runtime_dir() {
  local path="$1"

  if [[ -e "$path" ]]; then
    if rm -rf "$path" 2>/dev/null; then
      return 0
    fi

    echo "  Removing root-owned runtime path with sudo: $path"
    quiet_run_all sudo rm -rf "$path"
  fi
}

load_generated_env() {
  if [[ -f "$ROOT_DIR/config/generated.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/config/generated.env"
    set +a
  fi
}

clean_server_runtime() {
  step "Stopping monitoring stack..."
  if [[ -f "$ROOT_DIR/monitoring/docker-compose.yml" ]]; then
    (
      cd "$ROOT_DIR/monitoring"
      compose_run down -v --remove-orphans || true
    )
  fi

  step "Stopping BOINC server stack..."
  if [[ -f "$ROOT_DIR/server/docker-compose.yml" ]]; then
    (
      cd "$ROOT_DIR/server"
      compose_run down -v --remove-orphans || true
    )
  fi

  step "Removing server runtime directories..."
  remove_runtime_dir "$ROOT_DIR/server/project"
  remove_runtime_dir "$ROOT_DIR/server/mariadb-data"
  remove_runtime_dir "$ROOT_DIR/server/mysql-data"

  mkdir -p "$ROOT_DIR/server/project"

  step "Removing dangling BOINC server containers..."
  quiet_run_all docker rm -f boinc-server boinc-mariadb boinc-mysql || true
}

remove_generated_runtime_configs() {
  step "Removing generated runtime configs..."
  rm -f "$ROOT_DIR/config/generated.env"
  rm -f "$ROOT_DIR/ansible/inventory.ini"
  rm -f "$ROOT_DIR/ansible/group_vars/all/main.yml"
  rm -f "$ROOT_DIR/monitoring/.env"
}

ensure_remote_cleanup_possible() {
  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]] || ! command -v ansible >/dev/null 2>&1; then
    echo "Skip remote client cleanup: ansible/inventory.ini not found or ansible is not installed."
    return 1
  fi

  return 0
}

reset_client_tasks() {
  step "Resetting BOINC project tasks on remote clients..."

  if ! ensure_remote_cleanup_possible; then
    return 0
  fi

  if [[ -z "${BOINC_PROJECT_URL:-}" ]]; then
    echo "WARNING: BOINC_PROJECT_URL is not available; client task reset skipped."
    echo "         Run ./scripts/init_config.sh first if you need client reset only."
    return 0
  fi

  local project_url_q
  local rpc_password_q
  project_url_q="$(printf "%q" "${BOINC_PROJECT_URL:-}")"
  rpc_password_q="$(printf "%q" "${BOINC_CLIENT_RPC_PASSWORD:-}")"

  ANSIBLE_HOST_KEY_CHECKING=False \
    quiet_run_all ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
      BOINC_PROJECT_URL=$project_url_q
      BOINC_CLIENT_RPC_PASSWORD=$rpc_password_q
      export BOINC_PROJECT_URL BOINC_CLIENT_RPC_PASSWORD

      if docker ps --quiet --filter 'name=^/boinc-client$' | grep -q .; then
        docker exec \
          -e BOINC_PROJECT_URL \
          -e BOINC_CLIENT_RPC_PASSWORD \
          boinc-client \
          sh -lc '
            cd /var/lib/boinc 2>/dev/null || true

            if [ -n \"\$BOINC_CLIENT_RPC_PASSWORD\" ]; then
              boinccmd --passwd \"\$BOINC_CLIENT_RPC_PASSWORD\" --project \"\$BOINC_PROJECT_URL\" reset
              rc=\$?
            else
              boinccmd --project \"\$BOINC_PROJECT_URL\" reset
              rc=\$?
            fi

            if [ \"\$rc\" -ne 0 ]; then
              echo \"WARNING: BOINC project reset failed; client installation was kept.\"
            fi

            exit 0
          '
      else
        echo 'WARNING: boinc-client container is not running; client installation was kept.'
      fi
    " || true
}

purge_remote_clients() {
  step "Fully removing remote BOINC clients..."

  if ! ensure_remote_cleanup_possible; then
    return 0
  fi

  ANSIBLE_HOST_KEY_CHECKING=False \
    quiet_run_all ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a '
      docker rm -f boinc-client 2>/dev/null || true
      rm -rf /opt/boinc-client/data

      systemctl stop boinc-client 2>/dev/null || true
      systemctl disable boinc-client 2>/dev/null || true
      pkill -9 boinc 2>/dev/null || true

      rm -rf /var/lib/boinc-client
      rm -rf /var/lib/boinc
      rm -rf /etc/boinc-client
    ' || true
}

cd "$ROOT_DIR"

check_not_sudo

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-only)
      SERVER_ONLY=1
      shift
      ;;
    --clients-only)
      CLIENTS_ONLY=1
      shift
      ;;
    --purge-clients|--remove-clients)
      PURGE_CLIENTS=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$SERVER_ONLY" == "1" && "$CLIENTS_ONLY" == "1" ]]; then
  echo "ERROR: --server-only and --clients-only cannot be used together." >&2
  exit 2
fi

load_generated_env

step "Cleaning BOINC runtime data..."

if [[ "$CLIENTS_ONLY" != "1" ]]; then
  clean_server_runtime
fi

if [[ "$SERVER_ONLY" != "1" ]]; then
  if [[ "$PURGE_CLIENTS" == "1" ]]; then
    purge_remote_clients
  else
    reset_client_tasks
  fi
fi

if [[ "$CLIENTS_ONLY" != "1" ]]; then
  remove_generated_runtime_configs
fi

echo
step "Runtime cleanup completed."
echo
echo "Next steps:"
echo "  ./scripts/prepare_system.sh"
echo "  ./scripts/launch_cluster.sh"
