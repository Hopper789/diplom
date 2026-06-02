# Скрипты

Все команды запускаются из корня репозитория.

## Основные скрипты

| Скрипт | Назначение |
|---|---|
| `quickstart.sh` | Полный запуск: подготовка системы + запуск BOINC-кластера |
| `prepare_system.sh` | Первичная подготовка сервера и клиентских узлов |
| `launch_cluster.sh` | Запуск уже подготовленного BOINC-кластера |
| `status.sh` | Проверка состояния сервера, клиентов, задач и мониторинга |

Основной путь:

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment
```

Раздельный путь:

```bash
./scripts/prepare_system.sh
./scripts/launch_cluster.sh --with-monitoring --run-experiment
```

## Ручной запуск и отладка

| Скрипт | Назначение |
|---|---|
| `bootstrap_server.sh` | Ручной запуск серверной части |
| `bootstrap_clients.sh` | Ручной запуск клиентской части |
| `server_up.sh` | Запуск Docker Compose сервера |
| `create_account_db.sh` | Создание BOINC account в MariaDB |
| `deploy_clients.sh` | Ручной запуск Ansible playbook для клиентов |
| `deploy_monitoring_agents.sh` | Ручной запуск Ansible playbook для агентов мониторинга |
| `monitoring_up.sh` | Ручной запуск мониторинга |
| `monitoring_down.sh` | Остановка мониторинга |
| `run_experiment.sh` | Ручная отправка задач |
| `pump_clients.sh` | Принудительный опрос сервера клиентами |
| `run_quick_benchmarks.sh` | Короткие benchmark-сценарии |
| `alerts_up.sh` | Ручной запуск Telegram notifier |
| `alerts_down.sh` | Остановка Telegram notifier |

Эти скрипты полезны для диагностики и повторных отдельных операций. Они не являются основным способом первого запуска.

## Подготовка

| Скрипт | Назначение |
|---|---|
| `install_server_requirements.sh` | Установка зависимостей на управляющей машине |
| `copy_ssh_keys.sh` | Копирование SSH-ключей на клиентские узлы |
| `init_config.sh` | Генерация `generated.env`, `inventory.ini` и `group_vars` |
| `init_vault.sh` | Ручное создание Vault |

В обычном сценарии `prepare_system.sh` сам вызывает `init_config.sh`, проверяет Vault и при необходимости запускает `init_vault.sh`.

## Очистка

| Скрипт | Назначение |
|---|---|
| `clean_runtime.sh` | Очистка runtime-данных сервера и задач клиентов |

Обычная очистка:

```bash
./scripts/clean_runtime.sh
```

- очищает сервер;
- очищает runtime-данные;
- сбрасывает задачи на клиентах;
- не удаляет BOINC client с клиентских узлов.

Полная очистка:

```bash
./scripts/clean_runtime.sh --purge-clients
```

- очищает сервер;
- удаляет BOINC client с клиентских узлов.

Очистить только задачи клиентов:

```bash
./scripts/clean_runtime.sh --clients-only
```

Очистить только серверную часть:

```bash
./scripts/clean_runtime.sh --server-only
```

Подробнее: [Cleanup](CLEANUP.md).

## Vault-аргументы

Если существует `ansible/.vault_pass`, Ansible-скрипты используют его автоматически. Обычно не нужно передавать `--vault-password-file ansible/.vault_pass`.

Для нестандартных случаев поддерживаются:

```bash
--ask-vault-pass
--vault-password-file FILE
--ask-become-pass
```
