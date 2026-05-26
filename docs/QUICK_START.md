# Быстрый запуск

Эта инструкция рассчитана на человека, который впервые запускает кластер. Нужна управляющая машина и один или несколько клиентских узлов, доступных по SSH.

## 1. Создать локальную конфигурацию

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

В `config/cluster.yml` укажи:

- IP управляющей машины в `server.ip`;
- имя BOINC-проекта в `project.name`;
- список клиентов в `clients`;
- SSH-пользователя для каждого клиента.

## 2. Создать Vault

```bash
./scripts/init_vault.sh
```

Скрипт спросит sudo-пароль клиентов и пароль от Vault. После этого появятся:

```text
ansible/group_vars/all/vault.yml
ansible/.vault_pass
```

Оба файла являются локальными. Их нельзя коммитить.

## 3. Запустить всё одной командой

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment
```

Скрипт выполнит:

1. `./scripts/bootstrap_server.sh`;
2. `./scripts/bootstrap_clients.sh`;
3. `./scripts/monitoring_up.sh`;
4. `./scripts/run_experiment.sh`;
5. `./scripts/status.sh`.

## 4. Включить Telegram-уведомление

Этот шаг необязательный. Он нужен, если хочешь получить сообщение в Telegram, когда эксперимент завершится.

Сначала создай бота через `@BotFather`, напиши ему любое сообщение и получи `chat_id`.

Потом создай локальный конфиг:

```bash
cp config/alerts.example.env config/alerts.env
nano config/alerts.env
```

Заполни:

```env
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

После запуска quickstart с мониторингом включи notifier:

```bash
./scripts/alerts_up.sh
```

Логи:

```bash
docker logs -f boinc-alerts
```

Самый короткий полный запуск:

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml

./scripts/init_vault.sh
./scripts/quickstart.sh --with-monitoring --run-experiment
./scripts/alerts_up.sh
./scripts/status.sh
```

Для строки `./scripts/alerts_up.sh` заранее должен существовать заполненный `config/alerts.env`.

## Варианты quickstart

```bash
./scripts/quickstart.sh
./scripts/quickstart.sh --with-monitoring
./scripts/quickstart.sh --run-experiment
./scripts/quickstart.sh --with-monitoring --run-experiment
```

## Проверить результат

```bash
./scripts/status.sh
```

Grafana после запуска мониторинга:

```text
http://localhost:3000
admin / admin
```

Метрики BOINC:

```bash
curl -s http://localhost:9101/metrics | grep boinc_
```

## Если Docker требует sudo локально

На управляющей машине пользователь должен иметь доступ к Docker без постоянного sudo. Добавь пользователя в группу Docker и перелогинься:

```bash
sudo usermod -aG docker "$USER"
```
