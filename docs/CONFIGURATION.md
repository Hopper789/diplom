# Конфигурация

В проекте есть два основных конфигурационных файла:

```text
config/cluster.yml      # машины кластера и BOINC project
config/experiment.env   # параметры вычислительного эксперимента
```

Оба файла локальные и не должны коммититься в Git.

## config/cluster.yml

Создаётся из примера:

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

Пример:

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

boinc:
  client_rpc_password: auto

account:
  email: nodes@local.test
  name: nodes
  password: manual
```

### project.name

Имя BOINC project. Оно используется в URL:

```text
http://SERVER_IP:8080/my_project/
```

### server.ip

IP управляющей машины, на которой запускается BOINC server. Этот IP должен быть доступен клиентам.

### clients

Список вычислительных узлов. Для каждого клиента указываются:

- `name` — понятное имя узла;
- `ip` — IP адрес;
- `user` — SSH-пользователь с sudo-доступом.

### account

Один BOINC account используется для подключения всех клиентов. Скрипт `create_account_db.sh` создаёт его в MariaDB и сохраняет `authenticator` как `BOINC_ACCOUNT_KEY`.

## Сгенерированные файлы

После запуска:

```bash
./scripts/init_config.sh
```

создаются:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all/main.yml
monitoring/.env
```

Эти файлы генерируются автоматически и не коммитятся.

## config/experiment.env

Создаётся из примера:

```bash
cp config/experiment.example.env config/experiment.env
nano config/experiment.env
```

Основные параметры:

```env
EXPERIMENT_WALL_SECONDS=180
EXPERIMENT_CORES=12
TASK_SECONDS=8
TASK_COUNT=
TASK_DATASET_SIZE=500
TASK_SEED_BASE=1000
```

Если `TASK_COUNT` пустой, число задач считается так:

```text
ceil(EXPERIMENT_WALL_SECONDS * EXPERIMENT_CORES / TASK_SECONDS)
```

Например:

```text
180 * 12 / 8 = 270 workunits
```

## Как менять размер эксперимента

Больше задач:

```env
EXPERIMENT_WALL_SECONDS=600
```

Более короткие задачи:

```env
TASK_SECONDS=4
```

Точное число задач вручную:

```env
TASK_COUNT=1000
```
