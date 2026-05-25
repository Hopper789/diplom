# Архитектура проекта

## Общая схема

```text
              управляющая машина
        ┌────────────────────────────┐
        │ boinc-server Docker         │
        │ boinc-mysql Docker          │
        │ scripts/*.sh                │
        │ ansible                     │
        └─────────────┬──────────────┘
                      │ SSH
          ┌───────────┴───────────┐
          │                       │
   ┌──────▼──────┐         ┌──────▼──────┐
   │ client node │         │ client node │
   │ Docker      │         │ Docker      │
   │ boinc-client│         │ boinc-client│
   └─────────────┘         └─────────────┘
```

## Что запускается на сервере

В каталоге `server/` находится Docker Compose для двух контейнеров:

- `boinc-server` — BOINC server, Apache, project runtime;
- `boinc-mysql` — MariaDB с таблицами BOINC project.

Сервер доступен по URL:

```text
http://SERVER_IP:8080/PROJECT_NAME/
```

## Что запускается на клиентах

На клиентах Ansible устанавливает Docker и создаёт каталог:

```text
/opt/boinc-client
```

В нём создаётся Docker Compose файл, который запускает контейнер:

```text
boinc-client
```

Клиент подключается к BOINC project через `BOINC_ACCOUNT_KEY`.

## Как создаются задачи

`apps/ml_grid_search/run_task.sh` выполняет несколько действий:

1. компилирует BOINC application внутри `boinc-server`;
2. копирует XML-шаблоны input/output;
3. регистрирует приложение через `xadd` и `update_versions`;
4. создаёт workunits через `create_work`;
5. просит клиентов выполнить `project update`;
6. показывает краткий статус.

## Какие файлы создаются автоматически

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all/main.yml
monitoring/.env
```

Их можно удалить и создать заново через:

```bash
./scripts/init_config.sh
```

## Какие данные являются runtime

```text
server/project/
server/mysql-data/
/opt/boinc-client/data на клиентах
```

Эти данные очищаются через:

```bash
./scripts/clean_runtime.sh
```

## Как устроен мониторинг

Мониторинг состоит из серверной и клиентской части.

На управляющей машине запускаются:

- `boinc-exporter` — читает BOINC MariaDB и отдаёт метрики проекта;
- `boinc-prometheus` — собирает и хранит метрики;
- `boinc-grafana` — показывает dashboard;
- `boinc-cadvisor` — показывает нагрузку Docker-контейнеров на управляющей машине.

На каждом клиенте через Ansible запускаются:

- `boinc-node-exporter` — CPU, RAM, load average, сеть и диск узла;
- `boinc-client-cadvisor` — CPU/RAM/IO Docker-контейнера `boinc-client`.

`monitoring_up.sh` генерирует `monitoring/prometheus.yml` из `ansible/inventory.ini`, поэтому Prometheus автоматически знает IP клиентских узлов.
