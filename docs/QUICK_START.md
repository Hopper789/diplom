# Quick start

## 1. Склонировать репозиторий

```bash
git clone https://github.com/Hopper789/diplom.git
cd diplom
```

## 2. Создать `config/cluster.yml`

```bash
cp config/cluster.example.yml config/cluster.yml
```

## 3. Отредактировать IP-адреса и пользователей клиентов

```bash
nano config/cluster.yml
```

Проверь `server.ip`, список `clients`, IP-адреса и SSH-пользователей.

## 4. Запустить всё одной командой

```bash
./scripts/quickstart.sh --with-monitoring --run-experiment
```

## 5. Проверить статус

```bash
./scripts/status.sh
```

## 6. Открыть интерфейсы

BOINC server:

```text
http://SERVER_IP:8080/PROJECT_NAME/
```

Grafana:

```text
http://SERVER_IP:3000/
```
