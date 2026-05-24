# Ansible Vault для sudo-пароля клиентов

Если на клиентских узлах `sudo` требует пароль, можно не вводить `--ask-become-pass` каждый раз, а сохранить пароль в зашифрованном Ansible Vault файле.

## Создание vault-файла

```bash
./scripts/init_vault.sh
```

Скрипт спросит sudo-пароль для клиентских машин и создаст зашифрованный файл:

```text
ansible/group_vars/all/vault.yml
```

Файл добавлен в `.gitignore`, поэтому не попадёт в репозиторий.

## Запуск с Vault

Развернуть клиентов:

```bash
./scripts/deploy_clients.sh --ask-vault-pass
```

Запустить эксперимент:

```bash
./scripts/run_experiment.sh --ask-vault-pass
```

Очистить сервер и клиентов:

```bash
./scripts/clean_runtime.sh --ask-vault-pass
```

Можно использовать сокращение:

```bash
./scripts/deploy_clients.sh --vault
./scripts/run_experiment.sh --vault
```

## Если sudo без пароля

Если на клиентах настроен `NOPASSWD`, Vault не нужен:

```bash
./scripts/deploy_clients.sh
./scripts/run_experiment.sh
```

## Если у разных клиентов разные sudo-пароли

Тогда лучше использовать `ansible/host_vars/<host>/vault.yml` для каждого хоста и шифровать каждый файл через `ansible-vault encrypt`.
