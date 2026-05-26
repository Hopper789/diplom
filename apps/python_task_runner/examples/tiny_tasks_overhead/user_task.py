def run(params):
    value = int(params.get("value", 0))
    return {"value": value, "square": value * value}
