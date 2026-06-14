import os
import traceback
import time
from typing import Any

import pymysql
import requests
from prometheus_client import Counter, Gauge, start_http_server

PROJECT_NAME = os.getenv("PROJECT_NAME", "my_project")
PROJECT_URL = os.getenv("PROJECT_URL", "")
MARIADB_HOST = os.getenv("MARIADB_HOST", "boinc-mariadb")
MARIADB_PORT = int(os.getenv("MARIADB_PORT", "3306"))
MARIADB_USER = os.getenv("MARIADB_USER", "root")
MARIADB_PASSWORD = os.getenv("MARIADB_PASSWORD", "root")
MARIADB_DATABASE = os.getenv("MARIADB_DATABASE", PROJECT_NAME)
SCRAPE_INTERVAL = int(os.getenv("SCRAPE_INTERVAL", "10"))
CONFIG_TASK_SECONDS = float(os.getenv("TASK_SECONDS", "1200"))
CONFIG_REPLICATION_FACTOR = float(os.getenv("DISTRIBUTED_TARGET_NRESULTS", "1"))
CONFIG_MIN_QUORUM = float(os.getenv("DISTRIBUTED_MIN_QUORUM", "1"))
CONFIG_MAX_SUCCESS_RESULTS = float(os.getenv("DISTRIBUTED_MAX_SUCCESS_RESULTS", "1"))
CONFIG_MAX_ERROR_RESULTS = float(os.getenv("DISTRIBUTED_MAX_ERROR_RESULTS", "3"))
CONFIG_MAX_TOTAL_RESULTS = float(os.getenv("DISTRIBUTED_MAX_TOTAL_RESULTS", "3"))

# Availability
boinc_db_up = Gauge("boinc_db_up", "MariaDB connection status: 1 if up, 0 if down")
boinc_project_http_up = Gauge("boinc_project_http_up", "BOINC project HTTP status: 1 if reachable, 0 if down")
boinc_project_http_status_code = Gauge("boinc_project_http_status_code", "BOINC project HTTP status code")
boinc_exporter_scrape_errors_total = Counter("boinc_exporter_scrape_errors_total", "Exporter scrape errors")

# Inventory and queue size
boinc_users_total = Gauge("boinc_users_total", "Total BOINC users")
boinc_hosts_total = Gauge("boinc_hosts_total", "Total BOINC hosts registered in DB")
boinc_hosts_active_recent_total = Gauge(
    "boinc_hosts_active_recent_total",
    "Hosts with assigned unfinished BOINC results",
)
boinc_hosts_summary = Gauge(
    "boinc_hosts_summary",
    "Active and total hosts encoded as labels for compact Grafana display",
    ["active", "total"],
)
boinc_workunits_total = Gauge("boinc_workunits_total", "Total BOINC workunits")
boinc_results_total = Gauge("boinc_results_total", "Total BOINC result records")

# Result states
boinc_results_by_state_total = Gauge(
    "boinc_results_by_state_total",
    "BOINC results grouped by server_state/outcome/client_state",
    ["server_state", "outcome", "client_state"],
)
boinc_results_by_outcome_total = Gauge(
    "boinc_results_by_outcome_total",
    "BOINC results grouped by outcome",
    ["outcome"],
)
boinc_results_success_total = Gauge("boinc_results_success_total", "BOINC results with outcome=1")
boinc_results_error_total = Gauge("boinc_results_error_total", "BOINC results with error outcomes")
boinc_results_redundant_total = Gauge("boinc_results_redundant_total", "BOINC results with outcome=5 did not need")
boinc_results_unfinished_total = Gauge("boinc_results_unfinished_total", "BOINC results with outcome=0")
boinc_results_finished_total = Gauge("boinc_results_finished_total", "BOINC results with outcome!=0")
boinc_results_executed_total = Gauge("boinc_results_executed_total", "BOINC results actually executed by clients: success plus error outcomes")
boinc_results_unsent_total = Gauge("boinc_results_unsent_total", "BOINC results not assigned to any host yet")
boinc_results_assigned_total = Gauge("boinc_results_assigned_total", "BOINC results assigned to a host")
boinc_results_in_progress_total = Gauge("boinc_results_in_progress_total", "Assigned BOINC results not finished yet")
boinc_issued_results_percent = Gauge(
    "boinc_issued_results_percent",
    "Percent of all current BOINC result records that have been issued to a host",
)

# Rates and efficiency are calculated by Prometheus from gauges/counters, but these point-in-time metrics
# are useful for simple dashboards and diploma tables.
boinc_success_rate = Gauge("boinc_success_rate", "successful_results / finished_results")
boinc_error_rate = Gauge("boinc_error_rate", "error_results / finished_results")
boinc_results_error_percent = Gauge(
    "boinc_results_error_percent",
    "Percent of finished BOINC results with error outcomes",
)
boinc_queue_remaining_total = Gauge("boinc_queue_remaining_total", "Unfinished BOINC results")
boinc_completed_workunits_total = Gauge(
    "boinc_completed_workunits_total",
    "Workunits with a canonical result or enough successful quorum results",
)
boinc_remaining_workunits_total = Gauge(
    "boinc_remaining_workunits_total",
    "Workunits without a canonical result or enough successful quorum results yet",
)
boinc_error_workunits_total = Gauge("boinc_error_workunits_total", "Distinct workunits with at least one error result")
boinc_workunits_error_percent = Gauge("boinc_workunits_error_percent", "Percent of workunits with at least one error result")
boinc_effective_completion_ratio = Gauge("boinc_effective_completion_ratio", "completed_workunits / workunits_total")
boinc_replication_overhead = Gauge("boinc_replication_overhead", "results_total / workunits_total")
boinc_actual_results_per_workunit = Gauge("boinc_actual_results_per_workunit", "Executed success/error results per workunit")
boinc_target_nresults_avg = Gauge("boinc_target_nresults_avg", "Average workunit target_nresults")
boinc_min_quorum_avg = Gauge("boinc_min_quorum_avg", "Average workunit min_quorum")
boinc_max_success_results_avg = Gauge("boinc_max_success_results_avg", "Average workunit max_success_results")
boinc_max_error_results_avg = Gauge("boinc_max_error_results_avg", "Average workunit max_error_results")
boinc_max_total_results_avg = Gauge("boinc_max_total_results_avg", "Average workunit max_total_results")
boinc_latest_result_received_time = Gauge("boinc_latest_result_received_time", "Max result received_time value")
boinc_avg_success_turnaround_seconds = Gauge(
    "boinc_avg_success_turnaround_seconds",
    "Average received_time - create_time for successful results",
)
boinc_p95_success_turnaround_seconds = Gauge(
    "boinc_p95_success_turnaround_seconds",
    "Approximate p95 received_time - create_time for successful results",
)
boinc_oldest_unfinished_result_age_seconds = Gauge(
    "boinc_oldest_unfinished_result_age_seconds",
    "Age of the oldest unfinished result by create_time",
)
boinc_experiment_total_seconds = Gauge(
    "boinc_experiment_total_seconds",
    "Total experiment wall time from first workunit to latest received result",
)
boinc_completion_percent = Gauge(
    "boinc_completion_percent",
    "Percent of workunits with a canonical result or enough successful quorum results",
)
boinc_estimated_remaining_seconds = Gauge(
    "boinc_estimated_remaining_seconds",
    "Estimated seconds remaining for unfinished unique workunits",
)
boinc_useful_compute_percent = Gauge(
    "boinc_useful_compute_percent",
    "Percent of finished attempt lifecycle spent on first-quorum useful computation",
)

# Distributed-computing configuration loaded from config/distributed.env through monitoring/.env.
boinc_config_replication_factor = Gauge(
    "boinc_config_replication_factor",
    "Configured target_nresults per workunit from distributed.env",
)
boinc_config_min_quorum = Gauge(
    "boinc_config_min_quorum",
    "Configured min_quorum from distributed.env",
)
boinc_config_max_success_results = Gauge(
    "boinc_config_max_success_results",
    "Configured max_success_results from distributed.env",
)
boinc_config_max_error_results = Gauge(
    "boinc_config_max_error_results",
    "Configured max_error_results from distributed.env",
)
boinc_config_max_total_results = Gauge(
    "boinc_config_max_total_results",
    "Configured max_total_results from distributed.env",
)
boinc_config_task_seconds = Gauge(
    "boinc_config_task_seconds",
    "Fallback target compute seconds per workunit",
)

# Time decomposition.
# Compute time is read from BOINC result.elapsed_time when available.
# If the schema does not expose elapsed_time yet, the exporter falls back to configured TASK_SECONDS.
boinc_avg_compute_time_per_workunit_seconds = Gauge(
    "boinc_avg_compute_time_per_workunit_seconds",
    "Average compute time per successful result/workunit",
)
boinc_avg_overhead_time_per_workunit_seconds = Gauge(
    "boinc_avg_overhead_time_per_workunit_seconds",
    "Average non-compute overhead per successful result/workunit: turnaround - compute_time",
)

# Summary panels use only the latest experiment batch. Long-running graphs keep using the
# aggregate metrics above so history remains visible.
boinc_current_hosts_active_recent_total = Gauge(
    "boinc_current_hosts_active_recent_total",
    "Hosts with unfinished results assigned in the latest experiment batch",
)
boinc_current_workunits_total = Gauge("boinc_current_workunits_total", "Workunits in the latest experiment batch")
boinc_current_results_total = Gauge("boinc_current_results_total", "Result records in the latest experiment batch")
boinc_current_completion_percent = Gauge(
    "boinc_current_completion_percent",
    "Percent of latest-experiment workunits with a canonical result or enough successful quorum results",
)
boinc_current_estimated_remaining_seconds = Gauge(
    "boinc_current_estimated_remaining_seconds",
    "Estimated seconds remaining for latest-experiment unfinished unique workunits",
)
boinc_current_workunits_error_percent = Gauge(
    "boinc_current_workunits_error_percent",
    "Percent of latest-experiment workunits with at least one error result",
)
boinc_current_avg_compute_time_per_workunit_seconds = Gauge(
    "boinc_current_avg_compute_time_per_workunit_seconds",
    "Average compute time for latest-experiment first-quorum successful results",
)
boinc_current_useful_compute_percent = Gauge(
    "boinc_current_useful_compute_percent",
    "Percent of latest-experiment finished attempt lifecycle spent on first-quorum useful computation",
)
boinc_current_issued_results_percent = Gauge(
    "boinc_current_issued_results_percent",
    "Percent of latest-experiment result records that have been issued to a host",
)
boinc_current_actual_results_per_workunit = Gauge(
    "boinc_current_actual_results_per_workunit",
    "Latest-experiment executed success/error results per workunit",
)


def connect():
    return pymysql.connect(
        host=MARIADB_HOST,
        port=MARIADB_PORT,
        user=MARIADB_USER,
        password=MARIADB_PASSWORD,
        database=MARIADB_DATABASE,
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=5,
        read_timeout=5,
        write_timeout=5,
    )


def fetch_one(cur, sql: str, params: tuple[Any, ...] | None = None) -> Any:
    cur.execute(sql, params)
    row = cur.fetchone()
    if not row:
        return 0
    return list(row.values())[0] or 0


def safe_fetch_one(cur, sql: str, params: tuple[Any, ...] | None = None, default: Any = 0) -> Any:
    try:
        return fetch_one(cur, sql, params)
    except Exception:
        return default


def set_ratio(metric: Gauge, numerator: float, denominator: float) -> None:
    metric.set(float(numerator) / float(denominator) if denominator else 0)


def completed_workunits_sql(has_canonical_resultid: bool, where_clause: str = "1 = 1") -> str:
    canonical_condition = "COALESCE(w.canonical_resultid, 0) > 0 OR" if has_canonical_resultid else ""
    return f"""
        SELECT COUNT(*)
        FROM (
            SELECT w.id
            FROM workunit w
            LEFT JOIN result r
              ON r.workunitid = w.id
             AND r.outcome = 1
            WHERE {where_clause}
            GROUP BY w.id, w.min_quorum{", w.canonical_resultid" if has_canonical_resultid else ""}
            HAVING {canonical_condition}
                   COUNT(r.id) >= GREATEST(COALESCE(NULLIF(w.min_quorum, 0), 1), 1)
        ) completed
    """


def useful_success_query(metric_expr: str, where_clause: str = "1 = 1") -> str:
    return f"""
        SELECT {metric_expr}
        FROM (
            SELECT
                r.*,
                w.min_quorum,
                ROW_NUMBER() OVER (
                    PARTITION BY r.workunitid
                    ORDER BY r.received_time, r.id
                ) AS success_rank
            FROM workunit w
            JOIN result r
              ON r.workunitid = w.id
             AND r.outcome = 1
            WHERE {where_clause}
        ) useful
        WHERE useful.success_rank <= GREATEST(COALESCE(NULLIF(useful.min_quorum, 0), 1), 1)
    """


def latest_experiment_scope(cur) -> tuple[str, str, tuple[Any, ...]] | None:
    cur.execute("SELECT name FROM workunit ORDER BY create_time DESC, id DESC LIMIT 1")
    row = cur.fetchone() or {}
    latest_name = str(row.get("name") or "")
    if not latest_name:
        return None

    prefix = latest_name.rsplit("_", 1)[0] if "_" in latest_name else latest_name
    if not prefix:
        return None

    return prefix, "w.name LIKE %s", (prefix + "_%",)


def reset_current_experiment_metrics() -> None:
    boinc_current_hosts_active_recent_total.set(0)
    boinc_current_workunits_total.set(0)
    boinc_current_results_total.set(0)
    boinc_current_completion_percent.set(0)
    boinc_current_estimated_remaining_seconds.set(0)
    boinc_current_workunits_error_percent.set(0)
    boinc_current_avg_compute_time_per_workunit_seconds.set(0)
    boinc_current_useful_compute_percent.set(0)
    boinc_current_issued_results_percent.set(0)
    boinc_current_actual_results_per_workunit.set(0)


def table_has_column(cur, table: str, column: str) -> bool:
    cur.execute(
        """
        SELECT COUNT(*) AS cnt
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = %s
          AND column_name = %s
        """,
        (table, column),
    )
    row = cur.fetchone() or {}
    return bool(row.get("cnt"))


def update_current_experiment_metrics(cur, has_canonical_resultid: bool) -> None:
    scope = latest_experiment_scope(cur)
    if scope is None:
        reset_current_experiment_metrics()
        return

    _, workunit_where, workunit_params = scope
    result_from = f"FROM result r JOIN workunit w ON w.id = r.workunitid WHERE {workunit_where}"

    def current_result_count(condition: str = "1 = 1") -> float:
        return safe_fetch_one(cur, f"SELECT COUNT(*) {result_from} AND {condition}", workunit_params)

    current_workunits = safe_fetch_one(cur, f"SELECT COUNT(*) FROM workunit w WHERE {workunit_where}", workunit_params)
    current_results = current_result_count()
    current_success = current_result_count("r.outcome = 1")
    current_errors = current_result_count("r.outcome IN (2, 3, 4, 6)")
    current_executed = current_success + current_errors
    current_finished = current_result_count("r.outcome != 0")
    current_unfinished = current_result_count("r.outcome = 0")
    current_assigned = current_result_count("r.hostid != 0")
    current_in_progress = current_result_count("r.hostid != 0 AND r.outcome = 0")
    current_active_hosts = safe_fetch_one(
        cur,
        f"SELECT COUNT(DISTINCT r.hostid) {result_from} AND r.hostid != 0 AND r.outcome = 0",
        workunit_params,
    )
    current_completed_wu = safe_fetch_one(
        cur,
        completed_workunits_sql(has_canonical_resultid, workunit_where),
        workunit_params,
    )
    current_remaining_wu = max(0, current_workunits - current_completed_wu)
    current_error_wu = safe_fetch_one(
        cur,
        f"SELECT COUNT(DISTINCT r.workunitid) {result_from} AND r.outcome IN (2, 3, 4, 6)",
        workunit_params,
    )
    current_avg_min_quorum = safe_fetch_one(
        cur,
        f"SELECT COALESCE(AVG(w.min_quorum), 0) FROM workunit w WHERE {workunit_where}",
        workunit_params,
    )

    latest_result_received_time = float(
        safe_fetch_one(cur, f"SELECT COALESCE(MAX(r.received_time), 0) {result_from}", workunit_params)
    )
    first_workunit_create_time = float(
        safe_fetch_one(cur, f"SELECT COALESCE(MIN(w.create_time), 0) FROM workunit w WHERE {workunit_where}", workunit_params)
    )
    current_db_time = float(safe_fetch_one(cur, "SELECT UNIX_TIMESTAMP()"))
    experiment_total_seconds = 0.0
    if first_workunit_create_time > 0:
        if current_unfinished:
            experiment_total_seconds = max(0.0, current_db_time - first_workunit_create_time)
        elif latest_result_received_time > first_workunit_create_time:
            experiment_total_seconds = latest_result_received_time - first_workunit_create_time

    completion_rate = (
        float(current_completed_wu) / experiment_total_seconds
        if experiment_total_seconds and current_completed_wu
        else 0
    )
    active_capacity = max(float(current_active_hosts or 0), float(current_in_progress or 0))
    estimated_remaining_seconds = 0.0
    if current_remaining_wu > 0:
        if completion_rate > 0:
            estimated_remaining_seconds = float(current_remaining_wu) / completion_rate
        elif active_capacity > 0:
            quorum_attempts = max(float(current_avg_min_quorum or 0), 1.0)
            estimated_remaining_seconds = (
                float(current_remaining_wu) * quorum_attempts * max(CONFIG_TASK_SECONDS, 1.0) / active_capacity
            )

    useful_compute_sql = useful_success_query(
        "COALESCE(SUM(CASE WHEN elapsed_time > 0 THEN elapsed_time ELSE 0 END), 0) AS compute_seconds",
        workunit_where,
    )
    avg_compute_sql = useful_success_query(
        "COALESCE(AVG(CASE WHEN elapsed_time > 0 THEN elapsed_time END), 0)",
        workunit_where,
    )

    try:
        cur.execute(useful_compute_sql, workunit_params)
        useful_row = cur.fetchone() or {}
        useful_compute_seconds = float(useful_row.get("compute_seconds") or 0)
        useful_total_seconds = float(
            safe_fetch_one(
                cur,
                f"""
                SELECT COALESCE(SUM(
                  GREATEST(
                    COALESCE(r.elapsed_time, 0),
                    CASE
                      WHEN r.received_time > 0 AND r.sent_time > 0
                        THEN r.received_time - r.sent_time
                      WHEN r.received_time > 0 AND r.create_time > 0
                        THEN r.received_time - r.create_time
                      ELSE COALESCE(r.elapsed_time, 0)
                    END
                  )
                ), 0)
                {result_from}
                  AND r.outcome != 0
                  AND r.hostid != 0
                """,
                workunit_params,
            )
            or 0
        )
    except Exception:
        useful_compute_seconds = 0.0
        useful_total_seconds = 0.0

    useful_percent = 0.0
    if useful_total_seconds > 0:
        useful_percent = max(0.0, min(100.0, useful_compute_seconds / useful_total_seconds * 100.0))

    avg_compute_time = float(safe_fetch_one(cur, avg_compute_sql, workunit_params, default=0))
    if avg_compute_time <= 0:
        avg_compute_time = CONFIG_TASK_SECONDS if current_success else 0

    boinc_current_hosts_active_recent_total.set(current_active_hosts)
    boinc_current_workunits_total.set(current_workunits)
    boinc_current_results_total.set(current_results)
    boinc_current_completion_percent.set(
        (float(current_completed_wu) / float(current_workunits) * 100.0) if current_workunits else 0
    )
    boinc_current_estimated_remaining_seconds.set(estimated_remaining_seconds)
    boinc_current_workunits_error_percent.set(
        (float(current_error_wu) / float(current_workunits) * 100.0) if current_workunits else 0
    )
    boinc_current_avg_compute_time_per_workunit_seconds.set(avg_compute_time)
    boinc_current_useful_compute_percent.set(useful_percent)
    boinc_current_issued_results_percent.set(
        (float(current_assigned) / float(current_results) * 100.0) if current_results else 0
    )
    boinc_current_actual_results_per_workunit.set(
        (float(current_executed) / float(current_workunits)) if current_workunits else 0
    )


def update_db_metrics() -> None:
    try:
        conn = connect()
        boinc_db_up.set(1)

        with conn.cursor() as cur:
            users = safe_fetch_one(cur, "SELECT COUNT(*) FROM user")
            hosts = safe_fetch_one(cur, "SELECT COUNT(*) FROM host")
            workunits = safe_fetch_one(cur, "SELECT COUNT(*) FROM workunit")
            results = safe_fetch_one(cur, "SELECT COUNT(*) FROM result")
            has_canonical_resultid = table_has_column(cur, "workunit", "canonical_resultid")
            completed_wu_sql = completed_workunits_sql(has_canonical_resultid)
            active_hosts = safe_fetch_one(
                cur,
                """
                SELECT COUNT(DISTINCT hostid)
                FROM result
                WHERE hostid != 0 AND outcome = 0
                """,
            )

            boinc_users_total.set(users)
            boinc_hosts_total.set(hosts)
            boinc_hosts_active_recent_total.set(active_hosts)
            boinc_hosts_summary.clear()
            boinc_hosts_summary.labels(active=str(int(active_hosts)), total=str(int(hosts))).set(1)
            boinc_workunits_total.set(workunits)
            boinc_results_total.set(results)
            boinc_config_replication_factor.set(CONFIG_REPLICATION_FACTOR)
            boinc_config_min_quorum.set(CONFIG_MIN_QUORUM)
            boinc_config_max_success_results.set(CONFIG_MAX_SUCCESS_RESULTS)
            boinc_config_max_error_results.set(CONFIG_MAX_ERROR_RESULTS)
            boinc_config_max_total_results.set(CONFIG_MAX_TOTAL_RESULTS)
            boinc_config_task_seconds.set(CONFIG_TASK_SECONDS)
            update_current_experiment_metrics(cur, has_canonical_resultid)

            success = safe_fetch_one(cur, "SELECT COUNT(*) FROM result WHERE outcome = 1")
            unfinished = safe_fetch_one(cur, "SELECT COUNT(*) FROM result WHERE outcome = 0")
            finished = safe_fetch_one(cur, "SELECT COUNT(*) FROM result WHERE outcome != 0")
            errors = safe_fetch_one(cur, "SELECT COUNT(*) FROM result WHERE outcome IN (2, 3, 4, 6)")
            executed = success + errors
            redundant = safe_fetch_one(cur, "SELECT COUNT(*) FROM result WHERE outcome = 5")
            unsent = safe_fetch_one(cur, "SELECT COUNT(*) FROM result WHERE hostid = 0")
            assigned = safe_fetch_one(cur, "SELECT COUNT(*) FROM result WHERE hostid != 0")
            in_progress = safe_fetch_one(cur, "SELECT COUNT(*) FROM result WHERE hostid != 0 AND outcome = 0")
            completed_wu = safe_fetch_one(cur, completed_wu_sql)
            remaining_wu = max(0, workunits - completed_wu)
            error_wu = safe_fetch_one(cur, "SELECT COUNT(DISTINCT workunitid) FROM result WHERE outcome IN (2, 3, 4, 6)")
            avg_target_nresults = safe_fetch_one(cur, "SELECT COALESCE(AVG(target_nresults), 0) FROM workunit")
            avg_min_quorum = safe_fetch_one(cur, "SELECT COALESCE(AVG(min_quorum), 0) FROM workunit")
            avg_max_success_results = safe_fetch_one(cur, "SELECT COALESCE(AVG(max_success_results), 0) FROM workunit")
            avg_max_error_results = safe_fetch_one(cur, "SELECT COALESCE(AVG(max_error_results), 0) FROM workunit")
            avg_max_total_results = safe_fetch_one(cur, "SELECT COALESCE(AVG(max_total_results), 0) FROM workunit")

            boinc_results_success_total.set(success)
            boinc_results_error_total.set(errors)
            boinc_results_redundant_total.set(redundant)
            boinc_results_unfinished_total.set(unfinished)
            boinc_results_finished_total.set(finished)
            boinc_results_executed_total.set(executed)
            boinc_results_unsent_total.set(unsent)
            boinc_results_assigned_total.set(assigned)
            boinc_results_in_progress_total.set(in_progress)
            boinc_issued_results_percent.set((float(assigned) / float(results) * 100.0) if results else 0)
            boinc_queue_remaining_total.set(unfinished)
            boinc_completed_workunits_total.set(completed_wu)
            boinc_remaining_workunits_total.set(remaining_wu)
            boinc_error_workunits_total.set(error_wu)
            boinc_workunits_error_percent.set((float(error_wu) / float(workunits) * 100.0) if workunits else 0)

            set_ratio(boinc_success_rate, success, finished)
            set_ratio(boinc_error_rate, errors, finished)
            boinc_results_error_percent.set((float(errors) / float(finished) * 100.0) if finished else 0)
            set_ratio(boinc_effective_completion_ratio, completed_wu, workunits)
            set_ratio(boinc_replication_overhead, results, workunits)
            set_ratio(boinc_actual_results_per_workunit, executed, workunits)

            latest_result_received_time = float(
                safe_fetch_one(cur, "SELECT COALESCE(MAX(received_time), 0) FROM result")
            )
            first_workunit_create_time = float(
                safe_fetch_one(cur, "SELECT COALESCE(MIN(create_time), 0) FROM workunit")
            )
            current_db_time = float(safe_fetch_one(cur, "SELECT UNIX_TIMESTAMP()"))
            experiment_total_seconds = 0.0
            if first_workunit_create_time > 0:
                if unfinished:
                    experiment_total_seconds = max(0.0, current_db_time - first_workunit_create_time)
                elif latest_result_received_time > first_workunit_create_time:
                    experiment_total_seconds = latest_result_received_time - first_workunit_create_time

            boinc_latest_result_received_time.set(latest_result_received_time)
            boinc_experiment_total_seconds.set(experiment_total_seconds)
            completion_rate = (float(completed_wu) / experiment_total_seconds) if experiment_total_seconds else 0
            active_capacity = max(float(active_hosts or 0), float(in_progress or 0), float(hosts or 0))
            estimated_remaining_seconds = 0.0
            if remaining_wu > 0:
                if completion_rate > 0:
                    estimated_remaining_seconds = float(remaining_wu) / completion_rate
                elif active_capacity > 0:
                    quorum_attempts = max(float(avg_min_quorum or 0), 1.0)
                    estimated_remaining_seconds = (
                        float(remaining_wu) * quorum_attempts * max(CONFIG_TASK_SECONDS, 1.0) / active_capacity
                    )

            boinc_completion_percent.set((float(completed_wu) / float(workunits) * 100.0) if workunits else 0)
            boinc_estimated_remaining_seconds.set(estimated_remaining_seconds)

            useful_compute_sql = useful_success_query(
                "COALESCE(SUM(CASE WHEN elapsed_time > 0 THEN elapsed_time ELSE 0 END), 0) AS compute_seconds"
            )
            avg_compute_sql = useful_success_query(
                "COALESCE(AVG(CASE WHEN elapsed_time > 0 THEN elapsed_time END), 0)"
            )
            avg_turnaround_sql = useful_success_query(
                """
                COALESCE(AVG(
                    CASE
                      WHEN received_time > 0 AND sent_time > 0
                        THEN received_time - sent_time
                    END
                ), 0)
                """
            )
            p95_turnaround_sql = useful_success_query(
                """
                CASE
                  WHEN received_time > 0 AND sent_time > 0
                    THEN received_time - sent_time
                  ELSE NULL
                END AS turnaround
                """
            ) + "\nAND received_time > 0 AND sent_time > 0 ORDER BY turnaround"

            try:
                cur.execute(useful_compute_sql)
                useful_row = cur.fetchone() or {}
                useful_compute_seconds = float(useful_row.get("compute_seconds") or 0)
                useful_total_seconds = float(
                    safe_fetch_one(
                        cur,
                        """
                        SELECT COALESCE(SUM(
                          GREATEST(
                            COALESCE(elapsed_time, 0),
                            CASE
                              WHEN received_time > 0 AND sent_time > 0
                                THEN received_time - sent_time
                              WHEN received_time > 0 AND create_time > 0
                                THEN received_time - create_time
                              ELSE COALESCE(elapsed_time, 0)
                            END
                          )
                        ), 0)
                        FROM result
                        WHERE outcome != 0
                          AND hostid != 0
                        """,
                    )
                    or 0
                )
            except Exception:
                useful_compute_seconds = 0.0
                useful_total_seconds = 0.0

            useful_percent = 0.0
            if useful_total_seconds > 0:
                useful_percent = max(0.0, min(100.0, useful_compute_seconds / useful_total_seconds * 100.0))
            boinc_useful_compute_percent.set(useful_percent)

            avg_turnaround = float(
                safe_fetch_one(
                    cur,
                    avg_turnaround_sql,
                )
            )
            boinc_avg_success_turnaround_seconds.set(avg_turnaround)

            avg_compute_time = float(
                safe_fetch_one(
                    cur,
                    avg_compute_sql,
                    default=0,
                )
            )
            if avg_compute_time <= 0:
                avg_compute_time = CONFIG_TASK_SECONDS if success else 0

            avg_overhead_time = avg_turnaround - avg_compute_time if avg_turnaround > 0 else 0
            if avg_overhead_time < 0:
                avg_overhead_time = 0

            boinc_avg_compute_time_per_workunit_seconds.set(avg_compute_time)
            boinc_avg_overhead_time_per_workunit_seconds.set(avg_overhead_time)

            cur.execute(p95_turnaround_sql)
            turnaround_rows = [float(row["turnaround"] or 0) for row in cur.fetchall()]
            if turnaround_rows:
                p95_index = int(round(0.95 * (len(turnaround_rows) - 1)))
                boinc_p95_success_turnaround_seconds.set(turnaround_rows[p95_index])
            else:
                boinc_p95_success_turnaround_seconds.set(0)
            boinc_oldest_unfinished_result_age_seconds.set(
                safe_fetch_one(
                    cur,
                    """
                    SELECT COALESCE(UNIX_TIMESTAMP() - MIN(create_time), 0)
                    FROM result
                    WHERE outcome = 0 AND create_time > 0
                    """,
                )
            )

            # Replication-related workunit configuration. Some BOINC schemas may miss a column,
            # so every metric is filled best-effort.
            boinc_target_nresults_avg.set(avg_target_nresults)
            boinc_min_quorum_avg.set(avg_min_quorum)
            boinc_max_success_results_avg.set(avg_max_success_results)
            boinc_max_error_results_avg.set(avg_max_error_results)
            boinc_max_total_results_avg.set(avg_max_total_results)

            boinc_results_by_state_total.clear()
            cur.execute(
                """
                SELECT server_state, outcome, client_state, COUNT(*) AS cnt
                FROM result
                GROUP BY server_state, outcome, client_state
                """
            )
            for row in cur.fetchall():
                boinc_results_by_state_total.labels(
                    server_state=str(row["server_state"]),
                    outcome=str(row["outcome"]),
                    client_state=str(row["client_state"]),
                ).set(row["cnt"])

            boinc_results_by_outcome_total.clear()
            cur.execute("SELECT outcome, COUNT(*) AS cnt FROM result GROUP BY outcome")
            for row in cur.fetchall():
                boinc_results_by_outcome_total.labels(outcome=str(row["outcome"])).set(row["cnt"])

        conn.close()
    except Exception:
        traceback.print_exc()
        boinc_db_up.set(0)
        boinc_exporter_scrape_errors_total.inc()


def update_http_metrics() -> None:
    if not PROJECT_URL:
        boinc_project_http_up.set(0)
        boinc_project_http_status_code.set(0)
        return

    try:
        response = requests.get(PROJECT_URL, timeout=5)
        boinc_project_http_status_code.set(response.status_code)
        boinc_project_http_up.set(1 if response.status_code < 500 else 0)
    except Exception:
        traceback.print_exc()
        boinc_project_http_status_code.set(0)
        boinc_project_http_up.set(0)
        boinc_exporter_scrape_errors_total.inc()


def main() -> None:
    start_http_server(9101)
    while True:
        update_db_metrics()
        update_http_metrics()
        time.sleep(SCRAPE_INTERVAL)


if __name__ == "__main__":
    main()
