# Cleanup

## Обычная очистка

```bash
./scripts/clean_runtime.sh
```

Очищает runtime-данные сервера и сбрасывает задачи клиентов. BOINC client на клиентских узлах остаётся установленным.

## Очистить только сервер

```bash
./scripts/clean_runtime.sh --server-only
```

## Очистить только задачи клиентов

```bash
./scripts/clean_runtime.sh --clients-only
```

## Полностью удалить BOINC client с клиентов

```bash
./scripts/clean_runtime.sh --purge-clients
```

или:

```bash
./scripts/clean_runtime.sh --remove-clients
```
