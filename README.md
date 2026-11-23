# 生产级 sing-box 部署与调优实战手册（sing-box v1.14.4 零弃用语法）

[![sing-box](https://img.shields.io/badge/sing--box-v1.14.4-blue)](https://github.com/SagerNet/sing-box/releases)
[![Zero Panel](https://img.shields.io/badge/Memory-~20MB%20Single%20Binary-green)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Telegram](https://img.shields.io/badge/Telegram-%E7%8C%ABe%2Facc-26A5E4?logo=telegram)](https://t.me/CatCryptoMaster)

> **仓库地址**：`github.com/CatEacc/vps-singbox-runbook`  
> **系列矩阵**：[vps-xray-runbook](https://github.com/CatEacc/vps-xray-runbook)（Xray + 3x-ui 面板版） · [vps-clash-runbook](https://github.com/CatEacc/vps-clash-runbook)（Mihomo 客户端版） · **vps-singbox-runbook**（sing-box 无面板单内核全栈版）

---

## 小白一键执行（四套方案交互菜单，单进程极低内存）

新机以 `root` 执行下方命令，按提示选 `1`～`4`（与 `vps-xray-runbook` 四方案完全对齐，**无面板常驻仅 ~20MB 内存**，启动前自动执行 `sing-box check` 强校验）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/CatEacc/vps-singbox-runbook/main/singbox.sh)
```

![CatEacc vps-singbox-runbook 终端菜单](https://raw.githubusercontent.com/CatEacc/vps-singbox-runbook/main/singbox_menu.png)

* **方案 1：`VLESS + REALITY + Vision`**（回车默认 `443` 可自选端口，3 选 1 SNI `addons.mozilla.org` / `dl.google.com` / 自定义；**内置海外家宽 SS-2022 一键落地 + nftables 白名单，以及前置优化机一键中转家宽**）
* **方案 2：`Cloudflare CDN 优选`**（`VLESS + WS + TLS`，默认 `2053` 可自选回源端口）
* **方案 3：`Hysteria 2 + 20000-50000 端口跳跃`**（默认 `UDP 8443` 错开 `TCP 443`，**单进程原生直通后端家宽，无需本地 SOCKS5 桥接、省百兆内存**）
* **方案 4：`纯系统底层内核调优模式`**（BBR + FQ、按内存分档网络缓冲区、1GB Swap、禁 MPTCP、Fail2ban、Journald 50M 收敛）

---

## 一、为什么单独做 `sing-box v1.14.4` 零弃用版？

`sing-box` 在 **`v1.11` → `v1.14`** 期间进行了大幅架构重构，网上大量旧教程在 `v1.14.4` 上会直接报错或刷屏弃用警告。本仓库所有服务端与客户端 JSON 均已通过官方 **`sing-box v1.14.4 check -c`** 零报错、零警告验收：

| 核心变更点 | 已废弃旧写法（会报错/警告） | 本仓库 `v1.14.4` 规范写法 |
| :--- | :--- | :--- |
| **路由动作** | `"outbound": "block"` / 入站 `"sniff": true` | 显式 **`"action": "sniff"`** / **`"hijack-dns"`** / **`"reject"`** / **`"route"`** |
| **DNS 配置** | `address: "https://..."`（`v1.14` 已彻底移除） | 新版 typed 对象：`{"type": "https", "server": "1.1.1.1"}` / `{"type": "fakeip"}` |
| **规则集下载** | `download_detour`（`v1.14` 起废弃） | 显式定义 `http_clients` 并在 `rule_set` 中引用 `"http_client"` |
| **地理规则** | 旧版 `geoip.dat` / `geosite.dat` | 统一采用官方二进制 **`.srs`** 规则集（`format: "binary"`） |
| **链式中转** | Clash 的 `dialer-proxy` | 服务端与客户端统一使用 **`"detour"`** |

---

## 二、客户端开箱即用模板（[`client.json`](client.json)）

本仓库附带一份已通过 `sing-box v1.14.4 check -c` 校验的完整客户端配置 [`client.json`](client.json)（适配 Apple SFI/SFM、Android SFA、Windows/Linux）：

- **零泄露 `Fake-IP` DNS**：国内域名走 `dns-direct`（阿里 DoH），海外走 `dns-fakeip` + `dns-remote`（CF DoH），`strategy: "ipv4_only"` 杜绝脏 IPv6 污染住宅画像；
- **`detour` 链式中转家宽**：`Residential-ISP-Landing`（SS-2022）通过 `"detour": "🚀 前置优化机"` 经由前置优化机连入，AI（OpenAI / Claude / Gemini）与流媒体（Netflix / TikTok）精准走纯净家宽出口；
- **安全回环监听**：本地混合代理仅监听 `127.0.0.1:7890`，绝不向公网暴露端口。

---

## 三、常用运维命令

```bash
# 校验配置语法（零报错无输出即通过）
sing-box check -c /etc/sing-box/config.json

# 查看服务状态与实时日志
systemctl status sing-box
journalctl -u sing-box -n 50 --no-pager

# 重启生效
systemctl restart sing-box
```

---

> **免责声明**：本项目及脚本仅供 Linux 服务器性能调优、网络协议研究与合规技术学习使用，请遵守当地法律法规。
