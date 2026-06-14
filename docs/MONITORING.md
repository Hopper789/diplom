# Мониторинг

## Запуск

```bash
./scripts/monitoring_up.sh
```

Вместе с кластером:

```bash
./scripts/quickstart.sh --with-monitoring
```

Остановка:

```bash
./scripts/monitoring_down.sh
```

## Что запускается

На управляющей машине:

- Prometheus;
- Grafana;
- Loki;
- Promtail;
- `boinc-exporter`;
- Grafana renderer.

На клиентах:

- node-exporter;
- promtail.

CPU, RAM и сеть в Grafana считаются только по клиентским узлам через node-exporter. Нагрузка управляющей машины не собирается и не попадает в Prometheus.

## Grafana

Адрес:

```text
http://SERVER_IP:3000
```

Основной dashboard:

```text
/d/boinc-cluster/boinc
```

Dashboard ошибок:

```text
/d/boinc-errors/boinc-errors
```

Dashboard можно смотреть без логина. Админский вход: `admin / admin`.

## Основные метрики

Числовые панели считаются по последнему созданному batch workunit'ов. Поэтому
новый запуск эксперимента начинает эти значения заново, даже если старая история
остаётся в BOINC DB и на графиках.

Числовые панели:

- `Хосты` — hosts с назначенными незавершёнными BOINC result / всего зарегистрированных;
- `Готово` — процент workunit'ов с canonical result или набранным `min_quorum`;
- `Осталось` — примерная оценка оставшегося времени;
- `Ошибки` — процент workunit'ов с ошибкой;
- `Время на задачу` — среднее вычислительное время подтверждённой задачи;
- `Полезная нагрузка` — доля выполненного compute-time, потраченная на первые `min_quorum` успешных attempts; ожидание в очереди и доставка не учитываются, лишние реплики и ошибки снижают показатель;
- `% выданных задач` — доля всех result-записей очереди, уже назначенных хостам; учитывает репликацию и replacement-задачи после ошибок;
- `Факт. репликация` — attempts на workunit.

Графики:

- CPU min/avg/max по клиентским узлам;
- RAM min/avg/max по клиентским узлам;
- сеть min/avg/max по клиентским узлам;
- оставшиеся, завершённые и ошибочные workunit'ы.

## Loki

Loki собирает Docker JSON logs:

- с управляющей машины через `monitoring/promtail.yml`;
- с клиентов через promtail, установленный Ansible.

В окне ошибок Docker-логи берутся только из `stream="stderr"`. Логи BOINC project files не имеют поля `stream`, поэтому для них используется отдельный строгий фильтр по `[CRITICAL]`, ошибкам шаблонов, platform/app version и отсутствующим output-файлам. Штатный шум запуска Grafana/Loki/MariaDB и сообщение `Project has no tasks available` не считаются ошибками.

Пример LogQL:

```logql
{cluster="boinc", stream="stderr"} |= "ERROR"
```

## Проверка

```bash
./scripts/status.sh
curl -s http://SERVER_IP:9101/metrics | grep boinc_
curl -s http://SERVER_IP:9090/api/v1/targets
```

## Dump графиков и финальных метрик

```bash
./scripts/dump_grafana_results.sh --wait --max-seconds 600
```

Результаты сохраняются в `reports/grafana/`.

По умолчанию dump работает тихо. Для подробностей:

```bash
./scripts/dump_grafana_results.sh --wait --debug
```
