def run(params):
    size_mb = int(params.get("size_mb", 64))
    passes = int(params.get("passes", 3))
    size = max(1, size_mb) * 1024 * 1024

    data = bytearray((index * 131) % 256 for index in range(size))
    checksum = 0

    for _ in range(max(1, passes)):
        for index in range(0, size, 4096):
            checksum = (checksum + data[index]) % 1_000_000_007

    return {
        "size_mb": size_mb,
        "passes": passes,
        "checksum": checksum,
    }
