# Ansible Vault

Ansible выполняет команды на клиентских узлах с `sudo`: устанавливает Docker, создаёт директории, запускает контейнеры. Если sudo требует пароль, его нужно передать Ansible.

Чтобы не хранить sudo-пароль открытым текстом, используется Ansible Vault.

## Создание Vault

```bash
./scripts/init_vault.sh
```

Скрипт спросит:

1. sudo-пароль клиентских машин;
2. пароль от Vault.

После этого появятся файлы:

```text
ansible/group_vars/all/vault.yml
ansible/.vault_pass
```

`vault.yml` хранит sudo-пароль в зашифрованном виде. `.vault_pass` хранит пароль от Vault, чтобы скрипты не спрашивали его много раз.

Оба файла добавлены в `.gitignore`.

## Запуск с .vault_pass

Если `ansible/.vault_pass` существует, команды можно запускать без дополнительных ключей:

```bash
./scripts/bootstrap_clients.sh
./scripts/run_experiment.sh
./scripts/status.sh
```

## Запуск без .vault_pass

Если не хочешь хранить `ansible/.vault_pass`, удали его:

```bash
rm ansible/.vault_pass
```

Тогда запускай клиентские команды так:

```bash
./scripts/bootstrap_clients.sh --ask-vault-pass
./scripts/run_experiment.sh --ask-vault-pass
./scripts/status.sh --ask-vault-pass
```

## Посмотреть содержимое Vault

```bash
ansible-vault view ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

## Изменить sudo-пароль

```bash
ansible-vault edit ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

## Альтернатива: sudo без пароля

Для учебного стенда можно настроить на клиентах `NOPASSWD` и не использовать Vault:

```text
ubuntu ALL=(ALL) NOPASSWD:ALL
```

Но для более аккуратной конфигурации лучше использовать Vault.
