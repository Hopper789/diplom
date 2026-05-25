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
