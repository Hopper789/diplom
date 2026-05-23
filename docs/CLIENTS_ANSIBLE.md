# Клиенты и Ansible

## Что делает Ansible

Playbook:

```text
ansible/install_boinc_clients.yml
```

работает на группе:

```text
boinc_clients
```

Текущая схема не использует системный `boinc-client` как service. Вместо этого на каждом вычислительном узле запускается Docker-контейнер:

```text
boinc-client
```

Это сделано для воспроизводимости и чтобы не зависеть от версии `boinc-client` в конкретном дистрибутиве.

Playbook:

1. проверяет Debian/Ubuntu family;
2. проверяет наличие нужных BOINC-переменных;
3. устанавливает Docker и базовые пакеты;
4. останавливает и отключает нативный `boinc-client`, если он был установлен;
5. создаёт директорию `/opt/boinc-client`;
6. генерирует Dockerfile и `docker-compose.yml` для BOINC client;
7. пересоздаёт контейнер `boinc-client`;
8. ждёт готовности BOINC RPC внутри контейнера;
9. подключает контейнер к BOINC project;
10. выводит статус проекта.

## Inventory

Файл:

```text
ansible/inventory.ini
```

создаётся из `config/cluster.yml`.

Пример:

```ini
[boinc_server]
192.168.1.209 ansible_user=hopper

[boinc_clients]
192.168.1.189 ansible_user=hopper
192.168.1.190 ansible_user=ubuntu
```

## Переменные

Файл:

```text
ansible/group_vars/all.yml
```

создаётся автоматически.

Пример:

```yaml
project_name: "my_project"
project_port: "8080"
server_ip: "192.168.1.209"
boinc_project_url: "http://192.168.1.209:8080/my_project/"
boinc_client_rpc_password: "..."
boinc_account_key: "..."
```

## Проверка SSH

```bash
ssh user@client_ip
```

## Копирование SSH-ключей

```bash
./scripts/copy_ssh_keys.sh
```

## Проверка Ansible

```bash
ansible -i ansible/inventory.ini boinc_clients -m ping
```

Если требуется пароль:

```bash
ansible -i ansible/inventory.ini boinc_clients -m ping --ask-pass
```

## Деплой клиентов

```bash
./scripts/deploy_clients.sh --ask-become-pass
```

Если sudo без пароля уже настроен:

```bash
./scripts/deploy_clients.sh
```

## Проверка после деплоя

На сервере:

```bash
./scripts/status.sh
```

В БД:

```bash
docker exec -it boinc-mysql \
  mariadb -u root -proot my_project \
  -e "SELECT id, userid, domain_name, os_name, create_time FROM host;"
```

На клиенте:

```bash
sudo docker ps
sudo docker logs --tail 100 boinc-client
sudo docker exec -it boinc-client \
  boinccmd --passwd "RPC_PASSWORD" \
  --get_project_status
```

## Выдача задач клиентам

После создания workunits можно запросить обновление проекта на клиентах:

```bash
ANSIBLE_EXTRA_ARGS="--ask-become-pass" apps/ml_grid_search/run_task.sh boinc
```

Или вручную:

```bash
ansible -i ansible/inventory.ini boinc_clients -b --ask-become-pass -m shell -a '
docker exec boinc-client boinccmd --passwd "RPC_PASSWORD" --project "PROJECT_URL" update
'
```
