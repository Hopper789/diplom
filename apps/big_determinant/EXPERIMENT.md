# determinant

Фиксированный CPU-бенчмарк для BOINC Python runner.

Каждая workunit:

- генерирует плотную квадратную матрицу по `seed`;
- считает `numpy.linalg.slogdet`;
- запускает worker-процессы по числу доступных CPU;
- повторяет расчёт примерно 10 минут;
- возвращает знак определителя, `log_abs`, научную форму и время выполнения.

Ручной запуск через BOINC:

```bash
apps/big_determinant/run_task.sh boinc --workunits 2
```

Запуск через общий runner:

```bash
./scripts/run_experiment.sh --task determinant --workunits 2
```

У задачи нет внешних параметров сложности: размер матрицы, длительность и
число повторов заданы в `apps/big_determinant/main.py`.
