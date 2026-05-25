#!/usr/bin/env python3
"""CLI runner для одной независимой пользовательской Python-задачи."""

from __future__ import annotations

import argparse
import traceback
from pathlib import Path

from task_api import load_input, measure_compute_seconds, write_output


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Запустить одну Python-задачу")
    parser.add_argument("--task", required=True, help="Путь к user_task.py")
    parser.add_argument("--input", required=True, help="Путь к input.json")
    parser.add_argument("--output", required=True, help="Путь к output.json")
    parser.add_argument(
        "--fail-on-error",
        action="store_true",
        help="Вернуть ненулевой код, если user_task.py завершился ошибкой",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    task_id = None

    try:
        input_data = load_input(args.input)
        task_id = input_data["task_id"]
        result, compute_seconds = measure_compute_seconds(args.task, input_data["params"])

        output_data = {
            "task_id": task_id,
            "status": "ok",
            "result": result,
            "timing": {
                "compute_seconds": round(compute_seconds, 6),
            },
        }
        write_output(args.output, output_data)
        return 0

    except Exception as exc:  # noqa: BLE001
        output_data = {
            "task_id": task_id,
            "status": "error",
            "error": str(exc),
            "traceback": traceback.format_exc(limit=8),
        }
        write_output(args.output, output_data)
        return 1 if args.fail_on_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
