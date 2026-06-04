# Python-задачи

Python task runner — основной формат пользовательских вычислений в этом проекте.

## Контракт задачи

Файл задачи должен содержать функцию `run(params)`:

```python
def run(params):
    return {"answer": params["x"] + params["y"]}
```

`params` — JSON-объект из одной строки `params.jsonl`. Возвращаемое значение должно сериализоваться в JSON.

## Параметры задач

Каждая строка `params.jsonl` становится отдельной BOINC workunit:

```json
{"x": 2, "y": 3}
{"x": 10, "y": 15}
```

Runner превращает строки в `input_*.json`, запускает `run(params)` и сохраняет `output.json`.

## Оптимизация

BOINC clients запускают Python-код внутри контейнера `boinc-client`.

Обязательные библиотеки для Python-задач:

- `numpy`;
- `numba`.

Они устанавливаются в клиентский Docker-образ через `ansible/install_boinc_clients.yml`. На управляющей машине они также входят в `install_server_requirements.sh` и проверяются `prepare_system.sh`.

Проверить runtime на уже развёрнутых клиентах:

```bash
./scripts/check_client_runtime.sh
```

Пример с Numba:

```python
from numba import njit
import numpy as np


@njit
def compute(values):
    total = 0.0
    for value in values:
        total += value * value
    return total


def run(params):
    n = int(params.get("n", 1000))
    values = np.arange(n, dtype=np.float64)
    return {"sum_squares": float(compute(values))}
```

## Локальная проверка

```bash
python3 apps/python_task_runner/generate_inputs.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl \
  --out /tmp/python_task_inputs \
  --device cpu

python3 apps/python_task_runner/runner.py \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --input /tmp/python_task_inputs/input_000001.json \
  --output /tmp/output.json \
  --fail-on-error
```

## Запуск через BOINC

Сначала кластер должен быть подготовлен и запущен:

```bash
./scripts/quickstart.sh
```

После этого можно отправлять Python-задачи:

```bash
apps/python_task_runner/run_task.sh \
  --task path/to/user_task.py \
  --params path/to/params.jsonl
```

## Текущий пример

`apps/ml_grid_search/main.py` — пример parameter sweep на Python с `numpy` и `numba`.

`apps/ml_grid_search/prepare.py` готовит `params.jsonl` для этого примера и проверяет, что основной файл содержит `run(params)`.

Запуск через стандартный сценарий:

```bash
./scripts/quickstart.sh --run-experiment
```

Ручная повторная отправка задач:

```bash
./scripts/run_experiment.sh
```
