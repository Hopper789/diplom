def run(params):
    if params.get("fail"):
        raise RuntimeError("Намеренная ошибка для проверки обработки failures")
    return {"value": params.get("value")}
