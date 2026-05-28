# Бенчмарки

Бенчмарки нужны, чтобы понять сильные и слабые стороны кластера. Один тест может хорошо масштабироваться по CPU, другой покажет накладные расходы BOINC scheduler, третий упрётся в память, диск или сеть.

Перед запуском любого benchmark:

```bash
./scripts/init_vault.sh
./scripts/quickstart.sh --with-monitoring
```

Проверка прогресса:

```bash
./scripts/status.sh
curl -s http://SERVER_IP:9101/metrics | grep boinc_
```

## Быстрый подбор конфигурации

Для быстрой оценки кластера используй готовый короткий набор:

```bash
./scripts/run_quick_benchmarks.sh --yes --replicas 2
```

Скрипт не перезапускает контейнеры и рассчитан на короткий прогон. На слабом стенде он должен укладываться примерно в 10 минут, если кластер уже поднят.

Что запускается:

- `tiny_40_base` — 40 очень лёгких задач, показывает scheduler overhead;
- `cpu_light_16_base` — 16 CPU-задач примерно по 1.5 секунды;
- `cpu_heavy_8_base` — 8 CPU-задач примерно по 5 секунд;
- `io_small_8_base` — 8 небольших IO-задач;
- `cpu_light_16_replN` — тот же CPU-набор с репликацией, если `--replicas N > 1`.

Что измеряется:

| Метрика | Что показывает |
|---|---|
| Общее время эксперимента | Сколько времени занял набор задач |
| Пропускная способность | Сколько задач завершается за секунду |
| Ошибки, % | Доля ошибочных BOINC results |
| Средняя загрузка CPU, % | Насколько клиенты реально заняты вычислениями |
| Среднее использование RAM, % | Использование памяти клиентских узлов |
| Накладные расходы на задачу | Разница между turnaround и compute time |
| Фактический коэффициент репликации | Сколько result-записей приходится на один workunit |
| Network RX/TX | Средний сетевой трафик клиентов по Prometheus |
| SSH network probe | Быстрая оценка ping и upload throughput до клиентов |

Результаты сохраняются в:

```text
reports/quick_benchmarks/YYYYMMDD_HHMMSS/
```

Главные файлы:

- `summary.md` — короткий человекочитаемый вывод;
- `summary.csv` — таблица для сравнения сценариев;
- `network_probe.json` — ping и пробная SSH-пропускная способность;
- `<scenario>/metrics.json` — подробные метрики сценария.

Как читать результат:

- если `tiny_40_base` сильно хуже CPU-сценариев, задачи слишком мелкие для BOINC;
- если `cpu_heavy_8_base` даёт высокий CPU и хороший throughput, кластер лучше подходит для тяжёлых независимых задач;
- если `io_small_8_base` заметно хуже, узкое место может быть в файлах, диске или передаче;
- если `cpu_light_16_replN` сильно медленнее базового сценария, репликация повышает надёжность, но снижает throughput;
- если CPU низкий, а очередь задач есть, проблема обычно в scheduler/client update, сети или окружении клиента.

Полезные опции:

```bash
./scripts/run_quick_benchmarks.sh --yes --replicas 2 --timeout 240
./scripts/run_quick_benchmarks.sh --yes --no-replication
./scripts/run_quick_benchmarks.sh --yes --skip-network-probe
```

## 1. ml_grid_search

Текущий основной пример:

```bash
./scripts/run_experiment.sh
```

Что проверяет:

- parameter sweep;
- много независимых задач;
- базовую интеграцию C++ BOINC-приложения.

Метрики:

- `boinc_completed_workunits_total`;
- `boinc_results_error_total`;
- `boinc_avg_success_turnaround_seconds`;
- CPU usage клиентов.

## 2. monte_carlo_pi

CPU-bound benchmark для Python runner:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/monte_carlo_pi/user_task.py \
  --params apps/python_task_runner/examples/monte_carlo_pi/params.jsonl
```

Что проверяет:

- масштабирование CPU;
- throughput;
- стабильность Python runner.

Метрики:

- completed WUs/min;
- CPU usage;
- avg/p95 turnaround;
- avg compute/WU.

## 3. tiny_tasks_overhead

Очень короткие задачи:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/tiny_tasks_overhead/user_task.py \
  --params apps/python_task_runner/examples/tiny_tasks_overhead/params.jsonl
```

Что проверяет:

- накладные расходы BOINC scheduler;
- влияние коротких workunits;
- минимальный полезный размер задачи.

Метрики:

- avg overhead/WU;
- turnaround time;
- completed WUs/min.

## 4. synthetic_cpu

Фиксированное CPU-время на задачу:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/synthetic_cpu/user_task.py \
  --params apps/python_task_runner/examples/synthetic_cpu/params.jsonl
```

Что проверяет:

- равномерную CPU-нагрузку;
- сравнение числа клиентов;
- completed WUs/min при одинаковом времени задачи.

Параметр `task_seconds` задаётся в каждой строке `params.jsonl`.

## 5. memory_scan

Memory-bound benchmark:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/memory_scan/user_task.py \
  --params apps/python_task_runner/examples/memory_scan/params.jsonl
```

Что проверяет:

- влияние RAM;
- load average;
- поведение клиентов при задачах с разным `size_mb`.

Метрики:

- client memory usage;
- client CPU usage;
- turnaround.

## 6. io_test

I/O-heavy benchmark:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/io_test/user_task.py \
  --params apps/python_task_runner/examples/io_test/params.jsonl
```

Что проверяет:

- влияние локального диска;
- накладные расходы на чтение и запись;
- чувствительность коротких задач к файловому обмену.

Метрики:

- network traffic;
- turnaround;
- overhead/WU;
- completed WUs/min.

## 7. failure_demo

Часть задач намеренно падает:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/failure_demo/user_task.py \
  --params apps/python_task_runner/examples/failure_demo/params.jsonl
```

По умолчанию runner пишет `output.json` со статусом `error` и завершает процесс с кодом `0`, чтобы BOINC получил диагностический output.

Для проверки BOINC error results можно включить ненулевой код:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/failure_demo/user_task.py \
  --params apps/python_task_runner/examples/failure_demo/params.jsonl \
  --fail-on-error
```

Что проверяет:

- обработку ошибок пользовательского кода;
- `boinc_results_error_total`;
- поведение `DISTRIBUTED_MAX_ERROR_RESULTS`.

## 8. replication_benchmark

Один и тот же workload запускается с разными `config/distributed.env`.

Вариант без репликации:

```env
DISTRIBUTED_TARGET_NRESULTS=1
DISTRIBUTED_MIN_QUORUM=1
```

Вариант с дублированием без строгого quorum:

```env
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=1
```

Вариант с дублированием и quorum:

```env
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=2
```

После смены `config/distributed.env` лучше запускать эксперимент на чистом runtime:

```bash
./scripts/clean_runtime.sh
./scripts/quickstart.sh --with-monitoring
```

Метрики:

- replication factor;
- min quorum;
- error results;
- completed WUs/min;
- avg/p95 turnaround;
- avg overhead/WU;
- avg compute/WU.

## Как сравнивать результаты

Для каждого benchmark сохраняй:

- число клиентов и CPU-ядер;
- параметры `params.jsonl`;
- `config/distributed.env`;
- время старта и завершения;
- основные метрики из Grafana или Prometheus.

Сильный кластер для BOINC должен хорошо показывать себя на `monte_carlo_pi` и `synthetic_cpu`. Если `tiny_tasks_overhead` даёт плохой throughput, это не ошибка кластера: задачи слишком короткие, и scheduler overhead становится заметнее полезной работы.
