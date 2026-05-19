# Диагностика

## `Connection refused` при Ansible

Ошибка:

```text
ssh: connect to host 192.168.1.189 port 22: Connection refused
```

Причина:

- клиент доступен по сети;
- SSH-сервер не запущен;
- порт 22 закрыт.

Решение на клиенте:

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

## `No route to host`

Ошибка:

```text
ssh: connect to host 192.168.3.189 port 22: No route to host
```

Причина:

- неверный IP;
- другая подсеть;
- нет маршрута.

Решение:

1. проверить IP клиента;
2. исправить `config/cluster.yml`;
3. выполнить:

```bash
./scripts/init_config.sh
```

## `Permission denied (publickey,password)`

Причина:

- неверный `user` в `cluster.yml`;
- SSH-ключ не скопирован;
- пароль не подходит.

Решение:

```bash
ssh user@client_ip
./scripts/copy_ssh_keys.sh
```

или:

```bash
ansible -i ansible/inventory.ini boinc_clients -m ping --ask-pass
```

## `sudo: interactive authentication is required`

Решение:

```bash
./scripts/deploy_clients.sh --ask-become-pass
```

## `Timeout waiting for privilege escalation prompt`

Решение:

```bash
ANSIBLE_BECOME_TIMEOUT=60 ./scripts/deploy_clients.sh --ask-become-pass
```

или:

```bash
ANSIBLE_BECOME_TIMEOUT=60 ansible-playbook \
  -i ansible/inventory.ini \
  ansible/install_boinc_clients.yml \
  --ask-become-pass \
  -e 'ansible_ssh_common_args="-tt"'
```

Для учебного стенда можно временно включить passwordless sudo на клиенте:

```bash
sudo visudo
```

Добавить:

```text
hopper ALL=(ALL) NOPASSWD:ALL
```

## `Can't create database 'my_project'; database exists`

Причина:

- старая MariaDB БД осталась после прошлого запуска.

Решение:

```bash
./scripts/clean_runtime.sh
./scripts/init_config.sh
./scripts/server_up.sh
```

## `Table 'my_project.platform' doesn't exist`

Причина:

- BOINC project создался не полностью;
- `make_project` упал во время создания БД.

Решение:

```bash
./scripts/clean_runtime.sh
./scripts/init_config.sh
./scripts/server_up.sh
```

## `Table 'my_project.consent_type' doesn't exist`

Причина:

- web schema BOINC не создалась полностью;
- возможно, отсутствует `php-xml`.

Решение:

1. проверить `server/Dockerfile`;
2. убедиться, что установлен `php-xml`;
3. пересоздать runtime:

```bash
./scripts/clean_runtime.sh
./scripts/init_config.sh
./scripts/server_up.sh
```

## BOINC client не появляется в таблице `host`

Проверить статус клиента:

```bash
docker exec -it boinc-client boinccmd --get_project_status
```

Проверить URL:

```bash
grep BOINC_PROJECT_URL config/generated.env
```

Проверить, что URL доступен с клиента:

```bash
curl -I http://SERVER_IP:8080/my_project/
```

Проверить scheduler URL в проекте:

```bash
docker exec -it boinc-server bash -c \
  "grep -R 'http://' /project/my_project/html/user/schedulers.txt /project/my_project/config.xml"
```

Если там `localhost`, нужно выполнить:

```bash
./server/scripts/fix_project_url.sh
docker restart boinc-server
```
