#!/usr/bin/env bash
set -euo pipefail

# dnsproxy 一键安装（自动获取最新版，不用 GitHub API）
# 支持架构：amd64 / arm64 / armv7

BIN_PATH="/usr/local/bin/dnsproxy"
CONF_FILE="/etc/dnsproxy/dnsproxy.yaml"
UNIT_FILE="/etc/systemd/system/dnsproxy.service"
TMP_DIR="$(mktemp -d)"

if [[ $EUID -ne 0 ]]; then
  echo "❌ 请用 root 执行"
  exit 1
fi

# 尽量静默装工具
apt update -y >/dev/null 2>&1 || true
apt install -y curl wget tar libcap2-bin >/dev/null 2>&1 || true

# 映射架构到正确的包名片段（连字符）
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) build="linux-amd64" ;;
  aarch64|arm64) build="linux-arm64" ;;
  armv7l|armv7)  build="linux-armv7" ;;
  *) echo "❌ 不支持的架构: $arch"; exit 1 ;;
esac

# 通过 /releases/latest 取最终跳转 URL，再抽取 tag（如 v0.77.0）
latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/AdguardTeam/dnsproxy/releases/latest)"
tag="${latest_url##*/}"
if [[ -z "$tag" || "$tag" == "latest" ]]; then
  echo "❌ 无法获取最新版本标签（可能被拦，或 GitHub 改版）。"
  exit 1
fi

pkg="dnsproxy-${build}-${tag}.tar.gz"
url="https://github.com/AdguardTeam/dnsproxy/releases/download/${tag}/${pkg}"

echo "📦 下载 dnsproxy ${tag} (${build}) ..."
if ! wget -qO "${TMP_DIR}/${pkg}" "$url"; then
  echo "❌ 下载失败：$url"
  echo "🔎 调试建议：先试试 curl -I \"$url\" 看返回码是否为 200。"
  echo "🌐 如果网络限制，可用代理镜像："
  echo "    wget -O ${TMP_DIR}/${pkg} https://ghproxy.net/${url}"
  exit 1
fi

echo "📂 解压并安装..."
tar -xzf "${TMP_DIR}/${pkg}" -C "${TMP_DIR}"
install -m 0755 "$(find "$TMP_DIR" -type f -name dnsproxy -print -quit)" "$BIN_PATH"

# 允许非 root 绑定 53 端口（若你用高端口可忽略失败）
setcap 'cap_net_bind_service=+ep' "$BIN_PATH" || true

echo "⚙️ 写入 systemd 服务..."
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

echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable --now dnsproxy
systemctl --no-pager status dnsproxy || true

rm -rf "$TMP_DIR"

echo
echo "✅ 安装完成"
echo "版本: $tag"
echo "二进制: $BIN_PATH"
echo "配置:   $CONF_FILE   （脚本不会改动它）"
echo "服务:   $UNIT_FILE"
echo
echo "修改配置后重启： systemctl restart dnsproxy"
