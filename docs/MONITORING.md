# Мониторинг

Мониторинг нужен, чтобы видеть не только факт завершения задач, но и нагрузку клиентов.

## Что запускается

- `boinc-exporter` — отдаёт BOINC-метрики из MariaDB;
- Prometheus — собирает временные ряды;
- Loki — хранит логи контейнеров;
- Promtail — собирает Docker logs на управляющей машине и клиентах;
- Grafana — показывает dashboard;
- Grafana image renderer — сохраняет панели dashboard в PNG;
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
Loki:       http://SERVER_IP:3100
```

Dashboard Grafana можно смотреть без логина. Для администрирования:

```text
admin / admin
```

Основные dashboard:

```text
BOINC Cluster: http://SERVER_IP:3000/d/boinc-cluster/boinc-cluster
BOINC Errors:  http://SERVER_IP:3000/d/boinc-errors/boinc-errors
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
curl -s http://SERVER_IP:3100/ready
```

## Логи и ошибки

Loki хранит логи контейнеров. Promtail собирает Docker logs:

- на управляющей машине — server, MariaDB, exporter, Prometheus, Grafana, Loki;
- на клиентских узлах — `boinc-client` и monitoring agents.

Открыть dashboard ошибок:

```text
http://SERVER_IP:3000/d/boinc-errors/boinc-errors
```

Пример LogQL-запроса:

```logql
{cluster="boinc"} |~ "(?i)(error|failed|exception|traceback|fatal|panic|timeout|denied|refused)"
```

Подробнее: [Error handling](ERROR_HANDLING.md).

## Dump графиков и итоговых метрик

После завершения всех вычислений `run_experiment.sh` пытается автоматически сохранить:

- PNG всех панелей Grafana dashboards;
- `final_metrics.md` с итоговыми метриками из нижнего блока `BOINC Cluster`;
- `final_metrics.json` с сырыми ответами Prometheus;
- копии dashboard JSON.

Путь:

```text
reports/grafana_dumps/<timestamp>/
```

Ручной запуск:

```bash
./scripts/dump_grafana_results.sh --wait --max-seconds 600
```

Полезные переменные:

```bash
BOINC_AUTO_DUMP_RESULTS=0      # отключить автоматический dump в run_experiment.sh
BOINC_DUMP_WAIT_SECONDS=600    # сколько ждать завершения перед dump; по умолчанию как BOINC_AUTO_UPDATE_SECONDS
GRAFANA_DUMP_FROM=now-6h       # диапазон рендера графиков
GRAFANA_DUMP_TO=now
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
