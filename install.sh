#!/usr/bin/env bash
set -euo pipefail

REPO="acfrr/XrayR11"
REF="master"
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
TMP_DIR="/tmp/xrayr11-build"
GO_VERSION="1.22.12"

need_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "请用 root 运行"
    exit 1
  fi
}

need_go_upgrade() {
  if ! command -v go >/dev/null 2>&1; then
    return 0
  fi

  current="$(go version | awk '{print $3}' | sed 's/^go//')"
  minimum="1.21.0"

  if [ "$(printf '%s\n' "$minimum" "$current" | sort -V | head -n1)" != "$minimum" ]; then
    return 0
  fi

  return 1
}

install_go() {
  cd /tmp
  rm -rf /usr/local/go "go${GO_VERSION}.linux-amd64.tar.gz"
  wget -O "go${GO_VERSION}.linux-amd64.tar.gz" "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
  tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
  export PATH=/usr/local/go/bin:$PATH
}

need_root
export PATH=/usr/local/go/bin:$PATH

echo "==> 安装依赖"
apt update
apt install -y git wget curl ca-certificates tar gzip build-essential

if need_go_upgrade; then
  echo "==> 安装 Go ${GO_VERSION}"
  install_go
fi

echo "==> 当前 Go 版本"
go version

echo "==> 下载源码"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
cd "${TMP_DIR}"
wget -O source.tar.gz "https://github.com/${REPO}/archive/refs/heads/${REF}.tar.gz"
tar -xzf source.tar.gz
SRC_DIR="$(find "${TMP_DIR}" -maxdepth 1 -type d -name 'XrayR11-*' | head -n 1)"

echo "==> 编译程序"
cd "${SRC_DIR}"
go build -o XrayR ./main.go

echo "==> 安装程序"
mkdir -p 
