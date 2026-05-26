# Telegram alerts

Telegram notifier сообщает, когда BOINC-эксперимент завершился.

В текущей версии поддерживается одно уведомление: все workunits завершены, незавершённых results нет.

## Создать бота

1. Открой Telegram и найди `@BotFather`.
2. Создай бота командой `/newbot`.
3. Сохрани token.
4. Напиши любое сообщение своему боту.
5. Получи `chat_id`, например через `https://api.telegram.org/botTOKEN/getUpdates`.

## Настроить config/alerts.env

```bash
cp config/alerts.example.env config/alerts.env
nano config/alerts.env
```

Минимально нужны:

```env
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
ALERT_POLL_INTERVAL_SECONDS=30
BOINC_EXPORTER_URL=http://boinc-exporter:9101/metrics
ALERT_STATE_FILE=/state/alerts_state.json
```

`config/alerts.env` содержит секреты и не коммитится.

## Запуск

Сначала должен работать мониторинг:

```bash
./scripts/monitoring_up.sh
```

Затем:

```bash
./scripts/alerts_up.sh
```

Логи:

```bash
docker logs -f boinc-alerts
```

## Остановка

```bash
./scripts/alerts_down.sh
```

## Когда отправляется сообщение

Notifier читает метрики:

- `boinc_workunits_total`;
- `boinc_completed_workunits_total`;
- `boinc_results_unfinished_total`;
- `boinc_results_error_total`;
- `boinc_latest_result_received_time`.

Сообщение отправляется, если:

- `boinc_workunits_total > 0`;
- `boinc_completed_workunits_total >= boinc_workunits_total`;
- `boinc_results_unfinished_total == 0`;
- для текущего эксперимента уведомление ещё не отправлялось.

Состояние хранится в `monitoring/alert-state/alerts_state.json`, внутри контейнера это `/state/alerts_state.json`.
