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

Максимальное время на возврат результата задаёт:

```bash
DISTRIBUTED_DELAY_BOUND=86400
```

Значение по умолчанию — 1 день. Это лимит BOINC-задачи, а не искусственная
длительность вычисления внутри Python-кода.

## MariaDB

Runtime-контейнер базы называется `boinc-mariadb`, service в compose — `mariadb`, данные лежат в `server/mariadb-data/`.
