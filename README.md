# 🚀 Sing-box 现代极速终极版 v7.0

[![GitHub Release](https://img.shields.io/github/v/release/kzhx666/sb-install-plus?style=for-the-badge&logo=github&color=blue)](https://github.com/kzhx666/sb-install-plus/releases)
[![GitHub Stars](https://img.shields.io/github/stars/kzhx666/sb-install-plus?style=for-the-badge&logo=github&color=yellow)](https://github.com/kzhx666/sb-install-plus/stargazers)
[![GitHub License](https://img.shields.io/github/license/kzhx666/sb-install-plus?style=for-the-badge&logo=opensourceinitiative&color=green)](https://github.com/kzhx666/sb-install-plus/blob/main/LICENSE)
[![Shell Script](https://img.shields.io/badge/Shell-100%25-brightgreen?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Sing-Box](https://img.shields.io/badge/Sing--Box-latest-blue?style=for-the-badge&logo=go&logoColor=white)](https://github.com/SagerNet/sing-box)

---

> **专为高性能代理打造：精简聚焦现代黄金三大协议 (VLESS-Reality / Hysteria 2 / TUIC v5)，集成 Reality 伪装智能测速、原生 WireGuard WARP 分流、UDP 巨型缓冲与 BBR 深度提速，全权稳定运行。**

📌 **项目地址**： [https://github.com/kzhx666/sb-install-plus](https://github.com/kzhx666/sb-install-plus)

---

## 📖 目录

- [✨ v7.0 核心特性](#-v70-核心特性)
- [⚡ 速度极致优化 (新增)](#-速度极致优化-新增)
- [🖥️ 系统支持](#️-系统支持)
- [⚡ 快速安装](#-快速安装)
  - [一键安装命令](#一键安装命令)
  - [卸载](#卸载)
- [📦 项目结构](#-项目结构)
- [🚀 核心功能展示](#-核心功能展示)
  - [精简三大黄金协议](#精简三大黄金协议)
  - [Reality 伪装智能测速优选](#reality-伪装智能测速优选)
  - [原生 WireGuard WARP 分流](#原生-wireguard-warp-分流)
  - [Hy2 端口跳跃](#hy2-端口跳跃)
- [🛠️ 使用指南](#️-使用指南)
  - [查看节点链接](#查看节点链接)
  - [服务管理](#服务管理)
  - [伪装域名重测与更换](#伪装域名重测与更换)
  - [手动更新核心](#手动更新核心)
- [❓ FAQ](#-faq)
- [📄 许可证](#-许可证)

---

## ✨ v7.0 核心特性

- ✅ **精简聚焦王牌协议**：移除了历史冗余与客户端兼容性差的 AnyTLS、ShadowTLS、Trojan，全力打造 **VLESS-Reality**、**Hysteria 2**、**TUIC v5** 黄金组合，每个协议均支持**交互式自选开关**。
- ✅ **Reality 智能伪装测速** *(新功能)*：彻底抛弃已被防火墙高度重点关注的 Cloudflare 假伪装，内置全球主流真实 TLS 1.3 + H2/H3 目标池，安装时**自动对各候选域名执行并发握手测速**，优选延迟最低的目标。
- ✅ **极致网络提速方案** *(深度优化)*：
  - **64MB UDP 巨型缓冲**：彻底解决 Hysteria 2 与 TUIC 在高吞吐并发下的内核静默丢包问题，晚高峰跑满大带宽。
  - **强制 BBR 校验**：自动加载 `tcp_bbr` 内核模块并校验生效状态。
  - **TCP Fast Open (TFO)**：内核与 Sing-box 入站双向开启 0-RTT 极速握手。
  - **内存级 DNS 缓存**：Sing-box 内部启用并发 DNS 缓存池，首包响应由几十毫秒降至 **0ms**。
- ✅ **Cloudflare Argo 穿透**：集成 Cloudflare Tunnel，支持输入 Token 与域名，免开放端口穿透回落，Argo 节点自动附在最后。
- ✅ **极简直列节点输出**：移除节点上方冗余的分类标签，所有协议链接直接整齐罗列，复制导入更便捷。
- ✅ **灵活证书申请模式**：支持 **Cloudflare DNS-01 API 验证**（输入 CF Token，免开 80 端口，不怕 CDN 阻断）与 **Standalone HTTP-01 验证** 自主选择，同时保留免域名自签模式。
- ✅ **全权稳定运行**：以 root 全权守护服务运行，彻底杜绝个人 VPS 自行改配置导致的证书权限冲突或 443/80 端口拒绝绑定问题。
- ✅ **端口跳跃避坑加固**：优化端口重定向规则，杜绝老版本批量开启数千个后台 `socat` 导致爆进程假死的隐患。
- ✅ **双栈无缝支持**：支持 IPv4 单栈、IPv6 单栈以及双栈 VPS 独立分配端口。

---

## ⚡ 速度极致优化 (新增)

| 优化维度 | 原版问题 | v7.0 深度调优方案 | 实际提速成效 |
| :--- | :--- | :--- | :--- |
| **UDP 读写缓冲** | 默认内核仅 212KB 缓冲，Hy2 / TUIC 高并发时网卡层大量静默丢包 | 自适应扩大到 **32MB ~ 64MB** 巨型 Socket 缓冲区 | 彻底消除 UDP 丢包导致的限速卡顿，轻松飙满千兆 |
| **TCP 拥塞控制** | 仅写 sysctl，多发行版未加载模块导致 BBR 假生效 | 自动执行 `modprobe tcp_bbr` 并回读验证 | 提高跨国链路长肥管道 (BDP) 吞吐量 |
| **TCP 握手时延** | 每次均需进行 1-RTT 三次握手 | 开启客户端与服务端 `tcp_fastopen = 3` 与 TFO 入站 | 实现 **0-RTT** 极速首包建连 |
| **DNS 解析延迟** | 单线程同步请求 8.8.8.8，每次网页访问产生 20~80ms TTFB 等待 | Sing-box 原生内存 DNS 并发缓存池 | 缓存命中时 **0 毫秒** 立即发起目标建连，网页秒开 |
| **空闲窗口保持** | 默认在空闲数秒后重置 TCP 窗口 (`tcp_slow_start_after_idle=1`) | 强制关闭空闲慢启动 (`tcp_slow_start_after_idle=0`) | 浏览网页、频繁切换应用时始终维持最大吞吐速度 |

---

## 🖥️ 系统支持

| 发行版 | 支持版本 | 支持架构 | 包管理器 |
| :--- | :--- | :--- | :--- |
| **Ubuntu** | 18.04 / 20.04 / 22.04 / 24.04 | amd64, arm64 | apt |
| **Debian** | 10 / 11 / 12 | amd64, arm64 | apt |
| **CentOS / Rocky / Alma** | 7 / 8 / 9 | amd64, arm64 | yum / dnf |
| **Alpine Linux** | 3.16+ | amd64, arm64 | apk |

---

## ⚡ 快速安装

### 一键安装命令

```bash
curl -fsSL https://raw.githubusercontent.com/kzhx666/sb-install-plus/main/install.sh -o install.sh && bash install.sh
```

或使用 `wget`：

```bash
wget -qO install.sh https://raw.githubusercontent.com/kzhx666/sb-install-plus/main/install.sh && bash install.sh
```

> **全交互式流程**：脚本会清晰询问需要启用的协议（VLESS-Reality / Hysteria 2 / TUIC v5）、是否需要自动测试优选 Reality 伪装域名、是否启用端口跳跃与 WARP 分流，全部支持回车快速选用推荐值。

### 卸载

```bash
bash install.sh --uninstall
```

---

## 📦 项目结构

安装部署完成后，系统文件结构精简清晰：

```text
/etc/sing-box/
├── config.json           # Sing-box 主配置文件 (包含 DNS 高速缓存池)
├── .sb_state              # 状态记录文件 (记录 UUID、端口、密码与密钥，重装自动复用)
├── cert/                  # TLS 证书目录 (自签 ECC 证书或 ACME 证书)
├── warp/                  # Cloudflare WARP 凭据
└── mihomo_proxies.yaml    # 导出的 Mihomo / Clash Meta 格式节点配置

/usr/local/bin/
├── sing-box               # Sing-box 官方核心程序 (授予 CAP_NET_BIND_SERVICE)
├── sb                     # 节点展示快捷命令 (随时调出链接与 YAML)
└── sb-hop.sh              # Hysteria 2 端口跳跃管理脚本

/etc/systemd/system/
└── sing-box.service       # 守护进程服务 (以 root 全权守护运行)
```

---

## 🚀 核心功能展示

### 精简三大黄金协议

1. **VLESS-Reality (TCP)**：
   - 采用 `xtls-rprx-vision` 零拷贝直通与 uTLS 伪装，**无需任何域名或证书**，免遭主动探测。
2. **Hysteria 2 (UDP)**：
   - 基于 QUIC 协议的高速防丢包传输协议，支持自定义 UDP 端口跳跃范围，晚高峰拯救者。
3. **TUIC v5 (UDP)**：
   - 基于 QUIC 规范的高性能低握手延迟协议，内置 BBR 拥塞控制。

### Reality 伪装智能测速优选

脚本内置主流真实 TLS 1.3 候选域名池（如 Apple `swdist.apple.com`、`gateway.icloud.com`、Microsoft、Amazon 等）。安装或更新时：
```text
  -> swdist.apple.com: 18 ms
  -> gateway.icloud.com: 22 ms
  -> www.microsoft.com: 35 ms
  -> dl.google.com: 42 ms
[ OK ] 最优伪装域名已选定: swdist.apple.com (延迟: 18 ms)
```
自动测试延迟并自动回落解析对应真实 IP，省去手工寻找伪装目标的麻烦，大幅提升隐蔽性。

### 原生 WireGuard WARP 分流

- 无需在宿主机建立 `sb-warp` 网卡或加载额外内核模块，完美兼容 Docker / LXC 虚拟化容器。
- 仅对 ChatGPT、Claude、Gemini、Netflix、Disney+ 等特定域名执行 WARP 路由出站，解除 IP 机房风控；
- **常规测速、下载与正常流量 100% 走 VPS 原生高速网络直连**。

---

## 🛠️ 使用指南

### 查看节点链接与配置

安装完成后随时在终端输入：
```bash
sb
```
将打印出：
- `vless://...` (Reality)
- `hysteria2://...` (Hy2，含 mport 跳跃参数)
- `tuic://...` (TUIC v5)
- 以及配套的 **Mihomo / Clash Meta 格式代理配置**。

### 服务管理

```bash
systemctl status sing-box          # 查看运行状态
systemctl restart sing-box         # 重启服务
journalctl -u sing-box -f          # 查看实时日志
```

### 伪装域名重测与更换

无需重新安装，随时运行脚本并选择菜单第 3 项：
```bash
bash install.sh
# 输入 3 -> 智能测速并更换 Reality 伪装域名
```

### 独立配置 / 修改 Hysteria 2 端口跳跃范围

无需重装，随时自由新增、修改或关闭端口跳跃：
```bash
bash install.sh
# 输入 4 -> 配置 / 修改 Hysteria 2 端口跳跃范围
```

### 手动更新核心

```bash
bash install.sh
# 输入 5 -> 一键更新 Sing-box 核心至最新稳定版
```

---

## ❓ FAQ

### Q1: 部署后如何配合客户端使用？
- **Clash Verge / Clash Meta / Mihomo**：运行 `sb` 命令，将底部的 `proxies:` 代码块直接复制进你的配置文件中即可。
- **Shadowrocket (小火箭) / v2rayN / Sing-box 客户端**：直接复制 `vless://`、`hysteria2://` 或 `tuic://` 节点链接导入。

### Q2: 为什么选择自签证书后客户端提示证书不受信任？
- Hysteria 2 与 TUIC 采用自签证书模式时，客户端需开启“允许不安全连接 / 跳过证书校验 (`allowInsecure: true` / `skip-cert-verify: true`)”。脚本生成的链接和 Mihomo 配置中已**自动配置妥当**。
- 若追求完美真实证书，安装时证书模式选择“使用自有域名”，脚本会自动通过 `acme.sh` 签发免费证书。

### Q3: 端口跳跃是如何工作的？
- 脚本通过内核级 NAT REDIRECT 规则将指定端口范围（如 `30000-32000`）的 UDP 数据包自动转发到主 Hysteria 2 端口上，客户端配置相同的端口段即可在不同端口间智能跳跃以绕过运营商单端口 QoS 限速。

---

## 📄 许可证

本项目采用 [GNU General Public License v3.0](https://github.com/kzhx666/sb-install-plus/blob/main/LICENSE) 开源许可证。
