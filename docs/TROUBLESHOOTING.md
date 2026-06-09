# Диагностика

## С чего начать

```bash
./scripts/status.sh
./scripts/check_client_runtime.sh
```

Если обычного вывода мало:

```bash
./scripts/status.sh --debug
./scripts/launch_cluster.sh --with-monitoring --debug
```

## SSH к клиентам не работает

Проверь `config/cluster.yml`: IP, пользователь, `ssh_port`.

```bash
./scripts/prepare_system.sh --copy-ssh-keys --debug
```

Если порт не 22, он должен быть указан в `cluster.yml`. Сгенерированный `ansible/inventory.ini` должен содержать `ansible_port=...`.

## Docker Hub timeout

Типичный текст:

```text
failed to fetch anonymous token
TLS handshake timeout
```

Это сетевой сбой доступа к Docker Hub с сервера. Обычно помогает повторить запуск. Если проблема стабильная:

- проверь DNS/прокси на сервере;
- заранее подтяни образы вручную;
- используй локальный registry/cache;
- запусти с `--debug`, чтобы увидеть точную команду.

## MariaDB не поднялась

Проверь контейнер:

```bash
docker ps --filter name=boinc-mariadb
docker logs boinc-mariadb --tail 100
```

Полная очистка runtime:

```bash
./scripts/clean_runtime.sh --server-only
./scripts/launch_cluster.sh --with-monitoring
```

## Сервер не видит клиентов

Сначала проверь Ansible и клиентский runtime:

```bash
ansible -i ansible/inventory.ini boinc_clients -m ping
./scripts/check_client_runtime.sh
```

Потом перезапусти подключение клиентов:

```bash
./scripts/bootstrap_clients.sh
```

## Задачи есть, но клиенты их не берут

```bash
./scripts/pump_clients.sh --debug
```

Смотри в `status.sh`:

- есть ли `active_hosts`;
- есть ли подходящая `app_version`;
- нет ли `This project doesn't support computers of type...`;
- не стоят ли задачи в `uninitialized`.

## BOINC-клиент пишет `suspended`

BOINC может остановиться из-за своих preferences: non-BOINC CPU load, память, питание, режим использования. Повтори bootstrap, он применяет локальные настройки клиента:

```bash
./scripts/bootstrap_clients.sh
```

## Grafana пустая

Проверь targets Prometheus:

```bash
curl -s http://SERVER_IP:9090/api/v1/targets
```

Проверь exporter:

```bash
curl -s http://SERVER_IP:9101/metrics | grep boinc_db_up
```

После изменения dashboard или datasource перезапусти мониторинг:

```bash
./scripts/monitoring_down.sh
./scripts/monitoring_up.sh --force-recreate
```

## Loki пустой

Проверь API:

```bash
curl -s http://SERVER_IP:3100/loki/api/v1/labels
```

Проверь promtail:

```bash
docker logs boinc-promtail --tail 100
```

На клиентах:

```bash
./scripts/deploy_monitoring_agents.sh --debug
```

## Ошибки results растут

Смотри последние сообщения клиентов:

```bash
./scripts/status.sh --debug
```

Частые причины:

- output-файл не создан;
- app version не подходит платформе;
- клиент не скачал приложение;
- задача падает с исключением;
- не совпадают шаблоны input/output.

## Полная очистка

Оставить установленные клиенты, но сбросить runtime:

```bash
./scripts/clean_runtime.sh
```

Полностью удалить BOINC client с клиентских узлов:

```bash
./scripts/clean_runtime.sh --purge-clients
```
