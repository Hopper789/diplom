# Конфигурация

В репозитории есть примеры конфигов. Рабочие файлы создаются локально и не коммитятся.

## Главные файлы

```text
config/cluster.yml       # машины кластера и BOINC project
config/generated.env     # сгенерированные параметры запуска
config/experiment.env    # параметры конкретного эксперимента
config/distributed.env   # правила выдачи и репликации workunits
config/alerts.env        # Telegram alerts, добавляется позже
```

## config/cluster.yml

Создаётся так:

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

Пример структуры:

```yaml
project:
  name: my_project
  port: 8080

server:
  ip: 192.168.1.10

clients:
  - name: node1
    ip: 192.168.1.11
    user: ubuntu

boinc:
  client_rpc_password: auto

account:
  email: nodes@local.test
  name: nodes
  password: manual
```

`server.ip` должен быть доступен клиентам. `clients[].user` должен подключаться по SSH и иметь sudo-доступ.

## Сгенерированные файлы

`./scripts/init_config.sh` создаёт:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all/main.yml
monitoring/.env
```

Эти файлы можно пересоздавать. Они описывают текущее runtime-состояние и не должны попадать в Git.

## config/experiment.env

Если файла нет, скрипты используют значения из `config/experiment.example.env` или создают локальную копию.

```bash
cp config/experiment.example.env config/experiment.env
nano config/experiment.env
```

Основные параметры:

```env
EXPERIMENT_WALL_SECONDS=180
EXPERIMENT_CORES=12
TASK_SECONDS=8
TASK_COUNT=
TASK_DATASET_SIZE=500
TASK_SEED_BASE=1000
```

Если `TASK_COUNT` пустой, число задач считается примерно как:

```text
EXPERIMENT_WALL_SECONDS * EXPERIMENT_CORES / TASK_SECONDS
```

## config/distributed.env

Этот файл отвечает не за содержимое задачи, а за правила BOINC:

```bash
cp config/distributed.example.env config/distributed.env
nano config/distributed.env
```

Базовый режим без репликации:

```env
DISTRIBUTED_TARGET_NRESULTS=1
DISTRIBUTED_MIN_QUORUM=1
DISTRIBUTED_MAX_SUCCESS_RESULTS=1
DISTRIBUTED_MAX_ERROR_RESULTS=3
DISTRIBUTED_MAX_TOTAL_RESULTS=3
```

Смысл параметров:

- `DISTRIBUTED_TARGET_NRESULTS` — сколько result-записей сервер создаёт на workunit;
- `DISTRIBUTED_MIN_QUORUM` — сколько совпадающих успешных результатов нужно для подтверждения;
- `DISTRIBUTED_MAX_SUCCESS_RESULTS` — максимум успешных результатов;
- `DISTRIBUTED_MAX_ERROR_RESULTS` — допустимое число ошибочных попыток;
- `DISTRIBUTED_MAX_TOTAL_RESULTS` — общий предел попыток.

Для учебного первого запуска оставь значения по умолчанию.
