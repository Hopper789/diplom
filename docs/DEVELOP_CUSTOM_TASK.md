# Разработка пользовательских задач

Кластер лучше всего подходит для независимых задач: каждая задача получает свой вход, считает без общения с другими задачами и возвращает результат.

## CPU: базовый режим

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

Запуск через BOINC:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl
```

## C++

Для C++ сейчас используй текущий подход `apps/ml_grid_search` как пример:

1. исходник компилируется внутри `boinc-server`;
2. бинарник кладётся в runtime-каталог BOINC-приложения внутри project directory;
3. приложение регистрируется через `xadd` и `update_versions`;
4. workunits создаются через `create_work`.

Даже для C++ лучше держать вход и выход в JSON или простом `key=value`, чтобы результаты было легко проверять и сравнивать.

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
