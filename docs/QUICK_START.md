# Quick start

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

./scripts/clean_runtime.sh
./scripts/init_config.sh
./scripts/server_up.sh
```

Открыть сайт:

```text
http://SERVER_IP:8080/my_project/
```

Создать одного BOINC-пользователя через Web UI.

```bash
./scripts/create_account.sh

docker compose up -d --build
./scripts/attach_local_client.sh

./scripts/status.sh
```

Для реальных клиентов:

```bash
./scripts/copy_ssh_keys.sh
ansible -i ansible/inventory.ini boinc_clients -m ping

./scripts/deploy_clients.sh
./scripts/status.sh
```

Если Ansible требует sudo-пароль:

```bash
./scripts/deploy_clients.sh --ask-become-pass
```

Если нужен SSH-пароль и sudo-пароль:

```bash
./scripts/deploy_clients.sh --ask-pass --ask-become-pass
```
