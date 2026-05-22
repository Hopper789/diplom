# BOINC Cluster: monitoring and no local Docker client

## Быстрый запуск

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

chmod +x scripts/*.sh
chmod +x server/entrypoint.sh
chmod +x server/scripts/*.sh

./scripts/clean_runtime.sh
./scripts/init_config.sh
./scripts/server_up.sh
```

Откройте сайт проекта:

```text
http://SERVER_IP:8080/PROJECT_NAME/
```

Создайте одного пользователя через Web UI, затем:

```bash
./scripts/create_account.sh
./scripts/copy_ssh_keys.sh
ansible -i ansible/inventory.ini boinc_clients -m ping
./scripts/deploy_clients.sh --ask-become-pass
./scripts/status.sh
```

## Мониторинг

Запуск:

```bash
./scripts/monitoring_up.sh
```

Адреса:

```text
Prometheus: http://localhost:9090
Grafana:    http://localhost:3000
Login:      admin / admin
Exporter:   http://localhost:9101/metrics
```

Остановка:

```bash
./scripts/monitoring_down.sh
```

## Что мониторится

- доступность MariaDB: `boinc_db_up`;
- доступность web-страницы проекта: `boinc_project_http_up`;
- число пользователей: `boinc_users_total`;
- число клиентов: `boinc_hosts_total`;
- число workunits: `boinc_workunits_total`;
- число results: `boinc_results_total`;
- results по состояниям: `boinc_results_by_state_total`;
- активные hosts за последние 15 минут: `boinc_hosts_active_recent_total`;
- CPU/RAM Docker-контейнеров через cAdvisor.

## Что удалено

Из проекта нужно удалить локальный Docker client:

```bash
rm -f Dockerfile
rm -f docker-compose.yml
rm -f scripts/attach_local_client.sh
rm -rf boinc-data
```

Также удалены упоминания локального клиента из `clean_runtime.sh`, `status.sh` и README.
