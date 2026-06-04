#!/usr/bin/env bash
set -euo pipefail

echo "Installing server-side requirements..."

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: this script currently supports Debian/Ubuntu only."
  exit 1
fi

sudo apt update

sudo apt install -y \
  curl \
  ca-certificates \
  bash \
  python3 \
  python3-pip \
  python3-yaml \
  ansible \
  openssh-client \
  sshpass \
  build-essential \
  make \
  m4 \
  pkg-config \
  autoconf \
  automake \
  libtool \
  mysql-client \
  docker.io \
  docker-compose-v2

echo
echo "Installing Python compute packages..."
if ! python3 - <<'PY' >/dev/null 2>&1
import numpy
import numba
PY
then
  if ! sudo apt install -y python3-numpy python3-numba; then
    python3 -m pip install \
      --break-system-packages \
      --user \
      numpy \
      numba
  fi
fi

python3 - <<'PY'
import numpy
import numba
import yaml

print(f"OK: numpy -> {numpy.__version__}")
print(f"OK: numba -> {numba.__version__}")
print(f"OK: yaml -> {yaml.__version__}")
PY

echo
echo "Checking installed tools..."

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    echo "OK: $1 -> $($1 --version 2>/dev/null | head -n 1 || true)"
  else
    echo "MISSING: $1"
  fi
}

check_cmd git
check_cmd curl
check_cmd python3
check_cmd ansible
check_cmd ssh
check_cmd docker

echo
echo "Checking Docker Compose..."
docker compose version || true

echo
echo "Server requirements installation completed."
echo
echo "If Docker requires sudo, either run Docker commands with sudo or add current user to docker group:"
echo "  sudo usermod -aG docker \$USER"
echo "Then log out and log in again."
