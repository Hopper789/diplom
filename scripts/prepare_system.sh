#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

CLUSTER_CONFIG="$ROOT_DIR/config/cluster.yml"
CLUSTER_EXAMPLE="$ROOT_DIR/config/cluster.example.yml"
VAULT_FILE="$ROOT_DIR/ansible/group_vars/all/vault.yml"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

INSTALL_LOCAL=0
COPY_SSH_KEYS=0
USER_ANSIBLE_ARGS=()
MISSING_DEPS=()

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/prepare_system.sh [options]

Options:
  --install-local           install local control-machine dependencies
  --copy-ssh-keys           copy the current user's SSH public key to clients
  --ask-vault-pass, --vault ask Vault password manually
  --vault-password-file F   use custom Vault password file
  --ask-become-pass, -K     ask sudo password
  --help, -h
USAGE
}

check_not_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo "ERROR: Do not run this script with sudo."
    echo "Run as your normal user."
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-local)
        INSTALL_LOCAL=1
        shift
        ;;
      --copy-ssh-keys)
        COPY_SSH_KEYS=1
        shift
        ;;
      --ask-vault-pass|--vault)
        USER_ANSIBLE_ARGS+=("$1")
        shift
        ;;
      --vault-password-file)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --vault-password-file requires a path." >&2
          exit 2
        fi
        USER_ANSIBLE_ARGS+=("$1" "$2")
        shift 2
        ;;
      --ask-become-pass|-K)
        USER_ANSIBLE_ARGS+=("$1")
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
}

check_cluster_config() {
  if [[ -f "$CLUSTER_CONFIG" ]]; then
    return 0
  fi

  if [[ -f "$CLUSTER_EXAMPLE" ]]; then
    cp "$CLUSTER_EXAMPLE" "$CLUSTER_CONFIG"
    echo "Created config/cluster.yml from config/cluster.example.yml."
    echo "Edit it before continuing:"
    echo "  nano config/cluster.yml"
    exit 1
  fi

  echo "ERROR: config/cluster.yml not found."
  echo "Create it before continuing:"
  echo "  nano config/cluster.yml"
  exit 1
}

add_missing_cmd() {
  local cmd="$1"
  local label="$2"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING_DEPS+=("$label")
  fi
}

check_local_dependencies() {
  MISSING_DEPS=()

  add_missing_cmd bash bash
  add_missing_cmd python3 python3
  add_missing_cmd ansible ansible
  add_missing_cmd ansible-vault ansible-vault
  add_missing_cmd ssh ssh
  add_missing_cmd ssh-keygen ssh-keygen
  add_missing_cmd docker docker

  if command -v python3 >/dev/null 2>&1; then
    if ! python3 - <<'PY' >/dev/null 2>&1
import yaml
PY
    then
      MISSING_DEPS+=("python3-yaml or PyYAML")
    fi

    if ! python3 - <<'PY' >/dev/null 2>&1
import numpy
import numba
PY
    then
      MISSING_DEPS+=("numpy and numba Python packages")
    fi
  fi

  if command -v docker >/dev/null 2>&1; then
    if ! docker compose version >/dev/null 2>&1; then
      MISSING_DEPS+=("docker compose")
    fi
    if ! docker ps >/dev/null 2>&1; then
      MISSING_DEPS+=("docker access for current user")
    fi
  fi

  if ! command -v mysql >/dev/null 2>&1 && ! command -v mariadb >/dev/null 2>&1; then
    MISSING_DEPS+=("mysql client or mariadb client")
  fi
}

print_missing_dependencies() {
  echo "Missing local dependencies:"
  for dep in "${MISSING_DEPS[@]}"; do
    echo "  - $dep"
  done
  echo
  echo "Install them with:"
  echo "  ./scripts/prepare_system.sh --install-local"
  echo
  echo "If Docker is installed but not accessible, add your user to the docker group and log in again:"
  echo "  sudo usermod -aG docker \"\$USER\""
}

ensure_local_dependencies() {
  if [[ "$INSTALL_LOCAL" == "1" ]]; then
    ./scripts/install_server_requirements.sh
  fi

  check_local_dependencies
  if [[ "${#MISSING_DEPS[@]}" -gt 0 ]]; then
    print_missing_dependencies
    exit 1
  fi
}

ensure_vault() {
  if [[ -f "$VAULT_FILE" && -f "$VAULT_PASS_FILE" ]]; then
    echo "Vault exists; keeping current files."
    return 0
  fi

  echo "Initializing Ansible Vault..."
  ./scripts/init_vault.sh
}

ensure_ssh_key() {
  if [[ -f "$HOME/.ssh/id_ed25519" ]]; then
    echo "SSH key found: ~/.ssh/id_ed25519"
    return 0
  fi

  if [[ -f "$HOME/.ssh/id_rsa" ]]; then
    echo "SSH key found: ~/.ssh/id_rsa"
    return 0
  fi

  echo "SSH key not found; generating ~/.ssh/id_ed25519..."
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N ""
}

ansible_ping_clients() {
  ANSIBLE_HOST_KEY_CHECKING=False \
    ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients "${ANSIBLE_ARGS[@]}" -m ping
}

print_ssh_failed() {
  echo "SSH access to client nodes failed."
  echo
  echo "Try:"
  echo "  ./scripts/prepare_system.sh --copy-ssh-keys"
  echo
  echo "Or check manually:"
  echo "  ssh USER@CLIENT_IP"
}

check_ssh_access() {
  echo "Checking SSH access to BOINC clients..."
  if ansible_ping_clients; then
    return 0
  fi

  if [[ "$COPY_SSH_KEYS" == "1" ]]; then
    echo
    echo "Copying SSH keys to client nodes..."
    ./scripts/copy_ssh_keys.sh
    echo
    echo "Rechecking SSH access to BOINC clients..."
    if ansible_ping_clients; then
      return 0
    fi
  fi

  echo
  print_ssh_failed
  exit 1
}

prepare_client_nodes() {
  echo
  echo "Preparing BOINC client nodes..."
  ANSIBLE_HOST_KEY_CHECKING=False \
    ansible-playbook \
      -i "$ROOT_DIR/ansible/inventory.ini" \
      "$ROOT_DIR/ansible/prepare_nodes.yml" \
      "${ANSIBLE_ARGS[@]}"
}

print_summary() {
  echo
  echo "System preparation completed."
  echo
  echo "Generated:"
  echo "  config/generated.env"
  echo "  ansible/inventory.ini"
  echo "  ansible/group_vars/all/main.yml"
  echo "  monitoring/.env"
  echo
  echo "Vault:"
  echo "  ansible/group_vars/all/vault.yml"
  echo "  ansible/.vault_pass"
  echo
  echo "Next step:"
  echo "  ./scripts/launch_cluster.sh --with-monitoring --run-experiment"
}

cd "$ROOT_DIR"

parse_args "$@"
check_not_sudo
check_cluster_config
ensure_local_dependencies

./scripts/init_config.sh
ensure_vault
ensure_ssh_key

build_ansible_args "${USER_ANSIBLE_ARGS[@]}"
check_ssh_access
prepare_client_nodes
print_summary
