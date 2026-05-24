# Quick start

## 1. Подготовить конфиг кластера

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

## 2. Обычный запуск с вводом sudo-пароля

```bash
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh --ask-become-pass
./scripts/run_experiment.sh --ask-become-pass
```

## 3. Запуск через Ansible Vault

Создать зашифрованный vault-файл с sudo-паролем клиентов:

```bash
./scripts/init_vault.sh
```

Запуск:

```bash
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh --ask-vault-pass
./scripts/run_experiment.sh --ask-vault-pass
```

Сокращение:

```bash
./scripts/quickstart.sh --ask-vault-pass
./scripts/run_experiment.sh --ask-vault-pass
```

## 4. Очистка перед новым прогоном

С вводом sudo-пароля:

```bash
./scripts/clean_runtime.sh --ask-become-pass
```

Через Vault:

```bash
./scripts/clean_runtime.sh --ask-vault-pass
```

После очистки:

```bash
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh --ask-vault-pass
./scripts/run_experiment.sh --ask-vault-pass
```

## 5. Проверка состояния

```bash
./scripts/status.sh
```

Смотреть блоки:

```text
MariaDB hosts
MariaDB workunits/results summary
Remote BOINC client project status
Remote BOINC client task summary
```
