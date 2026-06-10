#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_ENV_FILE="$ROOT_DIR/config/generated.env"
REPORT_ROOT="$ROOT_DIR/reports/quick_benchmarks/$(date +%Y%m%d_%H%M%S)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

ASSUME_YES=0
REPLICA_COUNT="auto"
CASE_TIMEOUT=180
POLL_INTERVAL=10
NETWORK_PROBE_MIB=8
WITH_REPLICATION=1

usage() {
  cat <<'USAGE'
Использование:
  ./scripts/run_quick_benchmarks.sh --yes [опции]

Что делает:
  - запускает короткие Python-бенчмарки без перезапуска контейнеров;
  - сравнивает лёгкие, CPU-тяжёлые, IO-задачи и репликацию;
  - собирает BOINC, CPU, RAM и сетевые метрики;
  - сохраняет отчёт в reports/quick_benchmarks/.

Опции:
  --yes                    Запустить реально. Без флага будет показан план.
  --replicas N|auto        Максимум attempts для replicated-сценария. auto = число клиентов.
  --timeout N              Таймаут одного сценария, секунд. По умолчанию: 180.
  --poll-interval N        Пауза между проверками, секунд. По умолчанию: 10.
  --network-probe-mib N    Размер SSH network probe на клиента, MiB. По умолчанию: 8.
  --skip-network-probe     Не делать SSH network probe.
  --no-replication         Не запускать replicated-сценарий.
  --ask-vault-pass|--vault Передать Ansible --ask-vault-pass.
  --vault-password-file F  Передать Ansible --vault-password-file.
  --ask-become-pass|-K     Передать Ansible --ask-become-pass.
  --debug                  Показать полный вывод команд.

Перед запуском:
  ./scripts/quickstart.sh --with-monitoring

Пример:
  ./scripts/run_quick_benchmarks.sh --yes --replicas 2
USAGE
}

cd "$ROOT_DIR"
export ANSIBLE_HOST_KEY_CHECKING=False

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --replicas)
      REPLICA_COUNT="${2:-}"
      shift 2
      ;;
    --timeout)
      CASE_TIMEOUT="${2:-}"
      shift 2
      ;;
    --poll-interval)
      POLL_INTERVAL="${2:-}"
      shift 2
      ;;
    --network-probe-mib)
      NETWORK_PROBE_MIB="${2:-}"
      shift 2
      ;;
    --skip-network-probe)
      NETWORK_PROBE_MIB=0
      shift
      ;;
    --no-replication)
      WITH_REPLICATION=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Неизвестный аргумент: $1" >&2
      usage
      exit 2
      ;;
  esac
done

validate_nonnegative_int() {
  local name="$1"
  local value="$2"

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$name должен быть целым числом: $value" >&2
    exit 2
  fi
}

validate_positive_int() {
  local name="$1"
  local value="$2"

  validate_nonnegative_int "$name" "$value"
  if [[ "$value" -lt 1 ]]; then
    echo "$name должен быть больше 0: $value" >&2
    exit 2
  fi
}

count_clients_from_inventory() {
  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
    echo 0
    return
  fi

  awk '
    /^\[boinc_clients\]/ {inside=1; next}
    /^\[/ {inside=0}
    inside && $0 !~ /^[[:space:]]*($|#)/ {count++}
    END {print count + 0}
  ' "$ROOT_DIR/ansible/inventory.ini"
}

if [[ "$REPLICA_COUNT" == "auto" ]]; then
  REPLICA_COUNT="$(count_clients_from_inventory)"
  if [[ "$REPLICA_COUNT" -lt 1 ]]; then
    REPLICA_COUNT=1
  fi
fi

validate_positive_int "--replicas" "$REPLICA_COUNT"
validate_positive_int "--timeout" "$CASE_TIMEOUT"
validate_positive_int "--poll-interval" "$POLL_INTERVAL"
validate_nonnegative_int "--network-probe-mib" "$NETWORK_PROBE_MIB"

QUORUM=$((REPLICA_COUNT / 2 + 1))
if [[ "$QUORUM" -lt 1 ]]; then
  QUORUM=1
fi

require_runtime() {
  if [[ ! -f "$GENERATED_ENV_FILE" ]]; then
    echo "Не найден config/generated.env." >&2
    echo "Сначала запусти:" >&2
    echo "  ./scripts/bootstrap_server.sh" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$GENERATED_ENV_FILE"

  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-server'; then
    echo "boinc-server не запущен. Запусти quickstart перед бенчмарками." >&2
    exit 1
  fi

  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mariadb'; then
    echo "boinc-mariadb не запущен. Запусти quickstart перед бенчмарками." >&2
    exit 1
  fi
}

print_plan() {
  cat <<EOF
== Quick benchmarks ==

Цель: быстро сравнить конфигурации для независимых вычислений.
Ограничение: сценарии короткие, рассчитаны на запуск до ~10 минут на слабом стенде.

Сценарии:
  tiny_40_base          40 очень лёгких задач, replication=1
  cpu_light_16_base     16 CPU-задач по ~1.5 сек, replication=1
  cpu_heavy_8_base       8 CPU-задач по ~5 сек, replication=1
  io_small_8_base        8 IO-задач по 512 KiB, replication=1
EOF

  if [[ "$WITH_REPLICATION" == "1" ]]; then
    cat <<EOF
  cpu_light_16_repl     16 CPU-задач по ~1.5 сек, max attempts=$REPLICA_COUNT, quorum=$QUORUM
EOF
  fi

  cat <<EOF

Network probe: ${NETWORK_PROBE_MIB} MiB на клиента
Таймаут сценария: ${CASE_TIMEOUT} сек
Отчёт: $REPORT_ROOT
EOF
}

write_distributed_config() {
  local target_nresults="$1"
  local min_quorum="$2"
  local max_success_results="$3"
  local max_total_results="${4:-}"
  local max_error_results=3

  if [[ -z "$max_total_results" ]]; then
    max_total_results=3
  fi

  if [[ "$target_nresults" -gt "$max_total_results" ]]; then
    max_total_results=$((target_nresults + max_error_results))
  fi

  cat > "$ROOT_DIR/config/distributed.env" <<EOF
# Сгенерировано scripts/run_quick_benchmarks.sh.
# Runtime-файл, не коммитить.
DISTRIBUTED_TARGET_NRESULTS=$target_nresults
DISTRIBUTED_MIN_QUORUM=$min_quorum
DISTRIBUTED_MAX_SUCCESS_RESULTS=$max_success_results
DISTRIBUTED_MAX_ERROR_RESULTS=$max_error_results
DISTRIBUTED_MAX_TOTAL_RESULTS=$max_total_results
DISTRIBUTED_DELAY_BOUND=86400
DISTRIBUTED_RSC_MEMORY_BOUND=268435456
DISTRIBUTED_RSC_DISK_BOUND=104857600
DISTRIBUTED_RSC_FPOPS_EST=100000000000.0
DISTRIBUTED_RSC_FPOPS_BOUND=10000000000000.0
EOF
}

generate_params() {
  local benchmark_type="$1"
  local task_count="$2"
  local task_seconds="$3"
  local out_file="$4"

  python3 - "$benchmark_type" "$task_count" "$task_seconds" "$out_file" <<'PY'
import json
import sys
from pathlib import Path

benchmark_type = sys.argv[1]
task_count = int(sys.argv[2])
task_seconds = float(sys.argv[3])
out_file = Path(sys.argv[4])

out_file.parent.mkdir(parents=True, exist_ok=True)
with out_file.open("w", encoding="utf-8") as handle:
    for index in range(1, task_count + 1):
        if benchmark_type == "tiny":
            params = {"value": index}
        elif benchmark_type == "cpu":
            params = {"task_seconds": task_seconds}
        elif benchmark_type == "io":
            params = {"size_kb": 512, "repeats": 2}
        else:
            raise SystemExit(f"Неизвестный benchmark_type: {benchmark_type}")
        handle.write(json.dumps(params, ensure_ascii=False, sort_keys=True) + "\n")
PY
}

sql_tsv() {
  docker exec boinc-mariadb mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "$1"
}

request_client_update() {
  if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]] || ! command -v ansible >/dev/null 2>&1; then
    return 0
  fi

  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "
    docker exec boinc-client sh -lc \"cat > /var/lib/boinc/global_prefs_override.xml <<'EOF'
<global_preferences>
  <run_on_batteries>1</run_on_batteries>
  <run_if_user_active>1</run_if_user_active>
  <run_gpu_if_user_active>0</run_gpu_if_user_active>
  <suspend_cpu_usage>0.000000</suspend_cpu_usage>
  <cpu_usage_limit>100.000000</cpu_usage_limit>
  <max_ncpus_pct>100.000000</max_ncpus_pct>
  <work_buf_min_days>0.000000</work_buf_min_days>
  <work_buf_additional_days>0.000000</work_buf_additional_days>
  <disk_max_used_gb>50.000000</disk_max_used_gb>
  <disk_interval>60.000000</disk_interval>
</global_preferences>
EOF\"
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --read_global_prefs_override || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --set_run_mode always || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --set_network_mode always || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --project '$BOINC_PROJECT_URL' allowmorework || true
    docker exec boinc-client \
      boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' \
      --project '$BOINC_PROJECT_URL' update
  " >/dev/null 2>&1 || true
}

wait_for_case() {
  local prefix="$1"
  local deadline=$((SECONDS + CASE_TIMEOUT))

  echo "Ожидание завершения: $prefix"
  while true; do
    local row workunits completed unfinished client_errors redundant
    row="$(sql_tsv "
      SELECT
        COUNT(DISTINCT w.id),
        COUNT(DISTINCT CASE WHEN r.outcome = 1 THEN w.id END),
        COALESCE(SUM(CASE WHEN r.outcome = 0 THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN r.outcome IN (2, 3, 4, 6) THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN r.outcome = 5 THEN 1 ELSE 0 END), 0)
      FROM workunit w
      LEFT JOIN result r ON r.workunitid = w.id
      WHERE w.name LIKE '${prefix}\\_%';
    ")"

    IFS=$'\t' read -r workunits completed unfinished client_errors redundant <<< "$row"
    workunits="${workunits:-0}"
    completed="${completed:-0}"
    unfinished="${unfinished:-0}"
    client_errors="${client_errors:-0}"
    redundant="${redundant:-0}"

    echo "  workunits=$workunits completed=$completed unfinished=$unfinished client_errors=$client_errors redundant=$redundant"

    if [[ "$workunits" -gt 0 && "$unfinished" -eq 0 ]]; then
      return 0
    fi

    if [[ "$client_errors" -gt 0 ]]; then
      echo "В сценарии появились ошибки BOINC; сценарий завершается как проблемный."
      return 0
    fi

    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "Таймаут сценария: $prefix"
      return 0
    fi

    request_client_update
    sleep "$POLL_INTERVAL"
  done
}

collect_case_metrics() {
  local scenario="$1"
  local prefix="$2"
  local started_at="$3"
  local finished_at="$4"
  local out_file="$5"

  python3 - "$PROJECT_NAME" "$SERVER_IP" "$scenario" "$prefix" "$started_at" "$finished_at" "$out_file" <<'PY'
import json
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

project_name, server_ip, scenario, prefix = sys.argv[1:5]
started_at = int(float(sys.argv[5]))
finished_at = int(float(sys.argv[6]))
out_file = Path(sys.argv[7])

def sql(query: str) -> list[str]:
    output = subprocess.check_output(
        [
            "docker",
            "exec",
            "boinc-mariadb",
            "mariadb",
            "-u",
            "root",
            "-proot",
            "-N",
            "-B",
            "-D",
            project_name,
            "-e",
            query,
        ],
        text=True,
    ).strip()
    if not output:
        return []
    return output.split("\t")

row = sql(f"""
SELECT
  COUNT(DISTINCT w.id),
  COUNT(r.id),
  COUNT(DISTINCT CASE WHEN r.outcome = 1 THEN w.id END),
  SUM(CASE WHEN r.outcome = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN r.outcome = 0 THEN 1 ELSE 0 END),
  SUM(CASE WHEN r.outcome IN (2, 3, 4, 6) THEN 1 ELSE 0 END),
  SUM(CASE WHEN r.outcome = 5 THEN 1 ELSE 0 END),
  COALESCE(MIN(w.create_time), 0),
  COALESCE(MAX(CASE WHEN r.received_time > 0 THEN r.received_time ELSE 0 END), 0),
  COALESCE(AVG(CASE WHEN r.outcome = 1 AND r.received_time > 0 THEN r.received_time - w.create_time END), 0),
  COALESCE(AVG(CASE WHEN r.outcome = 1 AND r.elapsed_time > 0 THEN r.elapsed_time END), 0)
FROM workunit w
LEFT JOIN result r ON r.workunitid = w.id
WHERE w.name LIKE '{prefix}\\_%';
""")

def as_float(index: int) -> float:
    try:
        return float(row[index] or 0)
    except (IndexError, ValueError):
        return 0.0

workunits = as_float(0)
results = as_float(1)
completed = as_float(2)
success_results = as_float(3)
unfinished = as_float(4)
errors = as_float(5)
redundant = as_float(6)
first_create_time = as_float(7)
last_received_time = as_float(8)
avg_turnaround = as_float(9)
avg_compute = as_float(10)
executed_results = success_results + errors

if first_create_time > 0 and last_received_time > first_create_time:
    total_seconds = last_received_time - first_create_time
else:
    total_seconds = max(0, finished_at - started_at)

throughput = completed / total_seconds if total_seconds else 0.0
error_percent = errors / results * 100.0 if results else 0.0
replication_factor = executed_results / workunits if workunits else 0.0
overhead = max(0.0, avg_turnaround - avg_compute)

def prom_query_range(expr: str) -> list[float]:
    if finished_at <= started_at:
        return []
    params = urllib.parse.urlencode(
        {
            "query": expr,
            "start": str(started_at),
            "end": str(finished_at),
            "step": "10",
        }
    )
    url = f"http://{server_ip}:9090/api/v1/query_range?{params}"
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except Exception:
        return []

    values = []
    if payload.get("status") != "success":
        return values
    for series in payload.get("data", {}).get("result", []):
        for _, value in series.get("values", []):
            try:
                values.append(float(value))
            except (TypeError, ValueError):
                pass
    return values

def avg(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)

def max_or_none(values: list[float]) -> float | None:
    return max(values) if values else None

cpu_values = prom_query_range('100 * (1 - avg by(instance) (rate(node_cpu_seconds_total{job=~"node_exporter_(clients|server)",mode="idle"}[30s])))')
ram_values = prom_query_range('100 * (1 - node_memory_MemAvailable_bytes{job=~"node_exporter_(clients|server)"} / node_memory_MemTotal_bytes{job=~"node_exporter_(clients|server)"})')
rx_values = prom_query_range('sum by(instance) (rate(node_network_receive_bytes_total{job=~"node_exporter_(clients|server)",device!~"lo|docker.*|veth.*|br.*"}[30s]))')
tx_values = prom_query_range('sum by(instance) (rate(node_network_transmit_bytes_total{job=~"node_exporter_(clients|server)",device!~"lo|docker.*|veth.*|br.*"}[30s]))')

data = {
    "scenario": scenario,
    "prefix": prefix,
    "started_at": started_at,
    "finished_at": finished_at,
    "boinc": {
        "workunits": workunits,
        "results": results,
        "success_results": success_results,
        "executed_results": executed_results,
        "completed_workunits": completed,
        "unfinished_results": unfinished,
        "error_results": errors,
        "redundant_results": redundant,
        "error_percent": error_percent,
        "total_seconds": total_seconds,
        "throughput_workunits_per_second": throughput,
        "avg_turnaround_seconds": avg_turnaround,
        "avg_compute_seconds": avg_compute,
        "avg_overhead_seconds": overhead,
        "actual_replication_factor": replication_factor,
    },
    "clients": {
        "avg_cpu_percent": avg(cpu_values),
        "max_cpu_percent": max_or_none(cpu_values),
        "avg_ram_percent": avg(ram_values),
        "max_ram_percent": max_or_none(ram_values),
        "avg_network_rx_bytes_per_second": avg(rx_values),
        "max_network_rx_bytes_per_second": max_or_none(rx_values),
        "avg_network_tx_bytes_per_second": avg(tx_values),
        "max_network_tx_bytes_per_second": max_or_none(tx_values),
    },
}

out_file.parent.mkdir(parents=True, exist_ok=True)
out_file.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(data, ensure_ascii=False, sort_keys=True))
PY
}

run_network_probe() {
  local out_file="$1"

  python3 - "$ROOT_DIR/ansible/inventory.ini" "$NETWORK_PROBE_MIB" "$out_file" <<'PY'
import json
import shlex
import subprocess
import sys
import time
from pathlib import Path

inventory = Path(sys.argv[1])
size_mib = int(sys.argv[2])
out_file = Path(sys.argv[3])

hosts = []
if inventory.exists() and size_mib > 0:
    inside = False
    for raw in inventory.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            inside = line == "[boinc_clients]"
            continue
        if not inside:
            continue
        parts = line.split()
        host = parts[0]
        user = None
        port = None
        for part in parts[1:]:
            if part.startswith("ansible_host="):
                host = part.split("=", 1)[1]
            elif part.startswith("ansible_user="):
                user = part.split("=", 1)[1]
            elif part.startswith("ansible_port="):
                port = part.split("=", 1)[1]
        hosts.append({"host": host, "user": user, "port": port})

results = []
for item in hosts:
    target = item["host"]
    ssh_target = f'{item["user"]}@{target}' if item["user"] else target
    ssh_opts = ["-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null"]
    if item["port"]:
        ssh_opts += ["-p", item["port"]]

    ping_ms = None
    try:
        ping = subprocess.check_output(["ping", "-c", "3", "-q", target], text=True, stderr=subprocess.DEVNULL)
        marker = "rtt min/avg/max/mdev = "
        if marker in ping:
            ping_ms = float(ping.split(marker, 1)[1].split("/", 3)[1])
    except Exception:
        pass

    throughput_mib_s = None
    command = (
        f"dd if=/dev/zero bs=1M count={size_mib} 2>/dev/null | "
        f"ssh {' '.join(shlex.quote(x) for x in ssh_opts)} {shlex.quote(ssh_target)} "
        "'cat > /tmp/boinc_quick_benchmark_probe.bin && rm -f /tmp/boinc_quick_benchmark_probe.bin'"
    )
    started = time.perf_counter()
    completed = subprocess.run(command, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elapsed = time.perf_counter() - started
    if completed.returncode == 0 and elapsed > 0:
        throughput_mib_s = size_mib / elapsed

    results.append(
        {
            "host": target,
            "ping_avg_ms": ping_ms,
            "ssh_upload_probe_mib": size_mib,
            "ssh_upload_throughput_mib_per_second": throughput_mib_s,
        }
    )

out_file.parent.mkdir(parents=True, exist_ok=True)
out_file.write_text(json.dumps(results, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(results, ensure_ascii=False, sort_keys=True))
PY
}

write_summary() {
  local report_root="$1"

  python3 - "$report_root" <<'PY'
import csv
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
rows = []
for path in sorted(root.glob("*/metrics.json")):
    data = json.loads(path.read_text(encoding="utf-8"))
    boinc = data["boinc"]
    clients = data["clients"]
    row = {
        "scenario": data["scenario"],
        "workunits": boinc["workunits"],
        "completed": boinc["completed_workunits"],
        "errors": boinc["error_results"],
        "redundant": boinc.get("redundant_results", 0),
        "error_percent": boinc["error_percent"],
        "total_seconds": boinc["total_seconds"],
        "throughput_wu_s": boinc["throughput_workunits_per_second"],
        "avg_overhead_s": boinc["avg_overhead_seconds"],
        "replication_factor": boinc["actual_replication_factor"],
        "avg_cpu_percent": clients["avg_cpu_percent"],
        "avg_ram_percent": clients["avg_ram_percent"],
        "avg_net_rx_b_s": clients["avg_network_rx_bytes_per_second"],
        "avg_net_tx_b_s": clients["avg_network_tx_bytes_per_second"],
    }
    rows.append(row)

csv_path = root / "summary.csv"
with csv_path.open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()) if rows else ["scenario"])
    writer.writeheader()
    writer.writerows(rows)

valid = [row for row in rows if float(row["errors"]) == 0 and float(row["completed"]) > 0]
best = max(valid, key=lambda row: float(row["throughput_wu_s"]), default=None)

md = ["# Quick benchmark report", ""]
if best:
    md.append(f"Лучшая конфигурация по throughput без ошибок: `{best['scenario']}`.")
    md.append(
        f"Throughput: {float(best['throughput_wu_s']):.4f} задач/с, "
        f"overhead: {float(best['avg_overhead_s']):.2f} с, "
        f"replication: {float(best['replication_factor']):.2f}."
    )
else:
    md.append("Нет сценариев без ошибок. Сначала проверь app/task runner и статус клиентов.")
md.append("")
md.append("| Сценарий | Задач | Завершено | Ошибки,% | Время,с | Задач/с | Overhead,с | CPU,% | RAM,% | RX B/s | TX B/s |")
md.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for row in rows:
    def fmt(value, digits=2):
        if value is None:
            return ""
        try:
            return f"{float(value):.{digits}f}"
        except (TypeError, ValueError):
            return ""
    md.append(
        "| {scenario} | {workunits:.0f} | {completed:.0f} | {error_percent:.2f} | "
        "{total_seconds:.1f} | {throughput_wu_s:.4f} | {avg_overhead_s:.2f} | "
        "{cpu} | {ram} | {rx} | {tx} |".format(
            scenario=row["scenario"],
            workunits=float(row["workunits"]),
            completed=float(row["completed"]),
            error_percent=float(row["error_percent"]),
            total_seconds=float(row["total_seconds"]),
            throughput_wu_s=float(row["throughput_wu_s"]),
            avg_overhead_s=float(row["avg_overhead_s"]),
            cpu=fmt(row["avg_cpu_percent"], 1),
            ram=fmt(row["avg_ram_percent"], 1),
            rx=fmt(row["avg_net_rx_b_s"], 0),
            tx=fmt(row["avg_net_tx_b_s"], 0),
        )
    )

(root / "summary.md").write_text("\n".join(md) + "\n", encoding="utf-8")
print(root / "summary.md")
PY
}

run_case() {
  local scenario="$1"
  local benchmark_type="$2"
  local task_file="$3"
  local task_count="$4"
  local task_seconds="$5"
  local target_nresults="$6"
  local min_quorum="$7"
  local max_success_results="$8"
  local max_total_results="${9:-}"

  local scenario_dir="$REPORT_ROOT/$scenario"
  local params_file="$scenario_dir/params.jsonl"
  local metrics_file="$scenario_dir/metrics.json"
  local prefix
  prefix="qb_${scenario}_$(date +%s)_$$"
  prefix="${prefix//[^A-Za-z0-9_]/_}"

  echo
  echo "============================================================"
  echo "Benchmark: $scenario"
  echo "============================================================"

  mkdir -p "$scenario_dir"
  generate_params "$benchmark_type" "$task_count" "$task_seconds" "$params_file"
  write_distributed_config "$target_nresults" "$min_quorum" "$max_success_results" "$max_total_results"
  cp "$ROOT_DIR/config/distributed.env" "$scenario_dir/distributed.env"

  local started_at finished_at
  started_at="$(date +%s)"
  PYTHON_TASK_RUN_ID="$prefix" \
    apps/python_task_runner/run_task.sh \
      --task "$task_file" \
      --params "$params_file"

  wait_for_case "$prefix"
  request_client_update
  sleep 5
  finished_at="$(date +%s)"

  collect_case_metrics "$scenario" "$prefix" "$started_at" "$finished_at" "$metrics_file" > "$scenario_dir/metrics.compact.json"
}

print_plan

if [[ "$ASSUME_YES" != "1" ]]; then
  echo
  echo "Реальный запуск не начат."
  echo "Чтобы запустить:"
  echo "  ./scripts/run_quick_benchmarks.sh --yes --replicas $REPLICA_COUNT"
  exit 0
fi

require_runtime
mkdir -p "$REPORT_ROOT"

if [[ "$NETWORK_PROBE_MIB" -gt 0 ]]; then
  echo
  echo "== Network probe =="
  run_network_probe "$REPORT_ROOT/network_probe.json" || true
fi

run_case "tiny_40_base" "tiny" "$ROOT_DIR/apps/python_task_runner/examples/tiny_tasks_overhead/user_task.py" 40 0 1 1 1
run_case "cpu_light_16_base" "cpu" "$ROOT_DIR/apps/python_task_runner/examples/synthetic_cpu/user_task.py" 16 1.5 1 1 1
run_case "cpu_heavy_8_base" "cpu" "$ROOT_DIR/apps/python_task_runner/examples/synthetic_cpu/user_task.py" 8 5 1 1 1
run_case "io_small_8_base" "io" "$ROOT_DIR/apps/python_task_runner/examples/io_test/user_task.py" 8 0 1 1 1

if [[ "$WITH_REPLICATION" == "1" && "$REPLICA_COUNT" -gt 1 ]]; then
  run_case "cpu_light_16_repl${REPLICA_COUNT}" "cpu" "$ROOT_DIR/apps/python_task_runner/examples/synthetic_cpu/user_task.py" 16 1.5 "$QUORUM" "$QUORUM" "$QUORUM" "$REPLICA_COUNT"
fi

write_summary "$REPORT_ROOT"

echo
echo "Quick benchmarks завершены."
echo "Отчёт:"
echo "  $REPORT_ROOT/summary.md"
echo "CSV:"
echo "  $REPORT_ROOT/summary.csv"
