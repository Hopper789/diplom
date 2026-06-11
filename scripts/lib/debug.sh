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

quiet_run() {
  if debug_enabled; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

quiet_run_all() {
  if debug_enabled; then
    "$@"
  else
    "$@" >/dev/null 2>&1
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
    COMPOSE_BAKE=false COMPOSE_PROGRESS=quiet docker compose "$@" >/dev/null 2>&1
  fi
}

configure_quiet_ansible() {
  if ! debug_enabled; then
    export ANSIBLE_DISPLAY_OK_HOSTS="${ANSIBLE_DISPLAY_OK_HOSTS:-false}"
    export ANSIBLE_DISPLAY_SKIPPED_HOSTS="${ANSIBLE_DISPLAY_SKIPPED_HOSTS:-false}"
    export ANSIBLE_DISPLAY_FAILED_STDERR="${ANSIBLE_DISPLAY_FAILED_STDERR:-true}"
  fi
}
