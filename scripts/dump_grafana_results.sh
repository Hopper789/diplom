#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/config/generated.env"

# shellcheck source=scripts/lib/debug.sh
source "$ROOT_DIR/scripts/lib/debug.sh"

WAIT=0
MAX_SECONDS="${BOINC_DUMP_WAIT_SECONDS:-0}"
INTERVAL_SECONDS="${BOINC_DUMP_INTERVAL_SECONDS:-15}"
FROM="${GRAFANA_DUMP_FROM:-now-6h}"
TO="${GRAFANA_DUMP_TO:-now}"
WIDTH="${GRAFANA_DUMP_WIDTH:-1600}"
HEIGHT="${GRAFANA_DUMP_HEIGHT:-900}"
OUT_DIR=""
QUIET="${BOINC_DUMP_QUIET:-1}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/dump_grafana_results.sh [options]

What it does:
  Waits until BOINC work is complete, renders Grafana dashboard panels to PNG,
  and writes final experiment metrics to Markdown and JSON.

Options:
  --wait                    wait until all BOINC results are finished
  --max-seconds N           max wait time when --wait is used; 0 means check once
  --interval-seconds N      wait interval; default: 15
  --from VALUE              Grafana render range start; default: now-6h
  --to VALUE                Grafana render range end; default: now
  --output-dir DIR          output directory
  --width PX                rendered panel width; default: 1600
  --height PX               rendered panel height; default: 900
  --quiet                   suppress progress output; errors are still printed
  --debug                   show full command output
  --help, -h
USAGE
}

strip_debug_args "$@"
set -- "${DEBUG_ARGS[@]}"
if debug_enabled; then
  QUIET=0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait)
      WAIT=1
      shift
      ;;
    --max-seconds)
      MAX_SECONDS="${2:-}"
      shift 2
      ;;
    --interval-seconds)
      INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    --from)
      FROM="${2:-}"
      shift 2
      ;;
    --to)
      TO="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --width)
      WIDTH="${2:-}"
      shift 2
      ;;
    --height)
      HEIGHT="${2:-}"
      shift 2
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

for pair in "MAX_SECONDS:$MAX_SECONDS" "INTERVAL_SECONDS:$INTERVAL_SECONDS" "WIDTH:$WIDTH" "HEIGHT:$HEIGHT"; do
  name="${pair%%:*}"
  value="${pair#*:}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 0 ]]; then
    echo "$name must be a non-negative integer: $value" >&2
    exit 2
  fi
done

if [[ "$INTERVAL_SECONDS" -lt 1 ]]; then
  echo "INTERVAL_SECONDS must be >= 1" >&2
  exit 2
fi

cd "$ROOT_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: config/generated.env not found." >&2
  echo "Run first:" >&2
  echo "  ./scripts/prepare_system.sh" >&2
  echo "  ./scripts/launch_cluster.sh" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a

MONITORING_HOST="${SERVER_IP:-localhost}"
GRAFANA_URL="${GRAFANA_URL:-http://$MONITORING_HOST:3000}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://$MONITORING_HOST:9090}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$ROOT_DIR/reports/grafana_dumps/$(date +%Y%m%d_%H%M%S)"
fi

sql_tsv() {
  docker exec boinc-mariadb mariadb -u root -proot -N -B -D "$PROJECT_NAME" -e "$1"
}

read_progress() {
  local row
  row="$(sql_tsv "
    SELECT
      COUNT(*),
      COALESCE(SUM(CASE WHEN completed = 1 THEN 1 ELSE 0 END), 0),
      COALESCE(SUM(unfinished), 0),
      COALESCE(SUM(client_errors), 0),
      COALESCE(SUM(redundant), 0)
    FROM (
      SELECT
        w.id,
        CASE
          WHEN COALESCE(w.canonical_resultid, 0) > 0
            OR COALESCE(SUM(CASE WHEN r.outcome = 1 THEN 1 ELSE 0 END), 0)
               >= GREATEST(COALESCE(NULLIF(w.min_quorum, 0), 1), 1)
          THEN 1 ELSE 0
        END AS completed,
        COALESCE(SUM(CASE WHEN r.outcome = 0 THEN 1 ELSE 0 END), 0) AS unfinished,
        COALESCE(SUM(CASE WHEN r.outcome IN (2, 3, 4, 6) THEN 1 ELSE 0 END), 0) AS client_errors,
        COALESCE(SUM(CASE WHEN r.outcome = 5 THEN 1 ELSE 0 END), 0) AS redundant
      FROM workunit w
      LEFT JOIN result r ON r.workunitid = w.id
      GROUP BY w.id, w.min_quorum, w.canonical_resultid
    ) q;
  ")"

  IFS=$'\t' read -r WORKUNITS COMPLETED UNFINISHED CLIENT_ERRORS REDUNDANT <<< "$row"
  WORKUNITS="${WORKUNITS:-0}"
  COMPLETED="${COMPLETED:-0}"
  UNFINISHED="${UNFINISHED:-0}"
  CLIENT_ERRORS="${CLIENT_ERRORS:-0}"
  REDUNDANT="${REDUNDANT:-0}"
}

is_complete() {
  if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-mariadb'; then
    echo "ERROR: boinc-mariadb is not running." >&2
    return 2
  fi

  read_progress
  [[ "$WORKUNITS" -gt 0 && "$UNFINISHED" -eq 0 && "$COMPLETED" -ge "$WORKUNITS" ]]
}

log() {
  if [[ "$QUIET" != "1" ]]; then
    echo "$@"
  fi
}

if [[ "$WAIT" == "1" ]]; then
  log "Waiting for BOINC computations to finish before dumping Grafana..."
  deadline=$((SECONDS + MAX_SECONDS))

  while true; do
    if is_complete; then
      log "BOINC computations completed: workunits=$WORKUNITS completed=$COMPLETED unfinished=$UNFINISHED client_errors=$CLIENT_ERRORS redundant=$REDUNDANT"
      break
    fi

    log "BOINC still running: workunits=$WORKUNITS completed=$COMPLETED unfinished=$UNFINISHED client_errors=$CLIENT_ERRORS redundant=$REDUNDANT"

    if [[ "$MAX_SECONDS" -eq 0 || "$SECONDS" -ge "$deadline" ]]; then
      echo "ERROR: computations are not complete; Grafana dump skipped." >&2
      exit 1
    fi

    sleep "$INTERVAL_SECONDS"
  done
else
  if ! is_complete; then
    echo "ERROR: computations are not complete; use --wait to wait for completion." >&2
    exit 1
  fi
fi

if ! curl -fsS "$GRAFANA_URL/api/health" >/dev/null; then
  echo "ERROR: Grafana is not available at $GRAFANA_URL" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx 'boinc-grafana-renderer'; then
  echo "ERROR: boinc-grafana-renderer is not running; PNG rendering is unavailable." >&2
  echo "Start monitoring again:" >&2
  echo "  ./scripts/monitoring_up.sh" >&2
  exit 1
fi

if ! curl -fsS "$PROMETHEUS_URL/api/v1/query?query=up" >/dev/null; then
  echo "ERROR: Prometheus is not available at $PROMETHEUS_URL" >&2
  exit 1
fi

mkdir -p "$OUT_DIR/panels" "$OUT_DIR/dashboards"

python3 - "$ROOT_DIR" "$OUT_DIR" <<'PY' > "$OUT_DIR/panels.tsv"
import json
import re
import sys
import unicodedata
from pathlib import Path

root = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
dashboards_dir = root / "monitoring" / "grafana" / "dashboards"

def slug(value):
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"[^A-Za-z0-9]+", "-", value).strip("-").lower()
    return value or "dashboard"

def safe_name(value):
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("_")
    return value or "panel"

for path in sorted(dashboards_dir.glob("*.json")):
    dashboard = json.loads(path.read_text(encoding="utf-8"))
    uid = dashboard.get("uid") or path.stem
    title = dashboard.get("title") or uid
    dashboard_slug = slug(title)

    copied = out_dir / "dashboards" / path.name
    copied.write_text(json.dumps(dashboard, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    dashboard_out = out_dir / "panels" / safe_name(uid)
    dashboard_out.mkdir(parents=True, exist_ok=True)

    panels = dashboard.get("panels") or []
    for index, panel in enumerate(panels, start=1):
        if panel.get("type") == "row":
            continue
        panel_id = panel.get("id")
        if panel_id is None:
            continue
        panel_title = panel.get("title") or f"panel_{panel_id}"
        file_name = f"{index:02d}_{panel_id}_{safe_name(panel_title)}.png"
        out_path = dashboard_out / file_name
        print("\t".join([uid, dashboard_slug, str(panel_id), panel_title, str(out_path)]))
PY

log "Rendering Grafana panels..."
rendered=0
failed=0

while IFS=$'\t' read -r uid slug panel_id panel_title panel_out; do
  [[ -z "${uid:-}" ]] && continue

  if curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASSWORD" \
    --get "$GRAFANA_URL/render/d-solo/$uid/$slug" \
    --data-urlencode "orgId=1" \
    --data-urlencode "panelId=$panel_id" \
    --data-urlencode "from=$FROM" \
    --data-urlencode "to=$TO" \
    --data-urlencode "width=$WIDTH" \
    --data-urlencode "height=$HEIGHT" \
    --data-urlencode "tz=UTC" \
    -o "$panel_out"; then
    rendered=$((rendered + 1))
    log "  OK: $panel_title"
  else
    failed=$((failed + 1))
    echo "  FAILED: $panel_title" >&2
    rm -f "$panel_out"
  fi
done < "$OUT_DIR/panels.tsv"

log "Dumping final metrics..."
PROMETHEUS_URL="$PROMETHEUS_URL" python3 - "$ROOT_DIR" "$OUT_DIR" <<'PY'
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
dashboard_path = root / "monitoring" / "grafana" / "dashboards" / "boinc.json"
prometheus_url = os.environ["PROMETHEUS_URL"].rstrip("/")

dashboard = json.loads(dashboard_path.read_text(encoding="utf-8"))
panels = dashboard.get("panels") or []

summary_row_y = None
next_row_y = None
for panel in panels:
    if panel.get("type") == "row" and panel.get("title") == "Итоговые метрики эксперимента":
        gp = panel.get("gridPos") or {}
        summary_row_y = gp.get("y", 0) + gp.get("h", 0)
        break

if summary_row_y is not None:
    row_ys = [
        (panel.get("gridPos") or {}).get("y", 0)
        for panel in panels
        if panel.get("type") == "row" and (panel.get("gridPos") or {}).get("y", 0) >= summary_row_y
    ]
    if row_ys:
        next_row_y = min(row_ys)

if summary_row_y is None:
    summary_panels = [
        p for p in panels
        if p.get("title") in {
            "Хосты",
            "Готово",
            "Осталось",
            "Ошибки",
            "Время",
            "Полезная нагрузка",
            "% выданных задач",
            "Репликация",
        }
    ]
else:
    summary_panels = [
        p for p in panels
        if (
            p.get("type") == "stat"
            and (p.get("gridPos") or {}).get("y", -1) >= summary_row_y
            and (next_row_y is None or (p.get("gridPos") or {}).get("y", -1) < next_row_y)
        )
    ]

def query_prometheus(expr):
    url = prometheus_url + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    with urllib.request.urlopen(url, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return payload

def extract_value(payload):
    data = payload.get("data") or {}
    result = data.get("result") or []
    if not result:
        return None
    first = result[0]
    value = first.get("value") or []
    if len(value) >= 2:
        return value[1]
    return None

def extract_hosts_value(payload):
    data = payload.get("data") or {}
    result = data.get("result") or []
    if not result:
        return None
    metric = result[0].get("metric") or {}
    active = metric.get("active")
    total = metric.get("total")
    if active is None or total is None:
        return extract_value(payload)
    return f"{active}/{total}"

def query_hosts_pair():
    active_payload = query_prometheus("boinc_hosts_active_recent_total")
    total_payload = query_prometheus("boinc_hosts_total")
    active = extract_value(active_payload)
    total = extract_value(total_payload)
    if active is None or total is None:
        return active_payload, None
    return active_payload, f"{active}/{total}"

records = []
for panel in sorted(summary_panels, key=lambda p: ((p.get("gridPos") or {}).get("y", 0), (p.get("gridPos") or {}).get("x", 0))):
    targets = panel.get("targets") or []
    expr = next((target.get("expr") for target in targets if target.get("expr")), None)
    if not expr:
        continue
    try:
        if panel.get("title") == "Хосты":
            payload, value = query_hosts_pair()
        else:
            payload = query_prometheus(expr)
            if expr == "boinc_hosts_summary":
                value = extract_hosts_value(payload)
            else:
                value = extract_value(payload)
        status = payload.get("status", "unknown")
        error = None
    except Exception as exc:
        payload = None
        value = None
        status = "error"
        error = str(exc)

    records.append({
        "title": panel.get("title"),
        "expr": expr,
        "value": value,
        "status": status,
        "error": error,
        "raw": payload,
    })

metrics = {
    "generated_at": datetime.now(timezone.utc).isoformat(),
    "prometheus_url": prometheus_url,
    "dashboard_uid": dashboard.get("uid"),
    "dashboard_title": dashboard.get("title"),
    "metrics": records,
}

(out_dir / "final_metrics.json").write_text(
    json.dumps(metrics, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

lines = [
    "# Final Metrics",
    "",
    f"Generated at: `{metrics['generated_at']}`",
    "",
    "| Metric | Value | Prometheus query |",
    "|---|---:|---|",
]

for record in records:
    value = record["value"]
    if value is None:
        value = "n/a"
    lines.append(f"| {record['title']} | `{value}` | `{record['expr']}` |")

(out_dir / "final_metrics.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

cat > "$OUT_DIR/summary.md" <<EOF
# Grafana Dump

Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Grafana: $GRAFANA_URL
Prometheus: $PROMETHEUS_URL
Range: $FROM .. $TO

Rendered panels: $rendered
Failed panels: $failed

Files:
- panels: panels/
- final metrics: final_metrics.md
- final metrics JSON: final_metrics.json
- dashboard JSON copies: dashboards/
EOF

if [[ "$QUIET" != "1" ]]; then
  echo
  echo "Grafana dump completed:"
  echo "  $OUT_DIR"
  echo "Rendered panels: $rendered"
  echo "Failed panels:   $failed"
fi

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
