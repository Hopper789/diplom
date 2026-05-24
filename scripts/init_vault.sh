#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="$ROOT_DIR/ansible/group_vars/all"
VAULT_FILE="$VAULT_DIR/vault.yml"
EXAMPLE_FILE="$ROOT_DIR/ansible/group_vars/all/vault.example.yml"
LEGACY_EXAMPLE_FILE="$ROOT_DIR/ansible/group_vars/vault.example.yml"

usage() {
  cat <<'USAGE'
Usage: ./scripts/init_vault.sh

Creates ansible/group_vars/all/vault.yml with ansible_become_password and encrypts it with Ansible Vault.
The vault file is ignored by Git.

After creating it, use:
  ./scripts/deploy_clients.sh --ask-vault-pass
  ./scripts/run_experiment.sh --ask-vault-pass
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if ! command -v ansible-vault >/dev/null 2>&1; then
  echo "ERROR: ansible-vault not found. Install Ansible first."
  echo "Example: sudo apt install -y ansible"
  exit 1
fi

mkdir -p "$VAULT_DIR"

if [[ -f "$VAULT_FILE" ]]; then
  echo "Vault file already exists: $VAULT_FILE"
  echo "To edit it:"
  echo "  ansible-vault edit ansible/group_vars/all/vault.yml"
  exit 0
fi

echo "This will create encrypted Ansible Vault file:"
echo "  ansible/group_vars/all/vault.yml"
echo
read -r -s -p "Remote sudo password for clients: " BECOME_PASSWORD
echo

if [[ -z "$BECOME_PASSWORD" ]]; then
  echo "ERROR: password is empty"
  exit 1
fi

cat > "$VAULT_FILE" <<EOF2
ansible_become_password: "$BECOME_PASSWORD"
EOF2

chmod 600 "$VAULT_FILE"
ansible-vault encrypt "$VAULT_FILE"

if [[ -f "$LEGACY_EXAMPLE_FILE" && ! -f "$EXAMPLE_FILE" ]]; then
  cp "$LEGACY_EXAMPLE_FILE" "$EXAMPLE_FILE"
fi

echo
echo "Vault created: ansible/group_vars/all/vault.yml"
echo "Use it with:"
echo "  ./scripts/deploy_clients.sh --ask-vault-pass"
echo "  ./scripts/run_experiment.sh --ask-vault-pass"
