#!/usr/bin/env bash
set -euo pipefail

TAG="v0.9.5"
FILE="XrayR-linux-64.zip"
BASE_URL="https://github.com/acfrr/XrayR11/releases/download/${TAG}"
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
TMP_DIR="/tmp/xrayr-install"

if [ "$(id -u)" != "0" ]; then
  echo "请用 root 运行"
  exit 1
fi

echo "==> 安装依赖"
apt update
apt install -y wget unzip curl ca-certificates

echo "==> 下载预编译包"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
cd "${TMP_DIR}"
wget -O "${FILE}" "${BASE_URL}/${FILE}"

echo "==> 解压安装"
unzip -o "${FILE}"

mkdir -p "${INSTALL_DIR}"
mkdir -p "${CONFIG_DIR}"

if [ -f XrayR ]; then
  cp XrayR "${INSTALL_DIR}/XrayR"
elif [ -f ./XrayR/XrayR ]; then
  cp ./XrayR/XrayR "${INSTALL_DIR}/XrayR"
else
  BIN_PATH="$(find . -type f -name XrayR | head -n 1 || true)"
  if [ -z "${BIN_PATH}" ]; then
    echo "没找到 XrayR 可执行文件"
    exit 1
  fi
  cp "${BIN_PATH}" "${INSTALL_DIR}/XrayR"
fi

chmod +x "${INSTALL_DIR}/XrayR"

CFG_PATH="$(find . -type f \( -name config.yml -o -name config.yaml \) | head -n 1 || true)"
if [ -n "${CFG_PATH}" ]; then
  cp -n "${CFG_PATH}" "${CONFIG_DIR}/config.yml" || true
fi

echo "==> 完成"
echo "程序路径: ${INSTALL_DIR}/XrayR"
echo "配置路径: ${CONFIG_DIR}/config.yml"
echo "测试命令: ${INSTALL_DIR}/XrayR"
