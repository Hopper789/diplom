"""Numba-accelerated parameter sweep task for the BOINC Python runner."""

from __future__ import annotations

import hashlib
import platform
import time
from pathlib import Path
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
DATASET_FILE = "dataset.csv"
DATASET_SEED = 1000
LAMBDA_GRID = [0.0, 0.001, 0.003, 0.01, 0.03, 0.1, 0.3, 1.0, 3.0, 10.0]


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


def _resolve_dataset_path(params: dict[str, Any]) -> Path:
    file_name = str(params.get("dataset_file") or params.get("dataset") or DATASET_FILE)
    candidates = [Path(file_name)]

    dataset_path = params.get("dataset_path")
    if dataset_path:
        candidates.append(Path(str(dataset_path)))

    for candidate in candidates:
        if candidate.exists():
            return candidate

    checked = ", ".join(str(candidate) for candidate in candidates)
    raise FileNotFoundError(f"Dataset CSV not found. Checked: {checked}")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_dataset(params: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, Path]:
    dataset_path = _resolve_dataset_path(params)
    expected_sha256 = str(params.get("dataset_sha256") or "")
    if expected_sha256 and _sha256_file(dataset_path) != expected_sha256:
        raise ValueError(f"Dataset CSV checksum mismatch: {dataset_path}")

    data = np.loadtxt(dataset_path, delimiter=",", skiprows=1, dtype=np.float64)

    if data.ndim != 2 or data.shape[1] < 2:
        raise ValueError(f"Dataset CSV must contain at least two columns: {dataset_path}")

    xs = np.ascontiguousarray(data[:, 0], dtype=np.float64)
    ys = np.ascontiguousarray(data[:, 1], dtype=np.float64)
    if xs.size < 2:
        raise ValueError(f"Dataset CSV must contain at least two rows: {dataset_path}")

    return xs, ys, dataset_path


def _warm_up_numba() -> None:
    xs = np.linspace(-1.0, 1.0, 8, dtype=np.float64)
    ys = 1.25 + 2.75 * xs
    intercept, slope = _ridge_fit(xs, ys, 0.1)
    _mean_squared_error(xs, ys, intercept, slope)


def run(params: dict[str, Any]) -> dict[str, Any]:
    """Run one ridge-regression parameter point."""

    task_id = _as_int(params, "task_id", 0)
    regularization = float(params.get("lambda", params.get("regularization", 0.0)))
    repeat_count = max(1, _as_int(params, "repeats", REPEAT_COUNT))

    xs, ys, dataset_path = _load_dataset(params)
    _warm_up_numba()

    started = time.perf_counter()
    intercept = 0.0
    slope = 0.0
    loss_total = 0.0

    for repeat_index in range(repeat_count):
        intercept, slope = _ridge_fit(xs, ys, regularization)
        loss_total += _mean_squared_error(xs, ys, intercept, slope)

    loss = loss_total / repeat_count
    elapsed = time.perf_counter() - started

    return {
        "task_id": task_id,
        "lambda": regularization,
        "dataset_file": dataset_path.name,
        "n": int(xs.size),
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
