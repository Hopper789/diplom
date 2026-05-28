# Скрипты

Все основные действия выполняются из каталога `scripts/`.

## Главный путь

```bash
./scripts/init_vault.sh
./scripts/quickstart.sh --with-monitoring --run-experiment
./scripts/status.sh
```

## Основные скрипты

`quickstart.sh` запускает сервер, клиентов, опционально мониторинг и эксперимент.

```bash
./scripts/quickstart.sh
./scripts/quickstart.sh --with-monitoring
./scripts/quickstart.sh --run-experiment
./scripts/quickstart.sh --with-monitoring --run-experiment
```

`bootstrap_server.sh` поднимает локальную серверную часть:

```bash
./scripts/bootstrap_server.sh
```

`bootstrap_clients.sh` разворачивает BOINC clients на узлах из `config/cluster.yml`:

```bash
./scripts/bootstrap_clients.sh
```

`run_experiment.sh` создаёт workunits и просит клиентов забрать задачи:

```bash
./scripts/run_experiment.sh
```

`run_quick_benchmarks.sh` запускает короткие бенчмарки для подбора конфигурации вычислений:

```bash
./scripts/run_quick_benchmarks.sh --yes --replicas 2
```

`apps/python_task_runner/run_task.sh` запускает пользовательские Python-задачи:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl
```

`monitoring_up.sh` запускает Prometheus/Grafana и клиентские агенты:

```bash
./scripts/monitoring_up.sh
```

`alerts_up.sh` запускает Telegram notifier:

```bash
./scripts/alerts_up.sh
```

`alerts_down.sh` останавливает Telegram notifier:

```bash
./scripts/alerts_down.sh
```

`status.sh` показывает состояние сервера, клиентов, задач и мониторинга:

```bash
./scripts/status.sh
```

`clean_runtime.sh` очищает runtime-состояние:

```bash
./scripts/clean_runtime.sh
```

## Вспомогательные скрипты

- `init_config.sh` — генерирует `config/generated.env`, inventory и Ansible vars;
- `init_vault.sh` — создаёт Vault и `ansible/.vault_pass`;
- `server_up.sh` — запускает Docker Compose сервера;
- `create_account_db.sh` — создаёт BOINC account в MariaDB;
- `deploy_clients.sh` — запускает Ansible playbook клиентов;
- `deploy_monitoring_agents.sh` — ставит node-exporter и cAdvisor на клиентов;
- `monitoring_down.sh` — останавливает мониторинг;
- `run_quick_benchmarks.sh` — собирает короткий отчёт по базовой и реплицированной конфигурации;
- `alerts_up.sh` и `alerts_down.sh` — управляют Telegram notifier;
- `copy_ssh_keys.sh` — помогает скопировать SSH-ключи на клиентов.

## Vault

Основной сценарий такой:

```bash
./scripts/init_vault.sh
```

После этого скрипты автоматически используют `ansible/.vault_pass`. Ручной ввод Vault-пароля описан только в [диагностике](TROUBLESHOOTING.md), потому что это аварийный сценарий.
