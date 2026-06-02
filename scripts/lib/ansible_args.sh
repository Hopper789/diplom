#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

build_ansible_args() {
  ANSIBLE_ARGS=()
  ANSIBLE_REMAINING_ARGS=()
  ANSIBLE_VAULT_MODE_SELECTED=0

  local vault_mode_selected=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ask-vault-pass|--vault)
        ANSIBLE_ARGS+=(--ask-vault-pass)
        vault_mode_selected=1
        ANSIBLE_VAULT_MODE_SELECTED=1
        shift
        ;;
      --vault-password-file)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --vault-password-file requires a path." >&2
          exit 2
        fi
        ANSIBLE_ARGS+=(--vault-password-file "$2")
        vault_mode_selected=1
        ANSIBLE_VAULT_MODE_SELECTED=1
        shift 2
        ;;
      --ask-become-pass|-K)
        ANSIBLE_ARGS+=(--ask-become-pass)
        shift
        ;;
      *)
        ANSIBLE_REMAINING_ARGS+=("$1")
        shift
        ;;
    esac
  done

  if [[ "$vault_mode_selected" == "0" && -f "$ROOT_DIR/ansible/.vault_pass" ]]; then
    ANSIBLE_ARGS+=(--vault-password-file "$ROOT_DIR/ansible/.vault_pass")
  fi
}
