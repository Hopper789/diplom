# Быстрый запуск

Эта инструкция рассчитана на первый запуск. Предполагается, что у тебя есть одна управляющая машина и один или несколько клиентских узлов по SSH.

## 1. Подготовить конфигурацию

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

В `cluster.yml` укажи:

- IP управляющей машины в `server.ip`;
- список клиентских узлов в `clients`;
- SSH-пользователя для каждого клиента.

## 2. Создать Ansible Vault

```bash
./scripts/init_vault.sh
```

Скрипт спросит два пароля:

1. sudo-пароль на клиентских машинах;
2. пароль от Ansible Vault.

После этого будут созданы:

```text
ansible/group_vars/all/vault.yml   # зашифрованный sudo-пароль
ansible/.vault_pass                # пароль от Vault, чтобы не вводить его много раз
```

Оба файла игнорируются Git.

## 3. Поднять BOINC server

```bash
./scripts/bootstrap_server.sh
```

Скрипт создаёт runtime-конфиги, запускает Docker-контейнеры `boinc-server` и `boinc-mysql`, создаёт BOINC project account.

## 4. Развернуть клиентов

```bash
./scripts/bootstrap_clients.sh
```

Скрипт подключается к клиентам по SSH, устанавливает Docker и запускает контейнер `boinc-client` на каждом узле.

Если ты не используешь `ansible/.vault_pass`, запусти так:

```bash
./scripts/bootstrap_clients.sh --ask-vault-pass
```

## 5. Запустить вычисления

```bash
./scripts/run_experiment.sh
```

Скрипт создаст workunits на BOINC server и попросит клиентов забрать задачи.

## 6. Смотреть статус

```bash
./scripts/status.sh
```

В выводе важны блоки:

- `MariaDB hosts` — зарегистрированные клиенты;
- `MariaDB workunits/results summary` — созданные задачи и результаты;
- `Remote BOINC client task summary` — задачи на клиентских узлах.

## Полный запуск одной последовательностью

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

./scripts/init_vault.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
./scripts/run_experiment.sh
./scripts/status.sh
```

## Полная очистка перед новым прогоном

```bash
./scripts/clean_runtime.sh
./scripts/bootstrap_server.sh
./scripts/bootstrap_clients.sh
./scripts/run_experiment.sh
```
