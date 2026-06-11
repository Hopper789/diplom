#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="$ROOT_DIR/ansible/group_vars/all"
VAULT_FILE="$VAULT_DIR/vault.yml"
VAULT_EXAMPLE="$VAULT_DIR/vault.example.yml"
VAULT_PASS_FILE="$ROOT_DIR/ansible/.vault_pass"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

cd "$ROOT_DIR"

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"

if ! command -v ansible-vault >/dev/null 2>&1; then
  echo "ОШИБКА: нужен ansible-vault."
  echo "Сначала установи Ansible:"
  echo "  sudo apt install -y ansible"
  exit 1
fi

mkdir -p "$VAULT_DIR"

if [[ -f "$VAULT_FILE" ]]; then
  echo "Vault-файл уже существует:"
  echo "  ansible/group_vars/all/vault.yml"
  echo

  if [[ ! -f "$VAULT_PASS_FILE" ]]; then
    echo "Если ты знаешь пароль от Vault, создай ansible/.vault_pass вручную:"
    echo "  nano ansible/.vault_pass"
    echo "  chmod 600 ansible/.vault_pass"
    echo
  fi

  echo "Редактирование Vault:"
  if [[ -f "$VAULT_PASS_FILE" ]]; then
    echo "  ansible-vault edit ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass"
  else
    echo "  сначала восстанови ansible/.vault_pass, затем повтори команду"
  fi

  exit 0
fi

echo "Создаётся Ansible Vault для sudo-пароля клиентов."
echo
echo "Этот пароль используется для sudo на клиентских машинах."
echo "Он будет сохранён в зашифрованном виде:"
echo "  ansible/group_vars/all/vault.yml"
echo

read -rsp "Sudo-пароль клиентов: " BECOME_PASSWORD
echo
read -rsp "Повтори sudo-пароль клиентов: " BECOME_PASSWORD_REPEAT
echo

if [[ "$BECOME_PASSWORD" != "$BECOME_PASSWORD_REPEAT" ]]; then
  echo "ОШИБКА: sudo-пароли не совпадают."
  exit 1
fi

echo
read -rsp "Пароль Vault для сохранения в ansible/.vault_pass: " VAULT_PASSWORD
echo
read -rsp "Повтори пароль Vault: " VAULT_PASSWORD_REPEAT
echo

if [[ "$VAULT_PASSWORD" != "$VAULT_PASSWORD_REPEAT" ]]; then
  echo "ОШИБКА: пароли Vault не совпадают."
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
# Скопируй эту структуру в ansible/group_vars/all/vault.yml и зашифруй её.
# Не коммить настоящий vault.yml.

ansible_become_password: "your_client_sudo_password"
EOF

quiet_run_all ansible-vault encrypt "$VAULT_FILE" --vault-password-file "$VAULT_PASS_FILE"

echo
echo "Создано:"
echo "  ansible/group_vars/all/vault.yml"
echo "  ansible/.vault_pass"
echo
echo "Теперь скрипты будут использовать Vault автоматически:"
echo "  ./scripts/bootstrap_clients.sh"
echo "  ./scripts/run_experiment.sh"
echo "  ./scripts/status.sh"
