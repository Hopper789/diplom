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
./scripts/run_experiment.sh --task determinant --workunits 2 --submit-only
```

`determinant` фиксирован в коде: одна workunit примерно 10 минут, матрица
`1200 x 1200`, worker-процесс по каждому CPU. Сложность через конфиг не
настраивается.

Grid search:

```bash
./scripts/run_experiment.sh --task grid-search --submit-only
```

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
  --user-task apps/user_task_template/user_task.py \
  --user-params apps/user_task_template/params.jsonl \
  --submit-only
```

## Репликация и quorum

Если нужен режим “2 успешных результата, третий только запасной”:

```bash
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=2
DISTRIBUTED_MAX_SUCCESS_RESULTS=2
DISTRIBUTED_MAX_TOTAL_RESULTS=3
```

При `target_nresults=3` BOINC может создать и раздать 3 attempts сразу.

В Grafana:

- `Факт. репликация` — реально выполненные attempts на workunit;
- `Полезная нагрузка` — доля времени, потраченная на canonical result, без зачёта лишних реплик как полезной работы.
