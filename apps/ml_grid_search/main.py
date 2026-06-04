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
        "Install python3-numpy and python3-numba, then redeploy BOINC clients."
    ) from exc


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


@njit
def _burn_chunk(iterations: int, seed: int) -> float:
    value = 0.125 + seed * 0.000001
    checksum = 0.0
    for index in range(iterations):
        value = math.sin(value + index * 0.000013) + math.cos(value * 1.000017)
        checksum += math.sqrt(abs(value) + 1.0)
    return checksum


def _as_int(params: dict[str, Any], key: str, default: int) -> int:
    return int(params.get(key, default))


def _as_float(params: dict[str, Any], key: str, default: float) -> float:
    return float(params.get(key, default))


def _warm_up_numba() -> None:
    xs, ys = _build_dataset(8, 1)
    intercept, slope = _ridge_fit(xs, ys, 0.1)
    _mean_squared_error(xs, ys, intercept, slope)
    _burn_chunk(16, 1)


def _burn_for_seconds(target_seconds: float, seed: int) -> tuple[int, float, float]:
    if target_seconds <= 0:
        return 0, 0.0, 0.0

    iterations_per_chunk = 250_000
    iterations = 0
    checksum = 0.0
    started = time.perf_counter()

    while True:
        checksum += float(_burn_chunk(iterations_per_chunk, seed + iterations))
        iterations += iterations_per_chunk

        elapsed = time.perf_counter() - started
        if elapsed >= target_seconds:
            return iterations, checksum, elapsed


def run(params: dict[str, Any]) -> dict[str, Any]:
    """Run one ridge-regression parameter point."""

    task_id = _as_int(params, "task_id", 0)
    regularization = float(params.get("lambda", params.get("regularization", 0.0)))
    seed = _as_int(params, "seed", 1000 + task_id)
    dataset_size = max(2, _as_int(params, "n", 500))
    target_seconds = max(0.0, _as_float(params, "target_seconds", 0.0))

    _warm_up_numba()

    xs, ys = _build_dataset(dataset_size, seed)
    intercept, slope = _ridge_fit(xs, ys, regularization)
    loss = _mean_squared_error(xs, ys, intercept, slope)
    burn_iterations, burn_checksum, burn_seconds = _burn_for_seconds(target_seconds, seed)

    return {
        "task_id": task_id,
        "lambda": regularization,
        "seed": seed,
        "n": dataset_size,
        "target_seconds": target_seconds,
        "weights": {
            "intercept": intercept,
            "slope": slope,
        },
        "loss": loss,
        "burn": {
            "iterations": burn_iterations,
            "seconds": round(burn_seconds, 6),
            "checksum": burn_checksum,
        },
        "backend": {
            "python": platform.python_implementation(),
            "numpy": np.__version__,
            "numba": numba.__version__,
        },
    }
