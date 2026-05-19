# BOINC server

Серверная часть находится в директории:

```text
server/
```

## Состав

```text
server/
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
└── scripts/
    ├── create_project.sh
    └── fix_project_url.sh
```

## Контейнеры

`server/docker-compose.yml` поднимает:

```text
boinc-server
boinc-mysql
```

## `boinc-server`

Содержит:

```text
BOINC server
Apache
PHP
Python
BOINC tools
```

## `boinc-mysql`

MariaDB с базой проекта.

## Создание проекта

Проект создаётся командой BOINC:

```text
/opt/boinc/tools/make_project
```

Скрипт:

```text
server/scripts/create_project.sh
```

использует переменные из:

```text
config/generated.env
```

Главные переменные:

```text
PROJECT_NAME
PROJECT_URL_BASE
```

## Исправление URL

Скрипт:

```text
server/scripts/fix_project_url.sh
```

исправляет URL в файлах:

```text
/project/$PROJECT_NAME/html/user/schedulers.txt
/project/$PROJECT_NAME/config.xml
/project/$PROJECT_NAME/project.xml
/project/$PROJECT_NAME/gui_urls.xml
```

Это нужно, чтобы клиенты получали URL, доступный из сети.

## Проверка сервера

```bash
docker ps
```

```bash
curl -I http://SERVER_IP:8080/my_project/
```

```bash
docker logs --tail 100 boinc-server
```

```bash
docker exec -it boinc-server bash -c "cd /project/my_project && ./bin/status"
```

## Проверка БД

```bash
docker exec -it boinc-mysql \
  mariadb -u root -proot my_project \
  -e "SHOW TABLES;"
```

Пользователи:

```bash
docker exec -it boinc-mysql \
  mariadb -u root -proot my_project \
  -e "SELECT id, email_addr, name, authenticator FROM user;"
```

Клиенты:

```bash
docker exec -it boinc-mysql \
  mariadb -u root -proot my_project \
  -e "SELECT id, userid, domain_name, os_name, create_time FROM host;"
```
