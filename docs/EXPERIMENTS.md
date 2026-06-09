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

По умолчанию запускается пользовательская Python-задача из шаблона:

```bash
./scripts/run_experiment.sh --task user --submit-only
```

Тяжёлый determinant benchmark:

```bash
./scripts/run_experiment.sh --task big-det --workunits 2 --submit-only
```

`big-det` фиксирован в коде: одна workunit примерно 10 минут, матрица
`1200 x 1200`, worker-процесс по каждому CPU. Сложность через конфиг не
настраивается.

## Пользовательская Python-задача

Файл задачи должен иметь функцию:

```python
def run(params):
    return {"result": 42}
```

Параметры задаются JSONL:

```json
{"n": 1000}
{"n": 2000}
```

Запуск:

```bash
./scripts/run_experiment.sh \
  --task user \
  --user-task apps/python_task_runner/examples/sum_params/user_task.py \
  --user-params apps/python_task_runner/examples/sum_params/params.jsonl \
  --submit-only
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
