# Диагностика

## `config/cluster.yml not found`

Создай локальный конфиг:

```bash
cp config/cluster.example.yml config/cluster.yml
nano config/cluster.yml
```

Потом запусти:

```bash
./scripts/prepare_system.sh
```

## `ansible ping` failed

Проверь, что IP-адреса и пользователи в `config/cluster.yml` указаны правильно.

Можно попробовать автоматически скопировать SSH-ключи:

```bash
./scripts/prepare_system.sh --copy-ssh-keys
```

Или проверить вручную:

```bash
ssh USER@CLIENT_IP
```

## Vault file not found

В обычном сценарии достаточно запустить:

```bash
./scripts/prepare_system.sh
```

Он создаст Vault, если его нет.

Если удалён только `ansible/.vault_pass`, восстанови файл через известный Vault-пароль:

```bash
nano ansible/.vault_pass
chmod 600 ansible/.vault_pass
ansible-vault view ansible/group_vars/all/vault.yml --vault-password-file ansible/.vault_pass
```

Аварийный ручной ввод Vault-пароля:

```bash
./scripts/status.sh --ask-vault-pass
```

## System is not prepared

Если `launch_cluster.sh` сообщает, что система не подготовлена, сначала выполни:

```bash
./scripts/prepare_system.sh
```

## Docker требует sudo на управляющей машине

Пользователь управляющей машины должен иметь доступ к Docker без постоянного sudo:

```bash
sudo usermod -aG docker "$USER"
```

После этого выйди из сессии и зайди снова.

## Ansible: `Host key verification failed`

После пересоздания клиентской машины меняется SSH host key.

```bash
ssh-keygen -R CLIENT_IP
ssh USER@CLIENT_IP
```

Затем повтори:

```bash
./scripts/prepare_system.sh
```

## Клиенты подключены, но сервер не видит hosts

Проверь статус:

```bash
./scripts/status.sh
```

Если серверный runtime очищался, а клиенты сохранили старое состояние проекта, обычная очистка сбросит задачи клиентов без удаления BOINC client:

```bash
./scripts/clean_runtime.sh
./scripts/prepare_system.sh
./scripts/launch_cluster.sh
```

## `Invalid or missing account key` / `Can't find host record`

Это значит, что BOINC server был пересоздан и выдал новый account key, а клиент сохранил старую привязку проекта в `/opt/boinc-client/data`.
В таком состоянии workunits/results уже есть на сервере, но клиенты не получают задачи: scheduler не может сопоставить старый host/account с новой базой.

Переразверни клиентскую часть, чтобы удалить старое BOINC-состояние и заново привязать клиентов:

```bash
./scripts/bootstrap_clients.sh
```

Если эксперимент уже успел набрать ошибки из-за старого ключа, лучше перезапустить runtime целиком:

```bash
./scripts/clean_runtime.sh
./scripts/quickstart.sh --with-monitoring --run-experiment
```

После исправления `bootstrap_clients.sh` сохраняет Docker image cache, но сбрасывает `/opt/boinc-client/data`, чтобы stale account key не попадал в новый запуск.

## Проверить Python/Numba на клиентах

Python-задачи выполняются внутри контейнера `boinc-client`, поэтому `numpy` и `numba` должны быть установлены именно там.

Проверка:

```bash
./scripts/check_client_runtime.sh
```

Если проверка показывает, что `numpy` или `numba` отсутствуют, переразверни клиентскую часть:

```bash
./scripts/bootstrap_clients.sh
```

## `failed to fetch anonymous token` при запуске `boinc-client`

Это ошибка доступа клиентских узлов к Docker Hub при первом build образа `local/boinc-client:ubuntu24`.
BOINC ещё не дошёл до запуска задач: Docker не смог скачать базовый образ `ubuntu:24.04`.

Проверь на каждом клиенте:

```bash
docker pull ubuntu:24.04
```

Если pull падает с `TLS handshake timeout`, проблема в сети/registry/DNS/proxy на клиентских узлах. После восстановления доступа перезапусти только клиентскую часть:

```bash
./scripts/launch_cluster.sh --clients-only
```

Playbook делает несколько повторных попыток и не пересобирает клиентский образ, если `local/boinc-client:ubuntu24` уже есть на узле.

## `failed to fetch anonymous token` при запуске `boinc-exporter`

Это та же сетевая проблема с Docker Hub, но уже на управляющей машине, где запускается monitoring stack.
Exporter собирается из Python-образа:

```text
python:3.12-slim
```

Проверь:

```bash
docker pull python:3.12-slim
```

Если pull падает, можно попробовать другой тег или локальное зеркало:

```bash
BOINC_EXPORTER_BASE_IMAGE=python:3 ./scripts/monitoring_up.sh
```

```bash
BOINC_EXPORTER_BASE_IMAGE=registry.local/library/python:3.12-slim ./scripts/monitoring_up.sh
```

Если образ `monitoring-boinc-exporter:latest` уже собран локально, `monitoring_up.sh` больше не пересобирает его при каждом запуске.

## `results` сильно больше `workunits`

Это нормально, если включена BOINC-репликация. Например, `workunits=50` и `results=150` означает примерно три result-записи на одну workunit.

Results с `outcome=5` (`didnt_need`) не считаются ошибкой клиента. Проверяй реальные ошибки через:

```bash
./scripts/status.sh
```

Или во время ожидания задач:

```bash
./scripts/pump_clients.sh
```

В выводе `client_errors` показывает настоящие проблемные outcomes, а `redundant` показывает лишние results от replication/quorum.

## `upload failure ... error_code -161 (not found)`

BOINC-клиент завершил вычисление, но не нашёл output-файл для загрузки.
Для Python runner это обычно означает, что приложение записало удобное имя `output.json`, а BOINC ожидал физическое имя result-файла вроде `py_..._r123_0`.

После исправления runner читает `init_data.xml`, находит physical filename для `open_name=output.json` и пишет output сразу туда.
Текущий эксперимент с такими ошибками нужно перезапустить:

```bash
./scripts/clean_runtime.sh
./scripts/quickstart.sh --with-monitoring --run-experiment
```

## Loki отвечает `503 ready: failed`

Это проблема готовности хранилища логов и она не блокирует выполнение BOINC-задач.

Перезапусти monitoring stack:

```bash
./scripts/monitoring_down.sh
./scripts/monitoring_up.sh
```

Если ошибка повторяется, проверь логи Loki:

```bash
docker logs boinc-loki --tail 100
```

## Как полностью удалить BOINC client с узлов

Обычная очистка не удаляет BOINC client.

Для полного удаления используй:

```bash
./scripts/clean_runtime.sh --purge-clients
```

## `bad WU template - no <file_info>`

Проверь input template приложения.

Для Python task runner template генерируется автоматически в:

```text
apps/python_task_runner/build/<app_name>_in.generated
```

В template должен быть корректный блок `<file_info>` и блок `<workunit>`. Если файл выглядит старым или пустым, перезапусти отправку задачи:

```bash
./scripts/run_experiment.sh
```

## `workunits=0`, `results=0`

Задачи ещё не созданы:

```bash
./scripts/run_experiment.sh
```

Или запусти кластер с отправкой эксперимента:

```bash
./scripts/launch_cluster.sh --run-experiment
```

## Задачи созданы, но клиенты их не забирают

Проверь статус:

```bash
./scripts/status.sh
```

Если клиенты уже развёрнуты, не нужно повторно запускать весь кластер ради получения следующей порции задач. Запусти auto-update:

```bash
./scripts/pump_clients.sh --max-seconds 600 --interval-seconds 15
```

`run_experiment.sh` запускает этот helper автоматически после создания workunits.

## BOINC-клиент показывает `suspended`

Обычно это локальные preferences BOINC: клиент приостанавливает задачи из-за фоновой CPU-нагрузки.

Переразверни клиентскую часть:

```bash
./scripts/bootstrap_clients.sh
```

После этого проверь:

```bash
./scripts/status.sh
```

## Grafana открывается, но графики пустые

Проверь контейнеры:

```bash
docker ps --filter name=boinc-prometheus
docker ps --filter name=boinc-grafana
docker ps --filter name=boinc-exporter
```

Проверь exporter:

```bash
curl -s http://SERVER_IP:9101/metrics | grep boinc_
```

Проверь, что Prometheus видит targets:

```bash
curl -s http://SERVER_IP:9090/api/v1/targets | grep -E '"health":"up"|lastError'
```

Если Prometheus не видит клиентов, перезапусти мониторинг:

```bash
./scripts/monitoring_down.sh --with-client-agents
./scripts/monitoring_up.sh
```

## Loki пустой или dashboard ошибок не показывает логи

Проверь server-side Loki и Promtail:

```bash
docker ps --filter name=boinc-loki
docker ps --filter name=boinc-promtail
curl -s http://SERVER_IP:3100/ready
```

Проверь datasource и dashboard:

```bash
./scripts/status.sh
```

Если нужны логи клиентов, перезапусти monitoring agents:

```bash
./scripts/monitoring_down.sh --with-client-agents
./scripts/monitoring_up.sh
```

## Dump Grafana не создался после эксперимента

Dump создаётся только если:

- запущен мониторинг;
- `boinc-grafana`, `boinc-grafana-renderer` и Prometheus доступны;
- все текущие BOINC results завершены.

Проверь:

```bash
docker ps --filter name=boinc-grafana
docker ps --filter name=boinc-grafana-renderer
./scripts/status.sh
```

Ручной повтор:

```bash
./scripts/dump_grafana_results.sh --wait --max-seconds 600
```

## Ошибки results растут

Смотри логи серверного контейнера и последние results:

```bash
docker logs --tail=100 boinc-server
./scripts/status.sh
```

Для пользовательских задач проверь входной файл, права на исполняемый файл и формат output.
