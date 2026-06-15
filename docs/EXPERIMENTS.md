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

Тяжёлая regularized log-det задача:

```bash
./scripts/run_experiment.sh --task determinant --submit-only
```

`determinant` запускает regularized log-det benchmark: генерирует одну
детерминированную матрицу `8000 x 8000` и последовательно считает
`logdet(A + lambda I)` через `numpy.linalg.slogdet` для 16 значений `lambda`.
Искусственного ожидания нет; длительность растёт от числа точек регуляризации.

В пользовательском результате сохраняются параметры выданной задачи
(`task_id`, `seed`, размер матрицы), сетка `lambda`, выбранная регуляризация и
полный путь значений `log_abs`.

Количество workunit задаётся самой задачей в `apps/big_determinant/main.py`.
Сейчас используется простая константа `WORKUNITS=4`: будет создано 4 workunit
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
- `Полезная нагрузка` — доля полезного compute-time с учётом реальных накладных расходов; локальное ожидание заранее выданных задач на клиенте вычитается.

## Проверка репликации ошибками

Для проверки replacement attempts можно включить управляемые отказы. Обычный запуск не меняется:
по умолчанию `BOINC_SIMULATE_FAILURE_RATE=0`.

Пример: примерно 25% attempts падают, а BOINC может создать до 3 попыток на workunit:

```bash
cat > config/distributed.env <<'EOF'
DISTRIBUTED_TARGET_NRESULTS=1
DISTRIBUTED_MIN_QUORUM=1
DISTRIBUTED_MAX_SUCCESS_RESULTS=1
DISTRIBUTED_MAX_ERROR_RESULTS=2
DISTRIBUTED_MAX_TOTAL_RESULTS=3
EOF

BOINC_SIMULATE_FAILURE_RATE=0.25 \
BOINC_SIMULATE_FAILURE_SEED=replication-test \
./scripts/run_experiment.sh --task determinant --submit-only

./scripts/pump_clients.sh --debug
```

То же самое через quickstart:

```bash
./scripts/quickstart.sh \
  --with-monitoring \
  --run-experiment \
  --task determinant \
  --simulate-failures 0.25 \
  --simulate-failure-seed replication-test

./scripts/pump_clients.sh --debug
```

Сам quickstart только отправляет workunit'ы. Ошибки появятся после того, как
клиенты начнут забирать задачи, поэтому для проверки отказов запускай
`pump_clients.sh`.

Для режима “2 успешных из максимум 3 attempts”:

```bash
cat > config/distributed.env <<'EOF'
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=2
DISTRIBUTED_MAX_SUCCESS_RESULTS=2
DISTRIBUTED_MAX_ERROR_RESULTS=1
DISTRIBUTED_MAX_TOTAL_RESULTS=3
EOF
```

Отказ считается детерминированно по `seed + task_id + hostname`, поэтому разные реплики
одного workunit могут вести себя по-разному. Это лучше, чем специально ломать задачу по
`task_id`: такая ошибка повторится во всех репликах и quorum не сможет восстановиться.

## Выгрузка результатов

Пользовательский вывод функции `run(params)` лежит в загруженных `output.json`.
Какие поля BOINC DB нужны для поиска этих файлов: [Выгрузка результатов вычислений](RESULT_EXPORT.md).
