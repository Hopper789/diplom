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
- node-exporter;
- Grafana renderer.

На клиентах:

- node-exporter;
- promtail.

CPU, RAM и сеть в Grafana считаются по управляющей машине и клиентским узлам через node-exporter. Контейнерная нагрузка cAdvisor больше не используется в основном дашборде.

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

Числовые панели:

- `Хосты` — активные / всего зарегистрированных;
- `Готово` — процент завершённых workunit'ов;
- `Осталось` — примерная оценка оставшегося времени;
- `Ошибки` — процент workunit'ов с ошибкой;
- `Время` — среднее вычислительное время workunit;
- `Полезная нагрузка` — доля времени успешных attempts, потраченная на саму функцию `run(params)`;
- `Пропускная способность` — завершённые задачи в секунду, `задач/с`;
- `Факт. репликация` — attempts на workunit.

Графики:

- CPU min/avg/max по управляющей машине и клиентским узлам;
- RAM min/avg/max по управляющей машине и клиентским узлам;
- сеть min/avg/max по управляющей машине и клиентским узлам;
- оставшиеся, завершённые и ошибочные workunit'ы.

## Loki

Loki собирает Docker JSON logs:

- с управляющей машины через `monitoring/promtail.yml`;
- с клиентов через promtail, установленный Ansible.

В окне ошибок используются только записи с `stream="stderr"`.

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
