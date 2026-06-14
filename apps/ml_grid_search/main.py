"""Numba-accelerated parameter sweep task for the BOINC Python runner."""

from __future__ import annotations

import math
import platform
import time
from typing import Any

try:
    import numpy as np
    from numba import njit
    import numba
except ModuleNotFoundError as exc:  # pragma: no cover - validated on client image
    raise RuntimeError(
        "ml_grid_search requires numpy and numba. "
        "Run ./scripts/prepare_system.sh --install-local and redeploy BOINC clients."
    ) from exc


WORKUNITS = 20
DATASET_SIZE = 50_000
REPEAT_COUNT = 60
SEED_BASE = 1000
LAMBDA_GRID = [0.0, 0.001, 0.003, 0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 10.0]


@njit
def _noise(index: int, seed: int) -> float:
    value = math.sin((seed + 1) * (index + 1) * 12.9898) * 43758.5453
    return value - math.floor(value) - 0.5


@njit
def _build_dataset(n: int, seed: int) -> tuple[np.ndarray, np.ndarray]:
    xs = np.empty(n, dtype=np.float64)
    ys = np.empty(n, dtype=np.float64)

    denominator = max(1, n - 1)
    for index in range(n):
        x = -5.0 + 10.0 * index / denominator
        xs[index] = x
        ys[index] = 1.25 + 2.75 * x + 0.35 * _noise(index, seed)

    return xs, ys


@njit
def _ridge_fit(xs: np.ndarray, ys: np.ndarray, regularization: float) -> tuple[float, float]:
    count = xs.size
    sum_x = 0.0
    sum_y = 0.0
    sum_xx = 0.0
    sum_xy = 0.0

    for index in range(count):
        x = xs[index]
        y = ys[index]
        sum_x += x
        sum_y += y
        sum_xx += x * x
        sum_xy += x * y

    a00 = float(count)
    a01 = sum_x
    a11 = sum_xx + regularization
    determinant = a00 * a11 - a01 * a01

    if abs(determinant) < 1e-12:
        return 0.0, 0.0

    intercept = (sum_y * a11 - sum_xy * a01) / determinant
    slope = (a00 * sum_xy - a01 * sum_y) / determinant
    return intercept, slope


@njit
def _mean_squared_error(xs: np.ndarray, ys: np.ndarray, intercept: float, slope: float) -> float:
    total = 0.0
    for index in range(xs.size):
        diff = (intercept + slope * xs[index]) - ys[index]
        total += diff * diff
    return total / max(1, xs.size)


def _as_int(params: dict[str, Any], key: str, default: int) -> int:
    return int(params.get(key, default))


def _warm_up_numba() -> None:
    xs, ys = _build_dataset(8, 1)
    intercept, slope = _ridge_fit(xs, ys, 0.1)
    _mean_squared_error(xs, ys, intercept, slope)


def run(params: dict[str, Any]) -> dict[str, Any]:
    """Run one ridge-regression parameter point."""

    task_id = _as_int(params, "task_id", 0)
    regularization = float(params.get("lambda", params.get("regularization", 0.0)))
    seed = _as_int(params, "seed", SEED_BASE + task_id)
    dataset_size = max(2, _as_int(params, "n", DATASET_SIZE))
    repeat_count = max(1, _as_int(params, "repeats", REPEAT_COUNT))

    _warm_up_numba()

    started = time.perf_counter()
    intercept = 0.0
    slope = 0.0
    loss_total = 0.0

    for repeat_index in range(repeat_count):
        xs, ys = _build_dataset(dataset_size, seed + repeat_index)
        intercept, slope = _ridge_fit(xs, ys, regularization)
        loss_total += _mean_squared_error(xs, ys, intercept, slope)

    loss = loss_total / repeat_count
    elapsed = time.perf_counter() - started

    return {
        "task_id": task_id,
        "lambda": regularization,
        "seed": seed,
        "n": dataset_size,
        "repeats": repeat_count,
        "weights": {
            "intercept": intercept,
            "slope": slope,
        },
        "loss": loss,
        "elapsed_seconds": round(elapsed, 6),
        "backend": {
            "python": platform.python_implementation(),
            "numpy": np.__version__,
            "numba": numba.__version__,
        },
    }
