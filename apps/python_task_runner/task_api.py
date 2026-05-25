"""Общие функции для пользовательских Python-задач."""

from __future__ import annotations

import importlib.util
import json
import time
from pathlib import Path
from types import ModuleType
from typing import Any


def load_input(path: str | Path) -> dict[str, Any]:
    """Загрузить один input.json."""
    with Path(path).open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    if not isinstance(data, dict):
        raise ValueError("input.json должен быть JSON-объектом")
    if "task_id" not in data:
        raise ValueError("input.json должен содержать task_id")
    if "params" not in data:
        raise ValueError("input.json должен содержать params")
    if not isinstance(data["params"], dict):
        raise ValueError("params должен быть JSON-объектом")

    data.setdefault("resources", {"device": "cpu"})
    return data


def write_output(path: str | Path, data: dict[str, Any]) -> None:
    """Записать output.json атомарно для простого восстановления после сбоев."""
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = output_path.with_suffix(output_path.suffix + ".tmp")

    with tmp_path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")

    tmp_path.replace(output_path)


def _load_module(module_path: str | Path) -> ModuleType:
    path = Path(module_path).resolve()
    if not path.exists():
        raise FileNotFoundError(f"Файл задачи не найден: {path}")

    spec = importlib.util.spec_from_file_location("user_task", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"Не удалось загрузить модуль задачи: {path}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_user_task(module_path: str | Path, params: dict[str, Any]) -> Any:
    """Загрузить user_task.py и вызвать функцию run(params)."""
    module = _load_module(module_path)
    run_func = getattr(module, "run", None)

    if run_func is None or not callable(run_func):
        raise AttributeError("user_task.py должен содержать функцию run(params)")

    return run_func(params)


def measure_compute_seconds(module_path: str | Path, params: dict[str, Any]) -> tuple[Any, float]:
    """Выполнить пользовательскую задачу и измерить чистое время run(params)."""
    started = time.perf_counter()
    result = run_user_task(module_path, params)
    finished = time.perf_counter()
    return result, finished - started
