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

Он должен:

1. проверить доступность Python;
2. проверить наличие пакетного менеджера;
3. установить системные пакеты;
4. установить `boinc-client`;
5. записать RPC-пароль;
6. запустить и включить сервис `boinc-client`;
7. подключить клиент к BOINC project;
8. вывести статус клиента.

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

## Деплой

```bash
./scripts/deploy_clients.sh
```

С sudo-паролем:

```bash
./scripts/deploy_clients.sh --ask-become-pass
```

С SSH-паролем и sudo-паролем:

```bash
./scripts/deploy_clients.sh --ask-pass --ask-become-pass
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
boinccmd --get_project_status
```

Если нужен RPC-пароль:

```bash
sudo cat /var/lib/boinc-client/gui_rpc_auth.cfg
boinccmd --passwd "RPC_PASSWORD" --get_project_status
```
