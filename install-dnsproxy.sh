#!/usr/bin/env bash
set -euo pipefail

# === 用户自定义 ===
CONF_FILE="/etc/dnsproxy/dnsproxy.yaml"

# === 系统变量 ===
BIN_PATH="/usr/local/bin/dnsproxy"
UNIT_FILE="/etc/systemd/system/dnsproxy.service"
TMP_DIR="$(mktemp -d)"

# === 检查root权限 ===
if [[ $EUID -ne 0 ]]; then
  echo "请用 root 或 sudo 执行此脚本"
  exit 1
fi

# === 安装依赖 ===
apt update -y
apt install -y curl wget tar jq libcap2-bin

# === 获取最新版URL ===
echo "获取 dnsproxy 最新版本..."
URL=$(curl -s https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest \
  | jq -r '.assets[] | select(.name | test("linux_amd64.tar.gz$")) | .browser_download_url' | head -n1)

[[ -z "$URL" ]] && { echo "获取下载地址失败"; exit 1; }

# === 下载并安装 ===
echo "下载中：$URL"
wget -qO "$TMP_DIR/dnsproxy.tar.gz" "$URL"
tar -xzf "$TMP_DIR/dnsproxy.tar.gz" -C "$TMP_DIR"
install -m 0755 $(find "$TMP_DIR" -type f -name dnsproxy) "$BIN_PATH"

# 允许非root绑定53端口
setcap 'cap_net_bind_service=+ep' "$BIN_PATH" || true

# === 创建systemd服务 ===
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

# === 启动并启用 ===
systemctl daemon-reload
systemctl enable --now dnsproxy
systemctl --no-pager status dnsproxy

echo
echo "✅ 安装完成"
echo "二进制位置: $BIN_PATH"
echo "配置文件:   $CONF_FILE"
echo "systemd服务: dnsproxy"
echo
echo "如需修改配置，请编辑 $CONF_FILE 后执行："
echo "  systemctl restart dnsproxy"