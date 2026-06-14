"""Real determinant workload for the BOINC Python runner."""

from __future__ import annotations

import math
import os
import platform
import time
from typing import Any


def _configure_numeric_threads() -> int:
    threads = max(1, os.cpu_count() or 1)
    for name in (
        "OMP_NUM_THREADS",
        "OPENBLAS_NUM_THREADS",
        "MKL_NUM_THREADS",
        "NUMEXPR_NUM_THREADS",
        "VECLIB_MAXIMUM_THREADS",
    ):
        os.environ[name] = str(threads)
    return threads


NUMERIC_THREADS = _configure_numeric_threads()

try:
    import numpy as np
except ModuleNotFoundError as exc:  # pragma: no cover - validated on client image
    raise RuntimeError(
        "big_determinant requires numpy. "
        "Run ./scripts/prepare_system.sh --install-local and redeploy BOINC clients."
    ) from exc


MATRIX_SIZE = 8000
DIAGONAL_BOOST = max(1.0, MATRIX_SIZE * 0.01)
WORKUNITS = 20


def _as_int(params: dict[str, Any], key: str, default: int) -> int:
    return int(params.get(key, default))


def _scientific_from_log(sign: float, log_abs_det: float) -> dict[str, Any]:
    if sign == 0 or not math.isfinite(log_abs_det):
        return {"mantissa": 0.0, "exponent10": 0}

    exponent10 = math.floor(log_abs_det / math.log(10.0))
    mantissa = float(sign) * math.exp(log_abs_det - exponent10 * math.log(10.0))
    return {"mantissa": mantissa, "exponent10": int(exponent10)}


def _build_matrix(size: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    matrix = rng.standard_normal((size, size)).astype(np.float64, copy=False)
    diagonal = np.diag_indices_from(matrix)
    matrix[diagonal] += DIAGONAL_BOOST
    return matrix


def run(params: dict[str, Any]) -> dict[str, Any]:
    """Compute one determinant for one deterministic matrix."""

    task_id = _as_int(params, "task_id", 1)
    seed = _as_int(params, "seed", 10_000 + task_id)

    started = time.perf_counter()
    matrix = _build_matrix(MATRIX_SIZE, seed)
    sign, log_abs_det = np.linalg.slogdet(matrix)
    elapsed = time.perf_counter() - started

    sign = float(sign)
    log_abs_det = float(log_abs_det)

    return {
        "task_id": task_id,
        "workload": "big_determinant",
        "matrix": {
            "size": MATRIX_SIZE,
            "seed": seed,
            "diagonal_boost": DIAGONAL_BOOST,
            "dtype": "float64",
        },
        "determinant": {
            "sign": sign,
            "log_abs": log_abs_det,
            "scientific": _scientific_from_log(sign, log_abs_det),
        },
        "elapsed_seconds": round(elapsed, 6),
        "backend": {
            "python": platform.python_implementation(),
            "numpy": np.__version__,
            "linear_algebra": "numpy.linalg.slogdet",
            "numeric_threads": NUMERIC_THREADS,
        },
    }
