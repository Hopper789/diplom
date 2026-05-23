# Скрипты

## `scripts/clean_runtime.sh`

Полностью очищает runtime-состояние серверной части и мониторинга.

Удаляет:

```text
boinc-server / boinc-mysql containers
server/project/
server/mysql-data/
config/generated.env
ansible/inventory.ini
ansible/group_vars/all.yml
monitoring/.env
```

Не управляет Docker-клиентами на удалённых узлах. Их можно пересоздать повторным запуском:

```bash
./scripts/deploy_clients.sh --ask-become-pass
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

Поднимает серверную часть BOINC в Docker.

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

## `scripts/create_account_db.sh`

Основной способ создания BOINC account для стенда.

Скрипт:

1. читает `PROJECT_NAME`, `BOINC_ACCOUNT_EMAIL`, `BOINC_ACCOUNT_NAME`, `BOINC_ACCOUNT_PASSWORD` из `config/generated.env`;
2. проверяет пользователя в таблице `user`;
3. если пользователя нет — создаёт его напрямую в MariaDB;
4. получает `authenticator`;
5. записывает ключ в:
   - `config/generated.env` как `BOINC_ACCOUNT_KEY`;
   - `ansible/group_vars/all.yml` как `boinc_account_key`.

Запуск:

```bash
./scripts/create_account_db.sh
```

С переопределением параметров:

```bash
EMAIL="cluster_user@gmail.com" \
USERNAME="cluster_user" \
PASSWORD="123456" \
./scripts/create_account_db.sh
```

## `scripts/create_account.sh`

Альтернативный способ, если пользователь был создан вручную через Web UI.

Скрипт не создаёт пользователя. Он:

1. ищет пользователя в БД по `BOINC_ACCOUNT_EMAIL`;
2. берёт `authenticator`;
3. записывает его в `config/generated.env` и `ansible/group_vars/all.yml`.

Запуск:

```bash
./scripts/create_account.sh
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

Playbook устанавливает Docker на клиентах и запускает BOINC client в контейнере `boinc-client`.

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

- Docker containers на сервере;
- BOINC server daemons;
- users;
- hosts;
- workunits/results;
- Ansible ping;
- Docker BOINC clients на удалённых узлах;
- project status и task summary на клиентах;
- адреса мониторинга.

Запуск:

```bash
./scripts/status.sh
```

Если нужен sudo-пароль для удалённых клиентов:

```bash
ANSIBLE_EXTRA_ARGS="--ask-become-pass" ./scripts/status.sh
```

## `scripts/monitoring_up.sh`

Запускает мониторинг:

```text
boinc-exporter
Prometheus
Grafana
cAdvisor
```

Запуск:

```bash
./scripts/monitoring_up.sh
```

Адреса:

```text
Prometheus: http://localhost:9090
Grafana:    http://localhost:3000
Exporter:   http://localhost:9101/metrics
```

## `scripts/monitoring_down.sh`

Останавливает мониторинг:

```bash
./scripts/monitoring_down.sh
```
