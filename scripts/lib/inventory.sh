#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

inventory_client_hosts() {
  local inventory="${1:-$ROOT_DIR/ansible/inventory.ini}"

  if [[ ! -f "$inventory" ]]; then
    return 0
  fi

  awk '
    /^\[boinc_clients\]/ {inside=1; next}
    /^\[/ {inside=0}
    !inside || /^[[:space:]]*($|#)/ {next}
    {
      host=$1
      port=""
      for (i=2; i<=NF; i++) {
        if ($i ~ /^ansible_host=/) {
          split($i, a, "=")
          host=a[2]
        }
        if ($i ~ /^ansible_port=/) {
          split($i, a, "=")
          port=a[2]
        }
      }
      if (host != "") {
        print host "|" port
      }
    }
  ' "$inventory"
}

refresh_client_known_hosts() {
  local inventory="${1:-$ROOT_DIR/ansible/inventory.ini}"
  local row
  local host
  local port

  if [[ ! -f "$inventory" ]]; then
    return 0
  fi

  step "Refreshing SSH known_hosts..."
  while IFS="|" read -r host port; do
    [[ -z "$host" ]] && continue

    if [[ -n "$port" ]]; then
      debug_enabled && echo "  removing old SSH host key for $host:$port"
      ssh-keygen -R "[$host]:$port" >/dev/null 2>&1 || true
    else
      debug_enabled && echo "  removing old SSH host key for $host"
      ssh-keygen -R "$host" >/dev/null 2>&1 || true
    fi
  done < <(inventory_client_hosts "$inventory")
}
