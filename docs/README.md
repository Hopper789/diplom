# Документация

Здесь оставлен короткий набор документов для нового пользователя.

## Читать по порядку

1. [Быстрый старт](QUICK_START.md) — как запустить кластер первый раз.
2. [Конфигурация](CONFIGURATION.md) — что менять в `cluster.yml` и `distributed.env`.
3. [Архитектура](ARCHITECTURE.md) — как BOINC передаёт данные, запускает задачи и возвращает результаты.
4. [Эксперименты](EXPERIMENTS.md) — как выбрать задачу и запускать бенчмарки.
5. [Выгрузка результатов](RESULT_EXPORT.md) — где найти `output.json` и поле `result`.
6. [Мониторинг](MONITORING.md) — Grafana, Prometheus, Loki, финальные метрики.
7. [Диагностика](TROUBLESHOOTING.md) — что смотреть, когда что-то не работает.

## Главная идея

BOINC server хранит workunit'ы, клиенты забирают их, считают и возвращают result'ы. Репозиторий автоматизирует:

- подготовку управляющей машины;
- настройку клиентских узлов через Ansible;
- запуск BOINC server и MariaDB;
- отправку задач;
- мониторинг нагрузки клиентских узлов через node-exporter;
- сбор ошибок через Loki.

## Структура проекта

- `apps/ml_grid_search` — задача grid search.
- `apps/big_determinant` — CPU-бенчмарк regularized log-det.
- `apps/user_task_template` — шаблон пользовательской Python-задачи.
- `apps/python_task_runner` — общий BOINC runner для Python-задач.
- `scripts/` — подготовка, запуск, диагностика и очистка.
- `monitoring/` — Prometheus, Grafana, Loki и exporter.
- `server/` — BOINC server и MariaDB.

## BOINC-сущности

- `workunit` — уникальная задача.
- `result` — попытка выполнения workunit.
- `host` — зарегистрированный клиент.
- `app_version` — версия приложения под платформу клиента.
