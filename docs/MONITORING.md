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

## Основные окна dashboard

Верхняя строка показывает состояние системы: доступность БД и HTTP, количество hosts, workunits и results.

Вторая строка показывает прогресс и конфигурацию:

- `Finished results` — сколько result-записей завершилось;
- `Error results` — сколько result-записей завершилось ошибкой;
- `Replication` — значение `DISTRIBUTED_TARGET_NRESULTS` из `config/distributed.env`;
- `Min quorum` — значение `DISTRIBUTED_MIN_QUORUM` из `config/distributed.env`;
- `Avg compute/WU` — среднее время непосредственного выполнения задачи;
- `Avg overhead/WU` — среднее время накладных расходов на одну workunit.

`Avg overhead/WU` считается как полное время возврата результата минус время вычисления. Если BOINC schema не отдаёт `elapsed_time`, exporter использует `TASK_SECONDS` из `config/experiment.env` как приближение времени вычисления.

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
| `boinc_queue_remaining_total` | сколько results остаётся незавершёнными |
| `boinc_results_unsent_total` | results, ещё не назначенные клиентам |
| `boinc_results_assigned_total` | results, назначенные клиентам |
| `boinc_results_in_progress_total` | назначенные, но ещё не завершённые results |
| `boinc_completed_workunits_total` | число workunit, у которых есть успешный результат |
| `boinc_effective_completion_ratio` | доля завершённых workunits |
| `boinc_avg_success_turnaround_seconds` | среднее время от создания result до получения результата |
| `boinc_p95_success_turnaround_seconds` | 95-й процентиль времени возврата результата |
| `boinc_avg_compute_time_per_workunit_seconds` | среднее время вычисления на одну workunit |
| `boinc_avg_overhead_time_per_workunit_seconds` | средние накладные расходы на одну workunit |
| `boinc_config_replication_factor` | настроенная репликация из `config/distributed.env` |
| `boinc_config_min_quorum` | настроенный quorum из `config/distributed.env` |

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

В этой версии основная метрика `Replication` берётся из файла `config/distributed.env`:

```text
boinc_config_replication_factor = DISTRIBUTED_TARGET_NRESULTS
```

`Min quorum` также вынесен в отдельное числовое окно:

```text
boinc_config_min_quorum = DISTRIBUTED_MIN_QUORUM
```

Дополнительно exporter отдаёт фактическое среднее число result-записей на одну workunit:

```text
boinc_actual_results_per_workunit
```

Это полезно для проверки: настроенная репликация показывает желаемое поведение, а actual results/workunit показывает, что реально получилось в BOINC-БД.

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
- `boinc_results_error_total` растёт — приложение или окружение нестабильны;
- `boinc_config_replication_factor` показывает выбранный уровень репликации;
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

## Особенности cAdvisor в этой версии

На разных версиях Docker/cAdvisor имена контейнеров могут попадать в метрики по-разному. Иногда label `name="boinc-client"` отсутствует, хотя сами метрики cAdvisor есть. Поэтому dashboard использует более устойчивые агрегированные запросы:

```promql
sum by(instance) (rate(container_cpu_usage_seconds_total{job="cadvisor_clients",id!="/"}[1m]))
```

и:

```promql
sum by(instance) (container_memory_usage_bytes{job="cadvisor_clients",id!="/"})
```

Эти панели называются `Client cAdvisor CPU` и `Client cAdvisor memory`. Они показывают суммарную нагрузку cAdvisor-tracked cgroups/containers на клиенте. Для учебного стенда этого достаточно, чтобы видеть дополнительную активность контейнерного окружения. Основную нагрузку вычислительного узла лучше оценивать по `Client CPU usage` и `Client memory usage` из node-exporter.

## Почему throughput считается через `delta`

BOINC exporter отдаёт накопленные значения, например `boinc_results_success_total` и `boinc_completed_workunits_total`, как gauge. Поэтому в Grafana для скорости завершения задач используется:

```promql
clamp_min(delta(boinc_completed_workunits_total[1m]), 0)
```

Это показывает, сколько workunit завершилось за последнюю минуту. `clamp_min` нужен, чтобы при очистке runtime или пересоздании проекта график не уходил в отрицательные значения.

## Проверка, что все источники мониторинга работают

```bash
curl -s http://localhost:9090/api/v1/targets | grep -E "node_exporter|cadvisor|boinc" -n
curl -s http://localhost:9101/metrics | grep boinc_
curl -s http://CLIENT_IP:9100/metrics | grep node_cpu_seconds_total | head
curl -s http://CLIENT_IP:8081/metrics | grep container_cpu_usage_seconds_total | head
```

Если Prometheus target имеет `health: up`, значит источник метрик доступен. Если в Grafana отдельная панель показывает `No data`, сначала проверь PromQL-запрос в Explore: часто проблема не в exporter, а в label-ах конкретной версии cAdvisor.
