# determinant

CPU-задача для BOINC Python runner: вычисление определителя большой матрицы.

Каждая workunit:

- генерирует плотную квадратную матрицу по `seed`;
- считает `numpy.linalg.slogdet`;
- возвращает параметры выданной задачи, знак определителя, `log_abs`,
  научную форму и время выполнения.

Искусственной длительности нет: задача завершается после вычисления своего
определителя. Максимальный срок возврата результата задаётся BOINC-параметром
`DISTRIBUTED_DELAY_BOUND`; по умолчанию это `86400` секунд, то есть 1 день.

Ручной запуск через BOINC:

```bash
apps/big_determinant/run_task.sh boinc --workunits 2
```

Запуск через общий runner:

```bash
./scripts/run_experiment.sh --task determinant --workunits 2
```

У задачи нет внешних параметров сложности: размер матрицы задан в
`apps/big_determinant/main.py`. Через `--workunits` задаётся только количество
BOINC-задач.
