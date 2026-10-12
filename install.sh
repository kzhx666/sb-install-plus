#!/usr/bin/env bash
# ==============================================================================
# Sing-box 现代极速终极版 v7.0
# 精简核心协议 (VLESS-Reality / Hysteria 2 / TUIC v5) + 智能伪装测速 + 极致网络提速
# ==============================================================================

set -u

# --- 终端颜色 ---
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PURPLE="\033[35m"; PLAIN="\033[0m"
info(){ echo -e "${BLUE}[INFO]${PLAIN} $*"; }
ok(){ echo -e "${GREEN}[ OK ]${PLAIN} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${PLAIN} $*"; }
err(){ echo -e "${RED}[ERR ]${PLAIN} $*"; }

# --- Root 检查 ---
[[ ${EUID:-999} -ne 0 ]] && err "必须使用 root 权限运行此脚本！" && exit 1

# --- 全局路径与配置 ---
SB_USER="root"
SB_GROUP="root"
INSTALL_PATH="/usr/local/bin/sing-box"
CONF_DIR="/etc/sing-box"
CERT_DIR="/etc/sing-box/cert"
WARP_DIR="/etc/sing-box/warp"
SHORTCUT_BIN="/usr/local/bin/sb"
STATE_FILE="/etc/sing-box/.sb_state"
MIHOMO_FILE="/etc/sing-box/mihomo_proxies.yaml"
HOP_SCRIPT="/usr/local/bin/sb-hop.sh"
CHECK_SCRIPT="/usr/local/bin/sb-selfcheck.sh"

# --- 常见优质真实 TLS 1.3 / H2 伪装域名候选池 ---
REALITY_SNI_CANDIDATES=(
  "swdist.apple.com"
  "gateway.icloud.com"
  "www.microsoft.com"
  "dl.google.com"
  "aws.amazon.com"
  "www.yahoo.com"
  "itunes.apple.com"
  "addons.mozilla.org"
  "cdn.jsdelivr.net"
  "registry-1.docker.io"
)

# --- 默认 AI 与流媒体 WARP 分流域名列表 ---
WARP_AI_DOMAINS=(
  "chatgpt.com"
  "chat.openai.com"
  "openai.com"
  "api.openai.com"
  "auth.openai.com"
  "platform.openai.com"
  "oaistatic.com"
  "oaiusercontent.com"
  "claude.ai"
  "anthropic.com"
  "api.anthropic.com"
  "gemini.google.com"
  "aistudio.google.com"
  "generativelanguage.googleapis.com"
  "perplexity.ai"
  "copilot.microsoft.com"
  "x.ai"
  "grok.com"
  "meta.ai"
  "poe.com"
  "netflix.com"
  "nflxvideo.net"
  "nflximg.net"
  "disneyplus.com"
  "dssott.com"
  "bamgrid.com"
  "tiktok.com"
  "reddit.com"
  "spotify.com"
)

# --- 系统识别 ---
PKG_MGR="unknown"
command -v apk >/dev/null 2>&1 && PKG_MGR="apk"
command -v apt-get >/dev/null 2>&1 && PKG_MGR="apt"
command -v yum >/dev/null 2>&1 && PKG_MGR="yum"
command -v dnf >/dev/null 2>&1 && PKG_MGR="dnf"

has_systemd(){ command -v systemctl >/dev/null 2>&1; }
has_openrc(){ command -v rc-service >/dev/null 2>&1; }

service_stop(){
  if has_systemd; then systemctl stop sing-box >/dev/null 2>&1 || true
  elif has_openrc; then rc-service sing-box stop >/dev/null 2>&1 || true
  fi
}

service_enable_restart(){
  if has_systemd; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable sing-box >/dev/null 2>&1 || true
    systemctl restart sing-box >/dev/null 2>&1 || true
  elif has_openrc; then
    rc-update add sing-box default >/dev/null 2>&1 || true
    rc-service sing-box restart >/dev/null 2>&1 || rc-service sing-box start >/dev/null 2>&1 || true
  fi
}

service_disable(){
  if has_systemd; then
    systemctl disable --now sing-box >/dev/null 2>&1 || true
  elif has_openrc; then
    rc-service sing-box stop >/dev/null 2>&1 || true
    rc-update del sing-box default >/dev/null 2>&1 || true
  fi
}

# --- 依赖安装 ---
install_pkgs(){
  info "正在检测并安装必要依赖包..."
  case "$PKG_MGR" in
    apt)
      apt-get update -y >/dev/null 2>&1
      apt-get install -y bash curl wget tar jq openssl socat lsof net-tools file gzip grep \
        iptables iproute2 nftables ca-certificates coreutils util-linux libcap2-bin procps dnsutils >/dev/null 2>&1
      ;;
    yum|dnf)
      $PKG_MGR update -y >/dev/null 2>&1
      $PKG_MGR install -y bash curl wget tar jq openssl socat lsof net-tools file gzip grep \
        iptables iproute nftables ca-certificates coreutils util-linux libcap procps bind-utils >/dev/null 2>&1 || true
      ;;
    apk)
      apk add --no-cache bash curl wget tar jq openssl socat lsof net-tools file gzip grep \
        iptables ip6tables nftables iproute2 ca-certificates coreutils util-linux libcap procps bind-tools libc6-compat gcompat >/dev/null 2>&1
      ;;
    *)
      warn "未识别包管理器，跳过依赖自动化安装"
      ;;
  esac
  ok "依赖组件准备就绪"
}

# --- 用户/组管理（最小特权） ---
group_exists(){
  local g="$1"
  if command -v getent >/dev/null 2>&1; then getent group "$g" >/dev/null 2>&1
  else grep -q "^${g}:" /etc/group 2>/dev/null
  fi
}
user_exists(){ id "$1" >/dev/null 2>&1; }

create_user_group(){
  local u="$1" g="$2"
  local nologin_path="/sbin/nologin"
  [[ -x "$nologin_path" ]] || nologin_path="/bin/false"

  if ! group_exists "$g"; then
    if command -v addgroup >/dev/null 2>&1; then addgroup -S "$g" >/dev/null 2>&1 || true
    elif command -v groupadd >/dev/null 2>&1; then groupadd -r "$g" >/dev/null 2>&1 || true
    fi
  fi
  if ! user_exists "$u"; then
    if command -v adduser >/dev/null 2>&1; then adduser -S -G "$g" -s "$nologin_path" "$u" >/dev/null 2>&1 || true
    elif command -v useradd >/dev/null 2>&1; then useradd -r -g "$g" -s "$nologin_path" "$u" >/dev/null 2>&1 || true
    fi
  fi
}

# --- 端口工具 ---
port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntu 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"
    return $?
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntu 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"
    return $?
  fi
  return 1
}

find_free_base_port() {
  local need="$1"
  local tries=1000
  while (( tries > 0 )); do
    local base=$(( (RANDOM % 35000) + 20000 ))
    (( base + need - 1 > 65000 )) && tries=$((tries-1)) && continue
    local okflag=1
    for ((i=0; i<need; i++)); do
      local cp=$((base + i))
      if port_in_use "$cp"; then okflag=0; break; fi
    done
    if (( okflag == 1 )); then echo "$base"; return 0; fi
    tries=$((tries-1))
  done
  echo "23456"
}

default_iface() {
  local iface=""
  iface="$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  [[ -z "$iface" ]] && iface="eth0"
  echo "$iface"
}

_arch_norm(){
  local a
  a="$(uname -m 2>/dev/null || echo x86_64)"
  case "$a" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    i386|i686) echo "386" ;;
    *) echo "amd64" ;;
  esac
}

# ==============================================================================
# [深度提速] Linux 网络协议栈与 BBR / UDP 巨型缓冲调优
# ==============================================================================
apply_tuning() {
  info "正在应用极速网络内核参数调优 (BBR + 64MB UDP缓冲 + TCP Fast Open + TFO)..."

  # 1. 尝试加载 BBRv3 / BBR 内核模块
  modprobe tcp_bbr3 2>/dev/null || true
  modprobe tcp_bbr 2>/dev/null || true

  local avail_cc target_cc="bbr"
  avail_cc="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo "")"
  if echo "$avail_cc" | grep -qw "bbr3"; then
    target_cc="bbr3"
  elif echo "$avail_cc" | grep -qw "bbr"; then
    target_cc="bbr"
  elif echo "$avail_cc" | grep -qw "bbrplus"; then
    target_cc="bbrplus"
  fi

  # 2. 检查内存大小自适应缓冲区 (单位 KB)
  local mem_kb buf_max backlog
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$mem_kb" -ge 2000000 ]]; then
    buf_max=67108864 # 64MB
    backlog=50000
  elif [[ "$mem_kb" -ge 800000 ]]; then
    buf_max=33554432 # 32MB
    backlog=30000
  else
    buf_max=16777216 # 16MB
    backlog=15000
  fi

  # 3. 写入 sysctl 调优配置文件
  mkdir -p /etc/sysctl.d >/dev/null 2>&1 || true
  cat > /etc/sysctl.d/99-singbox-speed.conf <<EOF
# --- QUIC / UDP 巨型缓冲区 (为 Hysteria 2 / TUIC 极速并发拉满) ---
net.core.rmem_max=${buf_max}
net.core.wmem_max=${buf_max}
net.core.rmem_default=2621440
net.core.wmem_default=2621440
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384

# --- TCP 极速传输与 BBR / BBRv3 拥塞控制 ---
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=${target_cc}
net.ipv4.tcp_rmem=4096 87380 ${buf_max}
net.ipv4.tcp_wmem=4096 65536 ${buf_max}

# --- 握手与首包加速 (0-RTT TFO / 空闲不降速) ---
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1

# --- 连接保活与队列深度优化 ---
net.core.netdev_max_backlog=${backlog}
net.ipv4.tcp_max_syn_backlog=10000
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_probes=5
fs.file-max=1000000
EOF

  sysctl -p /etc/sysctl.d/99-singbox-speed.conf >/dev/null 2>&1 || true

  # 4. 优化网卡队列深度与卸载
  local IFACE
  IFACE="$(default_iface)"
  ip link set dev "$IFACE" txqueuelen 10000 >/dev/null 2>&1 || true

  # 5. 回读验证 BBR 状态
  local cc
  cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  if [[ "$cc" =~ ^(bbr|bbr3|bbrplus)$ ]]; then
    ok "BBR 拥塞控制 (${cc}) 与 64MB UDP 巨型缓冲调优已成功激活！"
  else
    warn "当前系统内核暂未直接返回 BBR (当前: ${cc:-未知})，已完成高并发与缓冲区配置"
  fi
}

# ==============================================================================
# [新功能] Reality 伪装域名智能自动测速与优选
# ==============================================================================
test_sni_latency() {
  local target="$1"
  local cost_ms=9999
  if command -v curl >/dev/null 2>&1; then
    local t
    t="$(curl -o /dev/null -s -w "%{time_connect}\n" --connect-timeout 2 --max-time 3 "https://${target}" 2>/dev/null || echo "")"
    if [[ -n "$t" && "$t" != "0.000" ]]; then
      cost_ms="$(awk -v v="$t" 'BEGIN { printf "%.0f", v * 1000 }' 2>/dev/null || echo 9999)"
    fi
  fi
  echo "$cost_ms"
}

resolve_ip() {
  local h="$1"
  local ip=""
  if command -v getent >/dev/null 2>&1; then
    ip="$(getent ahosts "$h" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
  fi
  if [[ -z "$ip" ]] && command -v dig >/dev/null 2>&1; then
    ip="$(dig +short A "$h" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true)"
  fi
  if [[ -z "$ip" ]] && command -v ping >/dev/null 2>&1; then
    ip="$(ping -c 1 -W 1 "$h" 2>/dev/null | grep -oE '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)' | tr -d '()' | head -n1 || true)"
  fi
  [[ -z "$ip" ]] && ip="$h"
  echo "$ip"
}

select_reality_sni() {
  if [[ "${AUTO_INSTALL:-0}" -eq 1 ]]; then
    if [[ -n "${REALITY_SNI:-}" ]]; then
      REALITY_SNI="$REALITY_SNI"
      REALITY_HS_SERVER="$(get_sni_dest_ip "$REALITY_SNI")"
      ok "自动模式使用指定 SNI: ${GREEN}${REALITY_SNI}${PLAIN} (目标: ${REALITY_HS_SERVER})"
      return 0
    fi
    info "自动模式：执行真实伪装候选池智能测速优选..."
    SNI_SEL=1
  else
    echo -e "\n${BLUE}==============================================================${PLAIN}"
    echo -e "${BLUE}          VLESS-Reality 真实伪装域名优选设置                 ${PLAIN}"
    echo -e "${BLUE}==============================================================${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 智能自动测速优选（从苹果/微软/亚马逊等主流 TLS 1.3 目标中选最低延迟）"
    echo -e "  ${GREEN}2.${PLAIN} 手动指定自定义伪装域名"
    read -r -p "请选择伪装策略 [1-2] (默认 1): " SNI_SEL || true
    SNI_SEL="${SNI_SEL:-1}"
  fi

  local BEST_SNI=""
  local BEST_MS=99999

  if [[ "$SNI_SEL" == "2" ]]; then
    read -r -p "请输入自定义 SNI (如 swdist.apple.com): " USER_SNI || true
    if [[ -n "${USER_SNI:-}" ]]; then
      BEST_SNI="$USER_SNI"
    else
      warn "未输入有效域名，自动切换为智能测速优选模式"
      SNI_SEL="1"
    fi
  fi

  if [[ "$SNI_SEL" == "1" ]]; then
    info "正在并发对优质伪装候选池执行 TLS 1.3 握手延迟测速..."
    for host in "${REALITY_SNI_CANDIDATES[@]}"; do
      local ms
      ms="$(test_sni_latency "$host")"
      if [[ "$ms" -lt 9999 ]]; then
        echo -e "  -> ${host}: ${GREEN}${ms} ms${PLAIN}"
        if [[ "$ms" -lt "$BEST_MS" ]]; then
          BEST_MS="$ms"
          BEST_SNI="$host"
        fi
      else
        echo -e "  -> ${host}: ${RED}超时/不可达${PLAIN}"
      fi
    done

    if [[ -z "$BEST_SNI" || "$BEST_MS" -ge 9999 ]]; then
      BEST_SNI="swdist.apple.com"
      warn "自动测速无响应，采用稳定默认候选: ${BEST_SNI}"
    else
      ok "最优伪装域名已选定: ${GREEN}${BEST_SNI}${PLAIN} (延迟: ${BEST_MS} ms)"
    fi
  fi

  REALITY_SNI="$BEST_SNI"
  REALITY_HS_SERVER="$(resolve_ip "$REALITY_SNI")"
  REALITY_HS_PORT=443
  ok "Reality 伪装目标: ${REALITY_SNI} (回落解析IP: ${REALITY_HS_SERVER})"
}

# --- 防火墙放行 ---
fw_allow_ports(){
  local tcp_ports="$1" udp_ports="$2" udp_range="${3:-}"

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then
    for p in $tcp_ports; do ufw allow "${p}/tcp" >/dev/null 2>&1 || true; done
    for p in $udp_ports; do ufw allow "${p}/udp" >/dev/null 2>&1 || true; done
    if [[ -n "$udp_range" ]]; then
      IFS=',' read -ra UPARTS <<< "$udp_range"
      for part in "${UPARTS[@]}"; do
        part="${part//-/:}"
        ufw allow "${part}/udp" >/dev/null 2>&1 || true
      done
    fi
    ufw reload >/dev/null 2>&1 || true
    ok "已配置 ufw 规则放行端口"
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    for p in $tcp_ports; do firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1 || true; done
    for p in $udp_ports; do firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1 || true; done
    if [[ -n "$udp_range" ]]; then
      IFS=',' read -ra UPARTS <<< "$udp_range"
      for part in "${UPARTS[@]}"; do
        part="${part//:/-}"
        firewall-cmd --permanent --add-port="${part}/udp" >/dev/null 2>&1 || true
      done
    fi
    firewall-cmd --reload >/dev/null 2>&1 || true
    ok "已配置 firewalld 规则放行端口"
    return 0
  fi

  if command -v iptables >/dev/null 2>&1; then
    for p in $tcp_ports; do
      iptables -C INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
    done
    for p in $udp_ports; do
      iptables -C INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
    done
    if [[ -n "$udp_range" ]]; then
      local r_ipt="${udp_range//-/:}"
      if [[ "$r_ipt" == *","* ]]; then
        iptables -C INPUT -p udp -m multiport --dports "$r_ipt" -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p udp -m multiport --dports "$r_ipt" -j ACCEPT >/dev/null 2>&1 || true
      else
        iptables -C INPUT -p udp --dport "$r_ipt" -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p udp --dport "$r_ipt" -j ACCEPT >/dev/null 2>&1 || true
      fi
    fi

    if command -v ip6tables >/dev/null 2>&1; then
      for p in $tcp_ports; do
        ip6tables -C INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
      done
      for p in $udp_ports; do
        ip6tables -C INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
      done
      if [[ -n "$udp_range" ]]; then
        local r6_ipt="${udp_range//-/:}"
        if [[ "$r6_ipt" == *","* ]]; then
          ip6tables -C INPUT -p udp -m multiport --dports "$r6_ipt" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p udp -m multiport --dports "$r6_ipt" -j ACCEPT >/dev/null 2>&1 || true
        else
          ip6tables -C INPUT -p udp --dport "$r6_ipt" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p udp --dport "$r6_ipt" -j ACCEPT >/dev/null 2>&1 || true
        fi
      fi
    fi
    ok "已配置 iptables 放行端口"
  fi
}

# --- 核心更新 ---
update_core(){
  echo -e "${YELLOW}正在获取 Sing-box 最新稳定版版本号...${PLAIN}"
  local SB_TAG
  SB_TAG="$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null | jq -r .tag_name || true)"
  if [[ -z "${SB_TAG:-}" || "$SB_TAG" == "null" ]]; then
    # 通过网页重定向 location 获取
    SB_TAG="$(curl -sI https://github.com/SagerNet/sing-box/releases/latest 2>/dev/null | grep -i '^location:' | grep -oE 'v[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
  fi
  [[ -z "${SB_TAG:-}" ]] && SB_TAG="v1.12.0"

  local SB_ARCH TMP_DIR
  SB_ARCH="$(_arch_norm)"
  TMP_DIR="$(mktemp -d)"

  info "正在下载 Sing-box 核心 $SB_TAG ($SB_ARCH)..."
  wget -q -O "$TMP_DIR/sb.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/${SB_TAG}/sing-box-${SB_TAG#v}-linux-${SB_ARCH}.tar.gz" || {
    err "下载核心失败，请检查网络！"
    rm -rf "$TMP_DIR"
    return 1
  }

  tar -xzf "$TMP_DIR/sb.tar.gz" -C "$TMP_DIR"
  service_stop
  mv "$TMP_DIR"/sing-box-*/sing-box "$INSTALL_PATH"
  rm -rf "$TMP_DIR"
  chmod +x "$INSTALL_PATH"
  command -v setcap >/dev/null 2>&1 && setcap 'cap_net_bind_service,cap_net_admin=+ep' "$INSTALL_PATH" >/dev/null 2>&1 || true
  service_enable_restart
  ok "Sing-box 核心已成功更新至 $SB_TAG 并重启服务！"
}

# --- 卸载逻辑 ---
do_uninstall(){
  info "正在彻底卸载 Sing-box 及全部关联配置与服务..."
  service_disable
  
  # 停止并卸载 Cloudflare Argo tunnel 守护进程
  if command -v cloudflared >/dev/null 2>&1; then
    cloudflared service uninstall >/dev/null 2>&1 || true
  fi
  if has_systemd; then
    systemctl stop cloudflared >/dev/null 2>&1 || true
    systemctl disable cloudflared >/dev/null 2>&1 || true
  elif has_openrc; then
    rc-service cloudflared stop >/dev/null 2>&1 || true
    rc-update del cloudflared default >/dev/null 2>&1 || true
  fi
  pkill -9 -f sing-box >/dev/null 2>&1 || true
  pkill -9 -f cloudflared >/dev/null 2>&1 || true

  # 清理端口跳跃 iptables 规则
  if command -v iptables >/dev/null 2>&1; then
    iptables -t nat -D PREROUTING -p udp -j SB_HOP >/dev/null 2>&1 || true
    iptables -t nat -D PREROUTING -j SB_HOP >/dev/null 2>&1 || true
    iptables -t nat -F SB_HOP >/dev/null 2>&1 || true
    iptables -t nat -X SB_HOP >/dev/null 2>&1 || true
  fi
  if command -v ip6tables >/dev/null 2>&1; then
    ip6tables -t nat -D PREROUTING -p udp -j SB_HOP6 >/dev/null 2>&1 || true
    ip6tables -t nat -D PREROUTING -j SB_HOP6 >/dev/null 2>&1 || true
    ip6tables -t nat -F SB_HOP6 >/dev/null 2>&1 || true
    ip6tables -t nat -X SB_HOP6 >/dev/null 2>&1 || true
  fi

  # 清理系统服务与单元
  rm -f /etc/systemd/system/sing-box.service* >/dev/null 2>&1 || true
  rm -rf /etc/systemd/system/sing-box.service.d >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/cloudflared.service* >/dev/null 2>&1 || true
  rm -rf /etc/systemd/system/cloudflared.service.d >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/sb-hop.service* >/dev/null 2>&1 || true
  rm -f /etc/init.d/sing-box /etc/init.d/cloudflared >/dev/null 2>&1 || true

  if has_systemd; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed >/dev/null 2>&1 || true
  fi

  # 清除所有二进制、脚本与快捷方式
  rm -f "$HOP_SCRIPT" "$CHECK_SCRIPT" "$SHORTCUT_BIN" "$INSTALL_PATH" /usr/local/bin/cloudflared /usr/bin/cloudflared /usr/bin/sing-box >/dev/null 2>&1 || true
  
  # 清除配置、证书、状态、日志及临时文件
  rm -rf "$CONF_DIR" /etc/cloudflared /var/log/sing-box* /tmp/sb* /tmp/sing-box* /tmp/cloudflared* >/dev/null 2>&1 || true
  
  # 清理 Crontab 任务
  if command -v crontab >/dev/null 2>&1; then
    crontab -l 2>/dev/null | grep -v 'sing-box' | grep -v 'sb-' | grep -v 'cloudflared' | crontab - 2>/dev/null || true
  fi

  rm -f /etc/sysctl.d/99-singbox-speed.conf >/dev/null 2>&1 || true
  sysctl -p >/dev/null 2>&1 || true
  ok "卸载完成！所有节点服务、证书、配置、二进制及残留已彻底清除。"
}

# --- 端口跳跃范围校验 ---
validate_hop_range(){
  local raw="$1"
  raw="${raw// /}"
  raw="${raw//:/-}"
  [[ -z "$raw" ]] && return 1

  if ! [[ "$raw" =~ ^[0-9,-]+$ ]]; then
    return 1
  fi

  IFS=',' read -ra PARTS <<< "$raw"
  [[ "${#PARTS[@]}" -eq 0 ]] && return 1

  for part in "${PARTS[@]}"; do
    [[ -z "$part" ]] && return 1
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local s="${BASH_REMATCH[1]}"
      local e="${BASH_REMATCH[2]}"
      if [[ "$s" -lt 1 || "$s" -gt 65535 || "$e" -lt 1 || "$e" -gt 65535 || "$s" -gt "$e" ]]; then
        return 1
      fi
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      if [[ "$part" -lt 1 || "$part" -gt 65535 ]]; then
        return 1
      fi
    else
      return 1
    fi
  done
  echo "$raw"
  return 0
}

# --- 生成快捷管理命令脚本 (sb) ---
generate_shortcut_script(){
  cat > "$SHORTCUT_BIN" <<'EOSB'
#!/usr/bin/env bash
set -u
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PURPLE="\033[35m"; PLAIN="\033[0m"
STATE="/etc/sing-box/.sb_state"
MIHOMO_FILE="/etc/sing-box/mihomo_proxies.yaml"
MGR_CONF="/etc/sing-box/.sb_mgr_conf"

if [[ ! -f "$STATE" ]]; then
  echo -e "${RED}[ERR] 未检测到配置，请先运行 install.sh 安装！${PLAIN}"
  exit 1
fi

# shellcheck disable=SC1090
source "$STATE"

HOSTS=(); LABELS=()
case "${SB_OUT_MODE:-ipv4}" in
  both)
    [[ -n "${SB_IPV4:-}" ]] && HOSTS+=("$SB_IPV4") && LABELS+=("IPv4")
    [[ -n "${SB_IPV6:-}" ]] && HOSTS+=("$SB_IPV6") && LABELS+=("IPv6")
    ;;
  ipv6)
    [[ -n "${SB_IPV6:-}" ]] && HOSTS+=("$SB_IPV6") && LABELS+=("")
    ;;
  *)
    [[ -n "${SB_IPV4:-}" ]] && HOSTS+=("$SB_IPV4") && LABELS+=("")
    ;;
esac

url_host(){ local h="$1"; [[ "$h" == *:* ]] && echo "[$h]" || echo "$h"; }

# 收集所有协议节点链接
MAIN_NODES_LIST=()
for i in "${!HOSTS[@]}"; do
  H="${HOSTS[$i]}"
  UHOST="$(url_host "$H")"
  LABEL="${LABELS[$i]}"
  SUFFIX=""
  [[ -n "$LABEL" ]] && SUFFIX="_${LABEL}"

  if [[ "${SB_ENABLE_REALITY:-0}" == "1" ]]; then
    PORT="${SB_REALITY_P4}"
    [[ "$LABEL" == "IPv6" ]] && PORT="${SB_REALITY_P6}"
    LINK="vless://${SB_UUID}@${UHOST}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SB_REALITY_SNI}&fp=chrome&pbk=${SB_REALITY_PUB}&sid=${SB_SHORT_ID}&type=tcp&headerType=none#Reality${SUFFIX}"
    MAIN_NODES_LIST+=("$LINK")
  fi

  if [[ "${SB_ENABLE_HY2:-0}" == "1" ]]; then
    PORT="${SB_HY2_P4}"
    [[ "$LABEL" == "IPv6" ]] && PORT="${SB_HY2_P6}"
    HOP_PARAM=""
    [[ -n "${SB_HOP_RANGE:-}" ]] && HOP_PARAM="&ports=${SB_HOP_RANGE}&mport=${SB_HOP_RANGE}"
    LINK="hysteria2://${SB_HY2_PASS}@${UHOST}:${PORT}?insecure=${SB_CERT_INSECURE}&sni=${SB_SNI_HOST}&alpn=h3${HOP_PARAM}#Hysteria2${SUFFIX}"
    MAIN_NODES_LIST+=("$LINK")
  fi

  if [[ "${SB_ENABLE_TUIC:-0}" == "1" ]]; then
    PORT="${SB_TUIC_P4}"
    [[ "$LABEL" == "IPv6" ]] && PORT="${SB_TUIC_P6}"
    LINK="tuic://${SB_TUIC_UUID}:${SB_TUIC_PASS}@${UHOST}:${PORT}?congestion_control=bbr&alpn=h3&sni=${SB_SNI_HOST}&allow_insecure=${SB_CERT_INSECURE}&insecure=${SB_CERT_INSECURE}&version=5&udp_relay_mode=native#TUIC${SUFFIX}"
    MAIN_NODES_LIST+=("$LINK")
  fi
done

ARGO_NODE_LINK=""
if [[ -n "${SB_ARGO_DOMAIN:-}" ]]; then
  ARGO_NODE_LINK="vless://${SB_UUID}@${SB_ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${SB_ARGO_DOMAIN}&type=ws&host=${SB_ARGO_DOMAIN}&path=%2Fargo#Argo"
fi

# 独立函数：推送到节点管理平台 (cf-node-manager-plus)
push_to_manager() {
  echo -e "\n${BLUE}==============================================================${PLAIN}"
  echo -e "${BLUE}        🚀 推送节点到节点管理平台 (cf-node-manager-plus)       ${PLAIN}"
  echo -e "${BLUE}==============================================================${PLAIN}"

  if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}[ERR] 系统缺少 curl 工具，无法发起推送！${PLAIN}"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}[ERR] 系统缺少 jq 工具，无法生成 JSON 格式！${PLAIN}"
    return 1
  fi

  SAVED_URL=""
  SAVED_TOKEN=""
  SAVED_TAG_M=""
  SAVED_TAG_A=""
  if [[ -f "$MGR_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$MGR_CONF" 2>/dev/null || true
    SAVED_URL="${SAVED_MGR_URL:-}"
    SAVED_TOKEN="${SAVED_MGR_TOKEN:-}"
    SAVED_TAG_M="${SAVED_TAG_MAIN:-}"
    SAVED_TAG_A="${SAVED_TAG_ARGO:-}"
  fi

  if [[ "${AUTO_INSTALL:-0}" -eq 1 || "${UNATTENDED:-0}" -eq 1 ]]; then
    # 非交互式自动模式
    P_URL="${PUSH_URL:-${SAVED_URL:-}}"
    MGR_TOKEN="${PUSH_TOKEN:-${SAVED_TOKEN:-}}"
    if [[ -z "$P_URL" || -z "$MGR_TOKEN" ]]; then
      warn "自动模式下未提供 PUSH_URL 或 PUSH_TOKEN，跳过推送！"
      return 0
    fi
    [[ "$P_URL" != http* ]] && P_URL="http://${P_URL}"
    MGR_URL="${P_URL%/}"

    DEF_TAG_M="${SAVED_TAG_M:-}"
    if [[ -z "$DEF_TAG_M" ]]; then
      HOST_NAME="$(hostname 2>/dev/null || echo "")"
      if [[ -n "$HOST_NAME" && "$HOST_NAME" != "localhost" ]]; then
        DEF_TAG_M="${HOST_NAME}本机"
      else
        DEF_TAG_M="SingBox本机"
      fi
    fi
    TAG_MAIN="${PUSH_TAG_MAIN:-$DEF_TAG_M}"

    TAG_ARGO=""
    if [[ -n "$ARGO_NODE_LINK" ]]; then
      DEF_TAG_A="${SAVED_TAG_A:-${TAG_MAIN%本机}优选}"
      TAG_ARGO="${PUSH_TAG_ARGO:-$DEF_TAG_A}"
    fi
  else
    # 交互式模式
    # 1. 输入面板地址
    if [[ -n "$SAVED_URL" ]]; then
      read -r -p "请输入节点管理面板地址 [默认: ${SAVED_URL}]: " P_URL
      P_URL="${P_URL:-$SAVED_URL}"
    else
      while true; do
        read -r -p "请输入节点管理面板地址 (例如 http://1.2.3.4:5000 或 https://sub.domain.com): " P_URL
        [[ -n "$P_URL" ]] && break
        echo -e "${RED}[!] 地址不能为空，请重新输入！${PLAIN}"
      done
    fi
    [[ "$P_URL" != http* ]] && P_URL="http://${P_URL}"
    MGR_URL="${P_URL%/}"

    # 2. 输入密码或 Token
    if [[ -n "$SAVED_TOKEN" ]]; then
      read -r -p "请输入管理面板密码或 Token (WEB_PASSWORD) [默认: 保留上次配置]: " P_TOKEN
      MGR_TOKEN="${P_TOKEN:-$SAVED_TOKEN}"
    else
      while true; do
        read -r -p "请输入管理面板密码或 Token (WEB_PASSWORD): " P_TOKEN
        [[ -n "$P_TOKEN" ]] && break
        echo -e "${RED}[!] 密码或 Token 不能为空，请重新输入！${PLAIN}"
      done
      MGR_TOKEN="$P_TOKEN"
    fi

    # 3. 输入主节点订阅源名称 (Reality / Hy2 / TUIC 三合一)
    DEF_TAG_M="${SAVED_TAG_M:-}"
    if [[ -z "$DEF_TAG_M" ]]; then
      HOST_NAME="$(hostname 2>/dev/null || echo "")"
      if [[ -n "$HOST_NAME" && "$HOST_NAME" != "localhost" ]]; then
        DEF_TAG_M="${HOST_NAME}本机"
      else
        DEF_TAG_M="SingBox本机"
      fi
    fi
    read -r -p "请输入主节点订阅源名称 (Reality/Hy2/TUIC 三合一) [默认: ${DEF_TAG_M}]: " P_TAG_M
    TAG_MAIN="${P_TAG_M:-$DEF_TAG_M}"

    # 4. 如果有 Argo 节点，输入 Argo 节点订阅源名称 (单独推送)
    TAG_ARGO=""
    if [[ -n "$ARGO_NODE_LINK" ]]; then
      DEF_TAG_A="${SAVED_TAG_A:-${TAG_MAIN%本机}优选}"
      echo -e "${YELLOW}>>> 检测到已启用 Cloudflare Argo 隧道节点！${PLAIN}"
      read -r -p "请输入 Argo 节点独立订阅源名称 [默认: ${DEF_TAG_A}]: " P_TAG_A
      TAG_ARGO="${P_TAG_A:-$DEF_TAG_A}"
    fi
  fi

  echo -e "\n${BLUE}正在连接面板并推送节点...${PLAIN}"

  PUSH_ERR=0
  # 1. 若启用了 Argo 隧道，先推送 Argo 节点 (独立订阅源，默认开启优选，sync: false 避免覆盖)
  if [[ -n "$ARGO_NODE_LINK" ]]; then
    echo -e ">>> [1/2] 正在推送 Argo 隧道节点 -> 订阅源: [${GREEN}${TAG_ARGO}${PLAIN}] (默认开启优选)..."
    PAYLOAD_A="$(jq -n \
      --arg tag "$TAG_ARGO" \
      --arg nodes "$ARGO_NODE_LINK" \
      --arg token "$MGR_TOKEN" \
      '{tag: $tag, nodes: $nodes, enabled: true, token: $token, replace: true, sync: false}')"

    RESP_A="$(curl -s -S -X POST "${MGR_URL}/api/push_nodes" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${MGR_TOKEN}" \
      --connect-timeout 10 \
      --max-time 30 \
      -d "$PAYLOAD_A" 2>&1)"

    if echo "$RESP_A" | grep -q '"status"[[:space:]]*:[[:space:]]*"success"'; then
      echo -e "${GREEN}[√] Argo 隧道节点推送成功！${PLAIN}"
    else
      echo -e "${RED}[×] Argo 节点推送失败！${PLAIN}"
      echo -e "${YELLOW}面板响应: ${RESP_A}${PLAIN}"
      PUSH_ERR=1
    fi
    sleep 1
  fi

  # 2. 推送主节点集合 (Reality / Hy2 / TUIC 三合一，默认关闭优选，sync: true 触发全量同步)
  if [[ ${#MAIN_NODES_LIST[@]} -gt 0 ]]; then
    MAIN_TEXT="$(printf "%s\n" "${MAIN_NODES_LIST[@]}")"
    echo -e ">>> [2/2] 正在推送主节点集合 (Reality / Hy2 / TUIC) -> 订阅源: [${GREEN}${TAG_MAIN}${PLAIN}] (默认关闭优选)..."
    PAYLOAD_M="$(jq -n \
      --arg tag "$TAG_MAIN" \
      --arg nodes "$MAIN_TEXT" \
      --arg token "$MGR_TOKEN" \
      '{tag: $tag, nodes: $nodes, enabled: false, token: $token, replace: true, sync: true}')"

    RESP_M="$(curl -s -S -X POST "${MGR_URL}/api/push_nodes" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${MGR_TOKEN}" \
      --connect-timeout 10 \
      --max-time 30 \
      -d "$PAYLOAD_M" 2>&1)"

    if echo "$RESP_M" | grep -q '"status"[[:space:]]*:[[:space:]]*"success"'; then
      echo -e "${GREEN}[√] 主节点集合推送成功！共 ${#MAIN_NODES_LIST[@]} 个节点。${PLAIN}"
    else
      echo -e "${RED}[×] 主节点推送失败！${PLAIN}"
      echo -e "${YELLOW}面板响应: ${RESP_M}${PLAIN}"
      PUSH_ERR=1
    fi
  else
    echo -e "${YELLOW}[!] 未启用 Reality / Hy2 / TUIC 协议节点，跳过主节点推送。${PLAIN}"
  fi

  if [[ $PUSH_ERR -eq 0 ]]; then
    cat > "$MGR_CONF" <<EOF
SAVED_MGR_URL="${MGR_URL}"
SAVED_MGR_TOKEN="${MGR_TOKEN}"
SAVED_TAG_MAIN="${TAG_MAIN}"
SAVED_TAG_ARGO="${TAG_ARGO}"
EOF
    chmod 600 "$MGR_CONF"
    echo -e "\n${GREEN}==============================================================${PLAIN}"
    echo -e "${GREEN}🎉 节点已成功推送到节点管理平台！${PLAIN}"
    echo -e "管理面板地址: ${BLUE}${MGR_URL}${PLAIN}"
    echo -e "聚合订阅地址: ${BLUE}${MGR_URL}/sub?token=${MGR_TOKEN}${PLAIN}"
    echo -e "${GREEN}==============================================================${PLAIN}\n"
  else
    echo -e "\n${RED}[!] 节点推送未完全成功，请检查上述面板响应！${PLAIN}\n"
    return 1
  fi
}

# 模式分支：如果带 push 参数，则直接进入推送流程
if [[ "${1:-}" == "push" ]]; then
  push_to_manager
  exit 0
fi

# 默认模式：展示所有节点链接与 Mihomo 配置
echo -e "${BLUE}==============================================================${PLAIN}"
echo -e "${BLUE}         Sing-box 极速节点输出 (VLESS-Reality / Hy2 / TUIC)   ${PLAIN}"
echo -e "${BLUE}==============================================================${PLAIN}"

for i in "${!HOSTS[@]}"; do
  H="${HOSTS[$i]}"
  UHOST="$(url_host "$H")"
  LABEL="${LABELS[$i]}"
  SUFFIX=""
  [[ -n "$LABEL" ]] && SUFFIX="_${LABEL}"

  echo -e "\n${YELLOW}>>> [节点组${SUFFIX}] 地址: ${H}${PLAIN}"

  if [[ "${SB_ENABLE_REALITY:-0}" == "1" ]]; then
    PORT="${SB_REALITY_P4}"
    [[ "$LABEL" == "IPv6" ]] && PORT="${SB_REALITY_P6}"
    LINK="vless://${SB_UUID}@${UHOST}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SB_REALITY_SNI}&fp=chrome&pbk=${SB_REALITY_PUB}&sid=${SB_SHORT_ID}&type=tcp&headerType=none#Reality${SUFFIX}"
    echo -e "${GREEN}${LINK}${PLAIN}"
  fi

  if [[ "${SB_ENABLE_HY2:-0}" == "1" ]]; then
    PORT="${SB_HY2_P4}"
    [[ "$LABEL" == "IPv6" ]] && PORT="${SB_HY2_P6}"
    HOP_PARAM=""
    [[ -n "${SB_HOP_RANGE:-}" ]] && HOP_PARAM="&ports=${SB_HOP_RANGE}&mport=${SB_HOP_RANGE}"
    LINK="hysteria2://${SB_HY2_PASS}@${UHOST}:${PORT}?insecure=${SB_CERT_INSECURE}&sni=${SB_SNI_HOST}&alpn=h3${HOP_PARAM}#Hysteria2${SUFFIX}"
    echo -e "${GREEN}${LINK}${PLAIN}"
  fi

  if [[ "${SB_ENABLE_TUIC:-0}" == "1" ]]; then
    PORT="${SB_TUIC_P4}"
    [[ "$LABEL" == "IPv6" ]] && PORT="${SB_TUIC_P6}"
    LINK="tuic://${SB_TUIC_UUID}:${SB_TUIC_PASS}@${UHOST}:${PORT}?congestion_control=bbr&alpn=h3&sni=${SB_SNI_HOST}&allow_insecure=${SB_CERT_INSECURE}&insecure=${SB_CERT_INSECURE}&version=5&udp_relay_mode=native#TUIC${SUFFIX}"
    echo -e "${GREEN}${LINK}${PLAIN}"
  fi
done

# Argo 隧道节点放最后
if [[ -n "${SB_ARGO_DOMAIN:-}" ]]; then
  LINK_ARGO="vless://${SB_UUID}@${SB_ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${SB_ARGO_DOMAIN}&type=ws&host=${SB_ARGO_DOMAIN}&path=%2Fargo#Argo"
  echo -e "${GREEN}${LINK_ARGO}${PLAIN}"
fi

# 生成并打印 Mihomo Proxies YAML
{
  echo "proxies:"
  for i in "${!HOSTS[@]}"; do
    H="${HOSTS[$i]}"
    LABEL="${LABELS[$i]}"
    SUFFIX=""
    [[ -n "$LABEL" ]] && SUFFIX="_${LABEL}"

    if [[ "${SB_ENABLE_REALITY:-0}" == "1" ]]; then
      PORT="${SB_REALITY_P4}"
      [[ "$LABEL" == "IPv6" ]] && PORT="${SB_REALITY_P6}"
      cat <<YAML
  - name: "Reality${SUFFIX}"
    type: vless
    server: "${H}"
    port: ${PORT}
    uuid: "${SB_UUID}"
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: "${SB_REALITY_SNI}"
    client-fingerprint: chrome
    reality-opts:
      public-key: "${SB_REALITY_PUB}"
      short-id: "${SB_SHORT_ID}"
YAML
    fi

    if [[ "${SB_ENABLE_HY2:-0}" == "1" ]]; then
      PORT="${SB_HY2_P4}"
      [[ "$LABEL" == "IPv6" ]] && PORT="${SB_HY2_P6}"
      cat <<YAML
  - name: "Hysteria2${SUFFIX}"
    type: hysteria2
    server: "${H}"
    port: ${PORT}
    password: "${SB_HY2_PASS}"
    sni: "${SB_SNI_HOST}"
    alpn: [h3]
    skip-cert-verify: $([[ "$SB_CERT_INSECURE" == "1" ]] && echo "true" || echo "false")
$([[ -n "${SB_HOP_RANGE:-}" ]] && echo "    ports: \"${SB_HOP_RANGE}\"")
YAML
    fi

    if [[ "${SB_ENABLE_TUIC:-0}" == "1" ]]; then
      PORT="${SB_TUIC_P4}"
      [[ "$LABEL" == "IPv6" ]] && PORT="${SB_TUIC_P6}"
      cat <<YAML
  - name: "TUIC${SUFFIX}"
    type: tuic
    server: "${H}"
    port: ${PORT}
    uuid: "${SB_TUIC_UUID}"
    password: "${SB_TUIC_PASS}"
    version: 5
    alpn: [h3]
    sni: "${SB_SNI_HOST}"
    skip-cert-verify: $([[ "$SB_CERT_INSECURE" == "1" ]] && echo "true" || echo "false")
    congestion-controller: bbr
    reduce-rtt: true
YAML
    fi
  done

  # Argo 放在最后
  if [[ -n "${SB_ARGO_DOMAIN:-}" ]]; then
    cat <<YAML
  - name: "Argo"
    type: vless
    server: "${SB_ARGO_DOMAIN}"
    port: 443
    uuid: "${SB_UUID}"
    udp: true
    tls: true
    servername: "${SB_ARGO_DOMAIN}"
    network: ws
    ws-opts:
      path: /argo
      headers:
        Host: "${SB_ARGO_DOMAIN}"
YAML
  fi
} > "$MIHOMO_FILE"

echo -e "\n${BLUE}==============================================================${PLAIN}"
echo -e "${YELLOW}>>> Mihomo / Clash Meta 格式配置已保存至: ${MIHOMO_FILE}${PLAIN}"
echo -e "${BLUE}==============================================================${PLAIN}"
cat "$MIHOMO_FILE"

echo -e "\n${BLUE}==============================================================${PLAIN}"
echo -e ">>> 随时输入 ${GREEN}sb${PLAIN} 查看所有节点，输入 ${GREEN}sb push${PLAIN} 推送节点至管理平台！"
echo -e "${BLUE}==============================================================${PLAIN}\n"
EOSB
  chmod +x "$SHORTCUT_BIN"
}

# --- 独立管理 Hysteria 2 端口跳跃 ---
manage_port_hop(){
  if [[ ! -f "$CONF_DIR/config.json" || ! -f "$STATE_FILE" ]]; then
    warn "未检测到已安装配置，请先运行安装！"
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$STATE_FILE"

  if [[ "${SB_ENABLE_HY2:-0}" -ne 1 ]]; then
    warn "当前配置未启用 Hysteria 2 协议，无法配置端口跳跃！"
    exit 1
  fi

  echo -e "\n${BLUE}==============================================================${PLAIN}"
  echo -e "${BLUE}          配置 / 修改 Hysteria 2 UDP 端口跳跃范围             ${PLAIN}"
  echo -e "${BLUE}==============================================================${PLAIN}"
  echo -e "Hysteria 2 主监听端口: ${GREEN}${SB_HY2_P4:-未分配}${PLAIN} $([[ "${SB_OUT_MODE:-}" == "both" ]] && echo "(IPv6: ${SB_HY2_P6:-未分配})")"
  if [[ -n "${SB_HOP_RANGE:-}" ]]; then
    echo -e "当前跳跃端口范围: ${GREEN}${SB_HOP_RANGE}${PLAIN}"
  else
    echo -e "当前跳跃端口范围: ${YELLOW}未配置 (未开启端口跳跃)${PLAIN}"
  fi
  echo -e "--------------------------------------------------------------"
  echo -e "提示："
  echo -e "  - 输入新范围，例如：${GREEN}30000-32000${PLAIN} 或 ${GREEN}1000-2000,3000,4000${PLAIN}"
  echo -e "  - 输入 ${YELLOW}0${PLAIN} 或 ${YELLOW}disable${PLAIN} 可关闭并清除端口跳跃"
  echo -e "  - 直接回车保留现有配置"
  echo -e "--------------------------------------------------------------"
  read -r -p "请输入新的端口跳跃范围: " NEW_HOP_INPUT || true

  NEW_HOP_INPUT="${NEW_HOP_INPUT// /}"

  if [[ -z "$NEW_HOP_INPUT" ]]; then
    info "已保留当前配置，未做修改。"
    exit 0
  fi

  local NEW_HOP_RANGE=""
  if [[ "$NEW_HOP_INPUT" == "0" || "$NEW_HOP_INPUT" =~ ^[Dd]isable$ ]]; then
    NEW_HOP_RANGE=""
    ok "已选择关闭端口跳跃"
  else
    NEW_HOP_RANGE="$(validate_hop_range "$NEW_HOP_INPUT" || true)"
    if [[ -z "$NEW_HOP_RANGE" ]]; then
      err "输入的端口跳跃范围格式无效！示例：30000-32000 或 1000-2000,3000,4000"
      exit 1
    fi
  fi

  # 更新 STATE_FILE
  if grep -q "^SB_HOP_RANGE=" "$STATE_FILE"; then
    sed -i "s/^SB_HOP_RANGE=.*/SB_HOP_RANGE=\"$NEW_HOP_RANGE\"/g" "$STATE_FILE"
  else
    echo "SB_HOP_RANGE=\"$NEW_HOP_RANGE\"" >> "$STATE_FILE"
  fi

  # 放行防火墙端口
  if [[ -n "$NEW_HOP_RANGE" ]]; then
    fw_allow_ports "" "" "$NEW_HOP_RANGE"
  fi

  # 立即执行端口跳跃挂载或清理
  /usr/local/bin/sb-hop.sh >/dev/null 2>&1 || true

  # 重新生成 sb 查看命令脚本 (同步更新链接中的 ports/mport 及 mihomo yaml)
  generate_shortcut_script

  ok "Hysteria 2 端口跳跃范围已成功更新！"
  [[ -n "$NEW_HOP_RANGE" ]] && ok "新跳跃范围: ${GREEN}${NEW_HOP_RANGE}${PLAIN}" || ok "端口跳跃已关闭"
  echo -e ">>> 正在展示最新节点链接及 Mihomo 格式配置...\n"
  if [[ -x "$SHORTCUT_BIN" ]]; then
    "$SHORTCUT_BIN"
  fi
}

# ==============================================================================
# [主菜单系统]
# ==============================================================================
if [[ "${AUTO_INSTALL:-0}" == "1" || "${1:-}" == "--auto" || "${1:-}" == "auto" ]]; then
  info "检测到集群管理/无人值守部署模式 (AUTO_INSTALL=1)，跳过主菜单交互并按指定参数自动配置..."
elif [[ -z "${1:-}" ]]; then
  clear
  echo -e "${BLUE}==============================================================${PLAIN}"
  echo -e "${BLUE}   Sing-box 现代极速终极版 v7.0 (VLESS-Reality / Hy2 / TUIC v5) ${PLAIN}"
  echo -e "${BLUE}==============================================================${PLAIN}"
  echo -e "  ${GREEN}1.${PLAIN} 全新安装 / 重新配置 (交互式定制三大协议与极速调优)"
  echo -e "  ${GREEN}2.${PLAIN} 查看所有节点链接与配置 (sb 快捷命令)"
  echo -e "  ${GREEN}3.${PLAIN} 推送节点至节点管理平台 (cf-node-manager-plus)"
  echo -e "  ${GREEN}4.${PLAIN} 智能测速并更换 Reality 伪装域名"
  echo -e "  ${GREEN}5.${PLAIN} 配置 / 修改 Hysteria 2 端口跳跃范围"
  echo -e "  ${GREEN}6.${PLAIN} 一键更新 Sing-box 核心至最新稳定版"
  echo -e "  ${GREEN}7.${PLAIN} 彻底卸载脚本及所有服务"
  echo -e "  ${GREEN}0.${PLAIN} 退出"
  echo -e "${BLUE}==============================================================${PLAIN}"
  read -r -p "请输入选择 [0-7] (默认 1): " MENU_SEL
  MENU_SEL="${MENU_SEL:-1}"

  case "$MENU_SEL" in
    2)
      if [[ -x "$SHORTCUT_BIN" ]]; then "$SHORTCUT_BIN"; else warn "未检测到配置，请先运行安装！"; fi
      exit 0
      ;;
    3)
      if [[ -x "$SHORTCUT_BIN" ]]; then "$SHORTCUT_BIN" push; else warn "未检测到配置，请先运行安装！"; fi
      exit 0
      ;;
    4)
      if [[ ! -f "$CONF_DIR/config.json" ]]; then
        warn "未检测到已安装配置，请先进行全新安装！"
        exit 1
      fi
      select_reality_sni
      # 更新已有配置中的 SNI
      if [[ -f "$CONF_DIR/config.json" ]]; then
        tmp_conf="$(mktemp)"
        jq --arg sni "$REALITY_SNI" --arg hs "$REALITY_HS_SERVER" '
          (.inbounds[] | select(.type=="vless") | .tls.server_name) = $sni |
          (.inbounds[] | select(.type=="vless") | .tls.reality.handshake.server) = $hs
        ' "$CONF_DIR/config.json" > "$tmp_conf" && mv "$tmp_conf" "$CONF_DIR/config.json"
        if [[ -f "$STATE_FILE" ]]; then
          sed -i "s/^SB_REALITY_SNI=.*/SB_REALITY_SNI=\"$REALITY_SNI\"/g" "$STATE_FILE" 2>/dev/null || true
          sed -i "s/^SB_REALITY_HS=.*/SB_REALITY_HS=\"$REALITY_HS_SERVER\"/g" "$STATE_FILE" 2>/dev/null || true
        fi
        service_enable_restart
        ok "Reality 伪装目标已更新并已重启服务！输入 sb 查看最新链接。"
      fi
      exit 0
      ;;
    5) manage_port_hop; exit 0 ;;
    6) update_core; exit 0 ;;
    7) do_uninstall; exit 0 ;;
    0) echo "已退出。"; exit 0 ;;
    1) echo -e "\n${GREEN}开始交互式安装流程...${PLAIN}\n" ;;
    *) err "无效选择"; exit 1 ;;
  esac
elif [[ "${1:-}" == "--uninstall" ]]; then
  do_uninstall; exit 0
fi

# 预载历史配置状态 (若存在) 以便在后续流程中无缝复用与继承
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" >/dev/null 2>&1 || true
fi

# ==============================================================================
# [1/10] 环境初始化
# ==============================================================================
echo -e "${YELLOW}[1/10] 检查并初始化基础运行环境...${PLAIN}"
service_stop
install_pkgs
command -v jq >/dev/null 2>&1 || { err "jq 安装失败，请检查包管理器配置！"; exit 1; }
mkdir -p "$CONF_DIR" "$CERT_DIR" "$WARP_DIR"
chown -R root:root "$CONF_DIR" >/dev/null 2>&1 || true
chmod 755 "$CONF_DIR" "$CERT_DIR" >/dev/null 2>&1 || true

# ==============================================================================
# [2/10] 网络检测与公网 IP 识别
# ==============================================================================
echo -e "${YELLOW}[2/10] 检测服务器网络与 IP 栈...${PLAIN}"
IPV4="$(curl -s4m6 --retry 2 ip.sb 2>/dev/null || curl -s4m6 --retry 2 ifconfig.co 2>/dev/null || true)"
IPV6="$(curl -s6m6 --retry 2 ip.sb 2>/dev/null || curl -s6m6 --retry 2 ifconfig.co 2>/dev/null || true)"

HAS_V4=0; HAS_V6=0
[[ -n "$IPV4" ]] && HAS_V4=1
[[ -n "$IPV6" ]] && HAS_V6=1

if [[ "$HAS_V4" -ne 1 && "$HAS_V6" -ne 1 ]]; then
  err "未能获取公网 IP，请检查 VPS 外网连通性或 DNS！"
  exit 1
fi
echo -e "公网栈识别：IPv4=${GREEN}${IPV4:-无}${PLAIN}  IPv6=${GREEN}${IPV6:-无}${PLAIN}"

IFACE="$(default_iface)"
LOCAL_IPV4="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
LOCAL_IPV6="$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
[[ -z "${LOCAL_IPV4:-}" ]] && LOCAL_IPV4="${IPV4:-}"
[[ -z "${LOCAL_IPV6:-}" ]] && LOCAL_IPV6="${IPV6:-}"

OUT_MODE="ipv4"
if [[ "${AUTO_INSTALL:-0}" -eq 1 ]]; then
  OUT_MODE="${SB_OUT_MODE:-${OUT_MODE:-ipv4}}"
elif [[ "$HAS_V4" -eq 1 && "$HAS_V6" -eq 1 ]]; then
  echo -e "--------------------------------------------------------------"
  echo -e "检测到双栈 VPS，请选择节点输出地址模式："
  echo -e "  1) 仅输出 IPv4 (推荐，最通用兼容)"
  echo -e "  2) 仅输出 IPv6"
  echo -e "  3) 同时输出 IPv4 + IPv6 双独立端口"
  read -r -p "请选择 [1-3] (默认 1): " SEL_OUT || true
  case "${SEL_OUT:-1}" in
    2) OUT_MODE="ipv6" ;;
    3) OUT_MODE="both" ;;
    *) OUT_MODE="ipv4" ;;
  esac
else
  [[ "$HAS_V6" -eq 1 && "$HAS_V4" -ne 1 ]] && OUT_MODE="ipv6"
  [[ "$HAS_V4" -eq 1 && "$HAS_V6" -ne 1 ]] && OUT_MODE="ipv4"
fi
ok "已选定节点网络输出模式：${OUT_MODE}"

# ==============================================================================
# [3/10] 核心协议交互式选择 (VLESS-Reality / Hysteria 2 / TUIC v5)
# ==============================================================================
echo -e "\n${YELLOW}[3/10] 核心协议选择 (精简三大王牌协议)...${PLAIN}"
echo -e "--------------------------------------------------------------"

ENABLE_REALITY=1
ENABLE_HY2=1
ENABLE_TUIC=1
if [[ "${AUTO_INSTALL:-0}" -eq 1 ]]; then
  ENABLE_REALITY="${SB_ENABLE_REALITY:-1}"
  ENABLE_HY2="${SB_ENABLE_HY2:-1}"
  ENABLE_TUIC="${SB_ENABLE_TUIC:-1}"
else
  read -r -p "是否启用 VLESS-Reality (TCP 顶流、免证书、抗封锁) [Y/n] (默认 Y): " ANS_R || true
  [[ "$ANS_R" =~ ^[Nn]$ ]] && ENABLE_REALITY=0

  read -r -p "是否启用 Hysteria 2 (UDP 极速、丢包克星、端口跳跃) [Y/n] (默认 Y): " ANS_H || true
  [[ "$ANS_H" =~ ^[Nn]$ ]] && ENABLE_HY2=0

  read -r -p "是否启用 TUIC v5 (QUIC 低延迟、高速备用栈) [Y/n] (默认 Y): " ANS_T || true
  [[ "$ANS_T" =~ ^[Nn]$ ]] && ENABLE_TUIC=0
fi

if [[ "$ENABLE_REALITY" -eq 0 && "$ENABLE_HY2" -eq 0 && "$ENABLE_TUIC" -eq 0 ]]; then
  warn "未启用任何协议，默认强制启用 VLESS-Reality！"
  ENABLE_REALITY=1
fi

echo -e "已选定协议组合："
[[ "$ENABLE_REALITY" -eq 1 ]] && echo -e "  - ${GREEN}VLESS-Reality${PLAIN} (TCP)"
[[ "$ENABLE_HY2" -eq 1 ]] && echo -e "  - ${GREEN}Hysteria 2${PLAIN} (UDP)"
[[ "$ENABLE_TUIC" -eq 1 ]] && echo -e "  - ${GREEN}TUIC v5${PLAIN} (UDP)"
echo -e "--------------------------------------------------------------"

# ==============================================================================
# [4/10] 端口与端口跳跃交互配置
# ==============================================================================
echo -e "${YELLOW}[4/10] 端口分配与跳跃设置...${PLAIN}"
PROTO_COUNT=$((ENABLE_REALITY + ENABLE_HY2 + ENABLE_TUIC))
TOTAL_PORTS=$PROTO_COUNT
[[ "$OUT_MODE" == "both" ]] && TOTAL_PORTS=$((PROTO_COUNT * 2))

if [[ "${AUTO_INSTALL:-0}" -eq 1 ]]; then
  # 自动部署模式
  if [[ -n "${PORT_REALITY:-}" || -n "${PORT_HY2:-}" || -n "${PORT_TUIC:-}" ]]; then
    # 直接使用显式指定的端口 (如 NAT 受限端口分配)
    P_REALITY_V4="${PORT_REALITY:-0}"
    P_REALITY_V6="${PORT_REALITY:-0}"
    P_HY2_V4="${PORT_HY2:-0}"
    P_HY2_V6="${PORT_HY2:-0}"
    P_TUIC_V4="${PORT_TUIC:-0}"
    P_TUIC_V6="${PORT_TUIC:-0}"
  else
    BASE_PORT="${BASE_PORT:-}"
    if [[ -z "${BASE_PORT:-}" ]] || ! [[ "$BASE_PORT" =~ ^[0-9]+$ ]] || [[ "$BASE_PORT" -lt 1024 || "$((BASE_PORT + TOTAL_PORTS))" -gt 65535 ]]; then
      BASE_PORT="$(find_free_base_port "$TOTAL_PORTS")"
    fi
    BASE_V4="$BASE_PORT"
    BASE_V6="$((BASE_V4 + PROTO_COUNT))"
    cur_offset=0
    P_REALITY_V4=0; P_REALITY_V6=0
    P_HY2_V4=0; P_HY2_V6=0
    P_TUIC_V4=0; P_TUIC_V6=0
    if [[ "$ENABLE_REALITY" -eq 1 ]]; then
      P_REALITY_V4=$((BASE_V4 + cur_offset))
      P_REALITY_V6=$((BASE_V6 + cur_offset))
      cur_offset=$((cur_offset + 1))
    fi
    if [[ "$ENABLE_HY2" -eq 1 ]]; then
      P_HY2_V4=$((BASE_V4 + cur_offset))
      P_HY2_V6=$((BASE_V6 + cur_offset))
      cur_offset=$((cur_offset + 1))
    fi
    if [[ "$ENABLE_TUIC" -eq 1 ]]; then
      P_TUIC_V4=$((BASE_V4 + cur_offset))
      P_TUIC_V6=$((BASE_V6 + cur_offset))
    fi
  fi
  HOP_RANGE="${SB_HOP_RANGE:-${HOP_RANGE:-}}"
else
  read -r -p "请输入服务起始基础端口 (回车自动随机安全高位端口): " BASE_PORT || true
  if [[ -z "${BASE_PORT:-}" ]] || ! [[ "$BASE_PORT" =~ ^[0-9]+$ ]] || [[ "$BASE_PORT" -lt 1024 || "$((BASE_PORT + TOTAL_PORTS))" -gt 65535 ]]; then
    BASE_PORT="$(find_free_base_port "$TOTAL_PORTS")"
  fi

  BASE_V4="$BASE_PORT"
  BASE_V6="$((BASE_V4 + PROTO_COUNT))"

  # 动态顺序分配端口
  cur_offset=0
  P_REALITY_V4=0; P_REALITY_V6=0
  P_HY2_V4=0; P_HY2_V6=0
  P_TUIC_V4=0; P_TUIC_V6=0

  if [[ "$ENABLE_REALITY" -eq 1 ]]; then
    P_REALITY_V4=$((BASE_V4 + cur_offset))
    P_REALITY_V6=$((BASE_V6 + cur_offset))
    cur_offset=$((cur_offset + 1))
  fi
  if [[ "$ENABLE_HY2" -eq 1 ]]; then
    P_HY2_V4=$((BASE_V4 + cur_offset))
    P_HY2_V6=$((BASE_V6 + cur_offset))
    cur_offset=$((cur_offset + 1))
  fi
  if [[ "$ENABLE_TUIC" -eq 1 ]]; then
    P_TUIC_V4=$((BASE_V4 + cur_offset))
    P_TUIC_V6=$((BASE_V6 + cur_offset))
    cur_offset=$((cur_offset + 1))
  fi
fi

echo -e ">>> 端口规划完成:"
[[ "$ENABLE_REALITY" -eq 1 ]] && echo -e "  Reality 端口: ${GREEN}${P_REALITY_V4}${PLAIN} $([[ "$OUT_MODE" == "both" ]] && echo "(v6: ${P_REALITY_V6})")"
[[ "$ENABLE_HY2" -eq 1 ]] && echo -e "  Hy2 端口    : ${GREEN}${P_HY2_V4}${PLAIN} $([[ "$OUT_MODE" == "both" ]] && echo "(v6: ${P_HY2_V6})")"
[[ "$ENABLE_TUIC" -eq 1 ]] && echo -e "  TUIC 端口   : ${GREEN}${P_TUIC_V4}${PLAIN} $([[ "$OUT_MODE" == "both" ]] && echo "(v6: ${P_TUIC_V6})")"

# Hysteria 2 端口跳跃交互
HOP_RANGE="${HOP_RANGE:-}"
if [[ "$ENABLE_HY2" -eq 1 && "${AUTO_INSTALL:-0}" -ne 1 ]]; then
  echo -e "--------------------------------------------------------------"
  CUR_HOP="${SB_HOP_RANGE:-}"
  if [[ -n "$CUR_HOP" ]]; then
    echo -e "检测到现有端口跳跃范围: ${GREEN}${CUR_HOP}${PLAIN}"
    read -r -p "是否保留此端口跳跃范围? [Y/n/修改] (直接回车保留当前配置): " ANS_HOP || true
    if [[ "$ANS_HOP" =~ ^[Nn]$ ]]; then
      HOP_RANGE=""
      info "已关闭端口跳跃"
    elif [[ "$ANS_HOP" =~ ^[CcMm]$ ]]; then
      read -r -p "请输入新的端口跳跃范围 (例如 30000-32000 或 1000-2000,3000,4000): " HOP_INPUT || true
      VALID_HOP="$(validate_hop_range "$HOP_INPUT" || true)"
      if [[ -n "$VALID_HOP" ]]; then
        HOP_RANGE="$VALID_HOP"
        ok "端口跳跃已更新为: ${HOP_RANGE}"
      else
        warn "输入格式有误，保留原端口跳跃配置: ${CUR_HOP}"
        HOP_RANGE="$CUR_HOP"
      fi
    else
      HOP_RANGE="$CUR_HOP"
      ok "已保留现有端口跳跃: ${HOP_RANGE}"
    fi
  else
    read -r -p "是否为 Hysteria 2 配置 UDP 端口跳跃? [Y/n] (默认 Y): " ANS_HOP || true
    if [[ "$ANS_HOP" =~ ^[Nn]$ ]]; then
      info "已跳过端口跳跃配置"
    else
      read -r -p "请输入端口跳跃范围 (例如 30000-32000 或 1000-2000,3000,4000) [默认 30000-32000]: " HOP_INPUT || true
      HOP_INPUT="${HOP_INPUT:-30000-32000}"
      VALID_HOP="$(validate_hop_range "$HOP_INPUT" || true)"
      if [[ -n "$VALID_HOP" ]]; then
        HOP_RANGE="$VALID_HOP"
        ok "端口跳跃已设置: ${HOP_RANGE}"
      else
        warn "输入格式有误，本次跳过端口跳跃配置"
      fi
    fi
  fi
fi

# ==============================================================================
# [5/10] Reality 伪装域名与证书处理
# ==============================================================================
echo -e "\n${YELLOW}[5/10] Reality 伪装目标与证书准备...${PLAIN}"
if [[ "$ENABLE_REALITY" -eq 1 ]]; then
  select_reality_sni
fi

CERT_MODE="self"
DOMAIN=""
SNI_HOST="www.bing.com"
CERT_INSECURE=1
CERT_PATH="$CERT_DIR/cert.pem"
KEY_PATH="$CERT_DIR/key.pem"

# Hy2 或 TUIC 需要 TLS 证书
if [[ "$ENABLE_HY2" -eq 1 || "$ENABLE_TUIC" -eq 1 ]]; then
  echo -e "--------------------------------------------------------------"
  echo -e "Hysteria 2 / TUIC v5 证书模式："
  echo -e "  1. 快速免域名自签证书 (10年有效，SNI=www.bing.com，客户端自动开启跳过证书校验)"
  echo -e "  2. 使用自有域名 (通过 acme.sh 自动申请免费 Let's Encrypt 证书)"
  if [[ "${AUTO_INSTALL:-0}" -eq 1 ]]; then
    ACME_MODE="${SB_ACME_MODE:-${ACME_MODE:-dns}}"
    CF_TOKEN="${SB_CF_TOKEN:-${CF_TOKEN:-}}"
    if [[ -n "${INPUT_DOMAIN:-${DOMAIN:-}}" ]]; then
      DOMAIN="${INPUT_DOMAIN:-$DOMAIN}"
      SNI_HOST="$DOMAIN"
      CERT_INSECURE=0
      CERT_MODE="acme"
      ok "自动模式使用自有域名申请证书: ${DOMAIN} (验证模式: ${ACME_MODE})"
    else
      CERT_MODE="self"
      SNI_HOST="www.bing.com"
      CERT_INSECURE=1
      info "自动模式未指定域名，默认使用 10 年 ECC 自签证书"
    fi
  else
    read -r -p "请选择证书模式 [1-2] (默认 1): " C_SEL || true
    C_SEL="${C_SEL:-1}"

    ACME_MODE="standalone"
    CF_TOKEN=""

    if [[ "$C_SEL" == "2" ]]; then
      read -r -p "请输入你的域名: " INPUT_DOMAIN || true
      if [[ -n "${INPUT_DOMAIN:-}" ]]; then
        DOMAIN="$INPUT_DOMAIN"
        SNI_HOST="$DOMAIN"
        CERT_INSECURE=0
        CERT_MODE="acme"

        echo -e "--------------------------------------------------------------"
        echo -e "请选择 ACME 证书申请验证方式："
        echo -e "  1. Cloudflare DNS-01 验证 (推荐：输入 CF Token，免开 80 端口，不怕 CDN 阻断)"
        echo -e "  2. Standalone HTTP-01 验证 (需 VPS 80 端口可用且域名直接解析到本机 IP)"
        read -r -p "请选择验证方式 [1-2] (默认 1): " ACME_SEL || true
        ACME_SEL="${ACME_SEL:-1}"

        if [[ "$ACME_SEL" == "1" ]]; then
          ACME_MODE="dns"
          # 尝试复用历史 CF Token
          if [[ -f "$STATE_FILE" ]]; then
            source "$STATE_FILE" >/dev/null 2>&1 || true
            CF_TOKEN="${SB_CF_TOKEN:-}"
          fi
          if [[ -n "$CF_TOKEN" ]]; then
            echo -e "检测到历史 Cloudflare Token: ${GREEN}${CF_TOKEN:0:6}******${PLAIN}"
            read -r -p "是否直接复用此 Token? [Y/n] (默认 Y): " REUSE_CF || true
            [[ "$REUSE_CF" =~ ^[Nn]$ ]] && CF_TOKEN=""
          fi
          if [[ -z "$CF_TOKEN" ]]; then
            read -r -p "请输入 Cloudflare API Token (需具备 Zone.DNS 编辑权限): " INPUT_CF_TOKEN || true
            CF_TOKEN="$INPUT_CF_TOKEN"
          fi
          if [[ -z "$CF_TOKEN" ]]; then
            warn "未输入 Cloudflare API Token，已自动切换为 Standalone HTTP-01 验证方式"
            ACME_MODE="standalone"
          fi
        else
          ACME_MODE="standalone"
        fi
      else
        warn "未输入有效域名，自动使用自签证书模式"
      fi
    fi
  fi

  if [[ "$CERT_MODE" == "self" ]]; then
    info "正在生成 10 年有效期 ECC 伪装自签证书..."
    cat > /tmp/sb_self_ssl.cnf <<EOF
[req]
distinguished_name=req_dn
x509_extensions=v3_req
prompt=no
[req_dn]
C=US
O=Microsoft
CN=${SNI_HOST}
[v3_req]
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names
[alt_names]
DNS.1=${SNI_HOST}
EOF
    openssl req -new -x509 -days 3650 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout "$KEY_PATH" -out "$CERT_PATH" -config /tmp/sb_self_ssl.cnf >/dev/null 2>&1 || true
    rm -f /tmp/sb_self_ssl.cnf
    ok "自签伪装证书生成完成"
  else
    # ACME 模式
    info "准备通过 acme.sh 签发证书 (验证方式: ${ACME_MODE})..."
    if ! command -v crontab >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then apt-get install -y cron >/dev/null 2>&1; systemctl enable --now cron >/dev/null 2>&1 || true; fi
      if command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then yum install -y cronie >/dev/null 2>&1; systemctl enable --now crond >/dev/null 2>&1 || true; fi
    fi

    curl -s https://get.acme.sh | sh -s email=admin@"${DOMAIN}" >/dev/null 2>&1 || true
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true

    if [[ "${ACME_MODE:-}" == "dns" ]]; then
      export CF_Token="${CF_TOKEN}"
      info "正在通过 Cloudflare DNS-01 API 验证并签发证书..."
      ~/.acme.sh/acme.sh --issue --dns dns_cf -d "$DOMAIN" --keylength ec-256 --force >/dev/null 2>&1 || true
    else
      info "正在通过 Standalone HTTP-01 独立验证签发证书..."
      # 提前放行 80 端口用于 standalone 验证
      command -v iptables >/dev/null 2>&1 && iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true
      command -v ufw >/dev/null 2>&1 && ufw allow 80/tcp >/dev/null 2>&1 || true
      command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --add-port=80/tcp >/dev/null 2>&1 || true
      ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force >/dev/null 2>&1 || true
    fi

    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
      --fullchain-file "$CERT_PATH" --key-file "$KEY_PATH" >/dev/null 2>&1 || true

    if [[ ! -s "$CERT_PATH" ]]; then
      warn "ACME 证书签发未成功（请检查域名解析或 Token 权限），自动降级为自签证书确保节点可用"
      CERT_INSECURE=1
      SNI_HOST="www.bing.com"
      openssl req -new -x509 -days 3650 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=${SNI_HOST}" >/dev/null 2>&1 || true
    else
      ok "ACME 域名证书申请成功！(${DOMAIN})"
    fi
  fi
  chmod 644 "$CERT_PATH" "$KEY_PATH" >/dev/null 2>&1 || true
fi

# ==============================================================================
# [6/10] Cloudflare WARP 智能分流设置
# ==============================================================================
echo -e "\n${YELLOW}[6/10] Cloudflare WARP 智能分流设置...${PLAIN}"
echo -e "说明：开启后仅将 ChatGPT、Claude、Gemini、Netflix 等 AI 与流媒体域名走 WARP 出口，解锁风控，其他流量保持 VPS 原生千兆直连！"
ENABLE_WARP=0
if [[ "${AUTO_INSTALL:-0}" -eq 1 ]]; then
  ENABLE_WARP="${SB_ENABLE_WARP:-${ENABLE_WARP:-0}}"
else
  read -r -p "是否启用 WARP 智能分流? [y/N] (默认 N): " ANS_WARP || true
  [[ "$ANS_WARP" =~ ^[Yy]$ ]] && ENABLE_WARP=1
fi

WARP_CFG_READY=0
WARP_PRIV=""
WARP_PUB="bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
WARP_V4="172.16.0.2"
WARP_V6=""
WARP_RESERVED="[0,0,0]"
WARP_EP="162.159.192.1"
WARP_EP_PORT=2408

if [[ "$ENABLE_WARP" -eq 1 ]]; then
  info "正在检测/注册 Cloudflare WARP 凭据..."
  # 如果已有旧配置则复用
  if [[ -f "$CONF_DIR/warp/warp.json" ]] && jq -e . "$CONF_DIR/warp/warp.json" >/dev/null 2>&1; then
    WARP_PRIV="$(jq -r .private_key "$CONF_DIR/warp/warp.json")"
    WARP_V4="$(jq -r .v4 "$CONF_DIR/warp/warp.json")"
    WARP_V6="$(jq -r .v6 "$CONF_DIR/warp/warp.json")"
    WARP_RESERVED="$(jq -r .reserved "$CONF_DIR/warp/warp.json")"
    WARP_CFG_READY=1
    ok "检测到现有 WARP 凭据，已直接复用"
  else
    # 尝试直接通过 Cloudflare 官方 API 注册
    TMP_KEY="$(openssl genpkey -algorithm X25519 -outform DER 2>/dev/null | tail -c 32 | base64 2>/dev/null || true)"
    TMP_PUB="$(echo -n "$TMP_KEY" | base64 -d 2>/dev/null | openssl pkey -inform DER -pubout -outform DER 2>/dev/null | tail -c 32 | base64 2>/dev/null || true)"

    if [[ -n "$TMP_KEY" && -n "$TMP_PUB" ]]; then
      REG_RES="$(curl -s -X POST -H 'Content-Type: application/json' -H 'User-Agent: okhttp/3.12.1' \
        -d "{\"key\":\"${TMP_PUB}\",\"install_id\":\"\",\"fcm_token\":\"\",\"tos\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"model\":\"PC\",\"serial_number\":\"\",\"locale\":\"en_US\"}" \
        "https://api.cloudflareclient.com/v0a3371/reg" 2>/dev/null || true)"

      if echo "$REG_RES" | grep -q "config"; then
        WARP_PRIV="$TMP_KEY"
        WARP_V4="$(echo "$REG_RES" | jq -r .result.config.interface.addresses.v4 2>/dev/null || echo "172.16.0.2")"
        WARP_V6="$(echo "$REG_RES" | jq -r .result.config.interface.addresses.v6 2>/dev/null || echo "")"
        cid="$(echo "$REG_RES" | jq -r .result.config.client_id 2>/dev/null || true)"
        if [[ -n "$cid" && "$cid" != "null" ]]; then
          # 解析保留字段
          r1=$(echo "$cid" | base64 -d 2>/dev/null | od -An -tu1 2>/dev/null | awk '{print $1,$2,$3}' || echo "0 0 0")
          WARP_RESERVED="[$(echo $r1 | tr ' ' ',')]"
        fi
        cat > "$CONF_DIR/warp/warp.json" <<EOF
{
  "private_key": "${WARP_PRIV}",
  "v4": "${WARP_V4}",
  "v6": "${WARP_V6}",
  "reserved": "${WARP_RESERVED}"
}
EOF
        WARP_CFG_READY=1
        ok "Cloudflare WARP 官方 API 注册成功！"
      fi
    fi
  fi

  if [[ "$WARP_CFG_READY" -ne 1 ]]; then
    warn "WARP 自动注册未连通 Cloudflare API，已跳过 WARP 分流，所有流量将走 VPS 原生网络"
    ENABLE_WARP=0
  fi
else
  info "已跳过 WARP 智能分流配置，所有流量走 VPS 原生网络"
fi

# ==============================================================================
# [6.5/10] Cloudflare Argo 隧道设置 (可选)
# ==============================================================================
echo -e "\n${YELLOW}[6.5/10] Cloudflare Argo 隧道设置 (免开端口 / CDN 穿透)...${PLAIN}"
echo -e "说明：如使用 Cloudflare Tunnel，可输入 Token 和已在 CF 绑定的域名；不需要请直接回车跳过。"
ARGO_TOKEN=""
ARGO_DOMAIN=""
ARGO_PORT=10086
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" >/dev/null 2>&1 || true
  ARGO_TOKEN="${SB_ARGO_TOKEN:-}"
  ARGO_DOMAIN="${SB_ARGO_DOMAIN:-}"
fi

if [[ "${AUTO_INSTALL:-0}" -eq 1 ]]; then
  ARGO_TOKEN="${SB_ARGO_TOKEN:-${ARGO_TOKEN:-}}"
  ARGO_DOMAIN="${SB_ARGO_DOMAIN:-${ARGO_DOMAIN:-}}"
  [[ -z "$ARGO_DOMAIN" ]] && ARGO_TOKEN=""
elif [[ -n "${ARGO_TOKEN:-}" && -n "${ARGO_DOMAIN:-}" ]]; then
  echo -e "检测到现有 Argo 隧道配置 (域名: ${GREEN}${ARGO_DOMAIN}${PLAIN})"
  read -r -p "是否保留此 Argo 隧道? [Y/n/修改] (默认 Y): " REUSE_ARGO || true
  if [[ "$REUSE_ARGO" =~ ^[Nn]$ ]]; then
    ARGO_TOKEN=""
    ARGO_DOMAIN=""
    info "已关闭 Argo 隧道"
  elif [[ "$REUSE_ARGO" =~ ^[CcMm]$ ]]; then
    read -r -p "请输入新的 Cloudflare Argo Token: " INPUT_ARGO_TOKEN || true
    read -r -p "请输入新的绑定的 Argo 域名: " INPUT_ARGO_DOMAIN || true
    ARGO_TOKEN="$INPUT_ARGO_TOKEN"
    ARGO_DOMAIN="$INPUT_ARGO_DOMAIN"
    [[ -z "$ARGO_DOMAIN" ]] && ARGO_TOKEN=""
  else
    ok "已保留现有 Argo 隧道: ${ARGO_DOMAIN}"
  fi
else
  read -r -p "Cloudflare Argo Token (直接回车跳过): " INPUT_ARGO_TOKEN || true
  if [[ -n "${INPUT_ARGO_TOKEN:-}" ]]; then
    ARGO_TOKEN="$INPUT_ARGO_TOKEN"
    read -r -p "请输入绑定的 Argo 域名: " INPUT_ARGO_DOMAIN || true
    ARGO_DOMAIN="$INPUT_ARGO_DOMAIN"
    [[ -z "$ARGO_DOMAIN" ]] && ARGO_TOKEN=""
  fi
fi

if [[ -n "${ARGO_TOKEN:-}" ]]; then
  if [[ "$ARGO_TOKEN" =~ eyJ ]]; then
    ARGO_TOKEN="eyJ${ARGO_TOKEN#*eyJ}"
    ARGO_TOKEN=$(echo "$ARGO_TOKEN" | awk '{print $1}' | tr -d '"'\''`;')
  fi
fi

if [[ -n "${ARGO_TOKEN:-}" && -n "${ARGO_DOMAIN:-}" ]]; then
  ok "Argo 隧道已配置: 域名 ${ARGO_DOMAIN}"
else
  info "已跳过 Argo 隧道配置"
fi

# ==============================================================================
# [7/10] 安装/更新 Sing-box 核心
# ==============================================================================
echo -e "\n${YELLOW}[7/10] 安装/校验 Sing-box 核心程序...${PLAIN}"
if [[ ! -x "$INSTALL_PATH" ]]; then
  update_core
else
  ok "Sing-box 核心已存在 ($($INSTALL_PATH version 2>/dev/null | head -n1 || echo '已就绪'))"
fi

# ==============================================================================
# [8/10] 凭证复用与生成主配置文件 config.json
# ==============================================================================
echo -e "${YELLOW}[8/10] 生成 Sing-box 核心极速配置文件 (config.json)...${PLAIN}"

# 凭据复用或生成
UUID=""; TUIC_UUID=""
HY2_PASS=""; TUIC_PASS=""
R_PRI=""; R_PUB=""; SHORT_ID=""

if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" >/dev/null 2>&1 || true
  UUID="${SB_UUID:-}"
  TUIC_UUID="${SB_TUIC_UUID:-}"
  HY2_PASS="${SB_HY2_PASS:-}"
  TUIC_PASS="${SB_TUIC_PASS:-}"
  R_PRI="${SB_REALITY_PRI:-}"
  R_PUB="${SB_REALITY_PUB:-}"
  SHORT_ID="${SB_SHORT_ID:-}"
fi

[[ -z "$UUID" ]] && UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)"
[[ -z "$TUIC_UUID" ]] && TUIC_UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)"
[[ -z "$HY2_PASS" ]] && HY2_PASS="$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20)"
[[ -z "$TUIC_PASS" ]] && TUIC_PASS="$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20)"
[[ -z "$SHORT_ID" ]] && SHORT_ID="$(openssl rand -hex 8)"

if [[ -z "$R_PRI" || -z "$R_PUB" ]]; then
  KEYPAIR="$($INSTALL_PATH generate reality-keypair 2>&1 || true)"
  R_PRI="$(echo "$KEYPAIR" | grep -i "PrivateKey" | awk '{print $2}' || true)"
  R_PUB="$(echo "$KEYPAIR" | grep -i "PublicKey" | awk '{print $2}' || true)"
  if [[ -z "$R_PRI" || -z "$R_PUB" ]]; then
    # 备用匹配
    R_PRI="$(echo "$KEYPAIR" | grep -i "Private" | awk '{print $2}' || true)"
    R_PUB="$(echo "$KEYPAIR" | grep -i "Public" | awk '{print $2}' || true)"
  fi
fi

# 构建 inbounds 数组
INBOUNDS_JSON="[]"

if [[ "$ENABLE_REALITY" -eq 1 ]]; then
  INBOUNDS_JSON="$(echo "$INBOUNDS_JSON" | jq --arg uuid "$UUID" --arg sid "$SHORT_ID" --arg pri "$R_PRI" \
    --arg sni "$REALITY_SNI" --arg hs "$REALITY_HS_SERVER" --argjson hsport "$REALITY_HS_PORT" \
    --argjson p4 "$P_REALITY_V4" --argjson p6 "$P_REALITY_V6" --arg mode "$OUT_MODE" '
    if $mode == "both" then
      . + [
        {
          "type": "vless",
          "tag": "vless-reality-v4",
          "listen": "0.0.0.0",
          "listen_port": $p4,
          "tcp_fast_open": true,
          "users": [{ "uuid": $uuid, "flow": "xtls-rprx-vision" }],
          "tls": {
            "enabled": true,
            "server_name": $sni,
            "reality": {
              "enabled": true,
              "handshake": { "server": $hs, "server_port": $hsport },
              "private_key": $pri,
              "short_id": [$sid]
            }
          }
        },
        {
          "type": "vless",
          "tag": "vless-reality-v6",
          "listen": "::",
          "listen_port": $p6,
          "tcp_fast_open": true,
          "users": [{ "uuid": $uuid, "flow": "xtls-rprx-vision" }],
          "tls": {
            "enabled": true,
            "server_name": $sni,
            "reality": {
              "enabled": true,
              "handshake": { "server": $hs, "server_port": $hsport },
              "private_key": $pri,
              "short_id": [$sid]
            }
          }
        }
      ]
    else
      . + [
        {
          "type": "vless",
          "tag": "vless-reality",
          "listen": (if $mode == "ipv6" then "::" else "0.0.0.0" end),
          "listen_port": $p4,
          "tcp_fast_open": true,
          "users": [{ "uuid": $uuid, "flow": "xtls-rprx-vision" }],
          "tls": {
            "enabled": true,
            "server_name": $sni,
            "reality": {
              "enabled": true,
              "handshake": { "server": $hs, "server_port": $hsport },
              "private_key": $pri,
              "short_id": [$sid]
            }
          }
        }
      ]
    end
  ')"
fi

if [[ "$ENABLE_HY2" -eq 1 ]]; then
  INBOUNDS_JSON="$(echo "$INBOUNDS_JSON" | jq --arg pwd "$HY2_PASS" --arg cert "$CERT_PATH" --arg key "$KEY_PATH" \
    --argjson p4 "$P_HY2_V4" --argjson p6 "$P_HY2_V6" --arg mode "$OUT_MODE" '
    if $mode == "both" then
      . + [
        {
          "type": "hysteria2",
          "tag": "hy2-in-v4",
          "listen": "0.0.0.0",
          "listen_port": $p4,
          "users": [{ "password": $pwd }],
          "ignore_client_bandwidth": false,
          "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cert, "key_path": $key }
        },
        {
          "type": "hysteria2",
          "tag": "hy2-in-v6",
          "listen": "::",
          "listen_port": $p6,
          "users": [{ "password": $pwd }],
          "ignore_client_bandwidth": false,
          "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cert, "key_path": $key }
        }
      ]
    else
      . + [
        {
          "type": "hysteria2",
          "tag": "hy2-in",
          "listen": (if $mode == "ipv6" then "::" else "0.0.0.0" end),
          "listen_port": $p4,
          "users": [{ "password": $pwd }],
          "ignore_client_bandwidth": false,
          "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cert, "key_path": $key }
        }
      ]
    end
  ')"
fi

if [[ "$ENABLE_TUIC" -eq 1 ]]; then
  INBOUNDS_JSON="$(echo "$INBOUNDS_JSON" | jq --arg uuid "$TUIC_UUID" --arg pwd "$TUIC_PASS" \
    --arg cert "$CERT_PATH" --arg key "$KEY_PATH" \
    --argjson p4 "$P_TUIC_V4" --argjson p6 "$P_TUIC_V6" --arg mode "$OUT_MODE" '
    if $mode == "both" then
      . + [
        {
          "type": "tuic",
          "tag": "tuic-in-v4",
          "listen": "0.0.0.0",
          "listen_port": $p4,
          "users": [{ "uuid": $uuid, "password": $pwd }],
          "congestion_control": "bbr",
          "zero_rtt_handshake": true,
          "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cert, "key_path": $key }
        },
        {
          "type": "tuic",
          "tag": "tuic-in-v6",
          "listen": "::",
          "listen_port": $p6,
          "users": [{ "uuid": $uuid, "password": $pwd }],
          "congestion_control": "bbr",
          "zero_rtt_handshake": true,
          "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cert, "key_path": $key }
        }
      ]
    else
      . + [
        {
          "type": "tuic",
          "tag": "tuic-in",
          "listen": (if $mode == "ipv6" then "::" else "0.0.0.0" end),
          "listen_port": $p4,
          "users": [{ "uuid": $uuid, "password": $pwd }],
          "congestion_control": "bbr",
          "zero_rtt_handshake": true,
          "tls": { "enabled": true, "alpn": ["h3"], "certificate_path": $cert, "key_path": $key }
        }
      ]
    end
  ')"
fi

# 构建 outbounds 数组 (纯原生直连与用户态 WireGuard，无需创建系统网卡)
OUTBOUNDS_JSON="[]"

if [[ "$OUT_MODE" == "both" ]]; then
  OUTBOUNDS_JSON="$(echo "$OUTBOUNDS_JSON" | jq --arg v4 "$LOCAL_IPV4" --arg v6 "$LOCAL_IPV6" '
    . + [
      { "type": "direct", "tag": "direct-v4", "inet4_bind_address": $v4 },
      { "type": "direct", "tag": "direct-v6", "inet6_bind_address": $v6 },
      { "type": "block", "tag": "block" }
    ]
  ')"
else
  OUTBOUNDS_JSON="$(echo "$OUTBOUNDS_JSON" | jq --arg v4 "$LOCAL_IPV4" --arg v6 "$LOCAL_IPV6" --arg mode "$OUT_MODE" '
    . + [
      {
        "type": "direct",
        "tag": "direct",
        "inet4_bind_address": (if $mode == "ipv4" then $v4 else null end),
        "inet6_bind_address": (if $mode == "ipv6" then $v6 else null end)
      },
      { "type": "block", "tag": "block" }
    ]
  ')"
fi

if [[ "$ENABLE_WARP" -eq 1 && "$WARP_CFG_READY" -eq 1 ]]; then
  OUTBOUNDS_JSON="$(echo "$OUTBOUNDS_JSON" | jq --arg priv "$WARP_PRIV" --arg pub "$WARP_PUB" \
    --arg v4 "$WARP_V4" --arg v6 "$WARP_V6" --arg ep "$WARP_EP" --argjson port "$WARP_EP_PORT" \
    --argjson res "$WARP_RESERVED" '
    . + [
      {
        "type": "wireguard",
        "tag": "warp-out",
        "server": $ep,
        "server_port": $port,
        "local_address": (if $v6 != "" then [($v4 + "/32"), ($v6 + "/128")] else [($v4 + "/32")] end),
        "private_key": $priv,
        "peer_public_key": $pub,
        "reserved": $res
      }
    ]
  ')"
fi

# 构建 route rules
RULES_JSON="[]"
if [[ "$ENABLE_WARP" -eq 1 && "$WARP_CFG_READY" -eq 1 ]]; then
  WARP_DOMAINS_JSON="$(printf '%s\n' "${WARP_AI_DOMAINS[@]}" | jq -R . | jq -s .)"
  RULES_JSON="$(echo "$RULES_JSON" | jq --argjson doms "$WARP_DOMAINS_JSON" '
    . + [{ "domain_suffix": $doms, "outbound": "warp-out" }]
  ')"
fi

if [[ "$OUT_MODE" == "both" ]]; then
  RULES_JSON="$(echo "$RULES_JSON" | jq '
    . + [
      { "inbound": ["vless-reality-v4", "hy2-in-v4", "tuic-in-v4"], "outbound": "direct-v4" },
      { "inbound": ["vless-reality-v6", "hy2-in-v6", "tuic-in-v6"], "outbound": "direct-v6" }
    ]
  ')"
fi

FINAL_OUT="direct"
[[ "$OUT_MODE" == "both" ]] && FINAL_OUT="direct-v4"

if [[ -n "${ARGO_TOKEN:-}" && -n "${ARGO_DOMAIN:-}" ]]; then
  INBOUNDS_JSON="$(echo "$INBOUNDS_JSON" | jq --arg uuid "$UUID" --argjson port "$ARGO_PORT" '
    . + [
      {
        "type": "vless",
        "tag": "vless-argo-in",
        "listen": "127.0.0.1",
        "listen_port": $port,
        "users": [{ "uuid": $uuid }],
        "transport": {
          "type": "ws",
          "path": "/argo"
        }
      }
    ]
  ')"
  RULES_JSON="$(echo "$RULES_JSON" | jq --arg final "$FINAL_OUT" '
    . + [
      { "inbound": ["vless-argo-in"], "outbound": $final }
    ]
  ')"
fi

# 整合最终配置 (带极速本地内存 DNS 缓存)
FINAL_CONFIG="$(jq -n \
  --argjson inbounds "$INBOUNDS_JSON" \
  --argjson outbounds "$OUTBOUNDS_JSON" \
  --argjson rules "$RULES_JSON" \
  --arg final_out "$FINAL_OUT" \
  '{
    "log": {
      "level": "warn",
      "timestamp": true
    },
    "dns": {
      "servers": [
        {
          "tag": "dns-remote",
          "type": "tls",
          "server": "1.1.1.1"
        },
        {
          "tag": "dns-direct",
          "type": "udp",
          "server": "1.1.1.1"
        },
        {
          "tag": "dns-local",
          "type": "local"
        }
      ],
      "strategy": "prefer_ipv4"
    },
    "inbounds": $inbounds,
    "outbounds": $outbounds,
    "route": {
      "auto_detect_interface": true,
      "default_domain_resolver": "dns-remote",
      "rules": $rules,
      "final": $final_out
    }
  }'
)"

echo "$FINAL_CONFIG" > "$CONF_DIR/config.json"
chown root:root "$CONF_DIR/config.json" >/dev/null 2>&1 || true
chmod 644 "$CONF_DIR/config.json" >/dev/null 2>&1 || true

# 验证生成的 JSON
if ! "$INSTALL_PATH" check -c "$CONF_DIR/config.json"; then
  err "Sing-box 配置文件语法校验失败，请检查配置！"
  exit 1
fi
ok "配置文件 /etc/sing-box/config.json 生成完毕并通过语法校验"

# ==============================================================================
# [9/10] 端口跳跃脚本、防火墙放行与内核提速应用
# ==============================================================================
echo -e "${YELLOW}[9/10] 配置防火墙放行、端口跳跃与内核极速参数...${PLAIN}"

# 生成端口跳跃脚本
cat > "$HOP_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -u
CONF="/etc/sing-box/.sb_state"
[[ -f "$CONF" ]] && source "$CONF"

HOP="${SB_HOP_RANGE:-}"
P4="${SB_HY2_P4:-0}"
P6="${SB_HY2_P6:-0}"
MODE="${SB_OUT_MODE:-ipv4}"

# 无论开启与否，先清理旧链以保证幂等与规则刷新
if command -v iptables >/dev/null 2>&1; then
  iptables -t nat -D PREROUTING -p udp -j SB_HOP >/dev/null 2>&1 || true
  iptables -t nat -F SB_HOP >/dev/null 2>&1 || true
fi
if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -t nat -D PREROUTING -p udp -j SB_HOP6 >/dev/null 2>&1 || true
  ip6tables -t nat -F SB_HOP6 >/dev/null 2>&1 || true
fi

[[ -z "$HOP" ]] && exit 0

# IPv4 跳跃端口 NAT REDIRECT
if [[ "$P4" -ne 0 ]] && command -v iptables >/dev/null 2>&1; then
  iptables -t nat -N SB_HOP 2>/dev/null || iptables -t nat -F SB_HOP
  R_IPT="${HOP//-/:}"
  if [[ "$R_IPT" == *","* ]]; then
    iptables -t nat -A SB_HOP -p udp -m multiport --dports "$R_IPT" -j REDIRECT --to-ports "$P4" 2>/dev/null || true
  else
    iptables -t nat -A SB_HOP -p udp --dport "$R_IPT" -j REDIRECT --to-ports "$P4" 2>/dev/null || true
  fi
  iptables -t nat -C PREROUTING -p udp -j SB_HOP 2>/dev/null || iptables -t nat -A PREROUTING -p udp -j SB_HOP 2>/dev/null || true
fi

# IPv6 跳跃端口 NAT REDIRECT (支持 ipv6 单栈及 both 双栈)
if [[ "$P6" -ne 0 && ( "$MODE" == "ipv6" || "$MODE" == "both" ) ]] && command -v ip6tables >/dev/null 2>&1; then
  ip6tables -t nat -N SB_HOP6 2>/dev/null || ip6tables -t nat -F SB_HOP6
  R6_IPT="${HOP//-/:}"
  if [[ "$R6_IPT" == *","* ]]; then
    ip6tables -t nat -A SB_HOP6 -p udp -m multiport --dports "$R6_IPT" -j REDIRECT --to-ports "$P6" 2>/dev/null || true
  else
    ip6tables -t nat -A SB_HOP6 -p udp --dport "$R6_IPT" -j REDIRECT --to-ports "$P6" 2>/dev/null || true
  fi
  ip6tables -t nat -C PREROUTING -p udp -j SB_HOP6 2>/dev/null || ip6tables -t nat -A PREROUTING -p udp -j SB_HOP6 2>/dev/null || true
fi
EOF
chmod +x "$HOP_SCRIPT"

# 放行防火墙端口
TCP_ALLOW=""
UDP_ALLOW=""
[[ "$ENABLE_REALITY" -eq 1 ]] && TCP_ALLOW="${P_REALITY_V4} $([[ "$OUT_MODE" == "both" ]] && echo "$P_REALITY_V6")"
[[ "$ENABLE_HY2" -eq 1 ]] && UDP_ALLOW="${UDP_ALLOW} ${P_HY2_V4} $([[ "$OUT_MODE" == "both" ]] && echo "$P_HY2_V6")"
[[ "$ENABLE_TUIC" -eq 1 ]] && UDP_ALLOW="${UDP_ALLOW} ${P_TUIC_V4} $([[ "$OUT_MODE" == "both" ]] && echo "$P_TUIC_V6")"

fw_allow_ports "$TCP_ALLOW" "$UDP_ALLOW" "$HOP_RANGE"
apply_tuning

# 执行一次端口跳跃挂载
if [[ -n "$HOP_RANGE" ]]; then
  /usr/local/bin/sb-hop.sh >/dev/null 2>&1 || true
fi

# 配置与启动 Cloudflare Argo 隧道 (cloudflared)
if [[ -n "${ARGO_TOKEN:-}" && -n "${ARGO_DOMAIN:-}" ]]; then
  info "正在配置 Cloudflare Argo 隧道 (cloudflared)..."
  local_arch="$(_arch_norm)"
  if ! command -v cloudflared >/dev/null 2>&1; then
    wget -q -O /usr/local/bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${local_arch}" || true
    chmod +x /usr/local/bin/cloudflared >/dev/null 2>&1 || true
  fi
  if command -v cloudflared >/dev/null 2>&1; then
    if has_systemd; then
      cloudflared service install "$ARGO_TOKEN" >/dev/null 2>&1 || true
      mkdir -p /etc/systemd/system/cloudflared.service.d >/dev/null 2>&1 || true
      cat > /etc/systemd/system/cloudflared.service.d/override.conf <<EOF
[Service]
Type=simple
TimeoutStartSec=0
ExecStart=
ExecStart=/usr/local/bin/cloudflared --no-autoupdate tunnel run --protocol http2 --token ${ARGO_TOKEN}
Restart=on-failure
RestartSec=5s
EOF
      systemctl daemon-reload >/dev/null 2>&1 || true
      systemctl restart cloudflared >/dev/null 2>&1 || true
      systemctl enable cloudflared >/dev/null 2>&1 || true
    elif has_openrc; then
      cat > /etc/init.d/cloudflared <<EOF
#!/sbin/openrc-run
name="cloudflared"
command="/usr/local/bin/cloudflared"
command_args="tunnel run --protocol http2 --token ${ARGO_TOKEN}"
command_background=true
pidfile="/run/cloudflared.pid"
depend() { need net; }
EOF
      chmod +x /etc/init.d/cloudflared
      rc-update add cloudflared default >/dev/null 2>&1 || true
      rc-service cloudflared restart >/dev/null 2>&1 || true
    fi
    ok "Cloudflare Argo 隧道守护进程已配置启动！"
  fi
fi

# 保存状态文件
cat > "$STATE_FILE" <<EOF
SB_OUT_MODE="${OUT_MODE}"
SB_IPV4="${IPV4}"
SB_IPV6="${IPV6}"
SB_UUID="${UUID}"
SB_TUIC_UUID="${TUIC_UUID}"
SB_HY2_PASS="${HY2_PASS}"
SB_TUIC_PASS="${TUIC_PASS}"
SB_REALITY_PRI="${R_PRI}"
SB_REALITY_PUB="${R_PUB}"
SB_SHORT_ID="${SHORT_ID}"
SB_REALITY_SNI="${REALITY_SNI}"
SB_REALITY_HS="${REALITY_HS_SERVER}"
SB_SNI_HOST="${SNI_HOST}"
SB_CERT_INSECURE="${CERT_INSECURE}"
SB_ENABLE_REALITY="${ENABLE_REALITY}"
SB_ENABLE_HY2="${ENABLE_HY2}"
SB_ENABLE_TUIC="${ENABLE_TUIC}"
SB_REALITY_P4="${P_REALITY_V4}"
SB_REALITY_P6="${P_REALITY_V6}"
SB_HY2_P4="${P_HY2_V4}"
SB_HY2_P6="${P_HY2_V6}"
SB_TUIC_P4="${P_TUIC_V4}"
SB_TUIC_P6="${P_TUIC_V6}"
SB_HOP_RANGE="${HOP_RANGE}"
SB_ENABLE_WARP="${ENABLE_WARP}"
SB_ACME_MODE="${ACME_MODE:-}"
SB_CF_TOKEN="${CF_TOKEN:-}"
SB_ARGO_TOKEN="${ARGO_TOKEN:-}"
SB_ARGO_DOMAIN="${ARGO_DOMAIN:-}"
SB_ARGO_PORT="${ARGO_PORT:-10086}"
EOF
chmod 600 "$STATE_FILE"

# ==============================================================================
# [10/10] 注册系统服务并配置快捷管理命令 (sb)
# ==============================================================================
echo -e "${YELLOW}[10/10] 注册系统服务并配置快捷管理命令 (sb)...${PLAIN}"

if has_systemd; then
  cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-box Service (High Performance)
After=network.target nss-lookup.target

[Service]
User=root
Group=root
LimitNOFILE=1048576
ExecStartPre=-/usr/local/bin/sb-hop.sh
ExecStart=${INSTALL_PATH} run -c ${CONF_DIR}/config.json
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
elif has_openrc; then
  cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
name="sing-box"
command="${INSTALL_PATH}"
command_args="run -c ${CONF_DIR}/config.json"
command_background=true
pidfile="/run/sing-box.pid"
rc_ulimit="-n 1048576"
start_pre() { /usr/local/bin/sb-hop.sh >/dev/null 2>&1 || true; }
depend() { need net; }
EOF
  chmod +x /etc/init.d/sing-box
fi

service_enable_restart

# 生成 /usr/local/bin/sb 查看命令
generate_shortcut_script

echo -e "\n${GREEN}=== 部署完成！Sing-box 极速服务已在后台稳定运行 ===${PLAIN}"
echo -e ">>> 随时输入 ${GREEN}sb${PLAIN} 查看所有节点链接与 Mihomo 配置！\n"
"$SHORTCUT_BIN"

# 提示是否推送到节点管理平台 (cf-node-manager-plus)
echo -e "${BLUE}==============================================================${PLAIN}"
echo -e "${BLUE}        🚀 自动推送到节点管理平台 (cf-node-manager-plus)       ${PLAIN}"
echo -e "${BLUE}==============================================================${PLAIN}"
if [[ "${AUTO_INSTALL:-0}" -eq 1 ]]; then
  if [[ "${AUTO_PUSH:-1}" -eq 1 && -n "${PUSH_URL:-${SAVED_MGR_URL:-}}" ]]; then
    info "自动部署模式：正在执行节点推送到管理平台..."
    "$SHORTCUT_BIN" push || true
  else
    info "自动部署模式：已跳过节点推送。"
  fi
else
  read -r -p "是否将本次生成的节点自动推送到节点管理面板? [Y/n] (默认: Y): " DO_PUSH
  DO_PUSH="${DO_PUSH:-Y}"
  case "$DO_PUSH" in
    [nN]|[nN][oO])
      echo -e "已跳过自动推送。后续可随时输入 ${GREEN}sb push${PLAIN} 推送节点至管理平台！\n"
      ;;
    *)
      "$SHORTCUT_BIN" push
      ;;
  esac
fi
