# Эксперименты

В проекте есть пример вычислительного приложения:

```text
apps/ml_grid_search/
```

Оно создаёт много маленьких BOINC workunits. Каждая задача получает входной файл с параметрами:

```text
task_id
lambda
seed
n
target_seconds
```

## Подготовка

Перед запуском эксперимента сервер и клиенты должны быть подняты:

```bash
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
```

## Настройка размера эксперимента

```bash
cp config/experiment.example.env config/experiment.env
nano config/experiment.env
```

Главные параметры:

- `EXPERIMENT_WALL_SECONDS` — желаемая длительность эксперимента;
- `EXPERIMENT_CORES` — примерное число CPU-ядер на одной машине;
- `TASK_SECONDS` — примерная длительность одной маленькой задачи;
- `TASK_COUNT` — ручное число задач, если не хочется использовать автоматический расчёт;
- `TASK_DATASET_SIZE` — размер синтетических данных;
- `TASK_SEED_BASE` — базовое значение seed.

## Настройка распределённого выполнения

```bash
cp config/distributed.example.env config/distributed.env
nano config/distributed.env
```

В этом файле задаются параметры BOINC workunit template: репликация, quorum и ограничения на число попыток. Например, для базовой версии без репликации:

```env
DISTRIBUTED_TARGET_NRESULTS=1
DISTRIBUTED_MIN_QUORUM=1
DISTRIBUTED_MAX_SUCCESS_RESULTS=1
```

Для запуска с дублированием задач:

```env
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=2
DISTRIBUTED_MAX_SUCCESS_RESULTS=2
DISTRIBUTED_MAX_TOTAL_RESULTS=4
```

Dashboard берёт метрику `Replication` именно из этой конфигурации через `boinc_config_replication_factor`.

## Запуск

```bash
./scripts/run_experiment.sh
```

Если нет `ansible/.vault_pass`:

```bash
./scripts/run_experiment.sh --ask-vault-pass
```

## Проверка прогресса

```bash
./scripts/status.sh
```

В блоке `Remote BOINC client task summary` видны задачи на клиентах. Возможные статусы:

- `executing` — задача выполняется;
- `uninitialized` — задача в очереди клиента;
- пустой список — клиент сейчас не держит активных задач.

## Проверка через БД

```bash
docker exec -it boinc-mysql \
  mariadb -u root -proot my_project \
  -e "
SELECT COUNT(*) AS hosts FROM host;
SELECT COUNT(*) AS workunits FROM workunit;
SELECT COUNT(*) AS results FROM result;
SELECT server_state, outcome, client_state, COUNT(*) AS cnt
FROM result
GROUP BY server_state, outcome, client_state;
"
```

## Новый прогон с чистого состояния

```bash
./scripts/clean_runtime.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
./scripts/run_experiment.sh
```


## Какие метрики смотреть

Для оценки эксперимента полезны две группы метрик.

BOINC-метрики:

- `boinc_workunits_total` — сколько логических задач создано;
- `boinc_results_total` — сколько попыток выполнения создано;
- `boinc_results_finished_total` — сколько results завершилось;
- `boinc_results_error_total` — сколько results завершилось ошибкой;
- `boinc_queue_remaining_total` — сколько результатов остаётся в очереди;
- `boinc_completed_workunits_total` — сколько workunits получили успешный результат;
- `boinc_config_replication_factor` — настроенная репликация из `config/distributed.env`;
- `boinc_config_min_quorum` — настроенный quorum из `config/distributed.env`;
- `boinc_avg_compute_time_per_workunit_seconds` — среднее время непосредственного выполнения задачи;
- `boinc_avg_overhead_time_per_workunit_seconds` — средние накладные расходы на одну workunit;
- `boinc_avg_success_turnaround_seconds` — среднее полное время возврата результата.

Метрики нагрузки клиентов:

- CPU usage по каждому клиенту;
- RAM usage по каждому клиенту;
- load average;
- network RX/TX;
- контейнерная нагрузка через cAdvisor.

Для просмотра графиков:

```bash
./scripts/monitoring_up.sh
```

Затем открыть:

```text
http://localhost:3000
```
