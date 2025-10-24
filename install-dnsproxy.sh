#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# dnsproxy 一键安装（自动获取最新版，不用 GitHub API）
# 作者: chowyuan1314
# 支持架构：amd64 / arm64 / armv7
# 工作目录: /etc/dnsproxy
# ==================================================

BIN_PATH="/usr/local/bin/dnsproxy"
CONF_DIR="/etc/dnsproxy"
CONF_FILE="${CONF_DIR}/dnsproxy.yaml"
UNIT_FILE="/etc/systemd/system/dnsproxy.service"
TMP_DIR="$(mktemp -d)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ 请使用 root 权限执行此脚本"
  exit 1
fi

# --- 安装必要依赖 ---
apt update -y >/dev/null 2>&1 || true
apt install -y curl wget tar libcap2-bin >/dev/null 2>&1 || true

# --- 检测架构 ---
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) build="linux-amd64" ;;
  aarch64|arm64) build="linux-arm64" ;;
  armv7l|armv7)  build="linux-armv7" ;;
  *) echo "❌ 不支持的架构: $arch"; exit 1 ;;
esac

# --- 获取最新版本 tag ---
latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/AdguardTeam/dnsproxy/releases/latest)"
tag="${latest_url##*/}"
if [[ -z "$tag" || "$tag" == "latest" ]]; then
  echo "❌ 无法获取最新版本标签（可能被拦）。"
  exit 1
fi

pkg="dnsproxy-${build}-${tag}.tar.gz"
url="https://github.com/AdguardTeam/dnsproxy/releases/download/${tag}/${pkg}"

echo "📦 下载 dnsproxy ${tag} (${build}) ..."
if ! wget -qO "${TMP_DIR}/${pkg}" "$url"; then
  echo "❌ 下载失败：$url"
  echo "👉 若网络被墙，可用镜像下载："
  echo "    wget -O ${TMP_DIR}/${pkg} https://ghproxy.net/${url}"
  exit 1
fi

# --- 安装 ---
echo "📂 解压并安装..."
tar -xzf "${TMP_DIR}/${pkg}" -C "${TMP_DIR}"
install -m 0755 "$(find "$TMP_DIR" -type f -name dnsproxy -print -quit)" "$BIN_PATH"

# --- 创建配置目录 ---
mkdir -p "$CONF_DIR"
if [[ ! -f "$CONF_FILE" ]]; then
  cat > "$CONF_FILE" <<EOF
# 默认配置文件
listen-addrs:
  - 127.0.0.1
listen-ports:
  - 53

upstream:
  - "https://dns.google/dns-query"
  - "https://dns.cloudflare.com/dns-query"
  - "https://dns.quad9.net/dns-query"
  - "quic://dns.adguard-dns.com"

http3: true

# 并发模式
# upstream-mode: parallel

bootstrap:
  - "8.8.8.8:53"

# 日志
output: log.log
EOF
fi

# --- 授权低端口 ---
setcap 'cap_net_bind_service=+ep' "$BIN_PATH" || true

# --- 写入 systemd 服务 ---
echo "⚙️ 写入 systemd 服务..."
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=AdGuard dnsproxy Service
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$CONF_DIR
ExecStart=$BIN_PATH --config-path $CONF_FILE
Restart=on-failure
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# --- 启动并启用服务 ---
echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable --now dnsproxy
systemctl --no-pager status dnsproxy || true

# --- 清理 ---
rm -rf "$TMP_DIR"

echo
echo "✅ dnsproxy 安装完成"
echo "版本: $tag"
echo "二进制: $BIN_PATH"
echo "工作目录: $CONF_DIR"
echo "配置文件: $CONF_FILE"
echo "服务文件: $UNIT_FILE"
echo
echo "修改配置后重启： systemctl restart dnsproxy"
echo
