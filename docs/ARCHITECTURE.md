# Архитектура

## Схема

```text
управляющая машина
  boinc-server
  boinc-mysql
  Prometheus/Grafana/Loki/Promtail
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
  Promtail
```

## Жизненный цикл запуска

```text
quickstart.sh
 ├── prepare_system.sh
 │   ├── init_config.sh
 │   ├── init_vault.sh, если Vault отсутствует
 │   ├── проверка SSH
 │   └── ansible/prepare_nodes.yml
 │
 └── launch_cluster.sh
     ├── bootstrap_server.sh
    ├── bootstrap_clients.sh
    ├── monitoring_up.sh, если указан --with-monitoring
     ├── run_experiment.sh, если указан --run-experiment
     └── status.sh
```

`prepare_system.sh` отвечает за готовность машин.

`launch_cluster.sh` отвечает за запуск BOINC-сервера, клиентов, мониторинга и задач.

`quickstart.sh` объединяет оба этапа.

## Сервер

Серверная часть находится в `server/` и запускается через Docker Compose:

- `boinc-server` — BOINC server, Apache и runtime проекта;
- `boinc-mysql` — MariaDB с таблицами BOINC.

URL проекта:

```text
http://SERVER_IP:8080/PROJECT_NAME/
```

## Клиенты

Клиентские узлы описаны в `config/cluster.yml`.

`ansible/prepare_nodes.yml` готовит узлы: проверяет Debian/Ubuntu, устанавливает Docker, Python, curl и запускает Docker.

`ansible/install_boinc_clients.yml` запускает контейнер `boinc-client` и подключает его к BOINC-проекту через account key, который создаёт `./scripts/create_account_db.sh`.

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

Обычная очистка:

```bash
./scripts/clean_runtime.sh
```

Она очищает server runtime и сбрасывает задачи клиентов, но не удаляет BOINC client с клиентских узлов.
