#!/usr/bin/env python3
"""Generate params.jsonl for the ml_grid_search Python workload."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


DEFAULT_LAMBDA_GRID = "0,0.001,0.003,0.01,0.03,0.1,0.3,1,3,10"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate ml_grid_search params.jsonl")
    parser.add_argument("--out", required=True, help="Output params.jsonl path")
    parser.add_argument("--wall-seconds", type=float, default=180.0)
    parser.add_argument("--cores", type=float, default=12.0)
    parser.add_argument("--task-seconds", type=float, default=8.0)
    parser.add_argument("--task-count", type=int, default=None)
    parser.add_argument("--dataset-size", type=int, default=500)
    parser.add_argument("--seed-base", type=int, default=1000)
    parser.add_argument("--lambda-grid", default=DEFAULT_LAMBDA_GRID)
    return parser.parse_args()


def parse_lambda_grid(value: str) -> list[float]:
    grid: list[float] = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        grid.append(float(item))

    if not grid:
        raise ValueError("lambda grid must contain at least one value")
    return grid


def resolve_task_count(args: argparse.Namespace) -> int:
    if args.task_count is not None:
        return max(1, args.task_count)

    task_seconds = max(1.0, args.task_seconds)
    cores = max(1.0, args.cores)
    wall_seconds = max(1.0, args.wall_seconds)
    return max(1, math.ceil(wall_seconds * cores / task_seconds))


def main() -> int:
    args = parse_args()
    task_count = resolve_task_count(args)
    lambda_grid = parse_lambda_grid(args.lambda_grid)
    output_path = Path(args.out)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", encoding="utf-8") as handle:
        for task_id in range(1, task_count + 1):
            regularization = lambda_grid[(task_id - 1) % len(lambda_grid)]
            payload = {
                "task_id": task_id,
                "lambda": regularization,
                "seed": args.seed_base + task_id,
                "n": max(2, args.dataset_size),
                "target_seconds": max(0.0, args.task_seconds),
            }
            json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
            handle.write("\n")

    print(f"Generated ml_grid_search params: {task_count}")
    print(f"Output: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
