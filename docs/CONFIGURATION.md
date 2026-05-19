# Конфигурация кластера

Основной файл конфигурации:

```text
config/cluster.yml
```

Создаётся из примера:

```bash
cp config/cluster.example.yml config/cluster.yml
```

## Пример

```yaml
project:
  name: my_project
  port: 8080

server:
  ip: 192.168.1.209
  user: hopper

clients:
  - name: laptop
    ip: 192.168.1.189
    user: hopper

  - name: node2
    ip: 192.168.1.190
    user: ubuntu

boinc:
  rpc_password: auto
  account_email: nodes@local.test
  account_password: manual
  account_name: nodes
```

## `project`

```yaml
project:
  name: my_project
  port: 8080
```

- `name` — имя BOINC-проекта.
- `port` — порт Web UI.

Итоговый URL:

```text
http://SERVER_IP:PORT/PROJECT_NAME/
```

## `server`

```yaml
server:
  ip: 192.168.1.209
  user: hopper
```

- `ip` — IP серверной машины, доступный всем клиентам.
- `user` — SSH-пользователь серверной машины.

Для реального кластера нельзя использовать:

```text
localhost
127.0.0.1
172.17.0.1
host.docker.internal
```

Нужно использовать LAN IP, например:

```text
192.168.1.209
```

## `clients`

Один клиент:

```yaml
clients:
  - name: laptop
    ip: 192.168.1.189
    user: hopper
```

Несколько клиентов:

```yaml
clients:
  - name: node1
    ip: 192.168.1.101
    user: ubuntu

  - name: node2
    ip: 192.168.1.102
    user: ubuntu

  - name: node3
    ip: 192.168.1.103
    user: student
```

Каждый клиент должен быть доступен по SSH:

```bash
ssh user@client_ip
```

## `boinc`

```yaml
boinc:
  rpc_password: auto
  account_email: nodes@local.test
  account_password: manual
  account_name: nodes
```

- `rpc_password` — пароль RPC-интерфейса BOINC clients.
- `account_email` — email BOINC-пользователя.
- `account_password` — справочное поле, если пользователь создаётся вручную.
- `account_name` — имя BOINC-пользователя.

Рекомендуется:

```yaml
rpc_password: auto
```

## Генерируемые файлы

После запуска:

```bash
./scripts/init_config.sh
```

создаются:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all.yml
```

`config/generated.env` содержит секреты и не должен храниться в Git.
