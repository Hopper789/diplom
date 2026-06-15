# Конфигурация

## `config/cluster.yml`

Создаётся из примера:

```bash
cp config/cluster.example.yml config/cluster.yml
```

Главные поля:

```yaml
server:
  ip: 172.17.12.151
  port: 8080

clients:
  - name: node1
    ip: 172.17.12.152
    user: auser
    ssh_port: 22

boinc:
  project_name: my_project
  account_email: nodes@local.test
  account_name: nodes
  client_rpc_password: auto
```

Для клиентов поддерживаются поля `ip`, `host`, `hostname`, `ansible_host`, `user`, `username`, `ansible_user`, `ssh_port`, `ansible_port`.

## Добавление узлов во время работы

Новые клиентские узлы можно добавить без полной очистки кластера:

```bash
nano config/cluster.yml
./scripts/add_nodes.sh
```

Что происходит:

- `prepare_system.sh` пересобирает `ansible/inventory.ini` из `cluster.yml`;
- `bootstrap_clients.sh` устанавливает/запускает BOINC client на новых узлах и подключает их к проекту;
- `monitoring_up.sh` обновляет Prometheus targets и агенты мониторинга;
- `pump_clients.sh` просит клиентов забрать доступные задачи.

Если вся очередь уже выдана старым клиентам, новые узлы могут получить мало
задач или не получить их сразу. BOINC обычно не отбирает уже назначенные
result у работающих клиентов. Новые узлы начнут помогать, когда в очереди есть
невыданные result, появляются новые workunit или сервер перевыдаёт просроченные
/ ошибочные attempts.

Если на новых узлах ещё нет SSH-ключа управляющей машины:

```bash
./scripts/add_nodes.sh --copy-ssh-keys
```

По умолчанию скрипт не сбрасывает состояние существующих клиентов. Принудительный
сброс нужен редко:

```bash
./scripts/add_nodes.sh --reset-client-state
```

## Сгенерированные файлы

`prepare_system.sh` создаёт:

- `config/generated.env`;
- `ansible/inventory.ini`;
- `ansible/group_vars/all/main.yml`;
- `monitoring/.env`;
- `ansible/group_vars/all/vault.yml`;
- `ansible/.vault_pass`.

Обычно их не редактируют руками.

## `config/distributed.env`

Репликация и quorum:

```bash
DISTRIBUTED_TARGET_NRESULTS=1
DISTRIBUTED_MIN_QUORUM=1
DISTRIBUTED_MAX_SUCCESS_RESULTS=1
DISTRIBUTED_MAX_ERROR_RESULTS=3
DISTRIBUTED_MAX_TOTAL_RESULTS=3
```

Если нужно “2 успешных результата, третий только запасной”:

```bash
DISTRIBUTED_TARGET_NRESULTS=2
DISTRIBUTED_MIN_QUORUM=2
DISTRIBUTED_MAX_SUCCESS_RESULTS=2
DISTRIBUTED_MAX_TOTAL_RESULTS=3
```

`target_nresults` — сколько result BOINC старается держать сначала. `max_total_results=3` разрешает третью попытку при ошибке/таймауте, но не заставляет создавать её сразу.

BOINC может создать больше result-записей, чем уникальных workunit'ов. Это нормально: result — попытка выполнения, workunit — уникальная задача.

Серверный `config.xml` автоматически поддерживается с опцией
`one_result_per_host_per_wu`: BOINC не должен выдавать одному BOINC host больше
одной attempt одного workunit. Для этого важно, чтобы клиент сохранял стабильный
BOINC host id между перезапусками контейнера.

Максимальное время на возврат результата задаёт:

```bash
DISTRIBUTED_DELAY_BOUND=86400
```

Значение по умолчанию — 1 день. Это лимит BOINC-задачи, а не искусственная
длительность вычисления внутри Python-кода.

## MariaDB

Runtime-контейнер базы называется `boinc-mariadb`, service в compose — `mariadb`, данные лежат в `server/mariadb-data/`.
