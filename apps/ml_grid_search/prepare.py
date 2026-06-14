#!/usr/bin/env python3
"""Prepare params.jsonl for the ml_grid_search workload."""

from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path
from typing import Any


DEFAULTS: dict[str, Any] = {
    "WORKUNITS": 1,
    "DATASET_SIZE": 500,
    "REPEAT_COUNT": 1,
    "SEED_BASE": 1000,
    "LAMBDA_GRID": [0.0, 0.001, 0.003, 0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 10.0],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare ml_grid_search BOINC tasks")
    parser.add_argument("--main", required=True, help="Path to main.py with run(params)")
    parser.add_argument("--out", required=True, help="Output params.jsonl path")
    return parser.parse_args()


def read_task_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"Main task file not found: {path}")

    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    has_run = any(isinstance(node, ast.FunctionDef) and node.name == "run" for node in tree.body)
    if not has_run:
        raise ValueError(f"{path} must define a top-level run(params) function")

    config = dict(DEFAULTS)
    for node in tree.body:
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        if not isinstance(target, ast.Name) or target.id not in config:
            continue
        config[target.id] = ast.literal_eval(node.value)

    config["WORKUNITS"] = int(config["WORKUNITS"])
    config["DATASET_SIZE"] = int(config["DATASET_SIZE"])
    config["REPEAT_COUNT"] = int(config["REPEAT_COUNT"])
    config["SEED_BASE"] = int(config["SEED_BASE"])
    config["LAMBDA_GRID"] = [float(value) for value in config["LAMBDA_GRID"]]

    if config["WORKUNITS"] < 1:
        raise ValueError("WORKUNITS must be >= 1")
    if config["DATASET_SIZE"] < 2:
        raise ValueError("DATASET_SIZE must be >= 2")
    if config["REPEAT_COUNT"] < 1:
        raise ValueError("REPEAT_COUNT must be >= 1")
    if not config["LAMBDA_GRID"]:
        raise ValueError("LAMBDA_GRID must contain at least one value")

    return config


def write_params(config: dict[str, Any], output_path: Path) -> int:
    task_count = int(config["WORKUNITS"])
    dataset_size = int(config["DATASET_SIZE"])
    repeat_count = int(config["REPEAT_COUNT"])
    seed_base = int(config["SEED_BASE"])
    lambda_grid = list(config["LAMBDA_GRID"])

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        for task_id in range(1, task_count + 1):
            payload = {
                "task_id": task_id,
                "lambda": lambda_grid[(task_id - 1) % len(lambda_grid)],
                "seed": seed_base + task_id,
                "n": dataset_size,
                "repeats": repeat_count,
            }
            json.dump(payload, handle, ensure_ascii=False, sort_keys=True)
            handle.write("\n")

    return task_count


def main() -> int:
    args = parse_args()
    main_path = Path(args.main)
    output_path = Path(args.out)

    config = read_task_config(main_path)
    task_count = write_params(config, output_path)

    print(f"Prepared ml_grid_search main: {main_path}")
    print(f"Generated ml_grid_search workunits: {task_count}")
    print(f"Dataset size: {config['DATASET_SIZE']}")
    print(f"Repeats per workunit: {config['REPEAT_COUNT']}")
    print(f"Lambda grid size: {len(config['LAMBDA_GRID'])}")
    print(f"Output: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
