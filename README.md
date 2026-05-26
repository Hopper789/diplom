# BOINC-кластер

Это учебный BOINC-кластер для запуска независимых вычислительных задач на нескольких машинах.

BOINC можно представить так: сервер хранит задания, клиенты забирают их, считают и возвращают результаты. Репозиторий автоматизирует этот цикл скриптами, Docker и Ansible.

## Что умеет

- поднимает BOINC server и MariaDB в Docker;
- разворачивает BOINC clients на удалённых узлах по SSH;
- хранит sudo-пароль клиентов через Ansible Vault;
- запускает пример `ml_grid_search`;
- запускает пользовательские Python-задачи через `apps/python_task_runner`;
- собирает метрики BOINC и нагрузки клиентов в Prometheus/Grafana;
- отправляет базовое Telegram-уведомление о завершении эксперимента.

## Архитектура в 5 строк

1. Управляющая машина запускает `boinc-server` и `boinc-mysql`.
2. `config/cluster.yml` описывает сервер, клиентов и BOINC-проект.
3. Ansible по SSH ставит Docker на клиентские узлы.
4. Клиентский контейнер `boinc-client` подключается к проекту.
5. Workunit создаётся на сервере, result выполняется клиентом и возвращается обратно.

## Самый быстрый запуск

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

./scripts/init_vault.sh
./scripts/quickstart.sh --with-monitoring --run-experiment
./scripts/status.sh
```

Если нужны Telegram-уведомления о завершении эксперимента, перед запуском alerts создай локальный файл с токеном бота:

```bash
cp config/alerts.example.env config/alerts.env
nano config/alerts.env
./scripts/alerts_up.sh
```

`./scripts/init_vault.sh` создаёт:

- `ansible/group_vars/all/vault.yml` — зашифрованный sudo-пароль клиентов;
- `ansible/.vault_pass` — пароль от Vault, чтобы скрипты могли читать Vault автоматически.

`ansible/.vault_pass` не коммитится. После `init_vault` скрипты сами используют `--vault-password-file ansible/.vault_pass`.

## Пошаговый запуск

```bash
./scripts/init_vault.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
./scripts/monitoring_up.sh
./scripts/run_experiment.sh
./scripts/status.sh
```

## Запуск мониторинга

```bash
./scripts/monitoring_up.sh
```

Grafana доступна по адресу:

```text
http://localhost:3000
admin / admin
```

## Telegram-уведомления

После запуска мониторинга:

```bash
cp config/alerts.example.env config/alerts.env
nano config/alerts.env
./scripts/alerts_up.sh
```

В `config/alerts.env` нужно указать `TELEGRAM_BOT_TOKEN` и `TELEGRAM_CHAT_ID`. Файл содержит секреты и не коммитится.

## Запуск своего Python task

```bash
apps/python_task_runner/run_task.sh \
  --task apps/python_task_runner/examples/sum_params/user_task.py \
  --params apps/python_task_runner/examples/sum_params/params.jsonl
```

`user_task.py` должен содержать функцию `run(params)`. Каждая строка `params.jsonl` становится отдельной BOINC workunit.

## Документация

- [Что это такое](docs/WHAT_IS_THIS.md)
- [Быстрый запуск](docs/QUICK_START.md)
- [Конфигурация](docs/CONFIGURATION.md)
- [Ansible Vault и sudo-пароль клиентов](docs/VAULT.md)
- [Архитектура](docs/ARCHITECTURE.md)
- [Эксперименты](docs/EXPERIMENTS.md)
- [Мониторинг и метрики](docs/MONITORING.md)
- [Скрипты](docs/SCRIPTS.md)
- [Диагностика](docs/TROUBLESHOOTING.md)
- [Разработка пользовательских задач](docs/DEVELOP_CUSTOM_TASK.md)
- [Telegram alerts](docs/ALERTS.md)
- [Обоснование технологий](docs/TECH_DECISIONS.md)
- [Бенчмарки](docs/BENCHMARKS.md)

## Что не коммитится

В Git не должны попадать секреты, локальные конфиги и runtime-данные:

- `config/cluster.yml`, `config/generated.env` — локальная и сгенерированная конфигурация;
- `config/experiment.env` — параметры конкретного эксперимента;
- `config/distributed.env` — локальные параметры репликации;
- `config/alerts.env` — токен Telegram-бота и chat id;
- `ansible/inventory.ini` — сгенерированный список клиентов;
- `ansible/group_vars/all/main.yml` — сгенерированные Ansible-переменные;
- `ansible/group_vars/all/vault.yml` — зашифрованный sudo-пароль клиентов;
- `ansible/.vault_pass` — пароль от Vault;
- `server/project/`, `server/mysql-data/` — runtime-данные сервера;
- `monitoring/.env` — runtime-настройки мониторинга.
