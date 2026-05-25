import random


def run(params):
    samples = int(params.get("samples", 100000))
    seed = int(params.get("seed", 1))

    rng = random.Random(seed)
    inside = 0

    for _ in range(samples):
        x = rng.random()
        y = rng.random()
        if x * x + y * y <= 1.0:
            inside += 1

    return {
        "samples": samples,
        "inside": inside,
        "pi": 4.0 * inside / samples,
    }
