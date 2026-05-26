import tempfile
from pathlib import Path


def run(params):
    size_kb = int(params.get("size_kb", 1024))
    repeats = int(params.get("repeats", 3))
    payload = b"boinc-python-task\n" * 64
    target_size = max(1, size_kb) * 1024
    checksum = 0

    with tempfile.TemporaryDirectory() as tmpdir:
        path = Path(tmpdir) / "payload.bin"
        with path.open("wb") as handle:
            written = 0
            while written < target_size:
                chunk = payload[: min(len(payload), target_size - written)]
                handle.write(chunk)
                written += len(chunk)

        for _ in range(max(1, repeats)):
            with path.open("rb") as handle:
                while True:
                    chunk = handle.read(64 * 1024)
                    if not chunk:
                        break
                    checksum = (checksum + sum(chunk)) % 1_000_000_007

    return {
        "size_kb": size_kb,
        "repeats": repeats,
        "checksum": checksum,
    }
