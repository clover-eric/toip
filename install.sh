#!/usr/bin/env sh
set -eu

REPO_URL="${TOIP_REPO_URL:-https://github.com/clover-eric/toip.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/toip}"
DATA_DIR="${DATA_DIR:-/opt/toip/data}"
CFST_VERSION="${CFST_VERSION:-2.3.5}"
SERVICE_NAME="toip-agent"

log() { printf '%s\n' "toip: $*"; }
need() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Linux) echo linux ;;
    Darwin) echo macos ;;
    *) echo unknown ;;
  esac
}

detect_arch() {
  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$arch" in
    x86_64|amd64) echo linux_amd64 ;;
    aarch64|arm64) echo linux_arm64 ;;
    armv7l|armv7*) echo linux_armv7 ;;
    armv6l|armv6*) echo linux_armv6 ;;
    i386|i686) echo linux_386 ;;
    *) echo "" ;;
  esac
}

as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  elif need sudo; then
    sudo "$@"
  else
    log "need root permission: $*"
    exit 1
  fi
}

install_pkg() {
  pkgs="$*"
  if need opkg; then
    as_root opkg update || true
    as_root opkg install $pkgs || true
  elif need apk; then
    as_root apk add --no-cache $pkgs || true
  elif need apt-get; then
    as_root apt-get update || true
    as_root apt-get install -y $pkgs || true
  elif need yum; then
    as_root yum install -y $pkgs || true
  elif need dnf; then
    as_root dnf install -y $pkgs || true
  elif need pacman; then
    as_root pacman -Sy --noconfirm $pkgs || true
  elif need brew; then
    brew install $pkgs || true
  fi
}

prepare_files() {
  as_root mkdir -p "$INSTALL_DIR" "$DATA_DIR"
  if [ "$(pwd)" != "$INSTALL_DIR" ]; then
    for f in run_best_ip_maintain_v4.sh status_best_ip_maintain_v4.sh stop_best_ip_maintain_v4.sh router_agent_24h.sh upload_best_to_worker.sh ip.txt ipv6.txt .env.example; do
      [ -f "$f" ] && as_root cp "$f" "$INSTALL_DIR/$f"
    done
  fi
  as_root chmod +x "$INSTALL_DIR"/*.sh
}

write_env() {
  env_file="$INSTALL_DIR/.env"
  if [ -f "$env_file" ]; then
    log "keep existing $env_file"
    return
  fi
  worker="${WORKER_URL:-}"
  token="${UPLOAD_TOKEN:-}"
  source="${SOURCE:-$(hostname 2>/dev/null || echo router)}"
  operator="${OPERATOR:-}"
  if [ -z "$operator" ]; then
    case "$(printf '%s' "$source" | tr 'A-Z' 'a-z')" in
      *cucc*|*unicom*|*lt*|*联通*) operator="CUCC" ;;
      *ctcc*|*telecom*|*dx*|*电信*) operator="CTCC" ;;
      *) operator="CMCC" ;;
    esac
  fi
  as_root sh -c "cat > '$env_file'" <<EOF
WORKER_URL=${worker:-https://cfip.i3.pub}
UPLOAD_TOKEN=${token}
SOURCE=${source}
OPERATOR=${operator}
SCAN_INTERVAL_SECONDS=${SCAN_INTERVAL_SECONDS:-7200}
RUN_ON_START=${RUN_ON_START:-1}
UPLOAD_AFTER_SCAN=${UPLOAD_AFTER_SCAN:-1}
SLA_LATENCY_MS=${SLA_LATENCY_MS:-30}
SLA_SPEED_MB=${SLA_SPEED_MB:-20}
REQUIRED_COUNT=${REQUIRED_COUNT:-10}
HEALTH_CHECK=${HEALTH_CHECK:-1}
CFST_REPLENISH=${CFST_REPLENISH:-1}
MAX_ROUNDS=${MAX_ROUNDS:-3}
MAX_CANDIDATES=${MAX_CANDIDATES:-24}
PARALLEL_DOWNLOADS=${PARALLEL_DOWNLOADS:-24}
DOWNLOAD_BYTES=${DOWNLOAD_BYTES:-5000000}
CURL_TIME_LIMIT=${CURL_TIME_LIMIT:-15}
PER_REQUEST_SLEEP=${PER_REQUEST_SLEEP:-1}
ROUND_SLEEP=${ROUND_SLEEP:-10}
CFST_THREADS=${CFST_THREADS:-120}
CFST_TESTS=${CFST_TESTS:-4}
CFST_DOWNLOADS=${CFST_DOWNLOADS:-20}
EOF
  as_root chmod 600 "$env_file" || true
}

download_cfst() {
  if [ -x "$INSTALL_DIR/cfst" ]; then
    return
  fi
  cfst_arch="$(detect_arch)"
  [ -n "$cfst_arch" ] || { log "unsupported arch for cfst"; exit 1; }
  url="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v${CFST_VERSION}/cfst_${cfst_arch}.tar.gz"
  tmp="/tmp/toip-cfst.tar.gz"
  log "download cfst $cfst_arch"
  if need curl; then
    curl -fsSL "$url" -o "$tmp"
  else
    wget -O "$tmp" "$url"
  fi
  as_root tar -xzf "$tmp" -C "$INSTALL_DIR" cfst
  as_root chmod +x "$INSTALL_DIR/cfst"
  rm -f "$tmp"
}

install_openwrt_service() {
  as_root sh -c "cat > /etc/init.d/$SERVICE_NAME" <<EOF
#!/bin/sh /etc/rc.common
START=95
STOP=10
USE_PROCD=1
start_service() {
  procd_open_instance
  procd_set_param command /bin/sh -c 'cd $INSTALL_DIR && set -a && [ -f .env ] && . ./.env; set +a; exec ./router_agent_24h.sh'
  procd_set_param respawn 3600 5 5
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}
stop_service() {
  cd $INSTALL_DIR && ./stop_best_ip_maintain_v4.sh >/dev/null 2>&1 || true
}
EOF
  as_root chmod +x "/etc/init.d/$SERVICE_NAME"
  as_root "/etc/init.d/$SERVICE_NAME" enable
  as_root "/etc/init.d/$SERVICE_NAME" restart
}

install_systemd_service() {
  as_root sh -c "cat > /etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=TOIP Cloudflare preferred IP agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/router_agent_24h.sh
ExecStop=$INSTALL_DIR/stop_best_ip_maintain_v4.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  as_root systemctl daemon-reload
  as_root systemctl enable --now "$SERVICE_NAME"
}

install_launchd_service() {
  plist="$HOME/Library/LaunchAgents/com.toip.agent.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.toip.agent</string>
  <key>WorkingDirectory</key><string>$INSTALL_DIR</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>-lc</string><string>set -a; [ -f .env ] &amp;&amp; . ./.env; set +a; exec ./router_agent_24h.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$INSTALL_DIR/launchd.out.log</string>
  <key>StandardErrorPath</key><string>$INSTALL_DIR/launchd.err.log</string>
</dict></plist>
EOF
  launchctl unload "$plist" >/dev/null 2>&1 || true
  launchctl load "$plist"
}

install_docker() {
  if need docker && { need docker-compose || docker compose version >/dev/null 2>&1; }; then
    log "docker detected; use compose deployment"
    mkdir -p "$DATA_DIR"
    [ -f .env ] || cp .env.example .env
    if need docker-compose; then
      docker-compose up -d --build
    else
      docker compose up -d --build
    fi
    exit 0
  fi
}

main() {
  mode="${1:-auto}"
  if [ ! -f "run_best_ip_maintain_v4.sh" ]; then
    tmp_dir="/tmp/toip-install-$$"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"
    tarball="$tmp_dir/toip.tar.gz"
    log "download installer package"
    if need curl; then
      curl -fsSL "${TOIP_TARBALL_URL:-https://github.com/clover-eric/toip/archive/refs/heads/main.tar.gz}" -o "$tarball"
    else
      wget -O "$tarball" "${TOIP_TARBALL_URL:-https://github.com/clover-eric/toip/archive/refs/heads/main.tar.gz}"
    fi
    tar -xzf "$tarball" -C "$tmp_dir" --strip-components=1
    cd "$tmp_dir"
  fi
  if [ "$mode" = "docker" ]; then
    install_docker
    log "docker not available"
    exit 1
  fi
  if [ "$mode" = "auto" ] && [ -f Dockerfile ] && [ -f docker-compose.yml ] && [ "${PREFER_NATIVE:-0}" != "1" ]; then
    install_docker || true
  fi
  if need opkg; then
    install_pkg bash curl ca-bundle python3 coreutils procps
  else
    install_pkg bash curl ca-certificates python3 coreutils procps-ng
  fi
  prepare_files
  write_env
  download_cfst
  os="$(detect_os)"
  if need opkg && [ -d /etc/init.d ]; then
    install_openwrt_service
  elif [ "$os" = "linux" ] && need systemctl; then
    install_systemd_service
  elif [ "$os" = "macos" ]; then
    install_launchd_service
  else
    log "no service manager detected; starting nohup fallback"
    as_root sh -c "cd '$INSTALL_DIR' && set -a && [ -f .env ] && . ./.env; set +a; nohup ./router_agent_24h.sh >> agent.out.log 2>> agent.err.log &"
  fi
  log "installed. edit $INSTALL_DIR/.env if token/url/source need change"
  log "status: $INSTALL_DIR/status_best_ip_maintain_v4.sh"
}

main "$@"
