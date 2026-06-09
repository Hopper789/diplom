"""CPU-heavy determinant workload for the BOINC Python runner."""

from __future__ import annotations

import math
import multiprocessing as mp
import os
import platform
import time
import traceback
from queue import Empty
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


MIN_WORKUNIT_SECONDS = 600.0
WORKER_SEED_STRIDE = 1_000_003


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


def _available_cpu_count() -> int:
    try:
        return max(1, len(os.sched_getaffinity(0)))
    except AttributeError:
        return max(1, os.cpu_count() or 1)


def _warm_up_numba() -> None:
    _fill_matrix(4, 1, 1.0)


def _scientific_from_log(sign: float, log_abs_det: float) -> dict[str, Any]:
    if sign == 0 or not math.isfinite(log_abs_det):
        return {"mantissa": 0.0, "exponent10": 0}

    exponent10 = math.floor(log_abs_det / math.log(10.0))
    mantissa = float(sign) * math.exp(log_abs_det - exponent10 * math.log(10.0))
    return {"mantissa": mantissa, "exponent10": int(exponent10)}


def _run_determinant_loop(
    *,
    size: int,
    seed: int,
    diagonal_boost: float,
    deadline: float,
    max_repeats: int,
    worker_index: int,
) -> dict[str, Any]:
    repeats = 0
    last_sign = 0.0
    last_log_abs_det = 0.0
    checksum = 0.0
    first_det_seconds = 0.0
    worker_started = time.perf_counter()
    worker_seed = seed + worker_index * WORKER_SEED_STRIDE

    while True:
        repeat_started = time.perf_counter()
        matrix = _fill_matrix(size, worker_seed + repeats, diagonal_boost)
        sign, log_abs_det = np.linalg.slogdet(matrix)
        repeat_seconds = time.perf_counter() - repeat_started

        repeats += 1
        last_sign = float(sign)
        last_log_abs_det = float(log_abs_det)
        checksum += last_sign * last_log_abs_det
        if repeats == 1:
            first_det_seconds = repeat_seconds

        if max_repeats > 0 and repeats >= max_repeats:
            break
        if time.perf_counter() >= deadline:
            break

    return {
        "worker_index": worker_index,
        "repeats": repeats,
        "checksum": checksum,
        "last_sign": last_sign,
        "last_log_abs_det": last_log_abs_det,
        "first_det_seconds": first_det_seconds,
        "elapsed_seconds": time.perf_counter() - worker_started,
    }


def _worker_main(queue: Any, kwargs: dict[str, Any]) -> None:
    try:
        queue.put({"ok": True, "result": _run_determinant_loop(**kwargs)})
    except Exception:
        queue.put({"ok": False, "error": traceback.format_exc()})
        raise


def _run_all_cpu_determinants(
    *,
    size: int,
    seed: int,
    diagonal_boost: float,
    target_seconds: float,
    max_repeats: int,
    workers: int,
) -> list[dict[str, Any]]:
    _warm_up_numba()

    if workers <= 1 or "fork" not in mp.get_all_start_methods():
        return [
            _run_determinant_loop(
                size=size,
                seed=seed,
                diagonal_boost=diagonal_boost,
                deadline=time.perf_counter() + target_seconds,
                max_repeats=max_repeats,
                worker_index=0,
            )
        ]

    ctx = mp.get_context("fork")
    queue = ctx.Queue()
    deadline = time.perf_counter() + target_seconds
    processes = []

    for worker_index in range(workers):
        kwargs = {
            "size": size,
            "seed": seed,
            "diagonal_boost": diagonal_boost,
            "deadline": deadline,
            "max_repeats": max_repeats,
            "worker_index": worker_index,
        }
        process = ctx.Process(target=_worker_main, args=(queue, kwargs))
        process.start()
        processes.append(process)

    for process in processes:
        process.join()

    messages = []
    for _ in processes:
        try:
            messages.append(queue.get(timeout=1))
        except Empty:
            break

    errors = [message.get("error", "") for message in messages if not message.get("ok")]
    bad_exitcodes = [process.exitcode for process in processes if process.exitcode not in (0, None)]
    missing_messages = len(processes) - len(messages)
    if errors or bad_exitcodes or missing_messages:
        details = "\n".join(errors) if errors else f"worker exit codes: {bad_exitcodes}"
        if missing_messages:
            details = f"{details}; missing worker messages: {missing_messages}"
        raise RuntimeError(f"determinant workers failed:\n{details}")

    return [message["result"] for message in messages]


def run(params: dict[str, Any]) -> dict[str, Any]:
    """Compute determinant-like metrics for one generated dense matrix."""

    task_id = _as_int(params, "task_id", 1)
    size = max(2, _as_int(params, "matrix_size", 1200))
    seed = _as_int(params, "seed", 10_000 + task_id)
    requested_target_seconds = max(0.0, _as_float(params, "target_seconds", MIN_WORKUNIT_SECONDS))
    target_seconds = max(MIN_WORKUNIT_SECONDS, requested_target_seconds)
    max_repeats = max(0, _as_int(params, "max_repeats", 0))
    diagonal_boost = _as_float(params, "diagonal_boost", max(1.0, size * 0.01))
    workers = max(1, _as_int(params, "workers", _available_cpu_count()))

    started = time.perf_counter()
    worker_results = _run_all_cpu_determinants(
        size=size,
        seed=seed,
        diagonal_boost=diagonal_boost,
        target_seconds=target_seconds,
        max_repeats=max_repeats,
        workers=workers,
    )

    elapsed = time.perf_counter() - started
    repeats = sum(int(result["repeats"]) for result in worker_results)
    checksum = sum(float(result["checksum"]) for result in worker_results)
    first_det_seconds = min(
        (float(result["first_det_seconds"]) for result in worker_results if result["first_det_seconds"] > 0),
        default=0.0,
    )
    last_result = max(worker_results, key=lambda result: (result["elapsed_seconds"], result["worker_index"]))
    last_sign = float(last_result["last_sign"])
    last_log_abs_det = float(last_result["last_log_abs_det"])

    return {
        "task_id": task_id,
        "matrix_size": size,
        "seed": seed,
        "target_seconds": target_seconds,
        "requested_target_seconds": requested_target_seconds,
        "min_workunit_seconds": MIN_WORKUNIT_SECONDS,
        "elapsed_seconds": round(elapsed, 6),
        "repeats": repeats,
        "workers": workers,
        "first_determinant_seconds": round(first_det_seconds, 6),
        "determinant": {
            "sign": last_sign,
            "log_abs": last_log_abs_det,
            "scientific": _scientific_from_log(last_sign, last_log_abs_det),
        },
        "worker_results": [
            {
                "worker_index": int(result["worker_index"]),
                "repeats": int(result["repeats"]),
                "elapsed_seconds": round(float(result["elapsed_seconds"]), 6),
                "first_determinant_seconds": round(float(result["first_det_seconds"]), 6),
            }
            for result in sorted(worker_results, key=lambda result: result["worker_index"])
        ],
        "checksum": checksum,
        "backend": {
            "python": platform.python_implementation(),
            "numpy": np.__version__,
            "numba": numba.__version__,
        },
    }
