# Скрипты

## Основной запуск

### `scripts/bootstrap_server.sh`

Генерирует runtime-конфиги, поднимает BOINC server и создаёт BOINC account.

```bash
./scripts/bootstrap_server.sh
```

### `scripts/bootstrap_clients.sh`

Проверяет SSH-доступ и разворачивает BOINC clients в Docker на вычислительных узлах.

```bash
./scripts/bootstrap_clients.sh --ask-become-pass
./scripts/bootstrap_clients.sh --ask-vault-pass
```

### `scripts/run_experiment.sh`

Запускает создание workunits и отправляет `project update` клиентам.

```bash
./scripts/run_experiment.sh --ask-become-pass
./scripts/run_experiment.sh --ask-vault-pass
```

### `scripts/quickstart.sh`

Выполняет `bootstrap_server.sh` и `bootstrap_clients.sh`.

```bash
./scripts/quickstart.sh --ask-vault-pass
```

## Низкоуровневые скрипты

### `scripts/init_config.sh`

Читает `config/cluster.yml`, создаёт:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all.yml
```

### `scripts/server_up.sh`

Поднимает BOINC server и MariaDB в Docker.

### `scripts/create_account_db.sh`

Создаёт или находит BOINC user напрямую в MariaDB и сохраняет `BOINC_ACCOUNT_KEY`.

### `scripts/deploy_clients.sh`

Запускает Ansible playbook `ansible/install_boinc_clients.yml`.

```bash
./scripts/deploy_clients.sh --ask-become-pass
./scripts/deploy_clients.sh --ask-vault-pass
./scripts/deploy_clients.sh --vault
```

### `scripts/init_vault.sh`

Создаёт зашифрованный файл `ansible/group_vars/all/vault.yml` с `ansible_become_password`.

```bash
./scripts/init_vault.sh
```

### `scripts/clean_runtime.sh`

Очищает runtime сервера, мониторинга и удалённое BOINC-состояние клиентов.

```bash
./scripts/clean_runtime.sh --ask-become-pass
./scripts/clean_runtime.sh --ask-vault-pass
```

### `scripts/status.sh`

Показывает состояние server containers, BOINC DB, клиентов и мониторинга.
