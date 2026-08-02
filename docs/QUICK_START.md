# Быстрый старт

## 1. Подготовить конфиг

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

Проверь:

- `server.ip` — IP управляющей машины;
- `clients` — IP, пользователь и SSH-порт каждого клиента;
- `project.name` и `project.port`.

Минимальный пример для сервера и двух клиентов в одной сети:

```yaml
project:
  name: my_project
  port: 8080

server:
  ip: 172.17.12.151

clients:
  - name: node1
    ip: 172.17.12.152
    user: auser
  - name: node2
    ip: 172.17.12.153
    user: auser

boinc:
  client_rpc_password: auto

account:
  email: nodes@local.test
  name: nodes
  password: manual
```

Пример, если у всех клиентов нестандартный SSH-порт:

```yaml
project:
  name: my_project
  port: 8080

server:
  ip: 10.10.0.10

clients_defaults:
  port: 2222

clients:
  - name: node1
    ip: 10.10.0.11
    user: ubuntu
  - name: node2
    ip: 10.10.0.12
    user: ubuntu
  - name: node3
    ip: 10.10.0.13
    user: ubuntu

boinc:
  client_rpc_password: auto

account:
  email: nodes@local.test
  name: nodes
  password: manual
```

Пример, если SSH-порт отличается только у одного клиента:

```yaml
project:
  name: my_project
  port: 8080

server:
  ip: 192.168.1.10

clients:
  - name: node1
    ip: 192.168.1.11
    user: ubuntu
  - name: node2
    ip: 192.168.1.12
    user: ubuntu
    ssh_port: 2222

boinc:
  client_rpc_password: auto

account:
  email: nodes@local.test
  name: nodes
  password: manual
```

`server.ip` должен быть адресом, который видят клиенты. Если клиенты не могут
достучаться до сервера, BOINC сможет зарегистрироваться не полностью или не
будет скачивать задачи.

## 2. Подготовить систему

```bash
./scripts/prepare_system.sh --copy-ssh-keys
```

Скрипт создаёт `config/generated.env`, Ansible inventory, Vault и проверяет SSH к клиентам.

Если sudo на клиентах требует пароль:

```bash
./scripts/prepare_system.sh --copy-ssh-keys --ask-become-pass
```

## 3. Запустить кластер

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment
```

`quickstart --run-experiment` отправляет задачи и завершает работу. Он не ждёт окончания вычислений и не запускает `status.sh` автоматически.

Чтобы вместо шаблона пользовательской задачи отправить CPU-задачу:

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment --task determinant
```

Чтобы отправить grid search:

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment --task grid-search
```

## 4. Смотреть прогресс

```bash
./scripts/status.sh
./scripts/pump_clients.sh
```

`status.sh` показывает состояние. `pump_clients.sh` периодически делает BOINC project update, чтобы клиенты забирали следующую порцию задач.

## 5. Открыть интерфейсы

- BOINC: `http://SERVER_IP:8080/PROJECT_NAME/`
- Grafana: `http://SERVER_IP:3000/`
- Prometheus: `http://SERVER_IP:9090/`
- Loki: `http://SERVER_IP:3100/`

Grafana доступна без логина. Админский вход: `admin / admin`.

## Повторный запуск

Если конфиг и клиенты уже подготовлены:

```bash
./scripts/launch_cluster.sh --with-monitoring
```

Если нужно только отправить эксперимент:

```bash
./scripts/run_experiment.sh --submit-only
```

Если нужно отправить и дождаться завершения:

```bash
./scripts/run_experiment.sh
```

## Подробный вывод

У скриптов есть общий флаг:

```bash
./scripts/quickstart.sh --with-monitoring --debug
```

Без `--debug` вывод сокращён. С `--debug` видны подробности Docker Compose, Ansible и вспомогательных команд.
