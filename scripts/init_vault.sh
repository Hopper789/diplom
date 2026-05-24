#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="$ROOT_DIR/ansible/group_vars/all"
VAULT_FILE="$VAULT_DIR/vault.yml"
VAULT_EXAMPLE="$ROOT_DIR/ansible/group_vars/all/vault.example.yml"

cd "$ROOT_DIR"

if ! command -v ansible-vault >/dev/null 2>&1; then
  echo "ERROR: ansible-vault is required."
  echo "Install Ansible first:"
  echo "  sudo apt install -y ansible"
  exit 1
fi

mkdir -p "$VAULT_DIR"

if [[ -f "$VAULT_FILE" ]]; then
  echo "Vault file already exists:"
  echo "  $VAULT_FILE"
  echo
  echo "To edit it:"
  echo "  ansible-vault edit ansible/group_vars/all/vault.yml"
  exit 0
fi

echo "Creating Ansible Vault file for sudo/become password."
echo
echo "This password is the sudo password on client machines."
echo "It will be stored encrypted in:"
echo "  ansible/group_vars/all/vault.yml"
echo

read -rsp "Client sudo password: " BECOME_PASSWORD
echo
read -rsp "Repeat client sudo password: " BECOME_PASSWORD_REPEAT
echo

if [[ "$BECOME_PASSWORD" != "$BECOME_PASSWORD_REPEAT" ]]; then
  echo "ERROR: passwords do not match."
  exit 1
fi

cat > "$VAULT_FILE" <<EOF
ansible_become_password: "$BECOME_PASSWORD"
EOF

chmod 600 "$VAULT_FILE"

cat > "$VAULT_EXAMPLE" <<'EOF'
# Copy this structure to ansible/group_vars/all/vault.yml and encrypt it with:
# ansible-vault encrypt ansible/group_vars/all/vault.yml

ansible_become_password: "your_client_sudo_password"
EOF

echo
echo "Now enter a Vault password."
echo "This Vault password will be used later with --ask-vault-pass."
echo

ansible-vault encrypt "$VAULT_FILE"

echo
echo "Created encrypted Vault file:"
echo "  ansible/group_vars/all/vault.yml"
echo
echo "Use it like this:"
echo "  ./scripts/bootstrap_clients.sh --ask-vault-pass"
echo "  ./scripts/run_experiment.sh --ask-vault-pass"
echo "  ./scripts/status.sh --ask-vault-pass"