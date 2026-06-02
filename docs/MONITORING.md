# Мониторинг

Мониторинг нужен, чтобы видеть не только факт завершения задач, но и нагрузку клиентов.

## Что запускается

- `boinc-exporter` — отдаёт BOINC-метрики из MariaDB;
- Prometheus — собирает временные ряды;
- Grafana — показывает dashboard;
- node-exporter на клиентах — CPU, RAM, load average, сеть, диск;
- cAdvisor на клиентах — нагрузка Docker-контейнеров.

## Запуск

Основная команда:

```bash
./scripts/quickstart.sh --with-monitoring
```

Раздельная команда:

```bash
./scripts/launch_cluster.sh --with-monitoring
```

Ручная команда для отладки:

```bash
./scripts/monitoring_up.sh
```

Адреса:

```text
Prometheus: http://SERVER_IP:9090
Grafana:    http://SERVER_IP:3000
Exporter:   http://SERVER_IP:9101/metrics
```

Dashboard Grafana можно смотреть без логина. Для администрирования:

```text
admin / admin
```

## Основные BOINC-метрики

| Метрика | Смысл |
|---|---|
| `boinc_db_up` | доступна ли MariaDB |
| `boinc_project_http_up` | доступна ли web-страница проекта |
| `boinc_hosts_total` | число зарегистрированных клиентов |
| `boinc_workunits_total` | число workunits |
| `boinc_results_total` | число result-записей |
| `boinc_results_success_total` | успешные results |
| `boinc_results_error_total` | ошибочные results |
| `boinc_results_unfinished_total` | незавершённые results |
| `boinc_completed_workunits_total` | workunits с успешным результатом |
| `boinc_avg_success_turnaround_seconds` | среднее время возврата результата |
| `boinc_p95_success_turnaround_seconds` | p95 времени возврата результата |
| `boinc_avg_compute_time_per_workunit_seconds` | среднее вычислительное время |
| `boinc_avg_overhead_time_per_workunit_seconds` | средние накладные расходы |

## Быстрая проверка

```bash
curl -s http://SERVER_IP:9101/metrics | grep boinc_
```

## Остановка

```bash
./scripts/monitoring_down.sh
```

Остановить также агенты на клиентах:

```bash
./scripts/monitoring_down.sh --with-client-agents
```

Очистка server runtime и monitoring stack:

```bash
./scripts/clean_runtime.sh
```

## Telegram alerts

Telegram alerts не запускаются автоматически через обычный quickstart.

Если нужно получить сообщение о завершении эксперимента:

```bash
cp config/alerts.example.env config/alerts.env
nano config/alerts.env
./scripts/alerts_up.sh
```

Подробнее: [Telegram alerts](ALERTS.md).
