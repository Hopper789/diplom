# Ansible Vault

Vault используется для хранения паролей и секретных значений Ansible.

Ansible выполняет часть команд на клиентах через `sudo`: устанавливает Docker, создаёт каталоги и запускает контейнеры. Если sudo требует пароль, его нельзя хранить открытым текстом.

## Обычный сценарий

При обычном запуске вручную создавать Vault не нужно:

```bash
./scripts/quickstart.sh
```

или:

```bash
./scripts/prepare_system.sh
```

Если `ansible/group_vars/all/vault.yml` и `ansible/.vault_pass` отсутствуют, `prepare_system.sh` создаст их через `init_vault.sh`.

## Путь по умолчанию

```text
ansible/.vault_pass
```

Это стандартный файл пароля Vault. Если он существует, скрипты автоматически используют его. Поэтому при повторном запуске не нужно писать:

```bash
--vault-password-file ansible/.vault_pass
```

## Ручной режим

Ручное создание Vault:

```bash
./scripts/init_vault.sh
```

Скрипт создаёт:

```text
ansible/group_vars/all/vault.yml   # sudo-пароль клиентов, зашифрованный Vault
ansible/.vault_pass                # пароль от Vault
```

Нестандартные режимы:

```bash
--ask-vault-pass
--vault-password-file FILE
```

Эти ключи нужны только для нестандартных случаев. В обычном сценарии используется `ansible/.vault_pass`.

## Посмотреть или изменить Vault

```bash
ansible-vault view ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
ansible-vault edit ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

## Что нельзя коммитить

```text
ansible/group_vars/all/vault.yml
ansible/.vault_pass
```

Даже зашифрованный `vault.yml` здесь считается локальным runtime-файлом: он зависит от конкретного стенда.
