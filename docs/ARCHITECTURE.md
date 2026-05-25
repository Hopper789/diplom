# Архитектура

## Схема

```text
управляющая машина
  boinc-server
  boinc-mysql
  Prometheus/Grafana
  scripts/
  ansible/
        |
        | SSH
        v
клиентские узлы
  Docker
  boinc-client
  node-exporter
  cAdvisor
```

## Сервер

Серверная часть находится в `server/` и запускается через Docker Compose:

- `boinc-server` — BOINC server, Apache и runtime проекта;
- `boinc-mysql` — MariaDB с таблицами BOINC.

URL проекта:

```text
http://SERVER_IP:8080/PROJECT_NAME/
```

## Клиенты

Клиентские узлы описаны в `config/cluster.yml`. Ansible подключается к ним по SSH, устанавливает Docker и запускает контейнер `boinc-client`.

Клиент подключается к BOINC-проекту через account key, который создаёт `./scripts/create_account_db.sh`.

## Workunit и result

`workunit` — логическая задача. `result` — конкретная попытка выполнить её на клиенте.

При базовых настройках:

```text
1 workunit -> 1 result
```

При репликации:

```text
1 workunit -> 2 или больше result
```

Репликация и quorum задаются в `config/distributed.env`.

## Runtime-файлы

Автоматически создаются и не коммитятся:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all/main.yml
monitoring/.env
server/project/
server/mysql-data/
```

Полная очистка:

```bash
./scripts/clean_runtime.sh
```
