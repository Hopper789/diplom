# Мониторинг и метрики

Мониторинг нужен, чтобы видеть не только факт выполнения задач, но и поведение распределённой системы во времени: сколько задач создано, сколько завершилось, сколько клиентов активно и насколько загружены вычислительные узлы.

В проекте используются:

- `boinc-exporter` — собственный exporter, который читает BOINC MariaDB и отдаёт метрики проекта;
- `node-exporter` на каждом клиенте — нагрузка хоста: CPU, RAM, load average, сеть, диск;
- `cAdvisor` на каждом клиенте — нагрузка Docker-контейнера `boinc-client`;
- Prometheus — собирает метрики;
- Grafana — показывает dashboard.

## Запуск

Сначала должны быть подняты сервер и клиенты:

```bash
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
```

Потом включается мониторинг:

```bash
./scripts/monitoring_up.sh
```

Если нет файла `ansible/.vault_pass`, передай Vault-пароль вручную:

```bash
./scripts/monitoring_up.sh --ask-vault-pass
```

Скрипт делает три вещи:

1. устанавливает на клиентах `node-exporter` и `cAdvisor` через Ansible;
2. генерирует `monitoring/prometheus.yml` по IP из `ansible/inventory.ini`;
3. запускает `boinc-exporter`, Prometheus, Grafana и серверный cAdvisor.

После запуска доступны:

```text
Prometheus: http://localhost:9090
Grafana:    http://localhost:3000
Exporter:   http://localhost:9101/metrics
```

Логин Grafana:

```text
admin / admin
```

## Что показывает BOINC exporter

Основные метрики BOINC:

| Метрика | Смысл |
|---|---|
| `boinc_db_up` | доступна ли MariaDB |
| `boinc_project_http_up` | доступна ли web-страница проекта |
| `boinc_users_total` | число пользователей BOINC |
| `boinc_hosts_total` | число зарегистрированных клиентов |
| `boinc_hosts_active_recent_total` | число клиентов, недавно выходивших на связь |
| `boinc_workunits_total` | число логических задач workunit |
| `boinc_results_total` | число result-записей, то есть попыток выполнения |
| `boinc_results_success_total` | число успешно завершённых results |
| `boinc_results_error_total` | число ошибочных results |
| `boinc_results_unfinished_total` | число незавершённых results |
| `boinc_results_unsent_total` | results, ещё не назначенные клиентам |
| `boinc_results_assigned_total` | results, назначенные клиентам |
| `boinc_results_in_progress_total` | назначенные, но ещё не завершённые results |
| `boinc_success_rate` | доля успешных результатов среди завершённых |
| `boinc_error_rate` | доля ошибок среди завершённых |
| `boinc_replication_overhead` | `results_total / workunits_total` |
| `boinc_completed_workunits_total` | число workunit, у которых есть успешный результат |
| `boinc_effective_completion_ratio` | доля завершённых workunits |
| `boinc_avg_success_turnaround_seconds` | среднее время от создания result до получения результата |
| `boinc_p95_success_turnaround_seconds` | 95-й процентиль времени возврата результата |

## Метрики репликации задач

BOINC различает `workunit` и `result`.

- `workunit` — логическая задача;
- `result` — конкретная попытка выполнить эту задачу на клиенте.

Без репликации обычно:

```text
1 workunit -> 1 result
```

С репликацией:

```text
1 workunit -> 2 или больше result
```

Поэтому важная метрика:

```text
replication_overhead = results_total / workunits_total
```

Если значение около `1.0`, репликации почти нет. Если около `2.0`, каждая задача в среднем считается дважды.

Дополнительно exporter отдаёт усреднённые параметры из таблицы `workunit`:

- `boinc_target_nresults_avg`;
- `boinc_min_quorum_avg`;
- `boinc_max_success_results_avg`;
- `boinc_max_error_results_avg`;
- `boinc_max_total_results_avg`.

Эти метрики помогают сравнивать конфигурации BOINC с разной надёжностью и накладными расходами.

## Метрики нагрузки клиентов

`node-exporter` показывает состояние машины целиком.

Примеры PromQL:

```promql
100 * (1 - avg by(instance) (rate(node_cpu_seconds_total{job="node_exporter_clients",mode="idle"}[1m])))
```

CPU-загрузка клиента.

```promql
100 * (1 - node_memory_MemAvailable_bytes{job="node_exporter_clients"} / node_memory_MemTotal_bytes{job="node_exporter_clients"})
```

Использование RAM.

```promql
node_load1{job="node_exporter_clients"}
```

Load average за 1 минуту.

`cAdvisor` показывает нагрузку Docker-контейнеров. Для BOINC-клиента полезны:

```promql
rate(container_cpu_usage_seconds_total{job="cadvisor_clients",name="boinc-client"}[1m])
```

CPU, который потребляет контейнер `boinc-client`.

```promql
container_memory_usage_bytes{job="cadvisor_clients",name="boinc-client"}
```

RAM, которую потребляет контейнер `boinc-client`.

## Как интерпретировать графики

Для распределённой системы полезно смотреть метрики вместе:

- CPU клиентов высокий, очередь уменьшается — система считает эффективно;
- CPU низкий, но `boinc_results_unfinished_total` высокий — клиенты не получают задачи или есть проблема scheduler/update;
- `boinc_error_rate` растёт — приложение или окружение нестабильны;
- `boinc_replication_overhead` растёт — надёжность повышается, но расход ресурсов увеличивается;
- `boinc_hosts_active_recent_total` меньше `boinc_hosts_total` — часть клиентов зарегистрирована, но неактивна.

## Остановка

Остановить серверный мониторинг:

```bash
./scripts/monitoring_down.sh
```

Остановить также агенты на клиентах:

```bash
./scripts/monitoring_down.sh --with-client-agents
```
