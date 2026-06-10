# Быстрый старт

## 1. Подготовить конфиг

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

Проверь:

- `server.ip` — IP управляющей машины;
- `clients` — IP, пользователь и SSH-порт каждого клиента;
- `boinc.project_name` и `boinc.project_url_base`.

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

`quickstart --run-experiment` теперь только отправляет задачи и завершает работу. Он не ждёт 10 минут и не запускает `status.sh` автоматически.

Чтобы вместо шаблона пользовательской задачи отправить CPU-бенчмарк:

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment --task determinant --workunits 2
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
