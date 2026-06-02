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
- позволяет вручную включить Telegram-уведомление о завершении эксперимента.

## Архитектура в 5 строк

1. Управляющая машина запускает `boinc-server` и `boinc-mysql`.
2. `config/cluster.yml` описывает сервер, клиентов и BOINC-проект.
3. Ansible по SSH готовит клиентские узлы.
4. Клиентский контейнер `boinc-client` подключается к проекту.
5. Workunit создаётся на сервере, result выполняется клиентом и возвращается обратно.

## Самый быстрый запуск

```bash
git clone https://github.com/Hopper789/diplom.git
cd diplom

cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

./scripts/quickstart.sh --with-monitoring --run-experiment
```

`quickstart.sh` выполняет полный сценарий:

1. подготавливает конфигурацию;
2. проверяет зависимости;
3. создаёт Vault при первом запуске;
4. проверяет SSH-доступ к клиентским узлам;
5. подготавливает узлы;
6. запускает BOINC server;
7. запускает BOINC clients;
8. при необходимости запускает мониторинг;
9. при необходимости отправляет тестовые задачи;
10. показывает статус системы.

## Раздельный запуск

```bash
./scripts/prepare_system.sh
./scripts/launch_cluster.sh --with-monitoring --run-experiment
```

Раздельный запуск нужен, если требуется отдельно проверить подготовку системы и отдельно запуск BOINC-кластера.

## Повторный запуск

```bash
./scripts/launch_cluster.sh --with-monitoring
```

Если система уже подготовлена, повторно выполнять prepare не обязательно.

## Интерфейсы

BOINC server:

```text
http://SERVER_IP:8080/PROJECT_NAME/
```

Grafana:

```text
http://SERVER_IP:3000/
```

Dashboard можно смотреть без логина. Для администрирования доступен вход `admin / admin`.

## Ручные инструменты

Отдельные скрипты вроде `init_vault.sh`, `bootstrap_server.sh`, `bootstrap_clients.sh`, `monitoring_up.sh` и `run_experiment.sh` остаются ручными инструментами диагностики и отладки. Основной путь запуска описан выше.

Telegram alerts не запускаются автоматически через обычный quickstart. Их можно включить вручную:

```bash
cp config/alerts.example.env config/alerts.env
nano config/alerts.env
./scripts/alerts_up.sh
```

## Быстрые бенчмарки

Чтобы быстро понять, какие задачи и настройки лучше подходят кластеру:

```bash
./scripts/quickstart.sh --with-monitoring
./scripts/run_quick_benchmarks.sh --yes --replicas 2
```

Отчёт появится в `reports/quick_benchmarks/`.

## Документация

- [Что это такое](docs/WHAT_IS_THIS.md)
- [Быстрый запуск](docs/QUICK_START.md)
- [Развёртывание](docs/DEPLOYMENT.md)
- [Конфигурация](docs/CONFIGURATION.md)
- [Ansible Vault и sudo-пароль клиентов](docs/VAULT.md)
- [Архитектура](docs/ARCHITECTURE.md)
- [Эксперименты](docs/EXPERIMENTS.md)
- [Мониторинг и метрики](docs/MONITORING.md)
- [Скрипты](docs/SCRIPTS.md)
- [Очистка](docs/CLEANUP.md)
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
