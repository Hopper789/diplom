# Эксперимент ml_grid_search

`run_task.sh` создаёт много маленьких BOINC workunits.

```bash
EXPERIMENT_WALL_SECONDS=180
EXPERIMENT_CORES=12
TASK_SECONDS=8
```

Количество задач считается так:

```text
TASK_COUNT = ceil(EXPERIMENT_WALL_SECONDS * EXPERIMENT_CORES / TASK_SECONDS)
```

При настройках по умолчанию:

```text
TASK_COUNT = ceil(180 * 12 / 8) = 270 задач
```

Запуск:

```bash
apps/ml_grid_search/run_task.sh boinc
```

Для другой машины можно поменять число ядер:

```bash
EXPERIMENT_CORES=8 EXPERIMENT_WALL_SECONDS=180 TASK_SECONDS=8 apps/ml_grid_search/run_task.sh boinc
```

Фиксированное количество задач:

```bash
TASK_COUNT=100 TASK_SECONDS=5 apps/ml_grid_search/run_task.sh boinc
```
