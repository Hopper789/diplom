#!/usr/bin/env python3
"""Генератор input_000001.json из params.jsonl."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from task_api import write_output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Сгенерировать input.json-файлы")
    parser.add_argument("--params", required=True, help="Путь к params.jsonl")
    parser.add_argument("--out", required=True, help="Каталог для input_*.json")
    parser.add_argument("--device", default="cpu", choices=["cpu", "gpu"], help="Тип ресурса")
    return parser.parse_args()


def read_params(path: Path) -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            try:
                value = json.loads(stripped)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: некорректный JSON: {exc}") from exc

            if not isinstance(value, dict):
                raise ValueError(f"{path}:{line_number}: каждая строка должна быть JSON-объектом")
            tasks.append(value)

    if not tasks:
        raise ValueError(f"В {path} нет задач")
    return tasks


def main() -> int:
    args = parse_args()
    params_path = Path(args.params)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    for old_file in out_dir.glob("input_*.json"):
        old_file.unlink()

    for index, params in enumerate(read_params(params_path), start=1):
        input_data = {
            "task_id": index,
            "params": params,
            "resources": {
                "device": args.device,
            },
        }
        write_output(out_dir / f"input_{index:06d}.json", input_data)

    print(f"Создано input-файлов: {index}")
    print(f"Каталог: {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
