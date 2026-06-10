#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/ansible_args.sh
source "$ROOT_DIR/scripts/lib/ansible_args.sh"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/diagnose_compute.sh [--debug] [--ask-vault-pass|--vault] [--vault-password-file FILE] [--ask-become-pass|-K]

Print BOINC DB state and remote client CPU/task diagnostics.
USAGE
}

cd "$ROOT_DIR"

build_ansible_args "$@"
set -- "${ANSIBLE_REMAINING_ARGS[@]}"

if [[ $# -gt 0 ]]; then
  case "$1" in
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
fi

if [[ ! -f "$ROOT_DIR/config/generated.env" ]]; then
  echo "ERROR: config/generated.env not found."
  echo "Run first:"
  echo "  ./scripts/prepare_system.sh"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "$ROOT_DIR/config/generated.env"
set +a

if [[ ! -f "$ROOT_DIR/ansible/inventory.ini" ]]; then
  echo "ERROR: ansible/inventory.ini not found."
  echo "Run first:"
  echo "  ./scripts/prepare_system.sh"
  exit 1
fi

echo "== BOINC DB app/version/result states =="
if docker ps --format '{{.Names}}' | grep -qx 'boinc-mariadb'; then
  docker exec boinc-mariadb mariadb -u root -proot -D "$PROJECT_NAME" -e "
    SELECT a.id, a.name, a.user_friendly_name FROM app a ORDER BY a.id;
    SELECT
      a.name AS app,
      av.version_num,
      p.name AS platform,
      av.plan_class,
      av.min_core_version
    FROM app_version av
    JOIN app a ON a.id = av.appid
    JOIN platform p ON p.id = av.platformid
    ORDER BY av.id;
    SELECT a.name AS app, COUNT(*) AS results
    FROM result r
    JOIN workunit w ON w.id = r.workunitid
    JOIN app a ON a.id = w.appid
    GROUP BY a.name;
    SELECT server_state, outcome, client_state, hostid, COUNT(*) AS results
    FROM result
    GROUP BY server_state, outcome, client_state, hostid
    ORDER BY server_state, outcome, client_state, hostid;
    SELECT id, name, appid, min_quorum, target_nresults, max_success_results, max_total_results
    FROM workunit
    ORDER BY id DESC
    LIMIT 10;
  " || true
else
  echo "boinc-mariadb is not running on this machine."
fi

echo
echo "== Remote BOINC client CPU/tasks =="
remote_cmd="$(cat <<EOF
echo '--- docker containers ---'
docker ps --no-trunc | sed -n '1,20p'

echo '--- BOINC tasks ---'
docker exec boinc-client boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' --get_tasks || true

echo '--- BOINC project status ---'
docker exec boinc-client boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' --get_project_status || true

echo '--- BOINC messages ---'
docker exec boinc-client boinccmd --passwd '$BOINC_CLIENT_RPC_PASSWORD' --get_messages | tail -80 || true

echo '--- CPU visible to boinc-client container ---'
docker exec boinc-client sh -lc '
echo nproc=\$(nproc)
echo cpu.max=\$(cat /sys/fs/cgroup/cpu.max 2>/dev/null || true)
echo cpuset=\$(cat /sys/fs/cgroup/cpuset.cpus.effective 2>/dev/null || cat /sys/fs/cgroup/cpuset/cpuset.cpus 2>/dev/null || true)
echo loadavg=\$(cat /proc/loadavg)
'

echo '--- top processes inside boinc-client ---'
docker exec boinc-client sh -lc 'ps -eo pid,ppid,stat,pcpu,pmem,args --sort=-pcpu | head -30' || true

echo '--- top threads inside boinc-client ---'
docker exec boinc-client sh -lc 'ps -eLo pid,tid,psr,stat,pcpu,args --sort=-pcpu | head -40' || true

echo '--- docker stats ---'
docker stats --no-stream boinc-client || true
EOF
)"

ANSIBLE_HOST_KEY_CHECKING=False \
  ansible -i "$ROOT_DIR/ansible/inventory.ini" boinc_clients -b "${ANSIBLE_ARGS[@]}" -m shell -a "$remote_cmd"
