# Конфигурация

В репозитории есть примеры конфигов. Рабочие файлы создаются локально и не коммитятся.

## Главные файлы

```text
config/cluster.yml       # машины кластера и BOINC project
config/generated.env     # сгенерированные параметры запуска
config/experiment.env    # параметры конкретного эксперимента
config/distributed.env   # правила выдачи и репликации workunits
```

## `config/cluster.yml`

Основной файл конфигурации:

```text
config/cluster.yml
```

Создаётся из примера:

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

Минимально пользователь должен проверить адрес сервера, адреса клиентов и SSH-пользователей:

```yaml
project:
  name: my_project
  port: 8080

server:
  ip: 192.168.1.10

clients_defaults:
  port: 2222

clients:
  - name: node1
    ip: 192.168.1.11
    user: user
  - name: node2
    ip: 192.168.1.12
    user: user
    port: 2222

boinc:
  client_rpc_password: auto
```

`server.ip` должен быть доступен клиентам. `clients[].user` должен подключаться по SSH и иметь sudo-доступ.

`clients[].port` или `clients[].ssh_port` задаёт SSH-порт конкретного клиента. Если у всех клиентов один нестандартный порт, укажи `clients_defaults.port`, `clients_defaults.ssh_port` или `ssh.port`. Если порт не указан, используется стандартный SSH-порт `22`.

Для клиентских узлов также поддерживаются поля `host`, `hostname`, `ansible_host`, `username`, `ansible_user` и `ansible_port`.

## BOINC RPC password

Правильный вариант для новых конфигураций:

```yaml
boinc:
  client_rpc_password: auto
```

Если указано `auto`, пароль для RPC-доступа BOINC client будет сгенерирован автоматически во время `prepare_system.sh` / `init_config.sh`.

Для совместимости также поддерживается старый ключ `boinc.rpc_password`, но в новых конфигурациях следует использовать `boinc.client_rpc_password`.

## Сгенерированные файлы

`prepare_system.sh` вызывает `init_config.sh` и создаёт:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all/main.yml
monitoring/.env
```

Эти файлы можно пересоздавать. Они описывают текущее runtime-состояние и не должны попадать в Git.

## `config/experiment.env`

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
TASK_LAMBDA_GRID=0,0.001,0.003,0.01,0.03,0.1,0.3,1,3,10
```

Если `TASK_COUNT` пустой, число задач считается примерно как:

```text
EXPERIMENT_WALL_SECONDS * EXPERIMENT_CORES / TASK_SECONDS
```

`TASK_LAMBDA_GRID` задаёт сетку параметров для примера `ml_grid_search`.

## `config/distributed.env`

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

Схема "2 из 3" с запасной попыткой:

```env
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=2
DISTRIBUTED_MAX_SUCCESS_RESULTS=2
DISTRIBUTED_MAX_ERROR_RESULTS=3
DISTRIBUTED_MAX_TOTAL_RESULTS=3
```

Важно: `DISTRIBUTED_TARGET_NRESULTS=3` означает, что BOINC будет стремиться создать и
выдать три result-записи сразу. При достаточном числе свободных клиентов это обычно
даёт ровно 3 выполнения на workunit, даже если `DISTRIBUTED_MIN_QUORUM=2`.

Для учебного первого запуска оставь значения по умолчанию.
