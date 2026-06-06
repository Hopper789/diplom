"""CPU-heavy determinant workload for the BOINC Python runner."""

from __future__ import annotations

import math
import platform
import time
from typing import Any

try:
    import numpy as np
    import numba
    from numba import njit
except ModuleNotFoundError as exc:  # pragma: no cover - validated on client image
    raise RuntimeError(
        "big_determinant requires numpy and numba. "
        "Run ./scripts/prepare_system.sh --install-local and redeploy BOINC clients."
    ) from exc


@njit(cache=True)
def _fill_matrix(size: int, seed: int, diagonal_boost: float) -> np.ndarray:
    matrix = np.empty((size, size), dtype=np.float64)
    seed_value = float(seed + 1)

    for row in range(size):
        row_value = float(row + 1)
        for col in range(size):
            col_value = float(col + 1)
            angle = (row_value * 12.9898 + col_value * 78.233 + seed_value * 0.137)
            value = math.sin(angle) * 0.5 + math.cos(angle * 0.37) * 0.5
            if row == col:
                value += diagonal_boost
            matrix[row, col] = value

    return matrix


def _as_int(params: dict[str, Any], key: str, default: int) -> int:
    return int(params.get(key, default))


def _as_float(params: dict[str, Any], key: str, default: float) -> float:
    return float(params.get(key, default))


def _warm_up_numba() -> None:
    _fill_matrix(4, 1, 1.0)


def _scientific_from_log(sign: float, log_abs_det: float) -> dict[str, Any]:
    if sign == 0 or not math.isfinite(log_abs_det):
        return {"mantissa": 0.0, "exponent10": 0}

    exponent10 = math.floor(log_abs_det / math.log(10.0))
    mantissa = float(sign) * math.exp(log_abs_det - exponent10 * math.log(10.0))
    return {"mantissa": mantissa, "exponent10": int(exponent10)}


def run(params: dict[str, Any]) -> dict[str, Any]:
    """Compute determinant-like metrics for one generated dense matrix."""

    task_id = _as_int(params, "task_id", 1)
    size = max(2, _as_int(params, "matrix_size", 1200))
    seed = _as_int(params, "seed", 10_000 + task_id)
    target_seconds = max(0.0, _as_float(params, "target_seconds", 1800.0))
    max_repeats = max(0, _as_int(params, "max_repeats", 0))
    diagonal_boost = _as_float(params, "diagonal_boost", max(1.0, size * 0.01))

    _warm_up_numba()

    started = time.perf_counter()
    repeats = 0
    last_sign = 0.0
    last_log_abs_det = 0.0
    checksum = 0.0
    first_det_seconds = 0.0

    while True:
        repeat_started = time.perf_counter()
        matrix = _fill_matrix(size, seed + repeats, diagonal_boost)
        sign, log_abs_det = np.linalg.slogdet(matrix)
        repeat_seconds = time.perf_counter() - repeat_started

        repeats += 1
        last_sign = float(sign)
        last_log_abs_det = float(log_abs_det)
        checksum += last_sign * last_log_abs_det
        if repeats == 1:
            first_det_seconds = repeat_seconds

        elapsed = time.perf_counter() - started
        if max_repeats > 0 and repeats >= max_repeats:
            break
        if target_seconds <= 0 or elapsed >= target_seconds:
            break

    elapsed = time.perf_counter() - started
    return {
        "task_id": task_id,
        "matrix_size": size,
        "seed": seed,
        "target_seconds": target_seconds,
        "elapsed_seconds": round(elapsed, 6),
        "repeats": repeats,
        "first_determinant_seconds": round(first_det_seconds, 6),
        "determinant": {
            "sign": last_sign,
            "log_abs": last_log_abs_det,
            "scientific": _scientific_from_log(last_sign, last_log_abs_det),
        },
        "checksum": checksum,
        "backend": {
            "python": platform.python_implementation(),
            "numpy": np.__version__,
            "numba": numba.__version__,
        },
    }
