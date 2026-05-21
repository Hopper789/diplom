import os
import time
from typing import Any

import pymysql
import requests
from prometheus_client import Gauge, Counter, start_http_server

PROJECT_NAME = os.getenv("PROJECT_NAME", "my_project")
PROJECT_URL = os.getenv("PROJECT_URL", "")
MYSQL_HOST = os.getenv("MYSQL_HOST", "boinc-mysql")
MYSQL_PORT = int(os.getenv("MYSQL_PORT", "3306"))
MYSQL_USER = os.getenv("MYSQL_USER", "root")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "root")
MYSQL_DATABASE = os.getenv("MYSQL_DATABASE", PROJECT_NAME)
SCRAPE_INTERVAL = int(os.getenv("SCRAPE_INTERVAL", "10"))

db_up = Gauge("boinc_db_up", "MariaDB connection status: 1 if up, 0 if down")
project_http_up = Gauge("boinc_project_http_up", "BOINC project HTTP status: 1 if reachable, 0 if down")
project_http_status_code = Gauge("boinc_project_http_status_code", "BOINC project HTTP status code")

users_total = Gauge("boinc_users_total", "Total BOINC users")
hosts_total = Gauge("boinc_hosts_total", "Total BOINC hosts")
workunits_total = Gauge("boinc_workunits_total", "Total BOINC workunits")
results_total = Gauge("boinc_results_total", "Total BOINC results")
results_by_state = Gauge("boinc_results_by_state_total", "BOINC results grouped by server_state/outcome/client_state", ["server_state", "outcome", "client_state"])
hosts_active_recent = Gauge("boinc_hosts_active_recent_total", "Hosts with recent RPC time in the last 15 minutes")
latest_result_received_time = Gauge("boinc_latest_result_received_time", "Max result received_time value")
scrape_errors_total = Counter("boinc_exporter_scrape_errors_total", "Exporter scrape errors")


def connect():
    return pymysql.connect(
        host=MYSQL_HOST,
        port=MYSQL_PORT,
        user=MYSQL_USER,
        password=MYSQL_PASSWORD,
        database=MYSQL_DATABASE,
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=5,
        read_timeout=5,
        write_timeout=5,
    )


def fetch_one(cur, sql: str) -> Any:
    cur.execute(sql)
    row = cur.fetchone()
    if not row:
        return 0
    return list(row.values())[0] or 0


def update_db_metrics() -> None:
    try:
        conn = connect()
        db_up.set(1)
        with conn.cursor() as cur:
            users_total.set(fetch_one(cur, "SELECT COUNT(*) FROM user"))
            hosts_total.set(fetch_one(cur, "SELECT COUNT(*) FROM host"))
            workunits_total.set(fetch_one(cur, "SELECT COUNT(*) FROM workunit"))
            results_total.set(fetch_one(cur, "SELECT COUNT(*) FROM result"))
            hosts_active_recent.set(fetch_one(cur, "SELECT COUNT(*) FROM host WHERE rpc_time > UNIX_TIMESTAMP() - 900"))
            latest_result_received_time.set(fetch_one(cur, "SELECT COALESCE(MAX(received_time), 0) FROM result"))

            results_by_state.clear()
            cur.execute(
                """
                SELECT server_state, outcome, client_state, COUNT(*) AS cnt
                FROM result
                GROUP BY server_state, outcome, client_state
                """
            )
            for row in cur.fetchall():
                results_by_state.labels(
                    server_state=str(row["server_state"]),
                    outcome=str(row["outcome"]),
                    client_state=str(row["client_state"]),
                ).set(row["cnt"])
        conn.close()
    except Exception:
        db_up.set(0)
        scrape_errors_total.inc()


def update_http_metrics() -> None:
    if not PROJECT_URL:
        project_http_up.set(0)
        project_http_status_code.set(0)
        return

    try:
        response = requests.get(PROJECT_URL, timeout=5)
        project_http_status_code.set(response.status_code)
        project_http_up.set(1 if response.status_code < 500 else 0)
    except Exception:
        project_http_status_code.set(0)
        project_http_up.set(0)
        scrape_errors_total.inc()


def main() -> None:
    start_http_server(9101)
    while True:
        update_db_metrics()
        update_http_metrics()
        time.sleep(SCRAPE_INTERVAL)


if __name__ == "__main__":
    main()
