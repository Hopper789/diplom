"""Regularized log-determinant benchmark for the BOINC Python runner."""

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
        "regularized_logdet requires numpy. "
        "Run ./scripts/prepare_system.sh --install-local and redeploy BOINC clients."
    ) from exc


MATRIX_SIZE = 8000
DIAGONAL_BOOST = max(1.0, MATRIX_SIZE * 0.01)
REGULARIZATION_LAMBDAS = (
    0.0,
    1.0e-4,
    3.0e-4,
    1.0e-3,
    3.0e-3,
    1.0e-2,
    3.0e-2,
    1.0e-1,
    3.0e-1,
    1.0,
    3.0,
    10.0,
    30.0,
    100.0,
    300.0,
    1000.0,
)
WORKUNITS = 4


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
    matrix = np.empty((size, size), dtype=np.float64, order="F")
    rng.standard_normal(out=matrix)
    diagonal = np.diag_indices_from(matrix)
    matrix[diagonal] += DIAGONAL_BOOST
    return matrix


def run(params: dict[str, Any]) -> dict[str, Any]:
    """Compute a regularized log-determinant path for one deterministic matrix."""

    task_id = _as_int(params, "task_id", 1)
    seed = _as_int(params, "seed", 10_000 + task_id)

    started = time.perf_counter()
    matrix = _build_matrix(MATRIX_SIZE, seed)
    diagonal = np.diag_indices_from(matrix)
    current_lambda = 0.0
    path = []

    for lambda_value in REGULARIZATION_LAMBDAS:
        lambda_value = float(lambda_value)
        matrix[diagonal] += lambda_value - current_lambda
        current_lambda = lambda_value

        lambda_started = time.perf_counter()
        sign, log_abs_det = np.linalg.slogdet(matrix)
        lambda_elapsed = time.perf_counter() - lambda_started

        sign = float(sign)
        log_abs_det = float(log_abs_det)
        path.append(
            {
                "lambda": lambda_value,
                "sign": sign,
                "log_abs": log_abs_det,
                "scientific": _scientific_from_log(sign, log_abs_det),
                "elapsed_seconds": round(lambda_elapsed, 6),
            }
        )

    elapsed = time.perf_counter() - started

    valid_path = [point for point in path if point["sign"] != 0.0 and math.isfinite(point["log_abs"])]
    selected = min(valid_path, key=lambda point: point["lambda"]) if valid_path else path[-1]

    return {
        "task_id": task_id,
        "workload": "regularized_logdet",
        "matrix": {
            "size": MATRIX_SIZE,
            "seed": seed,
            "diagonal_boost": DIAGONAL_BOOST,
            "dtype": "float64",
        },
        "regularization": {
            "lambdas": list(REGULARIZATION_LAMBDAS),
            "selected_lambda": selected["lambda"],
            "selected_rule": "smallest lambda with finite non-zero determinant",
            "path": path,
        },
        "elapsed_seconds": round(elapsed, 6),
        "backend": {
            "python": platform.python_implementation(),
            "numpy": np.__version__,
            "linear_algebra": "numpy.linalg.slogdet over A + lambda I",
            "numeric_threads": NUMERIC_THREADS,
        },
    }
