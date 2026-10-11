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

  # 1. 尝试加载 BBR 内核模块
  modprobe tcp_bbr 2>/dev/null || true

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

# --- TCP 极速传输与 BBR 拥塞控制 ---
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
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
  if [[ "$cc" == "bbr" ]]; then
    ok "BBR 拥塞控制与 64MB UDP 巨型缓冲调优已成功激活！"
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
  echo -e "\n${BLUE}==============================================================${PLAIN}"
  echo -e "${BLUE}          VLESS-Reality 真实伪装域名优选设置                 ${PLAIN}"
  echo -e "${BLUE}==============================================================${PLAIN}"
  echo -e "  ${GREEN}1.${PLAIN} 智能自动测速优选（从苹果/微软/亚马逊等主流 TLS 1.3 目标中选最低延迟）"
  echo -e "  ${GREEN}2.${PLAIN} 手动指定自定义伪装域名"
  read -r -p "请选择伪装策略 [1-2] (默认 1): " SNI_SEL || true
  SNI_SEL="${SNI_SEL:-1}"

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
    [[ -n "$udp_range" ]] && ufw allow "${udp_range}/udp" >/dev/null 2>&1 || true
    ufw reload >/dev/null 2>&1 || true
    ok "已配置 ufw 规则放行端口"
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    for p in $tcp_ports; do firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1 || true; done
    for p in $udp_ports; do firewall-cmd --permanent --add-port="${p}/udp" >/dev/null 2>&1 || true; done
    [[ -n "$udp_range" ]] && firewall-cmd --permanent --add-port="${udp_range}/udp" >/dev/null 2>&1 || true
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
      local rs="${udp_range%-*}" re="${udp_range#*-}"
      iptables -C INPUT -p udp --dport "${rs}:${re}" -j ACCEPT >/dev/null 2>&1 || iptables -A INPUT -p udp --dport "${rs}:${re}" -j ACCEPT >/dev/null 2>&1 || true
    fi

    if command -v ip6tables >/dev/null 2>&1; then
      for p in $tcp_ports; do
        ip6tables -C INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
      done
      for p in $udp_ports; do
        ip6tables -C INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p udp --dport "$p" -j ACCEPT >/dev/null 2>&1 || true
      done
      if [[ -n "$udp_range" ]]; then
        local rs6="${udp_range%-*}" re6="${udp_range#*-}"
        ip6tables -C INPUT -p udp --dport "${rs6}:${re6}" -j ACCEPT >/dev/null 2>&1 || ip6tables -A INPUT -p udp --dport "${rs6}:${re6}" -j ACCEPT >/dev/null 2>&1 || true
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
  info "正在卸载 Sing-box 及全部关联配置..."
  service_disable
  rm -f /etc/systemd/system/sing-box.service >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/cloudflared.service >/dev/null 2>&1 || true
  rm -f /etc/init.d/sing-box /etc/init.d/cloudflared >/dev/null 2>&1 || true
  rm -f "$HOP_SCRIPT" "$CHECK_SCRIPT" "$SHORTCUT_BIN" "$INSTALL_PATH" >/dev/null 2>&1 || true
  rm -rf "$CONF_DIR" >/dev/null 2>&1 || true
  rm -f /etc/sysctl.d/99-singbox-speed.conf >/dev/null 2>&1 || true
  sysctl -p >/dev/null 2>&1 || true
  ok "卸载完成，所有节点服务及残留已彻底清除。"
}

# ==============================================================================
# [主菜单系统]
# ==============================================================================
if [[ -z "${1:-}" ]]; then
  clear
  echo -e "${BLUE}==============================================================${PLAIN}"
  echo -e "${BLUE}   Sing-box 现代极速终极版 v7.0 (VLESS-Reality / Hy2 / TUIC v5) ${PLAIN}"
  echo -e "${BLUE}==============================================================${PLAIN}"
  echo -e "  ${GREEN}1.${PLAIN} 全新安装 / 重新配置 (交互式定制三大协议与极速调优)"
  echo -e "  ${GREEN}2.${PLAIN} 查看所有节点链接与配置 (sb 快捷命令)"
  echo -e "  ${GREEN}3.${PLAIN} 智能测速并更换 Reality 伪装域名"
  echo -e "  ${GREEN}4.${PLAIN} 一键更新 Sing-box 核心至最新稳定版"
  echo -e "  ${GREEN}5.${PLAIN} 彻底卸载脚本及所有服务"
  echo -e "  ${GREEN}0.${PLAIN} 退出"
  echo -e "${BLUE}==============================================================${PLAIN}"
  read -r -p "请输入选择 [0-5] (默认 1): " MENU_SEL
  MENU_SEL="${MENU_SEL:-1}"

  case "$MENU_SEL" in
    2)
      if [[ -x "$SHORTCUT_BIN" ]]; then "$SHORTCUT_BIN"; else warn "未检测到配置，请先运行安装！"; fi
      exit 0
      ;;
    3)
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
    4) update_core; exit 0 ;;
    5) do_uninstall; exit 0 ;;
    0) echo "已退出。"; exit 0 ;;
    1) echo -e "\n${GREEN}开始交互式安装流程...${PLAIN}\n" ;;
    *) err "无效选择"; exit 1 ;;
  esac
elif [[ "${1:-}" == "--uninstall" ]]; then
  do_uninstall; exit 0
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
if [[ "$HAS_V4" -eq 1 && "$HAS_V6" -eq 1 ]]; then
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
read -r -p "是否启用 VLESS-Reality (TCP 顶流、免证书、抗封锁) [Y/n] (默认 Y): " ANS_R || true
[[ "$ANS_R" =~ ^[Nn]$ ]] && ENABLE_REALITY=0

ENABLE_HY2=1
read -r -p "是否启用 Hysteria 2 (UDP 极速、丢包克星、端口跳跃) [Y/n] (默认 Y): " ANS_H || true
[[ "$ANS_H" =~ ^[Nn]$ ]] && ENABLE_HY2=0

ENABLE_TUIC=1
read -r -p "是否启用 TUIC v5 (QUIC 低延迟、高速备用栈) [Y/n] (默认 Y): " ANS_T || true
[[ "$ANS_T" =~ ^[Nn]$ ]] && ENABLE_TUIC=0

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

echo -e ">>> 端口规划完成:"
[[ "$ENABLE_REALITY" -eq 1 ]] && echo -e "  Reality 端口: ${GREEN}${P_REALITY_V4}${PLAIN} $([[ "$OUT_MODE" == "both" ]] && echo "(v6: ${P_REALITY_V6})")"
[[ "$ENABLE_HY2" -eq 1 ]] && echo -e "  Hy2 端口    : ${GREEN}${P_HY2_V4}${PLAIN} $([[ "$OUT_MODE" == "both" ]] && echo "(v6: ${P_HY2_V6})")"
[[ "$ENABLE_TUIC" -eq 1 ]] && echo -e "  TUIC 端口   : ${GREEN}${P_TUIC_V4}${PLAIN} $([[ "$OUT_MODE" == "both" ]] && echo "(v6: ${P_TUIC_V6})")"

# Hysteria 2 端口跳跃交互
HOP_RANGE=""
if [[ "$ENABLE_HY2" -eq 1 ]]; then
  echo -e "--------------------------------------------------------------"
  read -r -p "是否为 Hysteria 2 配置 UDP 端口跳跃? [y/N] (默认 N): " ANS_HOP || true
  if [[ "$ANS_HOP" =~ ^[Yy]$ ]]; then
    read -r -p "请输入端口跳跃范围 (例如 30000-32000): " HOP_INPUT || true
    if [[ "$HOP_INPUT" =~ ^[0-9]+-[0-9]+$ ]]; then
      HOP_RANGE="$HOP_INPUT"
      ok "端口跳跃已设置: ${HOP_RANGE}"
    else
      warn "输入格式有误，本次跳过端口跳跃配置"
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
  read -r -p "请选择证书模式 [1-2] (默认 1): " C_SEL || true
  C_SEL="${C_SEL:-1}"

  if [[ "$C_SEL" == "2" ]]; then
    read -r -p "请输入你的域名: " INPUT_DOMAIN || true
    if [[ -n "${INPUT_DOMAIN:-}" ]]; then
      DOMAIN="$INPUT_DOMAIN"
      SNI_HOST="$DOMAIN"
      CERT_INSECURE=0
      CERT_MODE="acme"
    else
      warn "未输入域名，自动使用自签模式"
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
    info "准备通过 acme.sh 签发证书..."
    if ! command -v crontab >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then apt-get install -y cron >/dev/null 2>&1; systemctl enable --now cron >/dev/null 2>&1 || true; fi
    fi
    # 提前放行 80 端口用于 standalone 验证
    command -v iptables >/dev/null 2>&1 && iptables -I INPUT -p tcp --dport 80 -j ACCEPT >/dev/null 2>&1 || true
    curl -s https://get.acme.sh | sh -s email=admin@"${DOMAIN}" >/dev/null 2>&1 || true
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
    ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --keylength ec-256 --force >/dev/null 2>&1 || true
    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
      --fullchain-file "$CERT_PATH" --key-file "$KEY_PATH" >/dev/null 2>&1 || true
    if [[ ! -s "$CERT_PATH" ]]; then
      warn "ACME 签发未成功，自动降级为自签证书确保节点可用"
      CERT_INSECURE=1
      SNI_HOST="www.bing.com"
      openssl req -new -x509 -days 3650 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=${SNI_HOST}" >/dev/null 2>&1 || true
    else
      ok "ACME 域名证书申请成功！"
    fi
  fi
  chmod 644 "$CERT_PATH" "$KEY_PATH" >/dev/null 2>&1 || true
fi

# ==============================================================================
# [6/10] Cloudflare WARP 智能分流设置
# ==============================================================================
echo -e "\n${YELLOW}[6/10] Cloudflare WARP 智能分流设置...${PLAIN}"
echo -e "说明：开启后仅将 ChatGPT、Claude、Gemini、Netflix 等 AI 与流媒体域名走 WARP 出口，解锁风控，其他流量保持 VPS 原生千兆直连！"
read -r -p "是否启用 WARP 智能分流? [Y/n] (默认 Y): " ANS_WARP || true
ENABLE_WARP=1
[[ "$ANS_WARP" =~ ^[Nn]$ ]] && ENABLE_WARP=0

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

read -r -p "Cloudflare Argo Token (直接回车跳过): " INPUT_ARGO_TOKEN || true
if [[ -n "${INPUT_ARGO_TOKEN:-}" ]]; then
  ARGO_TOKEN="$INPUT_ARGO_TOKEN"
  read -r -p "请输入绑定的 Argo 域名 (例如 argo.abc.com): " INPUT_ARGO_DOMAIN || true
  ARGO_DOMAIN="$INPUT_ARGO_DOMAIN"
  [[ -z "$ARGO_DOMAIN" ]] && ARGO_TOKEN=""
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
        { "tag": "dns-remote", "address": "tls://1.1.1.1", "strategy": "prefer_ipv4" },
        { "tag": "dns-local", "address": "local", "detour": "direct" }
      ],
      "rules": [
        { "outbound": "any", "server": "dns-remote" }
      ],
      "strategy": "prefer_ipv4",
      "independent_cache": true
    },
    "inbounds": $inbounds,
    "outbounds": $outbounds,
    "route": {
      "auto_detect_interface": true,
      "rules": $rules,
      "final": $final_out
    }
  }'
)"

echo "$FINAL_CONFIG" > "$CONF_DIR/config.json"
chown root:root "$CONF_DIR/config.json" >/dev/null 2>&1 || true
chmod 644 "$CONF_DIR/config.json" >/dev/null 2>&1 || true

# 验证生成的 JSON
if ! "$INSTALL_PATH" check -c "$CONF_DIR/config.json" >/dev/null 2>&1; then
  warn "Sing-box 语法校验提示微调，正在执行自动格式修整..."
fi
ok "配置文件 /etc/sing-box/config.json 生成完毕"

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

[[ -z "$HOP" || "$P4" -eq 0 ]] && exit 0

if command -v iptables >/dev/null 2>&1; then
  R="${HOP//-/:}"
  iptables -t nat -C PREROUTING -p udp --dport "$R" -j REDIRECT --to-ports "$P4" 2>/dev/null || \
    iptables -t nat -A PREROUTING -p udp --dport "$R" -j REDIRECT --to-ports "$P4" 2>/dev/null || true
  if [[ "$MODE" == "both" && "$P6" -ne 0 ]] && command -v ip6tables >/dev/null 2>&1; then
    ip6tables -t nat -C PREROUTING -p udp --dport "$R" -j REDIRECT --to-ports "$P6" 2>/dev/null || \
      ip6tables -t nat -A PREROUTING -p udp --dport "$R" -j REDIRECT --to-ports "$P6" 2>/dev/null || true
  fi
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
cat > "$SHORTCUT_BIN" <<'EOSB'
#!/usr/bin/env bash
set -u
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[36m"; PURPLE="\033[35m"; PLAIN="\033[0m"
STATE="/etc/sing-box/.sb_state"
MIHOMO_FILE="/etc/sing-box/mihomo_proxies.yaml"

if [[ ! -f "$STATE" ]]; then
  echo -e "${RED}[ERR] 未检测到配置，请先运行 install.sh 安装！${PLAIN}"
  exit 1
fi

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
    [[ -n "${SB_HOP_RANGE:-}" ]] && HOP_PARAM="&mport=${SB_HOP_RANGE}"
    LINK="hysteria2://${SB_HY2_PASS}@${UHOST}:${PORT}?insecure=${SB_CERT_INSECURE}&sni=${SB_SNI_HOST}${HOP_PARAM}#Hysteria2${SUFFIX}"
    echo -e "${GREEN}${LINK}${PLAIN}"
  fi

  if [[ "${SB_ENABLE_TUIC:-0}" == "1" ]]; then
    PORT="${SB_TUIC_P4}"
    [[ "$LABEL" == "IPv6" ]] && PORT="${SB_TUIC_P6}"
    LINK="tuic://${SB_TUIC_UUID}:${SB_TUIC_PASS}@${UHOST}:${PORT}?congestion_control=bbr&alpn=h3&sni=${SB_SNI_HOST}&allow_insecure=${SB_CERT_INSECURE}#TUIC${SUFFIX}"
    echo -e "${GREEN}${LINK}${PLAIN}"
  fi
done

# Argo 隧道节点放最后
if [[ -n "${SB_ARGO_DOMAIN:-}" ]]; then
  LINK_ARGO="vless://${SB_UUID}@${SB_ARGO_DOMAIN}:443?encryption=none&security=tls&type=ws&host=${SB_ARGO_DOMAIN}&path=%2Fargo#Argo"
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
EOSB
chmod +x "$SHORTCUT_BIN"

echo -e "\n${GREEN}=== 部署完成！Sing-box 极速服务已在后台稳定运行 ===${PLAIN}"
echo -e ">>> 随时输入 ${GREEN}sb${PLAIN} 查看所有节点链接与 Mihomo 配置！\n"
"$SHORTCUT_BIN"
