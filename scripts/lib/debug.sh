#!/usr/bin/env bash

DEBUG="${DEBUG:-0}"

strip_debug_args() {
  DEBUG_ARGS=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --debug)
        DEBUG=1
        export DEBUG
        shift
        ;;
      *)
        DEBUG_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

debug_enabled() {
  [[ "${DEBUG:-0}" == "1" ]]
}

run_quietly() {
  local output_file rc had_errexit=0
  output_file="$(mktemp -t diplom-command-output.XXXXXX)"

  case "$-" in
    *e*) had_errexit=1 ;;
  esac

  set +e
  "$@" >"$output_file" 2>&1
  rc=$?
  if [[ "$had_errexit" == "1" ]]; then
    set -e
  fi

  if [[ "$rc" -eq 0 ]]; then
    rm -f "$output_file"
    return 0
  fi

  echo "ERROR: command failed with exit code $rc:" >&2
  printf '  ' >&2
  printf '%q ' "$@" >&2
  printf '\n' >&2

  if [[ -s "$output_file" ]]; then
    echo >&2
    echo "Command output, last ${QUIET_ERROR_LINES:-120} lines:" >&2
    tail -n "${QUIET_ERROR_LINES:-120}" "$output_file" >&2 || true
  fi

  rm -f "$output_file"
  return "$rc"
}

quiet_run() {
  if debug_enabled; then
    "$@"
  else
    run_quietly "$@"
  fi
}

quiet_run_all() {
  if debug_enabled; then
    "$@"
  else
    run_quietly "$@"
  fi
}

quiet_output() {
  if debug_enabled; then
    cat
  else
    cat >/dev/null
  fi
}

step() {
  echo "$@"
}

compose_run() {
  if debug_enabled; then
    COMPOSE_BAKE=false docker compose "$@"
  else
    run_quietly env COMPOSE_BAKE=false COMPOSE_PROGRESS=quiet docker compose "$@"
  fi
}

configure_quiet_ansible() {
  if ! debug_enabled; then
    export ANSIBLE_DISPLAY_OK_HOSTS="${ANSIBLE_DISPLAY_OK_HOSTS:-false}"
    export ANSIBLE_DISPLAY_SKIPPED_HOSTS="${ANSIBLE_DISPLAY_SKIPPED_HOSTS:-false}"
    export ANSIBLE_DISPLAY_FAILED_STDERR="${ANSIBLE_DISPLAY_FAILED_STDERR:-true}"
  fi
}
