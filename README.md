# BOINC cluster

Репозиторий для развёртывания BOINC-кластера:

- BOINC server запускается в Docker на управляющей машине;
- BOINC clients запускаются в Docker-контейнерах на вычислительных узлах через Ansible;
- один BOINC project account создаётся автоматически через `scripts/create_account_db.sh` или вручную через Web UI;
- его `authenticator` сохраняется как `BOINC_ACCOUNT_KEY` и используется для подключения всех клиентов;
- каждый клиент регистрируется на сервере как отдельный `host`;
- задачи создаются на BOINC server и запрашиваются реальными клиентами через Ansible.

## Быстрый запуск

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh --ask-become-pass
./scripts/run_experiment.sh --ask-become-pass
```

Если хочешь хранить sudo-пароль клиентов в зашифрованном Ansible Vault:

```bash
./scripts/init_vault.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh --ask-vault-pass
./scripts/run_experiment.sh --ask-vault-pass
```

## Документация

- [Quick start](docs/QUICK_START.md)
- [Конфигурация кластера](docs/CONFIGURATION.md)
- [Ansible Vault для sudo-пароля](docs/VAULT.md)
- [Скрипты](docs/SCRIPTS.md)
- [Сервер](docs/SERVER.md)
- [Клиенты и Ansible](docs/CLIENTS_ANSIBLE.md)
- [Аккаунт BOINC и ключ подключения](docs/ACCOUNT.md)
- [Требования](docs/REQUIREMENTS.md)
- [Диагностика](docs/TROUBLESHOOTING.md)
