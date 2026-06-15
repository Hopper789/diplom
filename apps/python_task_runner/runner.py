#!/usr/bin/env python3
"""CLI runner для одной независимой пользовательской Python-задачи."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import socket
import time
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


def parse_failure_rate() -> float:
    value = os.getenv("BOINC_SIMULATE_FAILURE_RATE", "0").strip() or "0"
    try:
        rate = float(value)
    except ValueError as exc:
        raise ValueError("BOINC_SIMULATE_FAILURE_RATE должен быть числом от 0 до 1") from exc

    if not 0 <= rate <= 1:
        raise ValueError("BOINC_SIMULATE_FAILURE_RATE должен быть в диапазоне от 0 до 1")
    return rate


def parse_failure_after_seconds() -> float:
    value = os.getenv("BOINC_SIMULATE_FAILURE_AFTER_SECONDS", "0").strip() or "0"
    try:
        seconds = float(value)
    except ValueError as exc:
        raise ValueError("BOINC_SIMULATE_FAILURE_AFTER_SECONDS должен быть числом >= 0") from exc

    if seconds < 0:
        raise ValueError("BOINC_SIMULATE_FAILURE_AFTER_SECONDS должен быть >= 0")
    return seconds


def boinc_attempt_name() -> str:
    init_path = Path("init_data.xml")
    if not init_path.exists():
        return ""

    text = init_path.read_text(encoding="utf-8", errors="replace")
    for tag in ("result_name", "result"):
        match = re.search(rf"<{tag}>(.*?)</{tag}>", text, flags=re.S)
        if match:
            return match.group(1).strip()
    return ""


def burn_cpu(seconds: float) -> None:
    deadline = time.monotonic() + seconds
    value = 0x12345678
    while time.monotonic() < deadline:
        for _ in range(10000):
            value = ((value * 1664525) + 1013904223) & 0xFFFFFFFF


def maybe_simulate_failure(task_id: object) -> None:
    rate = parse_failure_rate()
    if rate <= 0:
        return

    seed = os.getenv("BOINC_SIMULATE_FAILURE_SEED", "default")
    host = socket.gethostname()
    attempt = boinc_attempt_name()
    key = f"{seed}:{task_id}:{host}:{attempt}"
    digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
    value = int(digest[:16], 16) / 0xFFFFFFFFFFFFFFFF

    if value < rate:
        after_seconds = parse_failure_after_seconds()
        if after_seconds > 0:
            burn_cpu(after_seconds)
        raise RuntimeError(
            "simulated BOINC attempt failure "
            f"(rate={rate:.3f}, seed={seed}, task_id={task_id}, host={host}, "
            f"attempt={attempt or 'local'}, after_seconds={after_seconds:.3f})"
        )


def main() -> int:
    args = parse_args()
    task_id = None

    try:
        input_data = load_input(args.input)
        task_id = input_data["task_id"]
        maybe_simulate_failure(task_id)
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
