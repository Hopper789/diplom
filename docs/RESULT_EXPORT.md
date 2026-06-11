# Выгрузка результатов вычислений

Этот файл описывает только поля BOINC DB, которые нужны, чтобы забрать вывод функции `run(params)`.

## Где лежит результат функции

Python runner пишет файл `output.json`. В нём пользовательский результат находится здесь:

```json
{
  "status": "ok",
  "result": {
    "...": "..."
  },
  "timing": {
    "compute_seconds": 12.34
  }
}
```

В MariaDB сам JSON не хранится. База хранит только связь `workunit -> result` и имя загруженного output-файла.

## Нужные таблицы

| Таблица | Поле | Зачем нужно |
|---|---|---|
| `workunit` | `id` | ID уникальной задачи |
| `workunit` | `name` | имя workunit, удобно для сопоставления с параметрами |
| `workunit` | `canonical_resultid` | ID принятого результата; главный указатель на финальный output |
| `result` | `id` | ID попытки выполнения |
| `result` | `workunitid` | связь с `workunit.id` |
| `result` | `name` | имя result/attempt |
| `result` | `outcome` | итог attempt; `1` означает успешное выполнение |
| `result` | `validate_state` | состояние валидации BOINC |
| `result` | `hostid` | клиентский узел, который вернул result |
| `result` | `received_time` | время возврата result на сервер |
| `result` | `elapsed_time` | время вычисления на клиенте, если заполнено |
| `result` | `xml_doc_out` | XML с физическим именем загруженного `output.json` |
| `result` | `stderr_out` | ошибка/диагностика, если задача упала |

## Финальные результаты

Для обычной выгрузки бери только canonical result:

```sql
SELECT
  w.id AS workunit_id,
  w.name AS workunit_name,
  r.id AS result_id,
  r.name AS result_name,
  r.hostid,
  r.received_time,
  r.elapsed_time,
  r.xml_doc_out
FROM workunit w
JOIN result r ON r.id = w.canonical_resultid
WHERE w.canonical_resultid <> 0
ORDER BY w.id;
```

В `r.xml_doc_out` нужно найти тег `<name>...</name>`. Это физическое имя output-файла в BOINC upload directory. Уже из этого файла читается поле JSON `result`.

## Если нужны все успешные attempts

Canonical result — это финальный результат workunit. Если нужно выгрузить все успешные реплики, используй:

```sql
SELECT
  w.id AS workunit_id,
  w.name AS workunit_name,
  r.id AS result_id,
  r.name AS result_name,
  r.hostid,
  r.received_time,
  r.elapsed_time,
  r.xml_doc_out
FROM result r
JOIN workunit w ON w.id = r.workunitid
WHERE r.outcome = 1
ORDER BY w.id, r.id;
```

## Ошибочные задачи

Для ошибок JSON-результата может не быть. Тогда смотри:

```sql
SELECT
  w.id AS workunit_id,
  w.name AS workunit_name,
  r.id AS result_id,
  r.name AS result_name,
  r.outcome,
  r.stderr_out
FROM result r
JOIN workunit w ON w.id = r.workunitid
WHERE r.outcome IN (2, 3, 4, 6)
ORDER BY r.id DESC;
```

Коротко: для пользовательских результатов нужны `workunit.canonical_resultid`, `result.xml_doc_out` и сам загруженный `output.json`.
