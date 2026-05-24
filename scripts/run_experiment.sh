#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./scripts/run_experiment.sh [OPTIONS]

Options passed to Ansible calls inside the experiment runner:
  --ask-vault-pass, --vault  Ask Ansible Vault password
  --vault-password-file FILE Use Vault password file
  --vault-id ID             Use Ansible Vault ID
  --ask-become-pass, -K      Ask sudo password for remote clients

Examples:
  ./scripts/run_experiment.sh --ask-vault-pass
  ./scripts/run_experiment.sh --vault-password-file ~/.vault_pass.txt
  ./scripts/run_experiment.sh --ask-become-pass
USAGE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

ANSIBLE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ask-vault-pass|--vault)
      ANSIBLE_ARGS+=(--ask-vault-pass)
      shift
      ;;
    --vault-password-file|--vault-id)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: $1 requires an argument" >&2
        exit 2
      fi
      ANSIBLE_ARGS+=("$1" "$2")
      shift 2
      ;;
    --ask-become-pass|-K)
      ANSIBLE_ARGS+=(--ask-become-pass)
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -n "${ANSIBLE_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_FROM_ENV=(${ANSIBLE_EXTRA_ARGS})
  ANSIBLE_ARGS+=("${EXTRA_FROM_ENV[@]}")
fi

if [[ ! -f "$ROOT_DIR/config/generated.env" ]]; then
  echo "ERROR: config/generated.env not found."
  echo "Run first:"
  echo "  ./scripts/init_config.sh"
  echo "  ./scripts/server_up.sh"
  echo "  ./scripts/create_account_db.sh"
  exit 1
fi

if [[ ! -f "$ROOT_DIR/config/experiment.env" && -f "$ROOT_DIR/config/experiment.example.env" ]]; then
  echo "Creating config/experiment.env from example..."
  cp "$ROOT_DIR/config/experiment.example.env" "$ROOT_DIR/config/experiment.env"
fi

if [[ ${#ANSIBLE_ARGS[@]} -gt 0 ]]; then
  printf -v ANSIBLE_EXTRA_ARGS_VALUE '%q ' "${ANSIBLE_ARGS[@]}"
  export ANSIBLE_EXTRA_ARGS="${ANSIBLE_EXTRA_ARGS_VALUE% }"
fi

echo "== BOINC experiment runner =="
echo

echo "Experiment config:"
if [[ -f "$ROOT_DIR/config/experiment.env" ]]; then
  grep -v '^#' "$ROOT_DIR/config/experiment.env" | grep -v '^$' || true
else
  echo "No config/experiment.env found; using defaults from run_task.sh."
fi

echo
echo "Submitting BOINC work..."
apps/ml_grid_search/run_task.sh boinc

echo
echo "Status after submitting work:"
./scripts/status.sh "${ANSIBLE_ARGS[@]}" || true
