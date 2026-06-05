# Deployment

## Полный запуск

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment
```

## Раздельный запуск

```bash
./scripts/prepare_system.sh
./scripts/launch_cluster.sh --with-monitoring --run-experiment
```

## Этап 1. Подготовка системы

Что делает `prepare_system.sh`:

- проверяет `config/cluster.yml`;
- создаёт `config/generated.env`;
- создаёт `ansible/inventory.ini`;
- создаёт `ansible/group_vars/all/main.yml`;
- создаёт Vault при первом запуске;
- проверяет SSH-ключи;
- проверяет доступ к клиентским узлам;
- подготавливает клиентские узлы;
- не запускает BOINC server;
- не запускает BOINC clients;
- не создаёт задачи.

## Этап 2. Запуск кластера

Что делает `launch_cluster.sh`:

- запускает BOINC server;
- создаёт BOINC account;
- запускает BOINC clients;
- подключает клиентов к проекту;
- опционально запускает мониторинг;
- опционально запускает эксперимент;
- показывает статус, если не указан `--skip-status`.

## Повторный запуск

```bash
./scripts/launch_cluster.sh --with-monitoring
```

Быстрый повторный запуск без большого отчёта:

```bash
./scripts/launch_cluster.sh --with-monitoring --skip-status
```

## Только подготовка

```bash
./scripts/prepare_system.sh
```

## Только запуск без мониторинга и эксперимента

```bash
./scripts/launch_cluster.sh
```
