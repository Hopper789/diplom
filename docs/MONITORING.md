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

Логи BOINC-вычислений:

```text
/d/boinc-logs/boinc-logs
```

Логи мониторинга и инфраструктуры:

```text
/d/monitoring-logs/monitoring-logs
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
- `Время на задачу` — среднее вычислительное время подтверждённой задачи без ошибочных attempts;
- `Полезная нагрузка` — доля compute-time первой успешной attempt на workunit; локальное ожидание заранее выданных задач вычитается, реплики и ошибки считаются накладными расходами;
- `% выданных задач` — доля всех result-записей очереди, уже назначенных хостам; учитывает репликацию и replacement-задачи после ошибок;
- `Факт. репликация` — attempts на workunit.
- `Общее время вычислений` — сумма compute-time всех завершённых attempts текущего эксперимента, включая реплики и ошибки.

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

## Log dashboards

`BOINC Logs` показывает scheduler/feeder/transitioner/file upload логи, BOINC workunit/client ошибки и сообщения, связанные с вычислениями. Его используют для анализа задач, репликации, выдачи workunit'ов и ошибок клиентов.

`Monitoring Logs` показывает Loki, Grafana, Promtail, Prometheus, Docker, Ansible и SSH. Его используют для диагностики инфраструктуры мониторинга и деплоя. Числовая панель считает только существенные сбои вроде `failed to connect`, `unreachable`, `permission denied`, `pull access denied` и `statusCode=500`. Сообщения `context canceled`, `scheduler_processor.go`, `retry.go`, `EOF` и похожие записи обычно относятся к обработке запросов Loki/Grafana; они остаются в общей панели Docker-логов, но не считаются авариями мониторинга, не попадают в панели query/internal failures и не означают падение BOINC-задачи.

Если Loki пишет строку вида `retry.go ... query="...permission denied..." err="context canceled"`, это отменённый Grafana/Loki-запрос. Слова внутри `query="..."` являются текстом фильтра, а не найденной ошибкой в системе.

У `Monitoring Logs` refresh выставлен в `30s`, чтобы сами панели реже провоцировали отменённые Loki-запросы при автообновлении.

После изменения dashboard'ов перезапустите мониторинг:

```bash
./scripts/monitoring_down.sh
./scripts/monitoring_up.sh
```

Если Grafana уже запущена и нужно только перечитать provisioning:

```bash
docker restart boinc-grafana
```

Проверка:

```text
http://SERVER_IP:3000/d/boinc-logs/boinc-logs
http://SERVER_IP:3000/d/monitoring-logs/monitoring-logs
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
