# Python task runner

Этот runner нужен для пользовательских независимых задач. Пользователь пишет функцию `run(params)`, а BOINC получает много отдельных `input.json`.

## user_task.py

Минимальный пример:

```python
def run(params):
    return {"sum": params["x"] + params["y"]}
```

Файл должен содержать функцию `run(params)`. `params` — JSON-объект из одной строки `params.jsonl`.

## params.jsonl

Каждая строка — отдельная независимая задача:

```json
{"x": 2, "y": 3}
{"x": 10, "y": 15}
```

Runner превращает строки в файлы:

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

## Формат результата

Успешная задача:

```json
{
  "task_id": 1,
  "status": "ok",
  "result": {
    "sum": 5
  },
  "timing": {
    "compute_seconds": 0.01
  }
}
```

Если `run(params)` падает, runner записывает `status: "error"` и текст ошибки. По умолчанию процесс завершается с кодом `0`, если `output.json` записан корректно. Для проверки отказов можно добавить `--fail-on-error`.

## Локальный запуск

Сначала создай один input:

```bash
python3 apps/python_task_runner/generate_inputs.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl \
  --out /tmp/python_task_inputs \
  --device cpu
```

Потом запусти runner:

```bash
python3 apps/python_task_runner/runner.py \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --input /tmp/python_task_inputs/input_000001.json \
  --output /tmp/output.json
```

Если хочешь использовать ровно `/tmp/input.json`:

```bash
cp /tmp/python_task_inputs/input_000001.json /tmp/input.json
python3 apps/python_task_runner/runner.py \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --input /tmp/input.json \
  --output /tmp/output.json
```

Проверка:

```bash
cat /tmp/output.json
```

## Запуск через BOINC

Сначала должен быть поднят сервер и клиенты:

```bash
./scripts/init_vault.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
```

Затем:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl
```

Для CPU/GPU-метки входа:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/monte_carlo_pi/user_task.py \
  --params apps/python_task_runner/examples/monte_carlo_pi/params.jsonl \
  --device cpu
```

В этой версии реально поддержан CPU. Значение `resources.device` оставлено в формате входа для будущей маршрутизации GPU-задач.
