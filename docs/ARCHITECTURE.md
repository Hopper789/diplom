# Архитектура

Этот документ описывает, как данные, задачи и результаты проходят через
кластер.

## Роли компонентов

- Управляющая машина запускает BOINC server, MariaDB, Prometheus, Grafana,
  Loki и служебные exporter'ы.
- Клиентские узлы запускают BOINC client в Docker-контейнере и выполняют
  полученные workunit'ы.
- Ansible нужен для подготовки клиентов, копирования SSH-ключей, запуска
  контейнеров и команд управления.
- BOINC отвечает за очередь задач, выдачу workunit'ов, скачивание входных
  файлов, запуск приложения и загрузку результатов.
- Python runner отвечает только за выполнение пользовательской функции
  `run(params)` внутри уже выданной BOINC-задачи.

## Общий поток выполнения

```text
params.jsonl / dataset.csv
        |
        v
apps/python_task_runner/run_task.sh
        |
        v
BOINC create_work + input/output templates
        |
        v
MariaDB: workunit/result/app_version
        |
        v
BOINC client получает задачу через scheduler HTTP API
        |
        v
BOINC client скачивает input-файлы по HTTP
        |
        v
slot-директория клиента: input.json, dataset.csv, приложение
        |
        v
Python runner вызывает run(params)
        |
        v
output.json
        |
        v
BOINC client загружает результат на сервер по HTTP
        |
        v
MariaDB + файлы результата + метрики Grafana
```

## Как передаются параметры

Параметры задачи задаются JSONL-файлом. Каждая строка — один уникальный
workunit:

```json
{"task_id": 1, "lambda": 0.1, "dataset_file": "dataset.csv"}
{"task_id": 2, "lambda": 1.0, "dataset_file": "dataset.csv"}
```

`apps/python_task_runner/generate_inputs.py` превращает эти строки в отдельные
файлы:

```text
input_000001.json
input_000002.json
...
```

При создании workunit BOINC получает физический файл вроде
`input_000001.json`, но на клиенте открывает его как:

```text
input.json
```

Python runner читает `input.json`, достаёт поле `params` и вызывает:

```python
run(params)
```

## Как передаётся датасет

Большие данные не кладутся внутрь JSONL. Они передаются отдельным входным
файлом BOINC.

Например для `grid-search` подготовительный шаг создаёт:

```text
apps/ml_grid_search/build/dataset.csv
apps/ml_grid_search/build/params.jsonl
```

Дальше `apps/ml_grid_search/run_task.sh` вызывает общий runner с дополнительным
файлом:

```bash
apps/python_task_runner/run_task.sh \
  --task apps/ml_grid_search/main.py \
  --params apps/ml_grid_search/build/params.jsonl \
  --extra-input apps/ml_grid_search/build/dataset.csv:dataset.csv
```

`--extra-input SOURCE:OPEN_NAME` означает:

- `SOURCE` — локальный файл на управляющей машине;
- `OPEN_NAME` — имя файла в рабочей директории задачи на клиенте.

Для клиента это выглядит просто:

```text
input.json
dataset.csv
```

Задача читает датасет как обычный локальный файл:

```python
data = np.loadtxt("dataset.csv", delimiter=",", skiprows=1)
```

Передача выполняется штатными механизмами BOINC по HTTP. Python-код не
отправляет файлы по сети.

## Как BOINC доставляет файлы

Серверная сторона:

1. `stage_file_native` помещает входной файл в download area BOINC-проекта.
2. `create_work` создаёт workunit и связывает его с входными файлами.
3. Input template задаёт, под какими именами файлы будут доступны клиенту.

Клиентская сторона:

1. BOINC client делает scheduler request по HTTP.
2. Сервер отвечает, какую задачу взять и какие файлы скачать.
3. Клиент скачивает приложение, `input.json` и дополнительные файлы по HTTP.
4. BOINC создаёт slot-директорию и запускает приложение.
5. После завершения клиент загружает `output.json` обратно на сервер по HTTP.

SSH и Ansible в этом процессе не передают данные workunit'ов. Они нужны только
для администрирования узлов.

## Как запускается Python-задача

BOINC запускает не сам `main.py`, а небольшой shell-launcher приложения.
Launcher:

1. находит корректный `input.json`;
2. вызывает `apps/python_task_runner/runner.py`;
3. runner импортирует файл задачи;
4. runner вызывает `run(params)`;
5. результат записывается в `output.json`;
6. launcher передаёт `output.json` обратно BOINC-клиенту.

Минимальная пользовательская задача:

```python
def run(params):
    return {"value": params["x"] * 2}
```

## Где хранится результат

Пользовательский результат хранится в загруженном `output.json`:

```json
{
  "status": "ok",
  "result": {
    "value": 42
  },
  "timing": {
    "compute_seconds": 12.34
  }
}
```

MariaDB не хранит весь JSON результата. В базе лежат состояния BOINC:
`workunit`, `result`, `host`, `app_version`, время выполнения, outcome и ссылка
на загруженный output-файл.

Подробнее про выгрузку: [RESULT_EXPORT.md](RESULT_EXPORT.md).

## Как появляются метрики

Метрики берутся из нескольких источников:

- `boinc-exporter` читает BOINC/MariaDB и отдаёт состояние workunit/result/host;
- node-exporter на клиентах отдаёт CPU, RAM и сеть клиентских узлов;
- Prometheus собирает эти метрики;
- Grafana показывает итоговые панели и графики;
- Promtail отправляет Docker/BOINC-логи в Loki.

Нагрузка управляющей машины в основные графики CPU/RAM/сеть не входит.

## Репликация

BOINC различает:

- `workunit` — уникальную задачу;
- `result` — попытку выполнения этой задачи.

Если включена репликация, у одного workunit может быть несколько result'ов.
Например при `target_nresults=2` и `min_quorum=2` BOINC старается получить две
успешные попытки. При ошибке или таймауте он может создать replacement attempt,
если это разрешено `max_total_results` и `max_error_results`.

Для дипломных метрик важно:

- `Готово` считается по подтверждённым workunit'ам;
- `Факт. репликация` показывает attempts на workunit;
- `Полезная нагрузка` считает реплики и ошибки накладными расходами.

## Как добавить свою задачу с датасетом

1. Подготовь данные на управляющей машине, например:

```text
data/train.csv
```

2. Подготовь параметры:

```json
{"task_id": 1, "alpha": 0.01, "dataset_file": "train.csv"}
{"task_id": 2, "alpha": 0.1, "dataset_file": "train.csv"}
```

3. В `user_task.py` читай файл по имени из параметров:

```python
from pathlib import Path
import numpy as np

def run(params):
    dataset_file = params.get("dataset_file", "train.csv")
    data = np.loadtxt(Path(dataset_file), delimiter=",", skiprows=1)
    return {"rows": int(data.shape[0]), "alpha": params["alpha"]}
```

4. Отправь задачу:

```bash
apps/python_task_runner/run_task.sh \
  --task path/to/user_task.py \
  --params path/to/params.jsonl \
  --extra-input data/train.csv:train.csv
```

Так параметры остаются маленькими, а датасет передаётся как отдельный файл
BOINC.
