# BOINC cluster

Проект поднимает небольшой BOINC-кластер для учебных экспериментов с распределёнными вычислениями.

BOINC можно представить как систему “сервер раздаёт задачи — клиенты считают — сервер собирает результаты”. В этом репозитории всё разворачивается скриптами:

- BOINC server и MariaDB запускаются в Docker на управляющей машине;
- BOINC clients запускаются в Docker-контейнерах на удалённых вычислительных узлах;
- Ansible устанавливает Docker на клиентах, запускает контейнеры и подключает их к проекту;
- BOINC account создаётся автоматически через MariaDB;
- пример эксперимента `ml_grid_search` создаёт много маленьких workunit-задач и раздаёт их клиентам.

## Быстрый запуск

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

./scripts/init_vault.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
./scripts/run_experiment.sh
./scripts/status.sh
```

Если не хочешь хранить пароль от Ansible Vault в `ansible/.vault_pass`, запускай клиентские команды с ручным вводом Vault-пароля:

```bash
./scripts/bootstrap_clients.sh --ask-vault-pass
./scripts/run_experiment.sh --ask-vault-pass
./scripts/status.sh --ask-vault-pass
```

## Документация

- [Что это такое](docs/WHAT_IS_THIS.md)
- [Быстрый запуск](docs/QUICK_START.md)
- [Конфигурация](docs/CONFIGURATION.md)
- [Ansible Vault и sudo-пароль клиентов](docs/VAULT.md)
- [Архитектура](docs/ARCHITECTURE.md)
- [Эксперименты](docs/EXPERIMENTS.md)
- [Скрипты](docs/SCRIPTS.md)
- [Диагностика](docs/TROUBLESHOOTING.md)

## Основной цикл работы

```bash
./scripts/bootstrap_server.sh     # создать конфиги, поднять сервер, создать BOINC account
./scripts/bootstrap_clients.sh    # развернуть BOINC clients на узлах
./scripts/run_experiment.sh       # создать workunits и попросить клиентов забрать задачи
./scripts/status.sh               # посмотреть состояние сервера, клиентов и задач
```

Для полного сброса runtime-состояния сервера и клиентов:

```bash
./scripts/clean_runtime.sh
```

## Что не хранится в Git

В репозитории не должны храниться runtime-данные и секреты:

- `config/cluster.yml` — локальная конфигурация кластера;
- `config/generated.env` — сгенерированные параметры запуска;
- `config/experiment.env` — параметры конкретного эксперимента;
- `ansible/inventory.ini` — сгенерированный список клиентов;
- `ansible/group_vars/all/main.yml` — сгенерированные Ansible-переменные;
- `ansible/group_vars/all/vault.yml` — зашифрованный sudo-пароль клиентов;
- `ansible/.vault_pass` — пароль от Vault;
- `server/project/`, `server/mysql-data/` — runtime-данные BOINC server и MariaDB.
