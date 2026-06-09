# Разработка и структура

## Архитектура

```text
control machine
  ├─ boinc-server
  ├─ boinc-mariadb
  ├─ Prometheus / Grafana / Loki
  └─ Ansible -> client nodes

client node
  ├─ boinc-client
  ├─ node-exporter
  └─ promtail
```

BOINC entities:

- workunit — уникальная задача;
- result — попытка выполнения workunit;
- host — зарегистрированный BOINC-клиент;
- app_version — версия приложения под платформу клиента.

## Основные скрипты

- `quickstart.sh` — подготовка, запуск, мониторинг, отправка задач.
- `prepare_system.sh` — конфиги, Vault, SSH, подготовка клиентов.
- `launch_cluster.sh` — запуск server/client/monitoring.
- `run_experiment.sh` — отправка и опциональное ожидание эксперимента.
- `pump_clients.sh` — project update на клиентах.
- `status.sh` — диагностика.
- `clean_runtime.sh` — очистка runtime.

Все пользовательские скрипты принимают `--debug`.

## Своя Python-задача

Минимальный файл:

```python
def run(params, context):
    value = params["value"]
    return {"square": value * value}
```

Параметры:

```json
{"value": 2}
{"value": 3}
```

Локальная проверка:

```bash
python3 apps/python_task_runner/runner.py \
  --task my_task.py \
  --input params.json \
  --output result.json
```

Запуск через BOINC:

```bash
EXPERIMENT_APP=python_task_runner
PYTHON_TASK_FILE=my_task.py
PYTHON_TASK_PARAMS=params.jsonl
./scripts/run_experiment.sh --submit-only
```

## Runtime-файлы

Не коммитятся:

- `server/project/`;
- `server/mariadb-data/`;
- `boinc-data/`;
- `reports/`;
- `config/generated.env`;
- `ansible/inventory.ini`;
- Vault-файлы с секретами.

## Очистка

```bash
./scripts/clean_runtime.sh
./scripts/clean_runtime.sh --server-only
./scripts/clean_runtime.sh --clients-only
./scripts/clean_runtime.sh --purge-clients
```

`clean_runtime.sh` также удаляет старые runtime-имена, оставшиеся от прежних версий.

## Почему такой стек

- BOINC уже решает scheduler, workunit/result, upload/download и host accounting.
- Docker даёт повторяемую серверную среду.
- Ansible управляет удалёнными клиентами по SSH.
- Prometheus/Grafana хорошо подходят для временных рядов.
- Loki хранит stderr/stdout логи без отдельной базы.
