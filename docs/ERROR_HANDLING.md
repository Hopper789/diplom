# Error handling

Ошибки в BOINC-кластере теперь смотрятся в двух местах:

- `./scripts/status.sh` — краткое состояние сервера, клиентов, задач, мониторинга и Loki;
- Grafana dashboard `BOINC Errors` — логи и категории ошибок из Loki.

## Запуск с логами

```bash
./scripts/quickstart.sh --with-monitoring
```

или для уже подготовленного кластера:

```bash
./scripts/launch_cluster.sh --with-monitoring
```

Grafana:

```text
http://SERVER_IP:3000/d/boinc-errors/boinc-errors
```

Loki:

```text
http://SERVER_IP:3100
```

## Что собирается

Promtail собирает Docker logs:

- на управляющей машине: `boinc-server`, `boinc-mysql`, `boinc-exporter`, Grafana, Prometheus, Loki и другие контейнеры;
- на клиентских узлах: `boinc-client`, `boinc-client-cadvisor`, `boinc-node-exporter`, `boinc-client-promtail`.

Все логи получают labels:

```text
cluster="boinc"
node="control" или имя клиента из inventory
node_role="server" или "client"
job="docker" или "boinc-project-logs"
```

## Категории ошибок

Dashboard `BOINC Errors` группирует типовые ошибки:

Dashboard показывает только Docker logs со `stream="stderr"`, чтобы stdout-сообщения
не забивали окно ошибок.

| Категория | Что ищет |
|---|---|
| `templates/workunits` | `bad WU template`, `no <file_info>`, `no <workunit>`, `create_work`, `xadd`, `update_versions` |
| `client/rpc` | `boinccmd`, `project attach`, `scheduler request failed`, `gui_rpc_auth` |
| `database` | `mariadb`, `mysql`, `database`, `connection refused` |
| `docker/permissions` | `no such container`, `cannot connect to docker`, `permission denied`, `pull access denied` |
| `ansible/ssh` | `ansible`, `ssh`, `unreachable`, `host key verification`, `failed to connect` |

## Полезные LogQL-запросы

Все ошибки:

```logql
{cluster="boinc"} |~ "(?i)(error|failed|exception|traceback|fatal|panic|timeout|denied|refused)"
```

BOINC daemon logs:

```logql
{job="boinc-project-logs"}
```

Логи серверных Docker-контейнеров:

```logql
{cluster="boinc", job="docker", node_role="server"}
```

Логи клиентов:

```logql
{cluster="boinc", node_role="client"}
```

Ошибки шаблонов workunit:

```logql
{cluster="boinc"} |~ "(?i)(bad WU template|no <file_info>|no <workunit>|create_work)"
```

Ошибки Docker и прав:

```logql
{cluster="boinc"} |~ "(?i)(docker.*error|no such container|cannot connect to docker|permission denied|pull access denied)"
```

## Если Loki пустой

Проверь, что запущены Loki и Promtail:

```bash
docker ps --filter name=boinc-loki
docker ps --filter name=boinc-promtail
./scripts/status.sh
```

Если нужны логи клиентов, monitoring agents должны быть развёрнуты:

```bash
./scripts/monitoring_up.sh
```

Если агенты уже были запущены до добавления Loki, перезапусти их:

```bash
./scripts/monitoring_down.sh --with-client-agents
./scripts/monitoring_up.sh
```

Если в `docker logs boinc-promtail` или `docker logs boinc-client-promtail`
видно `client version 1.42 is too old`, пересоздай monitoring stack и agents.
Актуальная конфигурация Promtail читает Docker JSON logs напрямую и не использует
Docker socket API:

```bash
./scripts/monitoring_down.sh --with-client-agents
./scripts/monitoring_up.sh --force-recreate
```
