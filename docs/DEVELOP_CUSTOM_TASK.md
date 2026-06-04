# Разработка пользовательских Python-задач

Кластер лучше всего подходит для независимых задач: каждая задача получает свой вход, считает без общения с другими задачами и возвращает результат.

Основной пользовательский формат — Python task runner.

Структура:

```text
apps/python_task_runner/
  runner.py
  task_api.py
  generate_inputs.py
  run_task.sh
  examples/
```

Пользователь пишет `user_task.py`:

```python
def run(params):
    return {"sum": params["x"] + params["y"]}
```

И задаёт параметры в `params.jsonl`:

```json
{"x": 2, "y": 3}
{"x": 10, "y": 15}
```

Каждая строка становится отдельной workunit. Внутренний вход одной задачи:

```json
{
  "task_id": 1,
  "params": {
    "x": 2,
    "y": 3
  },
  "resources": {
    "device": "cpu"
  }
}
```

Локальная проверка:

```bash
python3 apps/python_task_runner/generate_inputs.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl \
  --out /tmp/python_task_inputs \
  --device cpu

python3 apps/python_task_runner/runner.py \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --input /tmp/python_task_inputs/input_000001.json \
  --output /tmp/output.json
```

Основной способ проверить пользовательскую задачу через BOINC:

```bash
./scripts/quickstart.sh

apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl
```

Если кластер уже подготовлен и запущен, достаточно повторять только `apps/python_task_runner/run_task.sh`.

## Оптимизация Python

На клиентах обязательны `numpy` и `numba`. Они устанавливаются в Docker-образ BOINC client, поэтому пользовательская задача может использовать JIT-компиляцию:

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
    values = np.arange(int(params["n"]), dtype=np.float64)
    return {"score": float(compute(values))}
```

Подробнее: [Python-задачи](PYTHON_TASKS.md).

## GPU

Формат `input.json` уже содержит:

```json
{
  "resources": {
    "device": "gpu"
  }
}
```

В текущей версии GPU считается planned/experimental. Для реальной поддержки потребуется:

- `nvidia-container-toolkit` на клиентах NVIDIA или аналог для ROCm;
- Docker runtime с GPU;
- CUDA/ROCm-образ клиента;
- BOINC app plan class, отдельная платформа или отдельное приложение;
- фильтрация задач по GPU-клиентам.

Пока основной режим — CPU.
