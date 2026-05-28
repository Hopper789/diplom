# Monitoring

Актуальная документация по мониторингу находится здесь:

```text
docs/MONITORING.md
```

Короткий запуск:

```bash
./scripts/monitoring_up.sh
```

Если не используется `ansible/.vault_pass`:

```bash
./scripts/monitoring_up.sh --ask-vault-pass
```

После запуска:

```text
Prometheus: http://SERVER_IP:9090
Grafana:    http://SERVER_IP:3000
Exporter:   http://SERVER_IP:9101/metrics
```

Dashboard можно смотреть без логина. Для администрирования:

```text
admin / admin
```
