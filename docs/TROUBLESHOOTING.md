# Диагностика

## `config/cluster.yml not found`

Создай локальный конфиг:

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

## Нет Vault-файлов

Если отсутствует `ansible/.vault_pass` или `ansible/group_vars/all/vault.yml`, запусти:

```bash
./scripts/init_vault.sh
```

## Если удалён ansible/.vault_pass

Основной сценарий — восстановить файл через известный Vault-пароль:

```bash
nano ansible/.vault_pass
chmod 600 ansible/.vault_pass
ansible-vault view ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

Аварийно можно один раз передать пароль вручную:

```bash
./scripts/status.sh --ask-vault-pass
```

Если sudo-пароль клиентов тоже приходится вводить вручную, Ansible поддерживает:

```bash
./scripts/bootstrap_clients.sh --ask-become-pass
```

Это не основной сценарий. Для обычной работы вернись к `./scripts/init_vault.sh`.

## Ansible: `Host key verification failed`

После пересоздания клиентской машины меняется SSH host key.

```bash
ssh-keygen -R CLIENT_IP
ssh USER@CLIENT_IP
```

Затем повтори запуск.

## Ansible не видит переменные проекта

Проверь, что есть:

```text
config/generated.env
ansible/inventory.ini
ansible/group_vars/all/main.yml
```

Если файлов нет:

```bash
./scripts/init_config.sh
./scripts/create_account_db.sh
```

## Docker требует sudo на управляющей машине

Добавь пользователя в группу Docker и перелогинься:

```bash
sudo usermod -aG docker "$USER"
```

## Клиенты подключены, но сервер не видит hosts

Частая причина — сервер очищен, а на клиентах остались старые BOINC volume.

```bash
./scripts/clean_runtime.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
```

## `bad WU template - no <workunit>`

Проверь BOINC input template приложения. Для текущего примера:

```text
apps/ml_grid_search/templates/ml_grid_search_in
```

В файле должен быть блок `<workunit>...</workunit>`.

## `workunits=0`, `results=0`

Задачи ещё не созданы:

```bash
./scripts/run_experiment.sh
```

## Задачи созданы, но клиенты их не забирают

Проверь статус:

```bash
./scripts/status.sh
```

Потом проверь, что клиенты видят проект и контейнер `boinc-client` запущен.

## Grafana открывается, но графики пустые

Проверь контейнеры:

```bash
docker ps --filter name=boinc-prometheus
docker ps --filter name=boinc-grafana
docker ps --filter name=boinc-exporter
```

Проверь exporter:

```bash
curl -s http://SERVER_IP:9101/metrics | grep boinc_
```

Проверь, что Prometheus видит targets:

```bash
curl -s http://SERVER_IP:9090/api/v1/targets | grep -E '"health":"up"|lastError'
```

Проверь anonymous-доступ Grafana внутри контейнера:

```bash
docker exec boinc-grafana env | grep GF_AUTH
```

Если Prometheus не видит клиентов, перезапусти мониторинг:

```bash
./scripts/monitoring_up.sh
```

Если в логах Grafana остаётся `user token not found`, пересоздай контейнеры мониторинга:

```bash
./scripts/monitoring_down.sh
./scripts/monitoring_up.sh
```

## BOINC-клиент показывает `suspended`

Обычно это локальные preferences BOINC: клиент приостанавливает задачи из-за фоновой CPU-нагрузки. Переразверни клиентов, чтобы применить override:

```bash
./scripts/bootstrap_clients.sh
```

После этого проверь, что задачи больше не в `suspended`:

```bash
./scripts/status.sh
```

## Задачи выполняются только после повторного `bootstrap_clients.sh`

Не нужно повторно разворачивать клиентов ради получения следующей порции задач. Запусти авто-update:

```bash
./scripts/pump_clients.sh --max-seconds 600 --interval-seconds 15
```

`run_experiment.sh` запускает этот helper автоматически после создания workunits.
Если `active_hosts=0` держится несколько циклов, helper сам напечатает диагностику app_version, scheduler/feeder logs и последние сообщения клиентов.

## Ошибки results растут

Смотри логи серверного контейнера и последние results:

```bash
docker logs --tail=100 boinc-server
./scripts/status.sh
```

Для пользовательских задач проверь входной файл, права на исполняемый файл и формат output.
