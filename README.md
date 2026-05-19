# BOINC cluster

Репозиторий для развёртывания BOINC-кластера:

- BOINC server запускается в Docker на управляющей машине;
- BOINC clients устанавливаются на вычислительные узлы через Ansible;
- один BOINC project account создаётся вручную через Web UI;
- его `authenticator` используется как `BOINC_ACCOUNT_KEY` для подключения всех клиентов;
- каждый клиент регистрируется на сервере как отдельный `host`.

## Документация

- [Quick start](docs/QUICK_START.md)
- [Конфигурация кластера](docs/CONFIGURATION.md)
- [Скрипты](docs/SCRIPTS.md)
- [Сервер](docs/SERVER.md)
- [Клиенты и Ansible](docs/CLIENTS_ANSIBLE.md)
- [Требования](docs/REQUIREMENTS.md)
- [Диагностика](docs/TROUBLESHOOTING.md)
