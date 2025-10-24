#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# dnsproxy 一键安装（自动下载最新版，无需 GitHub API）
# 作者: chowyuan1314
# 适用系统: Debian 11/12/13、Ubuntu 20.04+
# ==================================================

BIN_PATH="/usr/local/bin/dnsproxy"
CONF_FILE="/etc/dnsproxy/dnsproxy.yaml"
UNIT_FILE="/etc/systemd/system/dnsproxy.service"
TMP_DIR="$(mktemp -d)"

# --- 检查 root 权限 ---
if [[ $EUID -ne 0 ]]; then
  echo "❌ 请使用 root 权限执行此脚本"
  exit 1
fi

# --- 安装必要依赖 ---
apt update -y >/dev/null
apt install -y curl wget tar libcap2-bin >/dev/null

# --- 检测 CPU 架构 ---
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) BUILD="linux_amd64" ;;
  aarch64|arm64) BUILD="linux_arm64" ;;
  armv7l|armv7)  BUILD="linux_armv7" ;;
  *) echo "❌ 不支持的架构: $ARCH"; exit 1 ;;
esac

# --- 自动拼接最新下载地址 ---
URL="https://github.com/AdguardTeam/dnsproxy/releases/latest/download/dnsproxy-${BUILD}.tar.gz"
PKG="$TMP_DIR/dnsproxy-${BUILD}.tar.gz"

echo "📦 下载 dnsproxy 最新版本 (${BUILD})..."
wget -qO "$PKG" "$URL" || { echo "❌ 下载失败: $URL"; exit 1; }

echo "📂 解压并安装..."
tar -xzf "$PKG" -C "$TMP_DIR"
install -m 0755 $(find "$TMP_DIR" -type f -name dnsproxy) "$BIN_PATH"

# --- 授权低端口运行 ---
setcap 'cap_net_bind_service=+ep' "$BIN_PATH" || true

# --- 创建 systemd 服务 ---
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

# --- 启动并启用服务 ---
echo "🚀 启动 dnsproxy..."
systemctl daemon-reload
systemctl enable --now dnsproxy
systemctl --no-pager status dnsproxy || true

# --- 清理临时文件 ---
rm -rf "$TMP_DIR"

# --- 完成信息 ---
echo
echo "✅ dnsproxy 安装完成！"
echo "二进制路径: $BIN_PATH"
echo "配置文件:   $CONF_FILE"
echo "服务文件:   $UNIT_FILE"
echo
echo "如需修改配置，请编辑:"
echo "  nano $CONF_FILE"
echo "修改后重启服务:"
echo "  systemctl restart dnsproxy"
echo
