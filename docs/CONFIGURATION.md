# Конфигурация

## `config/cluster.yml`

Создаётся из примера:

```bash
cp config/cluster.example.yml config/cluster.yml
```

Главные поля:

```yaml
server:
  ip: 172.17.12.151
  port: 8080

clients:
  - name: node1
    ip: 172.17.12.152
    user: auser
    ssh_port: 22

boinc:
  project_name: my_project
  account_email: nodes@local.test
  account_name: nodes
  client_rpc_password: auto
```

Для клиентов поддерживаются поля `ip`, `host`, `hostname`, `ansible_host`, `user`, `username`, `ansible_user`, `ssh_port`, `ansible_port`.

## Сгенерированные файлы

`prepare_system.sh` создаёт:

- `config/generated.env`;
- `ansible/inventory.ini`;
- `ansible/group_vars/all/main.yml`;
- `monitoring/.env`;
- `ansible/group_vars/all/vault.yml`;
- `ansible/.vault_pass`.

Обычно их не редактируют руками.

## `config/experiment.env`

Выбор задачи:

```bash
EXPERIMENT_APP=ml_grid_search
```

Поддерживаются:

- `ml_grid_search`;
- `big_determinant`;
- `python_task_runner`;
- `EXPERIMENT_TASK_CMD='...'` для полностью своей команды.

Размер эксперимента:

```bash
EXPERIMENT_WALL_SECONDS=1200
EXPERIMENT_CORES=2
TASK_SECONDS=1200
TASK_COUNT=
```

Если `TASK_COUNT` пустой, число workunit'ов считается примерно так:

```text
EXPERIMENT_WALL_SECONDS * EXPERIMENT_CORES / TASK_SECONDS
```

## Сложность задач

Для `ml_grid_search`:

```bash
TASK_SECONDS=1200
TASK_DATASET_SIZE=500
TASK_LAMBDA_GRID=0,0.001,0.01,0.1,1,10
```

Для `big_determinant`:

```bash
DETERMINANT_TASK_SECONDS=1200
DETERMINANT_MATRIX_SIZE=1200
DETERMINANT_MAX_REPEATS=0
```

Для `python_task_runner`:

```bash
EXPERIMENT_APP=python_task_runner
PYTHON_TASK_FILE=apps/python_task_runner/examples/synthetic_cpu/user_task.py
PYTHON_TASK_PARAMS=apps/python_task_runner/examples/synthetic_cpu/params.jsonl
PYTHON_TASK_DEVICE=cpu
```

## `config/distributed.env`

Репликация и quorum:

```bash
DISTRIBUTED_TARGET_NRESULTS=1
DISTRIBUTED_MIN_QUORUM=1
DISTRIBUTED_MAX_SUCCESS_RESULTS=1
DISTRIBUTED_MAX_ERROR_RESULTS=3
DISTRIBUTED_MAX_TOTAL_RESULTS=3
```

Если нужно 3 реплики и quorum 2:

```bash
DISTRIBUTED_TARGET_NRESULTS=3
DISTRIBUTED_MIN_QUORUM=2
DISTRIBUTED_MAX_SUCCESS_RESULTS=2
DISTRIBUTED_MAX_TOTAL_RESULTS=3
```

BOINC может создать больше result-записей, чем уникальных workunit'ов. Это нормально: result — попытка выполнения, workunit — уникальная задача.

## MariaDB

Runtime-контейнер базы называется `boinc-mariadb`, service в compose — `mariadb`, данные лежат в `server/mariadb-data/`.
