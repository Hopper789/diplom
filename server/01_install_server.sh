#!/usr/bin/env bash
echo Installing server...
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config.env"

echo "[1/6] Updating packages..."
sudo apt update

echo "[2/6] Installing dependencies..."
sudo apt install -y \
  git \
  build-essential \
  autoconf \
  automake \
  libtool \
  pkg-config \
  python3 \
  python3-pip \
  apache2 \
  mariadb-server \
  php \
  php-mysql \
  libmysqlclient-dev \
  libssl-dev \
  libcurl4-openssl-dev \
  libxml2-dev \
  ansible

echo "[3/6] Cloning BOINC source..."
if [ ! -d "$BOINC_SRC_DIR" ]; then
  git clone https://github.com/BOINC/boinc.git "$BOINC_SRC_DIR"
else
  echo "BOINC source already exists: $BOINC_SRC_DIR"
fi

cd "$BOINC_SRC_DIR"

echo "[4/6] Preparing BOINC build..."
./_autosetup

echo "[5/6] Configuring BOINC server build..."
./configure --disable-client --enable-server

echo "[6/6] Building BOINC..."
make -j"$(nproc)"

echo "BOINC server source built successfully."