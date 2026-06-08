# Эксперименты

Эксперимент в этом репозитории — это набор независимых задач, которые BOINC раздаёт клиентам.

## Текущий пример: `ml_grid_search`

Приложение находится в:

```text
apps/ml_grid_search/
```

Оно создаёт много workunits для перебора параметров. Каждая задача получает входные параметры, считает синтетическую работу и возвращает результат.

Текущий пример реализован на Python и использует `numpy`/`numba` для ускорения вычислений на клиентах. В `apps/ml_grid_search/prepare.py` находится подготовка параметров, а в `apps/ml_grid_search/main.py` — основной вычислительный код.

## Запуск эксперимента

Основной запуск:

```bash
./scripts/quickstart.sh --run-experiment
```

С мониторингом:

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment
```

Раздельный запуск:

```bash
./scripts/prepare_system.sh
./scripts/launch_cluster.sh --run-experiment
```

Если кластер уже подготовлен:

```bash
./scripts/launch_cluster.sh --run-experiment
```

Ручной запуск:

```bash
./scripts/run_experiment.sh
```

`run_experiment.sh` нужен для повторной отправки задач без повторного запуска всего кластера.

Если мониторинг запущен, после завершения всех вычислений `run_experiment.sh` сохраняет dump графиков Grafana и итоговых метрик:

```text
reports/grafana_dumps/<timestamp>/
```

Ручной dump:

```bash
./scripts/dump_grafana_results.sh --wait --max-seconds 600
```

## Пользовательские Python-задачи

Для независимых задач можно использовать:

```text
apps/python_task_runner/
```

Пользователь пишет `user_task.py` с функцией `run(params)` и список задач в `params.jsonl`.

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl
```

Подробнее: [Python-задачи](PYTHON_TASKS.md) и [Разработка пользовательских задач](DEVELOP_CUSTOM_TASK.md).

## Размер эксперимента

Локальный файл:

```bash
cp config/experiment.example.env config/experiment.env
nano config/experiment.env
```

Основные параметры:

- `EXPERIMENT_WALL_SECONDS` — желаемая длительность эксперимента;
- `EXPERIMENT_CORES` — ориентировочное число CPU-ядер;
- `TASK_SECONDS` — примерная длительность одной задачи;
- `TASK_COUNT` — точное число задач, если нужно задать вручную;
- `TASK_DATASET_SIZE` — размер синтетических данных;
- `TASK_SEED_BASE` — базовый seed.
- `TASK_LAMBDA_GRID` — сетка regularization/lambda для перебора.

## Репликация и quorum

```bash
cp config/distributed.example.env config/distributed.env
nano config/distributed.env
```

Без репликации:

```env
DISTRIBUTED_TARGET_NRESULTS=1
DISTRIBUTED_MIN_QUORUM=1
```

С дублированием и проверкой совпадения:

```env
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=2
DISTRIBUTED_MAX_SUCCESS_RESULTS=2
```

Схема "2 из 3", где третья попытка используется как запас:

```env
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=2
DISTRIBUTED_MAX_SUCCESS_RESULTS=2
DISTRIBUTED_MAX_TOTAL_RESULTS=3
```

Для первого запуска лучше оставить базовый режим.

## Проверка прогресса

```bash
./scripts/status.sh
```

Важные блоки:

- `MariaDB hosts` — зарегистрированные клиенты;
- `MariaDB workunits/results summary` — созданные задачи и попытки;
- `Remote BOINC client task summary` — очередь и активные задачи на клиентах.

Метрики:

```bash
curl -s http://SERVER_IP:9101/metrics | grep boinc_
```
