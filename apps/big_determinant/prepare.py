#!/usr/bin/env python3
"""Prepare params.jsonl for the big_determinant Python workload."""

from __future__ import annotations

import argparse
import ast
import json
import math
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare big determinant BOINC tasks")
    parser.add_argument("--main", required=True, help="Path to main.py with run(params)")
    parser.add_argument("--out", required=True, help="Output params.jsonl path")
    parser.add_argument("--wall-seconds", type=float, default=1800.0)
    parser.add_argument("--cores", type=float, default=1.0)
    parser.add_argument("--task-seconds", type=float, default=600.0)
    parser.add_argument("--task-count", type=int, default=None)
    parser.add_argument("--matrix-size", type=int, default=1200)
    parser.add_argument("--seed-base", type=int, default=10_000)
    parser.add_argument("--diagonal-boost", type=float, default=None)
    parser.add_argument("--max-repeats", type=int, default=0)
    return parser.parse_args()


def validate_main(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Main task file not found: {path}")

    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    has_run = any(isinstance(node, ast.FunctionDef) and node.name == "run" for node in tree.body)
    if not has_run:
        raise ValueError(f"{path} must define a top-level run(params) function")


def resolve_task_count(args: argparse.Namespace) -> int:
    if args.task_count is not None:
        return max(1, args.task_count)

    task_seconds = max(1.0, args.task_seconds)
    cores = max(1.0, args.cores)
    wall_seconds = max(1.0, args.wall_seconds)
    return max(1, math.ceil(wall_seconds * cores / task_seconds))


def write_params(args: argparse.Namespace, output_path: Path) -> int:
    task_count = resolve_task_count(args)
    matrix_size = max(2, args.matrix_size)
    diagonal_boost = args.diagonal_boost
    if diagonal_boost is None:
        diagonal_boost = max(1.0, matrix_size * 0.01)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for task_id in range(1, task_count + 1):
            payload = {
                "task_id": task_id,
                "matrix_size": matrix_size,
                "seed": args.seed_base + task_id,
                "target_seconds": max(0.0, args.task_seconds),
                "diagonal_boost": diagonal_boost,
                "max_repeats": max(0, args.max_repeats),
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

    print(f"Prepared big_determinant main: {main_path}")
    print(f"Generated big_determinant params: {task_count}")
    print(f"Output: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
