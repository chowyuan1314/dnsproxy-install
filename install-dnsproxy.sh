#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# dnsproxy 一键安装（自动拉取最新版）
# 作者: chowyuan1314
# ==================================================

BIN_PATH="/usr/local/bin/dnsproxy"
CONF_FILE="/etc/dnsproxy/dnsproxy.yaml"
UNIT_FILE="/etc/systemd/system/dnsproxy.service"
TMP_DIR="$(mktemp -d)"

# 检查 root
if [[ $EUID -ne 0 ]]; then
  echo "❌ 请使用 root 权限执行此脚本"
  exit 1
fi

# 检查依赖
apt update -y >/dev/null
apt install -y curl wget jq tar libcap2-bin >/dev/null

# 检测架构
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) BUILD="linux_amd64" ;;
  aarch64|arm64) BUILD="linux_arm64" ;;
  armv7l|armv7) BUILD="linux_armv7" ;;
  *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# 获取最新版 tag
echo "🔍 获取 dnsproxy 最新版本..."
TAG=$(curl -fsSL https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest | jq -r .tag_name)

if [[ -z "$TAG" || "$TAG" == "null" ]]; then
  echo "❌ 无法从 GitHub API 获取版本号，请稍后重试或检查网络。"
  exit 1
fi

PKG="dnsproxy-${BUILD}-${TAG}.tar.gz"
URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${TAG}/${PKG}"

echo "📦 下载 ${TAG} (${BUILD})..."
wget -qO "${TMP_DIR}/${PKG}" "$URL" || { echo "❌ 下载失败: $URL"; exit 1; }

echo "📂 解压安装..."
tar -xzf "${TMP_DIR}/${PKG}" -C "${TMP_DIR}"
install -m 0755 $(find "$TMP_DIR" -type f -name dnsproxy) "$BIN_PATH"
setcap 'cap_net_bind_service=+ep' "$BIN_PATH" || true

echo "⚙️ 创建 systemd 服务..."
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=AdGuard dnsproxy Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$BIN_PATH --config-path $CONF_FILE
Restart=on-failure
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo "🚀 启动并启用服务..."
systemctl daemon-reload
systemctl enable --now dnsproxy
systemctl --no-pager status dnsproxy

echo
echo "✅ 安装完成"
echo "版本:   ${TAG}"
echo "二进制: $BIN_PATH"
echo "配置:   $CONF_FILE"
echo
echo "如需更新至最新版本，只需再次执行此脚本即可。"
echo
