#!/bin/sh
set -e

BIN="/usr/sbin/dnsproxy"
CONF_DIR="/etc/dnsproxy"
CONF_FILE="$CONF_DIR/config.yaml"
INIT_FILE="/etc/init.d/dnsproxy"

# 依赖（curl 用来拿 latest 重定向；tar 解包；ca-bundle 走 https）
opkg update
opkg install curl ca-bundle ca-certificates tar wget-ssl >/dev/null 2>&1 || true

# 架构映射
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) BUILD="linux-amd64" ;;
  aarch64|arm64) BUILD="linux-arm64" ;;
  armv7l|armv7)  BUILD="linux-armv7" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

# 获取最新 tag（不走 GitHub API）
LATEST_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/AdguardTeam/dnsproxy/releases/latest)"
TAG="${LATEST_URL##*/}"
[ -n "$TAG" ] && [ "$TAG" != "latest" ] || { echo "Failed to resolve latest tag"; exit 1; }

PKG="dnsproxy-${BUILD}-${TAG}.tar.gz"
URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${TAG}/${PKG}"

echo "Downloading: $URL"
if ! wget -qO /tmp/dnsproxy.tgz "$URL"; then
  echo "Primary download failed, trying mirror..."
  wget -qO /tmp/dnsproxy.tgz "https://ghproxy.net/${URL}" || { echo "Download failed"; exit 1; }
fi

echo "Installing binary..."
tar -xzf /tmp/dnsproxy.tgz -C /tmp
install -m 0755 /tmp/dnsproxy "$BIN"

# 创建工作目录 & 默认配置（如不存在则写一个很小的模板）
mkdir -p "$CONF_DIR"
if [ ! -f "$CONF_FILE" ]; then
  cat > "$CONF_FILE" <<'EOF'
listen-addrs:
  - 127.0.0.1
listen-ports:
  - 53
upstream:
  - "quic://dns.alidns.com"
  - "https://dot.pub/dns-query"
http3: true
upstream-mode: parallel
bootstrap:
  - "tls://223.5.5.5:853"
output: /var/log/dnsproxy/log.log
EOF
fi

echo "Writing init.d service..."
cat > "$INIT_FILE" <<'EOF'
#!/bin/sh /etc/rc.common
# dnsproxy (procd)

START=95
STOP=10
USE_PROCD=1

PROG="$(command -v dnsproxy || echo /usr/sbin/dnsproxy)"
CONFIG="/etc/dnsproxy/config.yaml"

start_service() {
	[ -x "$PROG" ] || { echo "dnsproxy not found: $PROG"; return 1; }
	[ -f "$CONFIG" ] || { echo "missing $CONFIG"; return 1; }

	procd_open_instance
	procd_set_param command "$PROG" --config-path="$CONFIG"
	procd_set_param respawn 3600 5 5
	procd_set_param stdout 1
	procd_set_param stderr 1
	procd_set_param file "$CONFIG"
	procd_set_param limits nofile="65535 65535"
	procd_close_instance
}

reload_service() {
	restart
}
EOF

chmod +x "$INIT_FILE"
/etc/init.d/dnsproxy enable
/etc/init.d/dnsproxy restart

echo "✅ Installed/updated dnsproxy ($TAG)."
echo "Binary : $BIN"
echo "Workdir: $CONF_DIR"
echo "Config : $CONF_FILE"
echo "Service: /etc/init.d/dnsproxy (enable/start/stop/restart/status)"
