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

Тяжёлая determinant-задача:

```bash
./scripts/run_experiment.sh --task determinant --submit-only
```

`determinant` выполняет одну реальную задачу: генерирует детерминированную
матрицу `12000 x 12000` и считает её определитель через `numpy.linalg.slogdet`.
Искусственного ожидания или цикла “работать N минут” нет.

В пользовательском результате сохраняются параметры выданной задачи
(`task_id`, `seed`, размер матрицы) и результат вычисления: знак определителя,
`log_abs` и научная форма.

Количество workunit задаётся самой задачей в `apps/big_determinant/main.py`.
Сейчас используется простая константа `WORKUNITS=20`: будет создано 20 workunit
независимо от числа клиентов. BOINC сам раздаёт их клиентам из общей очереди.

Максимальное время возврата BOINC-задачи задаётся через
`DISTRIBUTED_DELAY_BOUND`. По умолчанию это `86400` секунд, то есть 1 день.

Grid search:

```bash
./scripts/run_experiment.sh --task grid-search --submit-only
```

`grid-search` выполняет реальные workunit: каждая считает ridge-регрессию для
одного значения `lambda` на синтетическом датасете. Количество workunit и
параметры сетки заданы в `apps/ml_grid_search/main.py`. Сейчас используется
`WORKUNITS=20`; искусственного ожидания или цикла “работать N минут” нет.

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
- `Полезная нагрузка` — доля времени первых `min_quorum` успешных attempts; лишние реплики считаются накладными расходами.

## Выгрузка результатов

Пользовательский вывод функции `run(params)` лежит в загруженных `output.json`.
Какие поля BOINC DB нужны для поиска этих файлов: [Выгрузка результатов вычислений](RESULT_EXPORT.md).
