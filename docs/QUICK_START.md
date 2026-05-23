# Quick start

## 1. Подготовить конфигурацию

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

## 2. Поднять BOINC server

```bash
./scripts/clean_runtime.sh
./scripts/init_config.sh
./scripts/server_up.sh
```

Открыть сайт проекта:

```text
http://SERVER_IP:8080/PROJECT_NAME/
```

Например:

```text
http://172.17.12.151:8080/my_project/
```

## 3. Создать BOINC account

Основной автоматический вариант:

```bash
./scripts/create_account_db.sh
```

Скрипт создаёт пользователя напрямую в MariaDB, получает `authenticator` и записывает его как `BOINC_ACCOUNT_KEY` в:

```text
config/generated.env
ansible/group_vars/all.yml
```

## 4. Подготовить SSH-доступ к клиентам

```bash
./scripts/copy_ssh_keys.sh
ansible -i ansible/inventory.ini boinc_clients -m ping
```

Если SSH требует пароль:

```bash
ansible -i ansible/inventory.ini boinc_clients -m ping --ask-pass
```

## 5. Развернуть BOINC clients

BOINC clients запускаются на вычислительных узлах как Docker-контейнеры.

```bash
./scripts/deploy_clients.sh --ask-become-pass
```

Если sudo без пароля настроен заранее:

```bash
./scripts/deploy_clients.sh
```

Проверка:

```bash
./scripts/status.sh
```

В таблице `host` должны появиться клиенты. Это можно проверить так

```bash
docker exec -it boinc-mysql \
  mariadb -u root -proot my_project \
  -e "SELECT id, userid, domain_name, os_name, create_time FROM host;"
```

## 6. Запустить эксперимент

```bash
ANSIBLE_EXTRA_ARGS="--ask-become-pass" apps/ml_grid_search/run_task.sh boinc
```

Если sudo без пароля:

```bash
apps/ml_grid_search/run_task.sh boinc
```

## 7. Смотреть статус

```bash
./scripts/status.sh
```

Или напрямую через БД:

```bash
docker exec -it boinc-mysql \
  mariadb -u root -proot my_project \
  -e "
SELECT COUNT(*) AS hosts FROM host;
SELECT COUNT(*) AS workunits FROM workunit;
SELECT COUNT(*) AS results FROM result;
SELECT id, workunitid, server_state, outcome, client_state, hostid FROM result ORDER BY id DESC LIMIT 20;
"
```
