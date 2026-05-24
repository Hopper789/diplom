#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="$ROOT_DIR/ansible/group_vars/all"
VAULT_FILE="$VAULT_DIR/vault.yml"
VAULT_EXAMPLE="$VAULT_DIR/vault.example.yml"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

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
  echo "  ansible/group_vars/all/vault.yml"
  echo

  if [[ ! -f "$VAULT_PASS_FILE" ]]; then
    echo "You can create ansible/.vault_pass manually if you know the Vault password:"
    echo "  nano ansible/.vault_pass"
    echo "  chmod 600 ansible/.vault_pass"
    echo
  fi

  echo "To edit Vault:"
  if [[ -f "$VAULT_PASS_FILE" ]]; then
    echo "  ansible-vault edit ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass"
  else
    echo "  ansible-vault edit ansible/group_vars/all/vault.yml --ask-vault-pass"
  fi

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
  echo "ERROR: sudo passwords do not match."
  exit 1
fi

echo
read -rsp "Vault password to save in ansible/.vault_pass: " VAULT_PASSWORD
echo
read -rsp "Repeat Vault password: " VAULT_PASSWORD_REPEAT
echo

if [[ "$VAULT_PASSWORD" != "$VAULT_PASSWORD_REPEAT" ]]; then
  echo "ERROR: Vault passwords do not match."
  exit 1
fi

cat > "$VAULT_PASS_FILE" <<EOF
$VAULT_PASSWORD
EOF

chmod 600 "$VAULT_PASS_FILE"

cat > "$VAULT_FILE" <<EOF
ansible_become_password: "$BECOME_PASSWORD"
EOF

chmod 600 "$VAULT_FILE"

cat > "$VAULT_EXAMPLE" <<'EOF'
# Copy this structure to ansible/group_vars/all/vault.yml and encrypt it.
# Do not commit real vault.yml.

ansible_become_password: "your_client_sudo_password"
EOF

ansible-vault encrypt "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE"

echo
echo "Created:"
echo "  ansible/group_vars/all/vault.yml"
echo "  ansible/.vault_pass"
echo
echo "Now you can run scripts without repeated Vault prompts:"
echo "  ./scripts/bootstrap_clients.sh"
echo "  ./scripts/run_experiment.sh"
echo "  ./scripts/status.sh"