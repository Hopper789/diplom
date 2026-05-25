# Диагностика

## `config/cluster.yml not found`

Создай файл из примера:

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

## Ansible: `Host key verification failed`

Такое бывает после пересоздания или отката клиентских машин. У них меняется SSH host key.

Решение вручную:

```bash
ssh-keygen -R CLIENT_IP
ssh USER@CLIENT_IP
```

`clean_runtime.sh` также пытается автоматически удалить старые host keys для клиентов из `inventory.ini`.

## Ansible: `Attempting to decrypt but no vault secrets found`

Ansible нашёл зашифрованный `vault.yml`, но не получил пароль от Vault.

Варианты:

```bash
./scripts/status.sh --ask-vault-pass
```

или создать файл пароля:

```bash
nano ansible/.vault_pass
chmod 600 ansible/.vault_pass
```

Проверка:

```bash
ansible-vault view ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

## Ansible не видит `boinc_project_url`

Проверь, что существует файл:

```text
ansible/group_vars/all/main.yml
```

Если нет:

```bash
./scripts/init_config.sh
./scripts/create_account_db.sh
```

## Клиенты подключены, но сервер не видит hosts

Возможно, сервер был очищен, а на клиентах остался старый BOINC volume.

Очисти runtime полностью:

```bash
./scripts/clean_runtime.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
```

## `bad WU template - no <workunit>`

Некорректный BOINC input template. Проверь файл:

```text
apps/ml_grid_search/templates/ml_grid_search_in
```

В нём должен быть блок:

```xml
<workunit>
...
</workunit>
```

## `workunits=0`, `results=0`

Задачи ещё не созданы. Запусти:

```bash
./scripts/run_experiment.sh
```

## Задачи созданы, но клиенты их не забирают

Проверь статус клиентов:

```bash
./scripts/status.sh
```

Затем принудительно запроси обновление проекта:

```bash
ansible -i ansible/inventory.ini boinc_clients -b --vault-password-file ansible/.vault_pass -m shell -a '
docker exec boinc-client boinccmd --passwd "$(cat /opt/boinc-client/data/gui_rpc_auth.cfg)" --project http://SERVER_IP:8080/my_project/ update
'
```

## Docker требует sudo на клиентах

Используй Vault:

```bash
./scripts/init_vault.sh
./scripts/bootstrap_clients.sh
```

Или настрой `NOPASSWD` для SSH-пользователя на клиентах.


## Grafana открывается, но графики пустые

Проверь, что мониторинг запущен:

```bash
docker ps --filter name=boinc-prometheus
docker ps --filter name=boinc-grafana
docker ps --filter name=boinc-exporter
```

Проверь exporter:

```bash
curl http://localhost:9101/metrics | grep boinc_
```

Проверь, что Prometheus видит клиентские targets. Файл генерируется из `ansible/inventory.ini`:

```bash
cat monitoring/prometheus.yml
```

Если нет targets клиентов, перезапусти:

```bash
./scripts/monitoring_up.sh
```

## Prometheus не видит node-exporter или cAdvisor клиентов

Проверь агенты на клиентах:

```bash
./scripts/deploy_monitoring_agents.sh
```

Или вручную через Ansible:

```bash
ansible -i ansible/inventory.ini boinc_clients -b -m shell -a 'docker ps --filter name=boinc-node-exporter --filter name=boinc-client-cadvisor'
```

Если используется Vault и нет `ansible/.vault_pass`, добавь `--ask-vault-pass`.
