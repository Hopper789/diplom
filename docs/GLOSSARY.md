# Glossary

Короткий словарь терминов BOINC и этого репозитория.

## BOINC

| Термин | Значение |
|---|---|
| `project` | BOINC-проект. Серверная область с приложениями, пользователями, задачами и результатами. URL обычно выглядит как `http://SERVER_IP:8080/PROJECT_NAME/`. |
| `app` | Приложение BOINC внутри проекта. Например, `ml_grid_search` или `python_task_runner`. |
| `app version` | Конкретная версия приложения для платформы BOINC. BOINC выдаёт задачи только если есть подходящая app version. |
| `platform` | Платформа выполнения приложения, например `x86_64-pc-linux-gnu`. |
| `workunit` / `WU` | Логическая единица работы. В ней описаны входные файлы, ограничения ресурсов и правила выдачи. |
| `result` | Конкретная попытка выполнить workunit на клиенте. Один workunit может иметь один или несколько results. |
| `host` | Клиентский узел, зарегистрированный в BOINC project. |
| `scheduler` | BOINC-компонент, который отвечает на запросы клиентов и выдаёт им results. |
| `feeder` | BOINC-компонент, который держит очередь задач для scheduler. |
| `transitioner` | BOINC-компонент, который переводит workunits/results между состояниями. |
| `validator` | BOINC-компонент, который проверяет результаты. |
| `assimilator` | BOINC-компонент, который забирает подтверждённые результаты для дальнейшей обработки. |

## Задачи и результаты

| Термин | Значение |
|---|---|
| `target_nresults` | Сколько result-записей BOINC старается держать для одного workunit. Это целевая стартовая выдача, а не верхний лимит. |
| `min_quorum` | Сколько успешных совпадающих результатов нужно для подтверждения workunit. |
| `max_success_results` | Максимум успешных results для одного workunit. |
| `max_error_results` | Сколько ошибочных попыток допускается до остановки выдачи. |
| `max_total_results` | Общий лимит result-записей для одного workunit. Для схемы "2 из 3" обычно `target_nresults=2`, `min_quorum=2`, `max_success_results=2`, `max_total_results=3`. |
| `delay_bound` | Максимальное время, за которое клиент должен вернуть result. |
| `server_state` | Состояние result на сервере: выдан, не выдан, завершён и так далее. |
| `client_state` | Состояние result с точки зрения клиента. |
| `outcome` | Итог result: успешно, ошибка, не завершён и так далее. |
| `outcome=5` / `didnt_need` | Лишний result, который больше не нужен после quorum/replication. Обычно это не ошибка клиента. |
| `turnaround` | Время от выдачи result клиенту до возврата на сервер. |
| `compute time` | Время фактического вычисления задачи клиентом. |
| `overhead` | Накладные расходы: ожидание, передача, scheduler/client update и другая невычислительная часть. |

## Шаблоны BOINC

| Термин | Значение |
|---|---|
| `input template` | XML-шаблон входа workunit. В нём должны быть блоки `<file_info>` и `<workunit>`. |
| `output template` | XML-шаблон выходных файлов result. |
| `logical name` | Имя файла внутри BOINC template, например `input.json`. |
| `physical file` | Реальный файл в project upload/download directory. |

## Инфраструктура репозитория

| Термин | Значение |
|---|---|
| `control machine` | Управляющая машина, на которой запускаются скрипты, BOINC server, MariaDB и мониторинг. |
| `client node` | Машина, на которой запускается контейнер `boinc-client`. |
| `prepare_system.sh` | Этап подготовки: config, Vault, SSH, inventory, системные пакеты на клиентах. |
| `launch_cluster.sh` | Этап запуска: BOINC server, clients, monitoring и experiment. |
| `quickstart.sh` | Полный сценарий: подготовка + запуск. |
| `generated.env` | Сгенерированные переменные runtime. |
| `inventory.ini` | Сгенерированный Ansible inventory клиентов. |
| `group_vars` | Сгенерированные Ansible-переменные. |
| `Vault` | Зашифрованные секреты Ansible, например sudo-пароль клиентов. |

## Мониторинг и логи

| Термин | Значение |
|---|---|
| `Prometheus` | Хранит числовые метрики. |
| `Grafana` | Показывает dashboard по метрикам и логам. |
| `Loki` | Хранит логи контейнеров. |
| `Promtail` | Собирает Docker logs и отправляет их в Loki. |
| `boinc-exporter` | Экспортирует BOINC-метрики из MariaDB в Prometheus. |
| `node-exporter` | Метрики ОС клиентских узлов. |
| `cAdvisor` | Метрики Docker-контейнеров. |
