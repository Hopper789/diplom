# BOINC cluster

Репозиторий для развёртывания BOINC-кластера:

- BOINC server запускается в Docker на управляющей машине;
- BOINC clients запускаются в Docker-контейнерах на вычислительных узлах через Ansible;
- один BOINC project account создаётся автоматически через `scripts/create_account_db.sh` или вручную через Web UI;
- его `authenticator` сохраняется как `BOINC_ACCOUNT_KEY` и используется для подключения всех клиентов;
- каждый клиент регистрируется на сервере как отдельный `host`;
- задачи создаются на BOINC server и запрашиваются реальными клиентами через Ansible.

## Документация

- [Quick start](docs/QUICK_START.md)
- [Конфигурация кластера](docs/CONFIGURATION.md)
- [Скрипты](docs/SCRIPTS.md)
- [Сервер](docs/SERVER.md)
- [Клиенты и Ansible](docs/CLIENTS_ANSIBLE.md)
- [Аккаунт BOINC и ключ подключения](docs/ACCOUNT.md)
- [Требования](docs/REQUIREMENTS.md)
- [Диагностика](docs/TROUBLESHOOTING.md)
