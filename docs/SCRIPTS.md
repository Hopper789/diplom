# Скрипты

Все основные действия выполняются через скрипты из каталога `scripts/`.

## Основные скрипты

### `bootstrap_server.sh`

Поднимает серверную часть:

1. запускает `init_config.sh`;
2. запускает `server_up.sh`;
3. создаёт или находит BOINC account через `create_account_db.sh`;
4. показывает серверный статус.

Запуск:

```bash
./scripts/bootstrap_server.sh
```

### `bootstrap_clients.sh`

Проверяет SSH-доступ до клиентов и запускает `deploy_clients.sh`.

```bash
./scripts/bootstrap_clients.sh
```

Если нет `ansible/.vault_pass`:

```bash
./scripts/bootstrap_clients.sh --ask-vault-pass
```

### `run_experiment.sh`

Запускает создание workunits и просит клиентов забрать задачи.

```bash
./scripts/run_experiment.sh
```

### `status.sh`

Показывает состояние сервера, БД, клиентов и задач.

```bash
./scripts/status.sh
```

Только серверная часть:

```bash
./scripts/status.sh --server-only
```

### `clean_runtime.sh`

Очищает runtime-состояние сервера и клиентов:

- контейнеры клиентов;
- `/opt/boinc-client/data` на клиентах;
- `server/project/`;
- `server/mysql-data/`;
- сгенерированные конфиги.

```bash
./scripts/clean_runtime.sh
```

## Вспомогательные скрипты

### `init_config.sh`

Читает `config/cluster.yml` и генерирует:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all/main.yml
monitoring/.env
```

### `init_vault.sh`

Создаёт Ansible Vault для sudo-пароля клиентов.

### `server_up.sh`

Запускает Docker Compose серверной части из каталога `server/`.

### `create_account_db.sh`

Создаёт BOINC account напрямую в MariaDB и сохраняет `BOINC_ACCOUNT_KEY`.

### `deploy_clients.sh`

Запускает Ansible playbook `ansible/install_boinc_clients.yml`.

### `copy_ssh_keys.sh`

Копирует SSH-ключ на клиентские узлы из `config/cluster.yml`.

## Аргументы Ansible/Vault

Большинство скриптов, которые обращаются к клиентам, поддерживают:

```bash
--ask-vault-pass
--vault-password-file FILE
--ask-become-pass
```

Если существует `ansible/.vault_pass`, скрипты используют его автоматически.
