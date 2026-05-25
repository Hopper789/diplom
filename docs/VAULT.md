# Ansible Vault

Ansible выполняет часть команд на клиентах через `sudo`: устанавливает Docker, создаёт каталоги и запускает контейнеры. Если sudo требует пароль, его нельзя хранить открытым текстом.

Для этого используется Ansible Vault.

## Основной сценарий

```bash
./scripts/init_vault.sh
```

Скрипт создаёт:

```text
ansible/group_vars/all/vault.yml   # sudo-пароль клиентов, зашифрованный Vault
ansible/.vault_pass                # пароль от Vault
```

`ansible/.vault_pass` нужен, чтобы остальные скрипты могли читать Vault без ручного ввода пароля. Этот файл не коммитится.

После этого запускай команды обычно:

```bash
./scripts/bootstrap_clients.sh
./scripts/run_experiment.sh
./scripts/status.sh
```

## Посмотреть Vault

```bash
ansible-vault view ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

## Изменить sudo-пароль клиентов

```bash
ansible-vault edit ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

## Что нельзя коммитить

```text
ansible/group_vars/all/vault.yml
ansible/.vault_pass
```

Даже зашифрованный `vault.yml` здесь считается локальным runtime-файлом: он зависит от конкретного стенда.
