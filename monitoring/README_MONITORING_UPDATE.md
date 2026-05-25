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
Prometheus: http://localhost:9090
Grafana:    http://localhost:3000
Exporter:   http://localhost:9101/metrics
```

Grafana login:

```text
admin / admin
```
