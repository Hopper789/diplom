# Big determinant

CPU-задача для BOINC Python runner.

Каждая workunit:

- генерирует плотную квадратную матрицу по `seed`;
- считает `numpy.linalg.slogdet`;
- повторяет расчёт до `target_seconds`, но не меньше 10 минут на workunit при обычном запуске;
- возвращает знак определителя, `log_abs`, научную форму и время выполнения.

По умолчанию одна workunit работает примерно 10 минут:

```env
DETERMINANT_TASK_SECONDS=600
```

Для 30 минут:

```env
DETERMINANT_TASK_SECONDS=1800
```

Ручной запуск через BOINC:

```bash
apps/big_determinant/run_task.sh boinc
```

Быстрая локальная проверка:

```bash
DETERMINANT_MAX_REPEATS=1 DETERMINANT_TASK_COUNT=1 DETERMINANT_MATRIX_SIZE=32 \
  apps/big_determinant/run_task.sh local
```

Настройки:

| Переменная | Смысл |
|---|---|
| `DETERMINANT_TASK_SECONDS` | целевая длительность одной workunit в секундах; кодовая нижняя граница — 600 секунд |
| `DETERMINANT_TASK_COUNT` | точное число workunits |
| `DETERMINANT_MATRIX_SIZE` | размер матрицы `N x N` |
| `DETERMINANT_SEED_BASE` | базовый seed |
| `DETERMINANT_DIAGONAL_BOOST` | добавка к диагонали для устойчивости |
| `DETERMINANT_MAX_REPEATS` | точное число повторов; `0` означает работать до `DETERMINANT_TASK_SECONDS` |
