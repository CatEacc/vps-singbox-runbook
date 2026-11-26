#!/bin/bash
# ==============================================================================
# CatEacc 生产级 sing-box (v1.14.4) 无面板极简一键部署与调优脚本
# 仓库: https://github.com/CatEacc/vps-singbox-runbook
# 适用系统: Debian 11/12/13, Ubuntu 20.04/22.04/24.04 (AMD64 / ARM64)
# 四套方案（与 vps-xray-runbook 完全对齐，单内核常驻仅 ~20MB 内存）:
#   1) VLESS + REALITY + Vision（回车默认 443，内置一键家宽 SS-2022 落地 / 一键中转）
#   2) Cloudflare CDN 优选（VLESS + WS + TLS，回车默认 2053）
#   3) Hysteria 2 + 20000-50000 端口跳跃（默认 UDP 8443，单进程原生直通家宽）
#   4) 纯系统底层内核调优模式（不装任何代理内核）
# ==============================================================================

set -euo pipefail
trap 'rm -rf /tmp/sb_result.txt /tmp/sb-dl' EXIT

SB_VERSION="1.14.4"

if [ "$(id -u)" != "0" ]; then
    echo "[错误] 必须以 root 用户运行此脚本！请先执行 sudo -i"
    exit 1
fi

SERVER_IP=$(curl -s4m 5 https://api.ipify.org || curl -s4m 5 https://ipv4.icanhazip.com || echo "YOUR_SERVER_IP")
OS_INFO=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Linux}" || uname -s)
KERNEL_INFO=$(uname -r | cut -d'-' -f1)
ARCH_INFO=$(uname -m)
MEM_SHOW=$(free -m | awk '/Mem:/ {print $2}')
BBR_STAT=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
MPTCP_STAT=$(sysctl -n net.mptcp.enabled 2>/dev/null || echo "0")

ESC="$(printf '\033')"
R="${ESC}[0m"
B="${ESC}[1m"
SKY="${ESC}[38;5;39m"
CYAN="${ESC}[38;5;51m"
GREEN="${ESC}[38;5;46m"
YELLOW="${ESC}[38;5;220m"
ORANGE="${ESC}[38;5;208m"
PINK="${ESC}[38;5;205m"
RED="${ESC}[38;5;196m"
WHITE="${ESC}[1;97m"
DIM="${ESC}[38;5;245m"

SCRIPT_VER=$(curl -fsSm 2 https://api.github.com/repos/CatEacc/vps-singbox-runbook/releases/latest 2>/dev/null | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | cut -d'"' -f4 || true)
SCRIPT_VER="${SCRIPT_VER:-v1.1.4}"

print_cateacc_logo() {
    G1="${ESC}[38;5;46m"
    G2="${ESC}[38;5;82m"
    G3="${ESC}[38;5;118m"
    G4="${ESC}[38;5;226m"
    G5="${ESC}[38;5;220m"
    G6="${ESC}[38;5;208m"
    G7="${ESC}[38;5;199m"
    awk -v c1="$G1" -v c2="$G2" -v c3="$G3" -v c4="$G4" -v c5="$G5" -v c6="$G6" -v c7="$G7" -v rs="$R" -v bd="$B" '
    {
        line = $0
        while (length(line) < 42) line = line " "
        printf "  %s%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n", \
            bd c1, substr(line, 1, 6), \
            c2, substr(line, 7, 6), \
            c3, substr(line, 13, 6), \
            c4, substr(line, 19, 6), \
            c5, substr(line, 25, 6), \
            c6, substr(line, 31, 6), \
            c7, substr(line, 37, 6), \
            rs
    }
    ' <<'BANNER'
   ______      __  ______               
  / ____/___ _/ /_/ ____/___ ___________
 / /   / __ `/ __/ __/ / __ `/ ___/ ___/
/ /___/ /_/ / /_/ /___/ /_/ / /__/ /__  
\____/\__,_/\__/_____/\__,_/\___/\___/  
BANNER
}

svc_badge() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        printf "${GREEN}● 运行中${R}"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^$1"; then
        printf "${YELLOW}● 已停止${R}"
    else
        printf "${DIM}○ 未安装${R}"
    fi
}

MODE="${1:-}"
if [ -z "$MODE" ]; then
    clear 2>/dev/null || true
    printf '\n'
    print_cateacc_logo
    printf '\n'
    printf "  ${CYAN}猫e/acc (CatEacc)${R} ${DIM}· sing-box v${SB_VERSION} 无面板极简一键部署脚本 ${YELLOW}${SCRIPT_VER}${R}\n"
    printf "  ${GREEN}──────────────────────────────────────────────────────────${R}\n"
    printf "  ${SKY}OS:${R}       ${GREEN}${OS_INFO} (${ARCH_INFO})${R}\n"
    printf "  ${SKY}Kernel:${R}   ${GREEN}${KERNEL_INFO}${R}  ${DIM}|${R}  ${SKY}BBR:${R} ${GREEN}${BBR_STAT}${R}  ${DIM}|${R}  ${SKY}MPTCP:${R} ${GREEN}${MPTCP_STAT}${R}\n"
    printf "  ${SKY}Memory:${R}   ${GREEN}${MEM_SHOW} MB${R}  ${DIM}|${R}  ${SKY}IP:${R} ${CYAN}${SERVER_IP}${R}\n"
    printf "  ${SKY}Service:${R}  sing-box $(svc_badge sing-box)  ${DIM}|${R}  ${PINK}v${SB_VERSION} 零弃用语法${R}\n"
    printf "  ${SKY}GitHub:${R}   ${CYAN}https://github.com/CatEacc/vps-singbox-runbook${R}\n"
    printf "  ${SKY}Channel:${R}  ${CYAN}https://t.me/CatCryptoMaster${R}\n"
    printf "  ${GREEN}──────────────────────────────────────────────────────────${R}\n\n"
    printf "  ${WHITE}请选择部署方案：${R}\n"
    printf "  ${GREEN}[1]${R} ${WHITE}VLESS + REALITY + Vision${R} ${CYAN}★ 推荐 · 支持一键家宽落地 / 一键中转${R}\n"
    printf "      ${DIM}全客户端通吃，9 大地区纯本土 X25519 SNI 自动测速 + 选后实时四重复检${R}\n"
    printf "  ${GREEN}[2]${R} ${WHITE}Cloudflare CDN 优选${R} ${YELLOW}· VLESS + WS + TLS${R}\n"
    printf "      ${DIM}隐藏源站真实 IP、晚高峰兜底，回车默认 2053 可自选回源端口${R}\n"
    printf "  ${GREEN}[3]${R} ${WHITE}Hysteria 2 + 端口跳跃${R} ${PINK}· UDP 20000-50000 · 单进程原生直通家宽${R}\n"
    printf "      ${DIM}无需 SOCKS5 桥接省百兆内存，默认 UDP 8443 错开 TCP 443${R}\n"
    printf "  ${GREEN}[4]${R} ${WHITE}纯系统底层内核调优模式${R} ${ORANGE}· 零代理内核${R}\n"
    printf "      ${DIM}仅部署 BBR / 按内存分档缓冲 / 1GB Swap / MPTCP 防护 / Fail2ban${R}\n"
    printf "  ${GREEN}[5]${R} ${WHITE}一键导出所有节点链接 & Hy2 公钥指纹${R} ${CYAN}· 只读${R}\n"
    printf "  ${GREEN}[6]${R} ${WHITE}本机家宽 / 商宽 / 机房 IP 与环境快检${R} ${SKY}· 只读 · 不测流媒体${R}\n\n"
    read -rp "$(printf "${YELLOW}  请输入方案编号 [1-6] (回车默认 1): ${R}")" MODE
    MODE="${MODE:-1}"
fi

LISTEN_PORT=""
SUBMODE="1"
REALITY_SNI="addons.mozilla.org"
CF_DOMAIN="cf.example.com"
HY2_BRUTAL="n"
ENABLE_RELAY="n"
RES_IP=""
RES_PORT=""
RES_SS_PASS=""
RES_WHITELIST_IP=""

verify_reality_sni() {
    local target_sni="$1"
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    printf "  ${SKY}-> 正在对 ${WHITE}%s${SKY} 执行实时四重复检 (TLS 1.3+H2 / 非 CF / 无国内 CDN / 中国大陆可达)...${R}\n" "$target_sni"
    local chk_out
    chk_out=$(SNI_TEST="$target_sni" python3 - << 'CHKPY'
import os, ssl, socket, time, json, http.client, urllib.request
h = os.environ["SNI_TEST"].strip()
ctx = ssl.create_default_context()
ctx.set_alpn_protocols(["h2", "http/1.1"])
t0 = time.monotonic()
try:
    with socket.create_connection((h, 443), timeout=3.0) as sock:
        with ctx.wrap_socket(sock, server_hostname=h) as ss:
            rtt = (time.monotonic() - t0) * 1000
            ver, alpn = ss.version(), ss.selected_alpn_protocol()
    is_cf = False
    try:
        conn = http.client.HTTPSConnection(h, timeout=2.5)
        conn.request("HEAD", "/", headers={"User-Agent": "Mozilla/5.0"})
        hdrs = {k.lower(): v for k, v in conn.getresponse().getheaders()}
        is_cf = ('cf-ray' in hdrs) or ('cloudflare' in hdrs.get('server', '').lower())
    except Exception:
        pass
    cn_note = "国内探针暂跳过"
    cn_warn = ""
    try:
        payload = json.dumps({
            "type": "http", "target": h, "locations": [{"country": "CN"}], "limit": 2,
            "measurementOptions": {"protocol": "HTTPS", "request": {"method": "HEAD", "path": "/"}}
        }).encode()
        req = urllib.request.Request("https://api.globalping.io/v1/measurements", data=payload,
            headers={"Content-Type": "application/json", "User-Agent": "CatEacc-SNI-Check/1.0"})
        mid = json.loads(urllib.request.urlopen(req, timeout=5).read().decode()).get("id")
        if mid:
            finished = None
            for _ in range(12):
                time.sleep(1.0)
                r = json.loads(urllib.request.urlopen(f"https://api.globalping.io/v1/measurements/{mid}", timeout=5).read().decode())
                if r.get("status") == "finished":
                    finished = r.get("results", [])
                    break
            if finished is None:
                cn_warn = "中国大陆探针超时未响应，疑似已被 GFW 阻断或国内无法访问！"
            elif finished:
                ok_cnt, cn_cdn_ip = 0, ""
                for item in finished:
                    rr = item.get("result", {})
                    if rr.get("status") == "finished" and rr.get("statusCode"):
                        ok_cnt += 1
                    rip = rr.get("resolvedAddress", "")
                    if rip and not cn_cdn_ip:
                        try:
                            cc = urllib.request.urlopen(f"https://ipinfo.io/{rip}/country", timeout=2.5).read().decode().strip()
                            if cc == "CN":
                                cn_cdn_ip = rip
                        except Exception:
                            pass
                if cn_cdn_ip:
                    cn_warn = f"中国大陆解析到境内 IP ({cn_cdn_ip})，存在国内 CDN，严禁用于 REALITY！"
                elif ok_cnt == 0:
                    cn_warn = f"中国大陆探针 0/{len(finished)} 可达，疑似已被 GFW 阻断或 SNI 封锁！"
                else:
                    cn_note = f"国内直连可达 {ok_cnt}/{len(finished)} | 无境内 CDN"
    except Exception:
        pass
    if is_cf:
        print(f"WARN|背后套了 Cloudflare CDN，易被扫作免费 CF 反代 IP ({ver}+{alpn}, {rtt:.1f} ms)")
    elif cn_warn:
        print(f"WARN|{cn_warn} ({ver}+{alpn}, {rtt:.1f} ms)")
    elif ver == "TLSv1.3" and alpn == "h2":
        print(f"OK|{ver} + {alpn} | 非 CF | {cn_note} ({rtt:.1f} ms)")
    else:
        print(f"WARN|{ver} / ALPN={alpn}")
except Exception as e:
    print(f"WARN|{e}")
CHKPY
)
    if [[ "$chk_out" == OK\|* ]]; then
        printf "  ${GREEN}-> [实时复检通过]${R} ${WHITE}%s${R}: ${GREEN}%s${R}\n" "$target_sni" "${chk_out#OK|}"
    else
        printf "  ${RED}-> [实时复检警告]${R} ${WHITE}%s${R}: ${ORANGE}%s${R}\n" "$target_sni" "${chk_out#WARN|}"
    fi
}

prompt_relay_target() {
    printf "\n  ${CYAN}─── 后端家宽中转对接方式 ───${R}\n"
    printf "  ${GREEN}[1]${R} ${WHITE}粘贴 ss:// 分享链接${R} ${DIM}(自动解析 IP/端口/密钥，也支持直接输入 IP 手填)${R}\n"
    printf "  ${GREEN}[2]${R} ${WHITE}全自动远程部署家宽机并对接${R} ${PINK}★ 终极懒人版 · 填 SSH 账密自动装好并拉回凭据${R}\n"
    read -rp "$(printf "  ${YELLOW}请选择对接方式 [1-2] (回车默认 1): ${R}")" RELAY_MODE
    RELAY_MODE="${RELAY_MODE:-1}"

    if [ "$RELAY_MODE" = "2" ]; then
        read -rp "$(printf "  ${SKY}-> 后端家宽机 SSH IP: ${R}")" RES_SSH_IP
        read -rp "$(printf "  ${SKY}-> 后端家宽机 SSH 端口 (回车默认 22): ${R}")" RES_SSH_PORT
        RES_SSH_PORT="${RES_SSH_PORT:-22}"
        read -rsp "$(printf "  ${SKY}-> 后端家宽机 root 密码 (输入不回显，仅内存生效不落盘): ${R}")" RES_SSH_PASS
        echo ""
        if [ -n "$RES_SSH_IP" ] && [ -n "$RES_SSH_PASS" ]; then
            if ! command -v sshpass >/dev/null 2>&1; then
                printf "  ${DIM}-> 正在安装 sshpass 以进行自动化对接...${R}\n"
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -qq && apt-get install -y -qq sshpass >/dev/null 2>&1 || true
            fi
            printf "  ${CYAN}-> 正在连接家宽机 %s:%s 自动部署 SS-2022 落地并添加本机白名单 (%s)...${R}\n" "$RES_SSH_IP" "$RES_SSH_PORT" "$SERVER_IP"
            local remote_out=""
            if command -v sshpass >/dev/null 2>&1; then
                remote_out=$(SSHPASS="$RES_SSH_PASS" sshpass -e ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -p "$RES_SSH_PORT" "root@${RES_SSH_IP}" \
                    "curl -fsSL https://raw.githubusercontent.com/CatEacc/vps-singbox-runbook/main/singbox.sh -o /tmp/_res_sb.sh && printf '2\n\n%s\n' '${SERVER_IP}' | bash /tmp/_res_sb.sh 1; rm -f /tmp/_res_sb.sh" 2>&1 || true)
            fi
            unset RES_SSH_PASS SSHPASS
            RES_IP=$(printf "%s\n" "$remote_out" | grep -oE 'SS_IP=[^[:space:]]+' | tail -n 1 | cut -d'=' -f2- || true)
            RES_PORT=$(printf "%s\n" "$remote_out" | grep -oE 'SS_PORT=[0-9]+' | tail -n 1 | cut -d'=' -f2- || true)
            RES_SS_PASS=$(printf "%s\n" "$remote_out" | grep -oE 'SS_PASS=[^[:space:]]+' | tail -n 1 | cut -d'=' -f2- || true)
            if [ -n "$RES_IP" ] && [ -n "$RES_PORT" ] && [ -n "$RES_SS_PASS" ]; then
                printf "  ${GREEN}-> [自动对接成功]${R} 家宽落地已就绪: ${CYAN}%s:%s${R} (已自动白名单放行本机 IP)\n" "$RES_IP" "$RES_PORT"
                return 0
            else
                printf "  ${ORANGE}-> [提示] 远程自动部署未能获取凭据（请检查密码/网络），自动切换为方式 1 手动粘贴：${R}\n"
            fi
        else
            unset RES_SSH_PASS SSHPASS
            printf "  ${ORANGE}-> [提示] IP 或密码为空，自动切换为方式 1：${R}\n"
        fi
    fi

    read -rp "$(printf "  ${YELLOW}-> 请粘贴家宽 ss:// 链接，或直接输入家宽机 IP: ${R}")" SS_OR_IP
    if [[ "$SS_OR_IP" == ss://* ]]; then
        local parsed
        parsed=$(SS_URI="$SS_OR_IP" python3 - << 'SSPY'
import os, base64, urllib.parse
u = os.environ.get("SS_URI", "").strip()
u = u[5:].split("#", 1)[0].split("?", 1)[0]
if "@" in u:
    cred, hp = u.rsplit("@", 1)
    cred = urllib.parse.unquote(cred)
    if ":" not in cred:
        pad = "=" * ((4 - len(cred) % 4) % 4)
        try:
            cred = base64.urlsafe_b64decode(cred + pad).decode("utf-8", "ignore")
        except Exception:
            cred = base64.b64decode(cred + pad).decode("utf-8", "ignore")
    pwd = cred.split(":", 1)[1] if ":" in cred else cred
    host, port = hp.rsplit(":", 1)
    print(f"{host.strip('[]')}|{port.strip()}|{pwd.strip()}")
SSPY
)
        if [ -n "$parsed" ]; then
            IFS='|' read -r RES_IP RES_PORT RES_SS_PASS <<< "$parsed"
            printf "  ${GREEN}-> [解析成功]${R} 目标家宽: ${CYAN}%s:%s${R} ${DIM}(密钥已自动提取)${R}\n" "$RES_IP" "$RES_PORT"
            return 0
        else
            printf "  ${ORANGE}-> [提示] ss:// 链接解析失败，请改为分步输入：${R}\n"
            read -rp "$(printf "  ${SKY}-> 请输入后端家宽机 IP: ${R}")" RES_IP
        fi
    else
        RES_IP="$SS_OR_IP"
    fi
    read -rp "$(printf "  ${SKY}-> 请输入后端家宽机 SS-2022 端口: ${R}")" RES_PORT
    read -rp "$(printf "  ${SKY}-> 请输入后端家宽机 SS-2022 密钥 (Base64): ${R}")" RES_SS_PASS
}

case "$MODE" in
    1)
        echo ""
        printf "  ${CYAN}─── 方案 1 子模式选择 ───${R}\n"
        printf "  ${GREEN}[1]${R} ${WHITE}VLESS + REALITY + Vision${R} ${CYAN}（前置/直连节点，支持一键中转家宽）${R}\n"
        printf "  ${GREEN}[2]${R} ${WHITE}设为【海外住宅家宽落地机】${R} ${PINK}（随机高位端口 SS-2022，供优化机一键中转）${R}\n"
        read -rp "$(printf "  ${YELLOW}请选择子模式 [1-2] (回车默认 1): ${R}")" SUBMODE
        SUBMODE="${SUBMODE:-1}"

        if [ "$SUBMODE" = "2" ]; then
            DEF_PORT=$((20000 + RANDOM % 30000))
            read -rp "$(printf "  ${YELLOW}请输入家宽落地 SS-2022 监听端口 (回车默认随机高位端口 ${CYAN}${DEF_PORT}${YELLOW}): ${R}")" LISTEN_PORT
            LISTEN_PORT="${LISTEN_PORT:-$DEF_PORT}"
            read -rp "$(printf "  ${YELLOW}请输入允许连入的前置优化机 IP（留空不设白名单，多个用逗号分隔）: ${R}")" RES_WHITELIST_IP
        else
            read -rp "$(printf "  ${YELLOW}请输入 REALITY 监听端口 (回车默认 443，也可手动输入如 8443): ${R}")" LISTEN_PORT
            LISTEN_PORT="${LISTEN_PORT:-443}"
            printf "\n  ${CYAN}─── 请选择 REALITY 回落目标域名 (SNI) ───${R}\n"
            printf "  ${GREEN}[1]${R} ${WHITE}按机房地区自动测速优选${R} ${ORANGE}★ 推荐：本土 5 站 + 全球兜底池 + 选后自动实时复检${R}\n"
            printf "  ${GREEN}[2]${R} ${WHITE}addons.mozilla.org${R}     ${DIM}（免测默认：Firefox 扩展商店 · 纯海外无国内 CDN）${R}\n"
            printf "  ${GREEN}[3]${R} ${WHITE}www.gentoo.org${R}         ${DIM}（免测默认：Gentoo Linux 官网 · 非 CF 国内直连可达）${R}\n"
            printf "  ${GREEN}[4]${R} ${WHITE}手动输入自定义域名${R}     ${DIM}（自动四重体检 TLS 1.3+H2 / 非 CF / 国内 CDN / 是否被墙）${R}\n"
            read -rp "$(printf "  ${YELLOW}请输入选项 [1-4] (回车默认 1): ${R}")" SNI_OPT
            case "${SNI_OPT:-1}" in
                1)
                    if command -v python3 >/dev/null 2>&1; then
                        VPS_CC=$( (curl -fsSm 2 https://ipinfo.io/country 2>/dev/null || curl -fsSm 2 https://ifconfig.co/country-iso 2>/dev/null || true) | tr -dc 'A-Za-z' | tr '[:lower:]' '[:upper:]' | head -c 2 )
                        echo ""
                        printf "  ${YELLOW}[说明]${R} ${DIM}REALITY 选站铁律：纯海外、TLSv1.3+H2、非 CF、无国内 CDN、国内直连可达，同地区低延迟更自然。${R}\n"
                        printf "  ${SKY}-> 正在并发测速当前地区 (${CYAN}${VPS_CC:-GLOBAL}${SKY}) 本土站 + 全球通用兜底池...${R}\n"
                        SNI_LIST=$(VPS_CC="$VPS_CC" python3 - << 'SNIPY'
import os, ssl, socket, time
from concurrent.futures import ThreadPoolExecutor

GLOBAL_POOL = [
    ("www.gentoo.org",     "Gentoo Linux 官网"),
    ("www.openssl.org",    "OpenSSL 加密库官网"),
    ("www.debian.org",     "Debian Linux 官网"),
    ("www.kernel.org",     "Linux 内核官网"),
    ("addons.mozilla.org", "Firefox 扩展商店"),
]
REGIONAL = {
    "US": ("美国", [
        ("www.ebay.com",     "eBay 国际电商"),
        ("www.airbnb.com",   "Airbnb 国际民宿"),
        ("www.ups.com",      "UPS 国际物流"),
        ("www.stanford.edu", "斯坦福大学官网"),
        ("www.harvard.edu",  "哈佛大学官网"),
    ]),
    "CA": ("加拿大", [
        ("www.utoronto.ca", "多伦多大学官网"),
        ("www.ubc.ca",      "英属哥伦比亚大学"),
        ("www.ebay.com",    "eBay 国际电商"),
        ("www.airbnb.com",  "Airbnb 国际民宿"),
        ("www.ups.com",     "UPS 国际物流"),
    ]),
    "JP": ("日本", [
        ("www.sony.jp",           "索尼日本官网"),
        ("www.yahoo.co.jp",       "日本雅虎门户"),
        ("www.honda.co.jp",       "本田日本官网"),
        ("www.yamaha.com",        "雅马哈国际官网"),
        ("www.lovelive-anime.jp", "日本动漫官网"),
    ]),
    "HK": ("香港", [
        ("www.mandarinoriental.com", "香港文华东方酒店"),
        ("www.k11musea.com",         "香港 K11 MUSEA"),
        ("www.pacificplace.com.hk",  "香港太古广场"),
        ("www.cityu.edu.hk",         "香港城市大学"),
        ("www.hku.hk",               "香港大学官网"),
    ]),
    "SG": ("新加坡", [
        ("www.grab.com",          "Grab 东南亚出行"),
        ("www.changiairport.com", "新加坡樟宜机场"),
        ("nus.edu.sg",            "新加坡国立大学"),
        ("www.smu.edu.sg",        "新加坡管理大学"),
        ("www.sutd.edu.sg",       "新加坡科技设计大学"),
    ]),
    "TW": ("台湾", [
        ("www.asus.com",     "华硕国际官网"),
        ("www.msi.com",      "微星国际官网"),
        ("www.gigabyte.com", "技嘉国际官网"),
        ("www.evaair.com",   "台湾长荣航空"),
        ("www.gskill.com",   "台湾芝奇内存"),
    ]),
    "KR": ("韩国", [
        ("www.naver.com",     "韩国 Naver 门户"),
        ("www.samsung.com",   "三星国际官网"),
        ("www.koreanair.com", "大韩航空官网"),
        ("www.coupang.com",   "韩国 Coupang 电商"),
        ("www.cj.net",        "韩国 CJ 集团官网"),
    ]),
    "EU": ("欧洲", [
        ("www.adidas.com",        "德国阿迪达斯官网"),
        ("www.nokia.com",         "芬兰诺基亚官网"),
        ("www.mercedes-benz.com", "梅赛德斯-奔驰官网"),
        ("www.tudelft.nl",        "荷兰代尔夫特理工"),
        ("www.postgresql.org",    "PostgreSQL (奥地利)"),
    ]),
    "GB": ("英国", [
        ("www.virginatlantic.com",  "英国维珍航空"),
        ("www.marksandspencer.com", "英国玛莎百货"),
        ("www.unilever.com",        "英国联合利华"),
        ("www.arm.com",             "英国 Arm 架构官网"),
        ("www.cam.ac.uk",           "剑桥大学官网"),
    ]),
}
cc = os.environ.get("VPS_CC", "")
if cc in ("US", "CA", "JP", "HK", "SG", "TW", "KR", "GB"):
    rk = cc
elif cc in ("DE", "NL", "FR", "CH", "AT", "SE", "FI", "PL", "IT", "ES", "LU", "IE", "NO", "DK", "BE", "CZ"):
    rk = "EU"
else:
    rk = ""

r_name, r_pool = REGIONAL.get(rk, ("", []))
all_items = [("REG", h, d) for h, d in r_pool] + [("GLB", h, d) for h, d in GLOBAL_POOL]

def probe(item):
    grp, host, desc = item
    ctx = ssl.create_default_context()
    ctx.set_alpn_protocols(["h2", "http/1.1"])
    t0 = time.monotonic()
    try:
        with socket.create_connection((host, 443), timeout=2.5) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as ss:
                if ss.version() == "TLSv1.3" and ss.selected_alpn_protocol() == "h2":
                    return (grp, (time.monotonic() - t0) * 1000, host, desc)
    except Exception:
        pass
    return None

with ThreadPoolExecutor(max_workers=12) as ex:
    res = [r for r in ex.map(probe, all_items) if r]

reg_res = sorted([r for r in res if r[0] == "REG"], key=lambda x: x[1])
glb_res = sorted([r for r in res if r[0] == "GLB"], key=lambda x: x[1])
if r_name and reg_res:
    print(f"HDR|当前地区推荐 ({r_name}) · 按实测延迟排序")
    for _, rtt, host, desc in reg_res[:5]:
        print(f"ITEM|{host}|{rtt:.1f}|{desc}")
if glb_res:
    print("HDR|全球通用兜底池 · 跨区通用 · 按实测延迟排序")
    for _, rtt, host, desc in glb_res[:5]:
        print(f"ITEM|{host}|{rtt:.1f}|{desc}")
SNIPY
)
                        if [ -n "$SNI_LIST" ]; then
                            idx=1
                            SNI_ARR=()
                            while IFS='|' read -r tag f1 f2 f3; do
                                [ -z "$tag" ] && continue
                                if [ "$tag" = "HDR" ]; then
                                    echo ""
                                    printf "  ${SKY}【%s】${R}\n" "$f1"
                                elif [ "$tag" = "ITEM" ]; then
                                    SNI_ARR+=("$f1")
                                    printf "    ${GREEN}%2d)${R} ${WHITE}%-23s${R} ${DIM}(${YELLOW}%6s ms${DIM} | ${CYAN}%s${DIM})${R}\n" "$idx" "$f1" "$f2" "$f3"
                                    idx=$((idx + 1))
                                fi
                            done <<< "$SNI_LIST"
                            echo ""
                            read -rp "$(printf "  ${YELLOW}-> 请选择编号 [1-${#SNI_ARR[@]}] (回车默认 1): ${R}")" PICK_IDX
                            PICK_IDX="${PICK_IDX:-1}"
                            if [[ "$PICK_IDX" =~ ^[0-9]+$ ]] && [ "$PICK_IDX" -ge 1 ] && [ "$PICK_IDX" -le "${#SNI_ARR[@]}" ]; then
                                REALITY_SNI="${SNI_ARR[$((PICK_IDX - 1))]}"
                            else
                                REALITY_SNI="${SNI_ARR[0]}"
                            fi
                            printf "  ${ORANGE}-> 已选定目标 SNI: ${WHITE}%s${R}\n" "$REALITY_SNI"
                            verify_reality_sni "$REALITY_SNI"
                        else
                            printf "  ${ORANGE}-> [提示] 测速未命中可用站点，自动回退 addons.mozilla.org${R}\n"
                            REALITY_SNI="addons.mozilla.org"
                        fi
                    else
                        printf "  ${ORANGE}-> [提示] 当前环境尚未安装 python3，自动回退 addons.mozilla.org${R}\n"
                        REALITY_SNI="addons.mozilla.org"
                    fi
                    ;;
                2) REALITY_SNI="addons.mozilla.org" ;;
                3) REALITY_SNI="www.gentoo.org" ;;
                4)
                    read -rp "$(printf "  ${YELLOW}-> 请输入自定义目标域名: ${R}")" SNI_CUSTOM
                    REALITY_SNI="${SNI_CUSTOM:-addons.mozilla.org}"
                    verify_reality_sni "$REALITY_SNI"
                    ;;
                *) REALITY_SNI="addons.mozilla.org" ;;
            esac
            read -rp "$(printf "  ${YELLOW}是否一键中转到后端海外家宽机？[y/N]: ${R}")" ENABLE_RELAY
            ENABLE_RELAY="${ENABLE_RELAY:-n}"
            if [[ "$ENABLE_RELAY" =~ ^[Yy]$ ]]; then
                prompt_relay_target
            fi
        fi
        ;;
    2)
        read -rp "$(printf "  ${YELLOW}请输入 Cloudflare 回源端口 (回车默认 2053，支持 443/2053/2083/8443): ${R}")" LISTEN_PORT
        LISTEN_PORT="${LISTEN_PORT:-2053}"
        read -rp "$(printf "  ${YELLOW}请输入 Cloudflare CDN 域名 (如 cf.example.com): ${R}")" CF_IN
        CF_DOMAIN="${CF_IN:-cf.example.com}"
        ;;
    3)
        read -rp "$(printf "  ${YELLOW}请输入 Hysteria 2 本地 UDP 监听端口 (回车默认 8443 错开 TCP 443，也可填 443): ${R}")" LISTEN_PORT
        LISTEN_PORT="${LISTEN_PORT:-8443}"
        read -rp "$(printf "  ${YELLOW}是否为廉价高丢包线路开启 Brutal？(CN2/9929 精品线强烈选 n) [y/N]: ${R}")" HY2_BRUTAL
        HY2_BRUTAL="${HY2_BRUTAL:-n}"
        read -rp "$(printf "  ${YELLOW}是否一键中转到后端海外家宽机？[y/N]: ${R}")" ENABLE_RELAY
        ENABLE_RELAY="${ENABLE_RELAY:-n}"
        if [[ "$ENABLE_RELAY" =~ ^[Yy]$ ]]; then
            prompt_relay_target
        fi
        ;;
    4)
        ;;
    5|links)
        echo ""
        SERVER_IP="$SERVER_IP" python3 - << 'SBEXPPY'
import json, os, base64, subprocess, urllib.parse, shutil

def print_qr(url):
    if shutil.which('qrencode') and url:
        try:
            subprocess.run(['qrencode', '-t', 'ANSIUTF8', '-m', '1', url], check=False)
        except Exception:
            pass

server_ip = os.environ.get('SERVER_IP', 'YOUR_SERVER_IP')
cfg_path = '/etc/sing-box/config.json'

def x25519_pub(priv_b64):
    pad = '=' * (-len(priv_b64) % 4)
    raw = base64.urlsafe_b64decode(priv_b64 + pad)
    der = bytes.fromhex('302e020100300506032b656e04220420') + raw
    pub_der = subprocess.check_output(['openssl', 'pkey', '-inform', 'DER', '-pubout', '-outform', 'DER'], input=der)
    return base64.urlsafe_b64encode(pub_der[-32:]).decode().rstrip('=')

print("==================================================================")
print("  【sing-box 节点分享链接一键导出】")
print("==================================================================")
if not os.path.exists(cfg_path):
    print("  (未检测到 /etc/sing-box/config.json)")
else:
    cfg = json.load(open(cfg_path))
    found = 0
    for inb in cfg.get('inbounds', []):
        t = inb.get('type')
        port = inb.get('listen_port')
        tag = inb.get('tag', f'{t}-{port}')
        if t == 'vless':
            u = (inb.get('users') or [{}])[0].get('uuid', '')
            tls = inb.get('tls', {})
            if tls.get('reality', {}).get('enabled'):
                sni = tls.get('server_name', 'addons.mozilla.org')
                sid = (tls['reality'].get('short_id') or [''])[0]
                try:
                    pbk = x25519_pub(tls['reality']['private_key'])
                except Exception:
                    pbk = 'DERIVE_FAILED'
                link = f"vless://{u}@{server_ip}:{port}?type=tcp&security=reality&pbk={pbk}&fp=chrome&sni={sni}&sid={sid}&flow=xtls-rprx-vision#{urllib.parse.quote(tag)}"
                print(f"  [{tag}] {link}")
                print_qr(link)
                found += 1
            elif tls.get('enabled'):
                host = tls.get('server_name', server_ip)
                path = urllib.parse.quote(inb.get('transport', {}).get('path', '/vless-ws'), safe='')
                link = f"vless://{u}@{host}:{port}?type=ws&security=tls&path={path}&host={host}&sni={host}#{urllib.parse.quote(tag)}"
                print(f"  [{tag}] {link}")
                print_qr(link)
                found += 1
        elif t == 'hysteria2':
            pwd = (inb.get('users') or [{}])[0].get('password', '')
            cert = inb.get('tls', {}).get('certificate_path', '/etc/sing-box/server.crt')
            fp = spki = ''
            if os.path.exists(cert):
                try:
                    fp = subprocess.check_output(['openssl', 'x509', '-in', cert, '-noout', '-sha256', '-fingerprint'], text=True).split('=', 1)[1].strip()
                    spki = subprocess.check_output(f"openssl x509 -in {cert} -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64", shell=True, text=True).strip()
                except Exception:
                    pass
            hy_url = f"hysteria2://{pwd}@{server_ip}:{port}?insecure=1&sni=www.bing.com&pinSHA256={fp}&mport=20000-50000#{urllib.parse.quote(tag)}"
            print(f"  [{tag}] {hy_url}")
            print_qr(hy_url)
            if spki:
                print(f"    (client.json certificate_public_key_sha256: {spki})")
            found += 1
        elif t == 'shadowsocks':
            method = inb.get('method', '')
            pwd = inb.get('password', '')
            cred = base64.urlsafe_b64encode(f"{method}:{pwd}".encode()).decode().rstrip('=')
            print(f"  [{tag}] ss://{cred}@{server_ip}:{port}#{urllib.parse.quote(tag)}")
            print(f"    (家宽中转参数: IP={server_ip} | PORT={port} | PASS={pwd})")
            found += 1
    if not found:
        print("  (当前未检测到入站节点)")
print("==================================================================")
SBEXPPY
        exit 0
        ;;
    6)
        echo ""
        echo "=================================================================="
        echo "  本机家宽 / 商宽 / 机房 IP 与环境快检（纯只读，不碰流媒体）"
        echo "=================================================================="
        SERVER_IP="$SERVER_IP" python3 - << 'ISPPY'
import os, json, socket, subprocess, urllib.request

ip = os.environ.get("SERVER_IP", "").strip()
if not ip or ip == "未知":
    for u in ("https://api.ipify.org", "https://ifconfig.me/ip"):
        try:
            ip = urllib.request.urlopen(u, timeout=4).read().decode().strip()
            if ip:
                break
        except Exception:
            pass

print(f"  公网 IPv4:   {ip or '获取失败'}")

ptr = "NONE"
if ip:
    try:
        ptr = socket.gethostbyaddr(ip)[0]
    except Exception:
        ptr = "NONE"

ptr_low = ptr.lower()
ptr_is_biz = any(k in ptr_low for k in (".biz.", "business", ".corp.", "-static-", "static."))
ptr_is_res = any(k in ptr_low for k in (".res.", "home", "dyn", "dhcp", "pool", "lightspeed", "fios", "cpe."))
if ptr == "NONE":
    ptr_tag = "无反解（需结合下方双类型判断）"
elif ptr_is_biz:
    ptr_tag = "预警：疑似商宽前缀（含 .biz / business / static）"
elif ptr_is_res:
    ptr_tag = "住宅宽带特征"
else:
    ptr_tag = "常规反解"
print(f"  rDNS / PTR:  {ptr}  [{ptr_tag}]")

asn_str = org_str = isp_str = loc = ""
is_dc = is_proxy = is_mobile = None
try:
    req = urllib.request.Request(
        f"http://ip-api.com/json/{ip}?fields=status,countryCode,regionName,city,isp,org,as,hosting,proxy,mobile",
        headers={"User-Agent": "CatEacc-ISP-Check/1.0"},
    )
    d = json.loads(urllib.request.urlopen(req, timeout=6).read().decode())
    if d.get("status") == "success":
        asn_str = d.get("as") or ""
        isp_str = d.get("isp") or ""
        org_str = d.get("org") or ""
        loc = f"{d.get('countryCode', '')} / {d.get('regionName', '')} / {d.get('city', '')}".strip(" /")
        is_dc = bool(d.get("hosting"))
        is_proxy = bool(d.get("proxy"))
        is_mobile = bool(d.get("mobile"))
except Exception:
    try:
        d = json.loads(urllib.request.urlopen(f"https://ipinfo.io/{ip}/json", timeout=5).read().decode())
        asn_str = d.get("org", "")
        loc = f"{d.get('country', '')} / {d.get('region', '')} / {d.get('city', '')}".strip(" /")
    except Exception:
        pass

print(f"  归属地区:    {loc or '未知'}")
print(f"  ASN / 组织:  {asn_str or org_str or '未知'}")
if isp_str or org_str:
    print(f"  ISP / Org:   ISP={isp_str or '-'} | Org={org_str or '-'}")
if is_dc is not None:
    print(f"  属性标记:    hosting(机房)={is_dc} | proxy(代理)={is_proxy} | mobile(蜂窝)={is_mobile}")

rdap_net = rdap_range = rdap_org = ""
if ip:
    try:
        req = urllib.request.Request(f"https://rdap.org/ip/{ip}", headers={"User-Agent": "CatEacc-ISP-Check/1.0", "Accept": "application/rdap+json"})
        rd = json.loads(urllib.request.urlopen(req, timeout=6).read().decode())
        rdap_net = rd.get("name") or ""
        s_ip, e_ip = rd.get("startAddress") or "", rd.get("endAddress") or ""
        if s_ip and e_ip:
            rdap_range = f"{s_ip} - {e_ip}"
        for ent in (rd.get("entities") or []):
            vcard = ent.get("vcardArray")
            if isinstance(vcard, list) and len(vcard) > 1:
                for item in vcard[1]:
                    if isinstance(item, list) and len(item) >= 4 and item[0] == "fn":
                        rdap_org = str(item[3])
                        break
            if rdap_org:
                break
    except Exception:
        pass
print(f"  RDAP 归属:   NetName={rdap_net or '查询超时'} | 组织={rdap_org or '-'} | 段={rdap_range or '-'}")

virt = "unknown"
try:
    virt = subprocess.check_output(["systemd-detect-virt"], text=True, stderr=subprocess.DEVNULL).strip() or "none"
except Exception:
    pass
hv_balloon = False
try:
    hv_balloon = "hv_balloon" in open("/proc/modules", encoding="utf-8", errors="ignore").read()
except Exception:
    pass
virt_note = f"{virt}"
if virt == "microsoft":
    virt_note += " (Hyper-V 母鸡，hv_balloon=" + ("已加载/建议屏蔽" if hv_balloon else "未加载") + ")"
print(f"  虚拟化环境:  {virt_note}")

smtp_stat = "已封禁/不可达（安全）"
try:
    with socket.create_connection(("gmail-smtp-in.l.google.com", 25), timeout=2.5):
        smtp_stat = "可连出（未封禁，建议跑本脚本封禁出站 TCP 25）"
except Exception:
    pass
print(f"  出站 TCP 25: {smtp_stat}")

print("------------------------------------------------------------------")
dc_kw = ("cogent", "psinet", "hosting", "datacenter", "data center", "cloud", "server", "vps", "digitalocean", "amazon", "aws", "google", "oracle", "hetzner", "ovh", "vultr", "linode", "akamai", "choopa", "colocrossing", "multacom", "zenlayer", "dmit")
comb_org = f"{asn_str} {isp_str} {org_str} {rdap_net} {rdap_org}".lower()
looks_dc_org = any(k in comb_org for k in dc_kw)
asn_tokens = {w for w in asn_str.lower().replace(",", " ").replace(".", " ").split() if len(w) >= 4 and not w.startswith("as")}
rdap_low = f"{rdap_net} {rdap_org}".lower()
is_broadcast_mismatch = bool(asn_tokens and rdap_org and not any(t in rdap_low for t in asn_tokens))

if is_dc is True or looks_dc_org:
    verdict = "[机房商业 VPS / 骨干网段] 建议作为前置迎宾/中转机（443 REALITY / CF CDN / Hy2 端口跳跃）"
elif is_dc is False and ptr_is_biz:
    verdict = "[运营商商宽段] 注意：非机房段但 PTR 含商宽特征（.biz / business / static），买住宅家宽建议换段"
elif is_dc is False and not is_proxy and ptr_is_res and not is_broadcast_mismatch:
    verdict = "[原生住宅家宽] 建议作为后端纯净落地机（选方案 1 -> 子模式 2 高位 SS-2022 + 白名单）"
elif is_broadcast_mismatch:
    verdict = "[疑似广播 IP / 非原生池] 注意：广播 ASN 与 RDAP 原始注册商不一致且无住宅 PTR，请复核 IPinfo 双字段"
elif is_dc is False and not is_proxy:
    verdict = "[疑似住宅/ISP 段] 无明显机房标记，建议再用 IPinfo 复核 asn.type 与 company.type 是否同为 isp"
else:
    verdict = "[混合/未知类型] 请结合上方 PTR 与 RDAP 归属综合判断"
print(f"  综合建议:    {verdict}")
print("==================================================================")
ISPPY
        exit 0
        ;;
    *)
        echo "[错误] 无效编号: ${MODE}，仅支持 1 / 2 / 3 / 4 / 5 / 6"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# 阶段一：系统底层优化、Swap 气囊、日志收敛、Fail2ban 与高并发内核栈
# ------------------------------------------------------------------------------
echo "[1/4] 更新系统组件并安装基础依赖..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget tar chrony iptables nftables iptables-persistent fail2ban python3 python3-systemd openssl qrencode || \
  apt-get install -y curl wget tar chrony iptables nftables iptables-persistent fail2ban python3 python3-systemd openssl

echo "[2/4] 配置原子钟对时、1GB Swap、Journald 50M 收敛与高并发内核栈..."
systemctl enable --now chrony
chronyc makestep || true
timedatectl set-timezone Asia/Shanghai 2>/dev/null || true

if [ ! -f /swapfile ]; then
    fallocate -l 1G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile || true
fi
grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab

cat << 'EOF' > /etc/systemd/journald.conf
[Journal]
SystemMaxUse=50M
SystemMaxFileSize=10M
RuntimeMaxUse=20M
MaxRetentionSec=7day
ForwardToSyslog=no
EOF
systemctl restart systemd-journald 2>/dev/null || true
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service 2>/dev/null || true

if [ -f /etc/gai.conf ]; then
    sed -i '/^precedence ::ffff:0:0\/96\s\+100/d' /etc/gai.conf
    echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
fi

SSH_PORTS=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2}' | paste -sd, -)
SSH_PORTS=${SSH_PORTS:-22}
cat << EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 86400
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 2592000
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = $SSH_PORTS
mode = aggressive
EOF
systemctl enable --now fail2ban && systemctl restart fail2ban

mkdir -p /etc/modules-load.d
printf "tcp_bbr\nnf_conntrack\n" > /etc/modules-load.d/99-proxy.conf
modprobe tcp_bbr 2>/dev/null || true
modprobe nf_conntrack 2>/dev/null || true

MEM_MB=$(free -m | awk '/Mem:/ {print $2}')
if [ "${MEM_MB:-1000}" -le 700 ]; then
    RMEM_MAX=16777216; TCP_MAX=8388608; DEF_BUF=262144; CONN_MAX=65536
elif [ "${MEM_MB:-1000}" -lt 1500 ]; then
    RMEM_MAX=33554432; TCP_MAX=16777216; DEF_BUF=524288; CONN_MAX=65536
else
    RMEM_MAX=67108864; TCP_MAX=33554432; DEF_BUF=1048576; CONN_MAX=131072
fi

cat << EOF > /etc/sysctl.d/99-zzz-proxy-tuning.conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
-net.mptcp.enabled = 0
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.core.rmem_max = $RMEM_MAX
net.core.wmem_max = $RMEM_MAX
net.core.rmem_default = $DEF_BUF
net.core.wmem_default = $DEF_BUF
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_rmem = 4096 87380 $TCP_MAX
net.ipv4.tcp_wmem = 4096 65536 $TCP_MAX
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_adv_win_scale = 1
-net.netfilter.nf_conntrack_max = $CONN_MAX
-net.netfilter.nf_conntrack_udp_timeout = 30
-net.netfilter.nf_conntrack_udp_timeout_stream = 60
net.ipv4.ip_forward = 1
fs.file-max = 2097152
vm.swappiness = 10
EOF
grep -vE '^\s*#|^\s*$' /etc/sysctl.d/99-zzz-proxy-tuning.conf | sed 's/^-//' | while IFS='=' read -r k v; do
    sysctl -w "$(echo "$k" | xargs)=$(echo "$v" | xargs)" >/dev/null 2>&1 || true
done

if [ "$MODE" = "4" ]; then
    echo "=================================================================="
    echo "  【方案 4】纯系统底层内核调优完成！BBR=$(sysctl -n net.ipv4.tcp_congestion_control) MPTCP=$(sysctl -n net.mptcp.enabled 2>/dev/null || echo 0)"
    echo "=================================================================="
    exit 0
fi

# ------------------------------------------------------------------------------
# 阶段二：下载官方 sing-box v1.14.4 并生成零弃用警告的 /etc/sing-box/config.json
# ------------------------------------------------------------------------------
echo "[3/4] 下载官方 sing-box v${SB_VERSION}..."
case "$ARCH_INFO" in
    x86_64)  SB_ARCH="amd64" ;;
    aarch64) SB_ARCH="arm64" ;;
    *)       echo "[错误] 暂不支持架构: ${ARCH_INFO}"; exit 1 ;;
esac

mkdir -p /etc/sing-box /tmp/sb-dl
curl -fsSL -o /tmp/sb-dl/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box-${SB_VERSION}-linux-${SB_ARCH}.tar.gz"
tar -xzf /tmp/sb-dl/sb.tar.gz -C /tmp/sb-dl
install -m 755 "/tmp/sb-dl/sing-box-${SB_VERSION}-linux-${SB_ARCH}/sing-box" /usr/local/bin/sing-box
rm -rf /tmp/sb-dl

# 若为方案 2 (CF TLS) 或方案 3 (Hy2)，生成 10 年自签 EC 证书
if [ "$MODE" = "2" ] || [ "$MODE" = "3" ]; then
    if [ ! -f /etc/sing-box/server.crt ] || [ ! -f /etc/sing-box/server.key ]; then
        openssl ecparam -genkey -name prime256v1 -out /etc/sing-box/server.key
        openssl req -new -x509 -days 3650 -key /etc/sing-box/server.key -out /etc/sing-box/server.crt \
          -subj "/CN=www.bing.com" -addext "subjectAltName=DNS:www.bing.com" 2>/dev/null
    fi
    chmod 644 /etc/sing-box/server.crt && chmod 600 /etc/sing-box/server.key
fi

echo "[4/4] 生成 sing-box v${SB_VERSION} 零弃用配置并启动服务..."
install -m 600 /dev/null /tmp/sb_result.txt
MODE="$MODE" SUBMODE="$SUBMODE" LISTEN_PORT="$LISTEN_PORT" REALITY_SNI="$REALITY_SNI" \
CF_DOMAIN="$CF_DOMAIN" HY2_BRUTAL="$HY2_BRUTAL" SERVER_IP="$SERVER_IP" \
ENABLE_RELAY="$ENABLE_RELAY" RES_IP="$RES_IP" RES_PORT="$RES_PORT" RES_SS_PASS="$RES_SS_PASS" \
python3 - << 'PYEOF' > /tmp/sb_result.txt
import json, os, uuid, secrets, subprocess, base64
os.umask(0o077)

mode = os.environ['MODE']
submode = os.environ['SUBMODE']
port = int(os.environ['LISTEN_PORT'])
sni = os.environ['REALITY_SNI']
cf_domain = os.environ['CF_DOMAIN']
hy2_brutal = os.environ['HY2_BRUTAL'].lower() == 'y'
server_ip = os.environ['SERVER_IP']
enable_relay = os.environ['ENABLE_RELAY'].lower() == 'y'
res_ip = os.environ['RES_IP'].strip()
res_port = os.environ['RES_PORT'].strip()
res_ss_pass = os.environ['RES_SS_PASS'].strip()

cfg_path = '/etc/sing-box/config.json'
if os.path.exists(cfg_path):
    try:
        cfg = json.load(open(cfg_path))
    except Exception:
        cfg = {}
else:
    cfg = {}

cfg['log'] = {"level": "warn", "timestamp": True}
cfg['http_clients'] = [{"tag": "direct-http", "detour": "direct"}]
cfg['dns'] = {
    "servers": [
        {"type": "https", "tag": "dns-remote", "server": "1.1.1.1"}
    ],
    "strategy": "ipv4_only"
}

if mode == '1' and submode == '2':
    proto_key, inb_tag = 'ss', f"in-ss-{port}"
elif mode == '1':
    proto_key, inb_tag = 'vless', f"in-vless-{port}"
elif mode == '2':
    proto_key, inb_tag = 'vless', f"in-cf-{port}"
else:
    proto_key, inb_tag = 'hy2', f"in-hy2-{port}"

def is_same_socket(existing, target_port, target_proto):
    if existing.get('listen_port') != target_port:
        return False
    etype = existing.get('type', '')
    # hysteria2 仅占 UDP，vless 仅占 TCP，二者同端口不冲突；shadowsocks 占 TCP+UDP
    if (etype == 'hysteria2' and target_proto == 'vless') or (etype == 'vless' and target_proto == 'hy2'):
        return False
    return True

inbounds = [i for i in cfg.get('inbounds', []) if i.get('tag') != inb_tag and not is_same_socket(i, port, proto_key)]
relay_tag = f"out-res-{inb_tag}"
outbounds = [o for o in cfg.get('outbounds', []) if o.get('tag') not in ('direct', relay_tag)]
outbounds.insert(0, {"type": "direct", "tag": "direct"})

if enable_relay and res_ip and res_port and res_ss_pass:
    outbounds.append({
        "type": "shadowsocks",
        "tag": relay_tag,
        "server": res_ip,
        "server_port": int(res_port),
        "method": "2022-blake3-aes-256-gcm",
        "password": res_ss_pass
    })
else:
    relay_tag = None

if mode == '1' and submode == '2':
    ss_pass = base64.b64encode(os.urandom(32)).decode()
    inbounds.append({
        "type": "shadowsocks",
        "tag": inb_tag,
        "listen": "::",
        "listen_port": port,
        "method": "2022-blake3-aes-256-gcm",
        "password": ss_pass
    })
    print("RESULT_TYPE=RESIDENTIAL_SS")
    print(f"SS_IP={server_ip}")
    print(f"SS_PORT={port}")
    print(f"SS_PASS={ss_pass}")

elif mode == '1':
    kp = subprocess.check_output(['/usr/local/bin/sing-box', 'generate', 'reality-keypair'], text=True)
    priv = pub = ''
    for line in kp.splitlines():
        if 'PrivateKey' in line: priv = line.split(':', 1)[1].strip()
        elif 'PublicKey' in line: pub = line.split(':', 1)[1].strip()
    sid = secrets.token_hex(4)
    u = str(uuid.uuid4())
    inbounds.append({
        "type": "vless",
        "tag": inb_tag,
        "listen": "::",
        "listen_port": port,
        "users": [{"uuid": u, "flow": "xtls-rprx-vision"}],
        "tls": {
            "enabled": True,
            "server_name": sni,
            "reality": {
                "enabled": True,
                "handshake": {"server": sni, "server_port": 443},
                "private_key": priv,
                "short_id": [sid]
            }
        }
    })
    print("RESULT_TYPE=LINK")
    print(f"SHARE_LINK=vless://{u}@{server_ip}:{port}?type=tcp&security=reality&pbk={pub}&fp=chrome&sni={sni}&sid={sid}&flow=xtls-rprx-vision#CatEacc-SB-REALITY")

elif mode == '2':
    u = str(uuid.uuid4())
    inbounds.append({
        "type": "vless",
        "tag": inb_tag,
        "listen": "::",
        "listen_port": port,
        "users": [{"uuid": u}],
        "tls": {
            "enabled": True,
            "server_name": cf_domain,
            "certificate_path": "/etc/sing-box/server.crt",
            "key_path": "/etc/sing-box/server.key"
        },
        "transport": {
            "type": "ws",
            "path": "/vless-ws",
            "headers": {"Host": cf_domain}
        }
    })
    print("RESULT_TYPE=LINK")
    print(f"SHARE_LINK=vless://{u}@{cf_domain}:{port}?type=ws&security=tls&path=%2Fvless-ws&host={cf_domain}&sni={cf_domain}#CatEacc-SB-CF-WS")

elif mode == '3':
    hy2_pass = ''.join(secrets.choice('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789') for _ in range(16))
    fp = subprocess.check_output(['openssl', 'x509', '-in', '/etc/sing-box/server.crt', '-noout', '-sha256', '-fingerprint'], text=True).split('=', 1)[1].strip()
    spki = subprocess.check_output(
        "openssl x509 -in /etc/sing-box/server.crt -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64",
        shell=True, text=True
    ).strip()
    hy2_inb = {
        "type": "hysteria2",
        "tag": inb_tag,
        "listen": "::",
        "listen_port": port,
        "users": [{"password": hy2_pass}],
        "ignore_client_bandwidth": (not hy2_brutal),
        "tls": {
            "enabled": True,
            "certificate_path": "/etc/sing-box/server.crt",
            "key_path": "/etc/sing-box/server.key"
        },
        "masquerade": "https://www.bing.com/"
    }
    if hy2_brutal:
        hy2_inb["up_mbps"] = 500
        hy2_inb["down_mbps"] = 100
    inbounds.append(hy2_inb)
    print("RESULT_TYPE=LINK")
    print(f"SHARE_LINK=hysteria2://{hy2_pass}@{server_ip}:{port}?insecure=1&sni=www.bing.com&pinSHA256={fp}&mport=20000-50000#CatEacc-SB-Hy2")
    print(f"SPKI_SHA256={spki}")

rules = [
    {"action": "sniff"},
    {"protocol": "bittorrent", "action": "reject"},
    {"port": [25], "action": "reject"},
    {"ip_is_private": True, "action": "reject"},
    {"rule_set": "geoip-cn", "action": "reject"}
]
active_inb_tags = {i.get('tag') for i in inbounds if i.get('tag')}
active_out_tags = {o.get('tag') for o in outbounds if o.get('tag')}
for r in cfg.get('route', {}).get('rules', []):
    inb_val = r.get('inbound')
    inb_list = [inb_val] if isinstance(inb_val, str) else (inb_val if isinstance(inb_val, list) else None)
    if r.get('action') == 'route' and inb_list and r.get('outbound') in active_out_tags:
        kept = [t for t in inb_list if t != inb_tag and t in active_inb_tags]
        if kept:
            rules.append({"inbound": kept, "action": "route", "outbound": r['outbound']})
if relay_tag:
    rules.append({"inbound": [inb_tag], "action": "route", "outbound": relay_tag})

# 清理已无任何规则引用的孤儿中转出站
used_outs = {r.get('outbound') for r in rules if r.get('action') == 'route'} | {'direct'}
outbounds = [o for o in outbounds if not o.get('tag', '').startswith('out-res') or o.get('tag') in used_outs]

cfg['inbounds'] = inbounds
cfg['outbounds'] = outbounds
cfg['route'] = {
    "rules": rules,
    "rule_set": [{
        "type": "remote",
        "tag": "geoip-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
        "http_client": "direct-http"
    }],
    "final": "direct",
    "default_domain_resolver": "dns-remote"
}

open(cfg_path, 'w').write(json.dumps(cfg, indent=2))
os.chmod(cfg_path, 0o600)
PYEOF
chmod 700 /etc/sing-box && chmod 600 /etc/sing-box/config.json

# 家宽白名单持久化
if [ "$MODE" = "1" ] && [ "$SUBMODE" = "2" ] && [ -n "$RES_WHITELIST_IP" ]; then
    mkdir -p /etc/nftables.d
    cat << EOF > /etc/nftables.d/sb-res-guard.nft
table inet sb_res_guard
delete table inet sb_res_guard
table inet sb_res_guard {
    set trusted_relays_v4 {
        type ipv4_addr
        flags interval
        elements = { 127.0.0.0/8, ${RES_WHITELIST_IP} }
    }
    chain input {
        type filter hook input priority filter; policy accept;
        iifname "lo" accept
        ct state established,related accept
        tcp dport ${LISTEN_PORT} ip saddr @trusted_relays_v4 accept
        udp dport ${LISTEN_PORT} ip saddr @trusted_relays_v4 accept
        tcp dport ${LISTEN_PORT} drop
        udp dport ${LISTEN_PORT} drop
    }
    chain output {
        type filter hook output priority filter; policy accept;
        tcp dport 25 reject with tcp reset
    }
}
EOF
    nft -f /etc/nftables.d/sb-res-guard.nft || true
fi

# 方案 3 端口跳跃
if [ "$MODE" = "3" ]; then
    cat << EOF > /etc/systemd/system/sb-hy2-hopping.service
[Unit]
Description=sing-box Hysteria 2 Port Hopping (IPv4/IPv6 Idempotent)
After=network.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'iptables -t nat -C PREROUTING -p udp -m addrtype --dst-type LOCAL --dport 20000:50000 -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || iptables -t nat -A PREROUTING -p udp -m addrtype --dst-type LOCAL --dport 20000:50000 -j REDIRECT --to-ports ${LISTEN_PORT}; ip6tables -t nat -C PREROUTING -p udp -m addrtype --dst-type LOCAL --dport 20000:50000 -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || ip6tables -t nat -A PREROUTING -p udp -m addrtype --dst-type LOCAL --dport 20000:50000 -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true'
ExecStop=/bin/sh -c 'iptables -t nat -D PREROUTING -p udp -m addrtype --dst-type LOCAL --dport 20000:50000 -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true; ip6tables -t nat -D PREROUTING -p udp -m addrtype --dst-type LOCAL --dport 20000:50000 -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now sb-hy2-hopping.service
fi

# 严格校验配置并启动 systemd 守护
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
cat << 'EOF' > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always
RestartSec=3s
LimitNOFILE=1048576
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now sing-box && systemctl restart sing-box

echo ""
printf "  ${GREEN}──────────────────────────────────────────────────────────${R}\n"
printf "  ${WHITE}部署完成！服务状态验收：${R}\n"
printf "  - sing-box : $(svc_badge sing-box)  (${PINK}v${SB_VERSION}${R})\n"
printf "  - 配置文件 : ${CYAN}/etc/sing-box/config.json${R}\n"
if [ -f /tmp/sb_result.txt ]; then
    if grep -q "RESULT_TYPE=RESIDENTIAL_SS" /tmp/sb_result.txt; then
        printf "  ${YELLOW}【家宽落地 SS-2022 中转凭据】（请复制到前置优化机脚本中）：${R}\n"
        grep -E "^SS_(IP|PORT|PASS)=" /tmp/sb_result.txt | sed 's/^/  /'
    elif grep -q "RESULT_TYPE=LINK" /tmp/sb_result.txt; then
        printf "  ${YELLOW}【客户端导入链接】：${R}\n"
        SB_URL=$(grep "^SHARE_LINK=" /tmp/sb_result.txt | cut -d'=' -f2-)
        echo "  ${SB_URL}"
        if command -v qrencode >/dev/null 2>&1 && [ -n "$SB_URL" ]; then
            printf "  ${YELLOW}【手机扫码导入（Shadowrocket / v2rayNG / Stash）】：${R}\n"
            qrencode -t ANSIUTF8 -m 1 "$SB_URL" || true
        fi
        if grep -q "^SPKI_SHA256=" /tmp/sb_result.txt; then
            printf "  ${YELLOW}【sing-box client.json 证书锁定 (certificate_public_key_sha256)】：${R}\n"
            grep "^SPKI_SHA256=" /tmp/sb_result.txt | cut -d'=' -f2- | sed 's/^/  /'
        fi
    fi
    rm -f /tmp/sb_result.txt
fi
if [ "$MODE" = "2" ]; then
    printf "  ${GREEN}──────────────────────────────────────────────────────────${R}\n"
    printf "  ${YELLOW}【Cloudflare 后台 4 步检查清单（小白照着点）】：${R}\n"
    printf "  1. DNS 添加 A 记录: ${WHITE}${CF_DOMAIN}${R} -> ${WHITE}${SERVER_IP}${R}（务必开启小黄云 Proxied）\n"
    printf "  2. SSL/TLS 设为: ${WHITE}Full${R}（自签证书勿选 Flexible 或 Full Strict，防 525/526）\n"
    printf "  3. Network 开启 ${WHITE}WebSockets${R}，云安全组放行 ${WHITE}TCP ${LISTEN_PORT}${R}\n"
    printf "  4. 客户端优选提速: 仅改「地址」为优选 IP/域名，Host/SNI 保持 ${WHITE}${CF_DOMAIN}${R} 不变\n"
fi
printf "  ${GREEN}──────────────────────────────────────────────────────────${R}\n"
printf "  ${CYAN}本脚本由 猫e/acc (CatEacc) 维护提供${R}\n"
printf "  ${SKY}GitHub:${R}  ${CYAN}https://github.com/CatEacc/vps-singbox-runbook${R}\n"
printf "  ${SKY}Channel:${R} ${CYAN}https://t.me/CatCryptoMaster${R}\n"
printf "  ${GREEN}──────────────────────────────────────────────────────────${R}\n"
