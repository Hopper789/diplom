# Эксперимент ml_grid_search

`run_task.sh` создаёт BOINC workunits и отправляет Python-задачу `main.py` через `apps/python_task_runner`.

`prepare.py` готовит `params.jsonl` и проверяет, что в `main.py` есть функция `run(params)`. `main.py` содержит вычислительный код parameter sweep для ridge-регрессии. Вычислительная часть ускоряется через `numpy` и `numba`.

```bash
EXPERIMENT_WALL_SECONDS=1200
EXPERIMENT_CORES=1
TASK_SECONDS=1200
TASK_LAMBDA_GRID=0,0.001,0.003,0.01,0.03,0.1,0.3,1,3,10
```

Количество задач считается так:

```text
TASK_COUNT = ceil(EXPERIMENT_WALL_SECONDS * EXPERIMENT_CORES / TASK_SECONDS)
```

При настройках по умолчанию:

```text
TASK_COUNT = ceil(1200 * 1 / 1200) = 1 задача
```

Запуск:

```bash
apps/ml_grid_search/run_task.sh boinc
```

Для другой машины можно поменять число ядер:

```bash
EXPERIMENT_CORES=8 EXPERIMENT_WALL_SECONDS=1200 TASK_SECONDS=1200 apps/ml_grid_search/run_task.sh boinc
```

Фиксированное количество задач:

```bash
TASK_COUNT=100 TASK_SECONDS=5 apps/ml_grid_search/run_task.sh boinc
```

## Как менять сложность

- `TASK_SECONDS` — главная ручка. Время одной workunit почти линейно: `600` около
  10 минут, `1200` около 20 минут, `1800` около 30 минут.
- `TASK_COUNT` — точное число workunits. Если пусто, считается по формуле выше.
- `EXPERIMENT_CORES` — сколько параллельных workunits планируется держать в работе
  при автоматическом расчёте `TASK_COUNT`.
- `TASK_DATASET_SIZE` — размер синтетического набора данных. Влияет примерно
  линейно на часть с построением массива и ridge-регрессией, но при большом
  `TASK_SECONDS` вклад обычно мал.
- `TASK_LAMBDA_GRID` — список значений lambda. Он меняет параметры задач, но не
  делает одну задачу тяжелее; значения распределяются по workunits циклически.

Локальная проверка одного и того же Python-пайплайна:

```bash
TASK_COUNT=1 TASK_SECONDS=0 apps/ml_grid_search/run_task.sh local
```
