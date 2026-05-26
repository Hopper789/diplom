import time


def run(params):
    task_seconds = float(params.get("task_seconds", 5))
    started = time.perf_counter()
    iterations = 0
    value = 0.0

    while time.perf_counter() - started < task_seconds:
        value = (value + 1.000001) * 1.0000003
        if value > 1_000_000:
            value = value / 3.0
        iterations += 1

    return {
        "target_seconds": task_seconds,
        "iterations": iterations,
        "checksum": round(value, 6),
    }
