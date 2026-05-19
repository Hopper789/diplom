# Скрипты

## `scripts/clean_runtime.sh`

Полностью очищает runtime-состояние проекта.

Удаляет:

```text
boinc-client container
boinc-data/
boinc-server / boinc-mysql containers
server/project/
server/mysql-data/
config/generated.env
ansible/inventory.ini
ansible/group_vars/all.yml
```

Запуск:

```bash
./scripts/clean_runtime.sh
```

## `scripts/init_config.sh`

Читает:

```text
config/cluster.yml
```

Создаёт:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all.yml
```

Запуск:

```bash
./scripts/init_config.sh
```

Использует Python 3 и PyYAML.

## `scripts/server_up.sh`

Поднимает серверную часть.

Использует:

```text
server/docker-compose.yml
server/scripts/create_project.sh
server/scripts/fix_project_url.sh
```

Запуск:

```bash
./scripts/server_up.sh
```

## `scripts/create_account.sh`

Не создаёт пользователя автоматически.

Скрипт:

1. читает `BOINC_ACCOUNT_EMAIL` из `config/generated.env`;
2. ищет пользователя в таблице `user`;
3. берёт поле `authenticator`;
4. записывает его в `config/generated.env` как `BOINC_ACCOUNT_KEY`;
5. обновляет `ansible/group_vars/all.yml`.

Запуск:

```bash
./scripts/create_account.sh
```

## `scripts/attach_local_client.sh`

Подключает локальный Docker BOINC client к проекту.

Использует:

```text
BOINC_PROJECT_URL
BOINC_ACCOUNT_KEY
BOINC_CLIENT_RPC_PASSWORD
```

Запуск:

```bash
./scripts/attach_local_client.sh
```

## `scripts/copy_ssh_keys.sh`

Копирует SSH public key на всех клиентов из `config/cluster.yml`.

Запуск:

```bash
./scripts/copy_ssh_keys.sh
```

Другой ключ:

```bash
SSH_KEY="$HOME/.ssh/id_rsa" ./scripts/copy_ssh_keys.sh
```

## `scripts/deploy_clients.sh`

Запускает Ansible playbook:

```text
ansible/install_boinc_clients.yml
```

Запуск:

```bash
./scripts/deploy_clients.sh
```

С sudo-паролем:

```bash
./scripts/deploy_clients.sh --ask-become-pass
```

С SSH-паролем и sudo-паролем:

```bash
./scripts/deploy_clients.sh --ask-pass --ask-become-pass
```

## `scripts/status.sh`

Показывает состояние:

- Docker containers;
- BOINC daemons;
- users;
- hosts;
- Ansible ping.

Запуск:

```bash
./scripts/status.sh
```
