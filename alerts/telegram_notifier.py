#!/usr/bin/env python3
"""Telegram-уведомление о завершении BOINC-эксперимента."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

import requests

BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "").strip()
POLL_INTERVAL_SECONDS = int(os.getenv("ALERT_POLL_INTERVAL_SECONDS", "30"))
BOINC_EXPORTER_URL = os.getenv("BOINC_EXPORTER_URL", "http://boinc-exporter:9101/metrics")
STATE_FILE = Path(os.getenv("ALERT_STATE_FILE", "/state/alerts_state.json"))
PROJECT_NAME = os.getenv("PROJECT_NAME", "BOINC project")


def parse_metrics(text: str) -> dict[str, float]:
    metrics: dict[str, float] = {}

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        parts = line.split()
        if len(parts) < 2:
            continue

        name = parts[0].split("{", 1)[0]
        try:
            value = float(parts[1])
        except ValueError:
            continue

        metrics[name] = value

    return metrics


def fetch_metrics() -> dict[str, float]:
    response = requests.get(BOINC_EXPORTER_URL, timeout=10)
    response.raise_for_status()
    return parse_metrics(response.text)


def load_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {}

    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def save_state(state: dict[str, Any]) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = STATE_FILE.with_suffix(STATE_FILE.suffix + ".tmp")
    tmp_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp_path.replace(STATE_FILE)


def experiment_key(metrics: dict[str, float]) -> str:
    workunits = int(metrics.get("boinc_workunits_total", 0))
    latest_received = int(metrics.get("boinc_latest_result_received_time", 0))
    return f"{workunits}:{latest_received}"


def should_notify(metrics: dict[str, float], state: dict[str, Any]) -> bool:
    workunits = int(metrics.get("boinc_workunits_total", 0))
    completed = int(metrics.get("boinc_completed_workunits_total", 0))
    unfinished = int(metrics.get("boinc_results_unfinished_total", 0))

    if workunits <= 0:
        return False
    if completed < workunits:
        return False
    if unfinished != 0:
        return False

    current_key = experiment_key(metrics)
    last_key = state.get("last_notified_experiment_key")
    last_workunits = int(state.get("last_notified_workunits_total", 0) or 0)

    if current_key != last_key:
        return True
    if workunits > last_workunits:
        return True

    return False


def build_message(metrics: dict[str, float]) -> str:
    workunits = int(metrics.get("boinc_workunits_total", 0))
    completed = int(metrics.get("boinc_completed_workunits_total", 0))
    errors = int(metrics.get("boinc_results_error_total", 0))

    lines = [
        "✅ BOINC experiment finished",
        f"project: {PROJECT_NAME}",
        f"workunits: {workunits}",
        f"completed: {completed}",
        f"errors: {errors}",
    ]

    if errors > 0:
        lines.append(f"⚠️ Errors detected: {errors}")

    return "\n".join(lines)


def send_telegram(message: str) -> None:
    if not BOT_TOKEN or not CHAT_ID:
        raise RuntimeError("TELEGRAM_BOT_TOKEN и TELEGRAM_CHAT_ID должны быть заданы")

    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    response = requests.post(url, json={"chat_id": CHAT_ID, "text": message}, timeout=10)
    response.raise_for_status()


def mark_notified(metrics: dict[str, float], state: dict[str, Any]) -> None:
    state["last_notified_experiment_key"] = experiment_key(metrics)
    state["last_notified_workunits_total"] = int(metrics.get("boinc_workunits_total", 0))
    state["last_notified_latest_result_received_time"] = int(
        metrics.get("boinc_latest_result_received_time", 0)
    )
    state["last_notified_at"] = int(time.time())
    save_state(state)


def run_once() -> None:
    metrics = fetch_metrics()
    state = load_state()

    if not should_notify(metrics, state):
        return

    message = build_message(metrics)
    send_telegram(message)
    mark_notified(metrics, state)
    print("Отправлено Telegram-уведомление о завершении эксперимента", flush=True)


def main() -> int:
    print("Telegram notifier запущен", flush=True)
    while True:
        try:
            run_once()
        except Exception as exc:  # noqa: BLE001
            print(f"Ошибка notifier: {exc}", flush=True)
        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())
