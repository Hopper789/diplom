# BOINC-кластер

Учебный BOINC-кластер для запуска независимых вычислительных задач на нескольких машинах. Управляющая машина поднимает BOINC server, MariaDB и мониторинг; клиентские узлы подключаются по SSH через Ansible и считают workunit'ы в контейнерах.

## Быстрый запуск

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

./scripts/quickstart.sh --with-monitoring --run-experiment
```

После `quickstart --run-experiment` задачи только отправляются в BOINC. Чтобы смотреть прогресс:

```bash
./scripts/status.sh
```

Чтобы автоматически просить клиентов забирать следующие задачи и дождаться конца:

```bash
./scripts/pump_clients.sh
```

## Главные адреса

- BOINC: `http://SERVER_IP:8080/PROJECT_NAME/`
- Grafana: `http://SERVER_IP:3000/`
- Prometheus: `http://SERVER_IP:9090/`
- Loki: `http://SERVER_IP:3100/`

Grafana открывается без логина. Админский вход: `admin / admin`.

## Частые команды

```bash
./scripts/prepare_system.sh --copy-ssh-keys
./scripts/launch_cluster.sh --with-monitoring
./scripts/run_experiment.sh
./scripts/run_experiment.sh --task big-det --workunits 2
./scripts/status.sh
./scripts/clean_runtime.sh
```

У всех пользовательских скриптов есть `--debug`. Без него вывод старается быть коротким; с ним показываются подробности Docker/Ansible/служебных команд.

## Что где лежит

- `config/cluster.yml` — IP сервера, клиенты, SSH-порты, параметры BOINC.
- `config/distributed.env` — репликация, quorum и ограничения BOINC result.
- `apps/` — вычислительные задачи.
- `scripts/` — запуск, диагностика, очистка.
- `monitoring/` — Prometheus, Grafana, Loki, exporter.
- `server/` — BOINC server и MariaDB compose.

## Документация

Начинай с [docs/README.md](docs/README.md). Там короткий маршрут по оставшимся документам:

- [Быстрый старт](docs/QUICK_START.md)
- [Конфигурация](docs/CONFIGURATION.md)
- [Эксперименты](docs/EXPERIMENTS.md)
- [Мониторинг](docs/MONITORING.md)
- [Диагностика](docs/TROUBLESHOOTING.md)
- [Разработка и структура](docs/DEVELOPMENT.md)

## Что не коммитится

В Git не должны попадать локальные конфиги, секреты и runtime:

- `config/cluster.yml`
- `config/generated.env`
- `config/distributed.env`
- `ansible/inventory.ini`
- `ansible/group_vars/all/main.yml`
- `ansible/group_vars/all/vault.yml`
- `ansible/.vault_pass`
- `server/project/`
- `server/mariadb-data/`
- `monitoring/.env`
