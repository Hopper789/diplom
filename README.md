# BOINC cluster (Docker + Ansible)

## Quick start

```bash
# настройка конфиг под конкретный кластер
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

# запуск сервера
./scripts/init_config.sh
./scripts/server_up.sh

# Cоздание аккаунта (вручную) и получение ключа
http://localhost:8080/my_project/signup.php

# Проверка, что в config/generated.env правильные данные. Передача ssh ключа проверка, что все ноды пингуются по 22 порту
./scripts/copy_ssh_keys.sh 
ansible -i ansible/inventory.ini boinc_clients -m ping

# Local test client (Docker on the same machine)
docker compose up -d --build
./scripts/attach_local_client.sh

# Deploy real clients via Ansible
./scripts/deploy_clients.sh

./scripts/status.sh
```

Notes:
- `server/project/` is BOINC runtime data and is not stored in Git.
- `config/generated.env` is generated and is not stored in Git.
- `BOINC_ACCOUNT_KEY` appears after you create a user (then rerun `./scripts/create_account.sh`).
- For a real cluster, `server.ip` must be reachable from all client machines.

# net to firewall windows 
```
netsh advfirewall firewall add rule name="BOINC Server 8080" dir=in action=allow protocol=TCP localport=8080
```
