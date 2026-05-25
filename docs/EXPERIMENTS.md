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

## Настройка параметров

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
- `boinc_results_success_total` — сколько results завершилось успешно;
- `boinc_results_error_total` — сколько results завершилось ошибкой;
- `boinc_results_unfinished_total` — сколько results ещё не завершено;
- `boinc_success_rate` и `boinc_error_rate` — доли успехов и ошибок;
- `boinc_replication_overhead` — накладные расходы репликации;
- `boinc_avg_success_turnaround_seconds` — среднее время возврата результата.

Метрики нагрузки клиентов:

- CPU usage по каждому клиенту;
- RAM usage по каждому клиенту;
- load average;
- CPU/RAM контейнера `boinc-client`;
- network RX/TX.

Для просмотра графиков:

```bash
./scripts/monitoring_up.sh
```

Затем открыть:

```text
http://localhost:3000
```
