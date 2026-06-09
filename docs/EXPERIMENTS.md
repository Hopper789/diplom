# Эксперименты

## Запуск

Отправить задачи и сразу вернуть управление:

```bash
./scripts/run_experiment.sh --submit-only
```

Отправить задачи, прокачивать клиентов и дождаться завершения:

```bash
./scripts/run_experiment.sh
```

Через quickstart:

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment
```

## Выбор задачи

В `config/experiment.env`:

```bash
EXPERIMENT_APP=ml_grid_search
```

Встроенные задачи:

- `ml_grid_search` — CPU-задача на Python/Numba;
- `big_determinant` — тяжёлая линейная алгебра;
- `python_task_runner` — запуск пользовательского Python-файла.

Можно задать свою команду:

```bash
EXPERIMENT_TASK_CMD='apps/big_determinant/run_task.sh boinc'
```

## Как менять длительность

Главный параметр — желаемое время одного workunit:

```bash
TASK_SECONDS=1200
```

Для `ml_grid_search` время растёт от:

- `TASK_SECONDS`;
- `TASK_DATASET_SIZE`;
- числа значений в `TASK_LAMBDA_GRID`;
- числа повторов, которое подбирает задача для удержания нужной длительности.

Для `big_determinant` время растёт от:

- `DETERMINANT_TASK_SECONDS`;
- `DETERMINANT_MATRIX_SIZE`;
- `DETERMINANT_MAX_REPEATS`, если задано больше нуля.

Для своих Python-задач время зависит от параметров в `params.jsonl` и кода `user_task.py`.

## Пользовательская Python-задача

Файл задачи должен иметь функцию:

```python
def run(params, context):
    return {"result": 42}
```

Параметры задаются JSONL:

```json
{"n": 1000}
{"n": 2000}
```

Запуск:

```bash
EXPERIMENT_APP=python_task_runner
PYTHON_TASK_FILE=apps/python_task_runner/examples/sum_params/user_task.py
PYTHON_TASK_PARAMS=apps/python_task_runner/examples/sum_params/params.jsonl
./scripts/run_experiment.sh --submit-only
```

## Бенчмарки

Для быстрого подбора конфигурации:

```bash
./scripts/quickstart.sh --with-monitoring
./scripts/run_quick_benchmarks.sh --yes --replicas 2
```

Бенчмарки короткие и сравнивают:

- лёгкие задачи;
- CPU-тяжёлые задачи;
- IO-задачи;
- memory scan;
- репликацию.

Отчёт сохраняется в `reports/quick_benchmarks/`.

## Репликация и quorum

Если `target_nresults=3`, `min_quorum=2`, BOINC создаёт до 3 попыток, но задача считается полезно завершённой после quorum. Лишние attempts могут стать redundant.

В Grafana:

- `Факт. репликация` — реально выполненные attempts на workunit;
- `Полезная нагрузка` — доля времени успешных attempts, потраченная на саму функцию `run(params)`.
