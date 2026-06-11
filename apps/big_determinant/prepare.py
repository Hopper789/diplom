#!/usr/bin/env python3
"""Prepare params.jsonl for the big determinant workload."""

from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare big determinant BOINC tasks")
    parser.add_argument("--main", required=True, help="Path to main.py with run(params)")
    parser.add_argument("--out", required=True, help="Output params.jsonl path")
    parser.add_argument("--task-count", type=int, default=1, help="Number of BOINC workunits")
    parser.add_argument("--seed-base", type=int, default=10_000)
    return parser.parse_args()


def validate_main(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Main task file not found: {path}")

    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    has_run = any(isinstance(node, ast.FunctionDef) and node.name == "run" for node in tree.body)
    if not has_run:
        raise ValueError(f"{path} must define a top-level run(params) function")


def write_params(args: argparse.Namespace, output_path: Path) -> int:
    task_count = args.task_count
    if task_count < 1:
        raise ValueError("--task-count must be >= 1")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for task_id in range(1, task_count + 1):
            payload = {
                "task_id": task_id,
                "seed": args.seed_base + task_id,
            }
            json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
            handle.write("\n")

    return task_count


def main() -> int:
    args = parse_args()
    main_path = Path(args.main)
    output_path = Path(args.out)

    validate_main(main_path)
    task_count = write_params(args, output_path)

    print(f"Prepared big_det main: {main_path}")
    print(f"Generated big_det workunits: {task_count}")
    print(f"Output: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
