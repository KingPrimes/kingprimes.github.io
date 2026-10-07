#!/usr/bin/env bash
# Script: nyxbot-go-deploy.sh
# Description: NyxBot-Go One-Click Deploy Script (Linux/macOS) / NyxBot-Go 一键部署脚本
# Usage: curl -fsSL <url> | bash -s -- [options]
#
# 与 Java 版 nyxbot-deploy.sh 对应的 Go 端部署脚本，差异说明：
#   - 产物是单二进制（NyxBot-linux-<arch>），无需安装 Java 运行时
#   - 安装布局为系统级：/opt/nyxbot + 系统用户 nyxbot + systemd（对齐 NyxBot-Go 官方部署文档）
#   - 配置以 /opt/nyxbot/config.yaml 为唯一事实来源（不维护脚本侧 JSON 状态文件）
#   - glibc 硬约束：Alpine 等 musl 系统跑不了官方 Linux 产物，只能走 Docker（--docker）
#   - 下载策略：优先稳定版（releases/latest）；无稳定版时回退最新预览版（releases.atom）
#   - 首启由程序自行生成 config.yaml（不要预写占位文件，否则会被回填空配置、JWT 仅驻内存）

set -uo pipefail  # -e disabled: don't exit on non-zero return (handled explicitly)
IFS=$'\n\t'

readonly SCRIPT_NAME="nyxbot-go-deploy.sh"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_PATH="${BASH_SOURCE[0]:-}"
readonly SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH:-.}")" && pwd)"

# ============================================================================
# Constants / 常量
# ============================================================================
readonly REPO="KingPrimes/NyxBot-Go"
readonly GITHUB_URL="https://github.com/${REPO}"
readonly API_LATEST_URL="https://api.github.com/repos/${REPO}/releases/latest"
readonly RELEASES_ATOM_URL="https://github.com/${REPO}/releases.atom"

# Docker 镜像（Docker Hub 官方 + GHCR 回退）
readonly IMAGE_NAME="kingprimes/nyxbot-go"
readonly GHCR_IMAGE="ghcr.io/${REPO%%/*}/nyxbot-go"

# 系统级安装布局（对齐官方部署文档 docs/deploy/linux.md）
readonly INSTALL_DIR="/opt/nyxbot"
readonly BINARY_NAME="NyxBot"
readonly BINARY_PATH="$INSTALL_DIR/NyxBot"
readonly CONFIG_FILE="$INSTALL_DIR/config.yaml"
readonly CRED_FILE="$INSTALL_DIR/admin-credentials.txt"
readonly LOG_FILE="$INSTALL_DIR/nyxbot.log"
readonly PID_FILE="$INSTALL_DIR/nyxbot.pid"
readonly SERVICE_NAME="nyxbot"
readonly SERVICE_USER="nyxbot"
readonly SERVICE_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
readonly CONTAINER_NAME="nyxbot"
readonly GEN_CONTAINER_NAME="nyxbot-gen"
readonly SYSTEM_CMD_PATH="/usr/local/bin/nyxbot-go"

readonly DEFAULT_PORT="8080"
readonly DEFAULT_WS_SERVER_PATH="/ws/shiro"
readonly DEFAULT_WS_CLIENT_URL="ws://localhost:3001"

# GitHub 代理列表
readonly PROXY_LIST=(
    "https://ghfast.top"
    "https://gh-proxy.com"
    "https://gh-proxy.net"
    "https://ghproxy.vip"
    "https://gh-proxy.org"
    "https://edgeone.gh-proxy.org"
    "https://ghm.078465.xyz"
    "https://git.yylx.win"
)

# Docker Hub 国内镜像源
readonly DOCKER_MIRRORS=(
    "docker.1panel.live"
    "docker.m.daocloud.io"
    "hub.rat.dev"
)

# ============================================================================
# Colors & Logging / 颜色 & 日志
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

log() {
    local type="$1"; shift
    local msg="$*"
    case "$type" in
        info)    echo -e "${BLUE}[ ]${NC} ${msg}" ;;
        success) echo -e "${GREEN}[✔]${NC} ${msg}" ;;
        warn)    echo -e "${YELLOW}[!]${NC} ${msg}" ;;
        error)   echo -e "${RED}[✘]${NC} ${msg}" ;;
        step)    echo -e "${CYAN}[>]${NC} ${msg}" ;;
        *)       echo -e "${msg}" ;;
    esac
}

# 双语日志辅助
log_info()    { log info    "${1}${2:+ / $2}"; }
log_success() { log success "${1}${2:+ / $2}"; }
log_warn()    { log warn    "${1}${2:+ / $2}"; }
log_error()   { log error   "${1}${2:+ / $2}"; exit 1; }
log_step()    { log step    "${1}${2:+ / $2}"; }

mask_secret() {
    local value="${1:-}"
    if [[ -z "$value" ]]; then
        echo "Not set / 未设置"
    elif (( ${#value} <= 8 )); then
        echo "****"
    else
        echo "${value:0:4}****${value: -4}"
    fi
}

banner() {
    echo -e "${GREEN}"
    echo ".__   __. ____    ____ ___   ___ .______     ______   .___________."
    echo "|  \\ |  | \\   \\  /   / \\  \\ /  / |   _  \\   /  __  \\  |           |"
    echo "|   \\|  |  \\   \\/   /   \\  V  /  |  |_)  | |  |  |  | \`---|  |----\`"
    echo "|  . \`  |   \\_    _/     >   <   |   _  <  |  |  |  |     |  |     "
    echo "|  |\\   |     |  |      /  .  \\  |  |_)  | |  \`--'  |     |  |     "
    echo "|__| \\__|     |__|     /__/ \\__\\ |______/   \\______/      |__|     "
    echo -e "${NC}"
    echo -e "  ${BOLD}NyxBot-Go Deploy v${SCRIPT_VERSION} / NyxBot-Go 一键部署脚本${NC}"
    echo ""
}

cleanup() {
    rm -rf /tmp/nyxbot_godeploy_* 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================================
# Privilege / 权限
# ============================================================================
# as_root: 以 root 执行命令（已是 root 则直接运行，不依赖 sudo）
as_root() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ensure_privilege: 安装/管理是系统级操作（/opt/nyxbot、systemd、Docker），提前校验并缓存 sudo 凭据
ensure_privilege() {
    if [[ "$EUID" -eq 0 ]]; then
        return 0
    fi
    if ! command -v sudo &>/dev/null; then
        log_error "This script needs root or sudo (system-level install to ${INSTALL_DIR})" \
            "本脚本需要 root 或 sudo 权限（系统级安装到 ${INSTALL_DIR}）"
    fi
    if ! sudo -v 2>/dev/null; then
        log_error "sudo authentication failed. Run as root, or run 'sudo -v' first" \
            "sudo 认证失败。请以 root 运行，或先执行 'sudo -v' 缓存凭据"
    fi
}

# ============================================================================
# Environment Detection / 环境检测
# ============================================================================
detect_os() {
    case "$(uname -s)" in
        Linux)  OS="linux"; GOOS="linux";  OS_NAME="$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')" ;;
        Darwin) OS="macos"; GOOS="darwin"; OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null)" ;;
        *)      log_error "Unsupported system: $(uname -s) (use PowerShell script on Windows)" \
                    "不支持的系统: $(uname -s)（Windows 请使用 PowerShell 部署脚本）" ;;
    esac
    if [[ -z "${OS_NAME:-}" ]]; then OS_NAME="$OS"; fi

    case "$(uname -m)" in
        x86_64|amd64)   ARCH="amd64" ;;
        aarch64|arm64)  ARCH="arm64" ;;
        *)              log_error "Unsupported arch: $(uname -m)" "不支持的架构: $(uname -m)" ;;
    esac

    # Release 资产固定命名：NyxBot-linux-amd64 / NyxBot-darwin-arm64 ...
    readonly ASSET_NAME="NyxBot-${GOOS}-${ARCH}"
    log_success "System: ${OS_NAME} ${ARCH}" "系统: ${OS_NAME} ${ARCH}"
}

# is_musl: Alpine 等 musl 系统无法运行官方 glibc 动态链接产物，只能走 Docker
is_musl() {
    [[ -f /etc/alpine-release ]] && return 0
    if command -v ldd &>/dev/null && ldd /bin/sh 2>/dev/null | grep -qi musl; then
        return 0
    fi
    return 1
}

have_systemd() {
    [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null
}

check_docker() {
    command -v docker &>/dev/null \
        && log_success "Docker: installed ($(as_root docker --version 2>/dev/null | awk '{print $3}' | tr -d ','))" \
            "Docker: 已安装 ($(as_root docker --version 2>/dev/null | awk '{print $3}' | tr -d ','))" \
        && return 0
    return 1
}

check_docker_running() {
    if as_root docker info &>/dev/null 2>&1; then
        return 0
    fi
    log_warn "Docker daemon not running" "Docker 守护进程未运行"
    return 1
}

# ============================================================================
# Runtime State / 运行状态
# ============================================================================
# check_nyxbot_running: systemd 服务 / Docker 容器 / HTTP 探活 / 进程
check_nyxbot_running() {
    if have_systemd && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        return 0
    fi
    if command -v docker &>/dev/null \
        && as_root docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
        return 0
    fi
    if curl -s --connect-timeout 2 -o /dev/null "http://127.0.0.1:${PORT}/api/health" &>/dev/null; then
        return 0
    fi
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && ps -p "$pid" &>/dev/null; then
            return 0
        fi
        rm -f "$PID_FILE" 2>/dev/null || true
    fi
    pgrep -f "$BINARY_PATH" &>/dev/null && return 0
    return 1
}

# wait_nyxbot_started: 轮询 /api/health，检查 "status":"ok"（官方验收标准）
wait_nyxbot_started() {
    local timeout="${1:-90}"
    local deadline=$((SECONDS + timeout))
    log_step "Waiting for NyxBot to become ready..." "等待 NyxBot 启动完成..."
    while (( SECONDS < deadline )); do
        local body
        body=$(curl -sf --connect-timeout 2 "http://127.0.0.1:${PORT}/api/health" 2>/dev/null || true)
        if [[ "$body" == *'"status":"ok"'* ]]; then
            echo ""
            log_success "NyxBot is running" "NyxBot 已运行"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    log_warn "NyxBot did not become ready within ${timeout}s" "NyxBot 在 ${timeout}s 内未就绪"
    return 1
}

# is_installation_complete: 本脚本的安装是否已完成（二进制/容器 + 配置）
is_installation_complete() {
    if command -v docker &>/dev/null \
        && as_root docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "nyxbot-go"; then
        return 0
    fi
    if as_root test -s "$CONFIG_FILE" 2>/dev/null && as_root test -s "$BINARY_PATH" 2>/dev/null; then
        return 0
    fi
    return 1
}

# detect_install_mode: 已有安装时识别部署方式（docker / local）
detect_install_mode() {
    if command -v docker &>/dev/null \
        && as_root docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null | grep -q "nyxbot-go"; then
        echo "docker"
        return 0
    fi
    if as_root test -s "$BINARY_PATH" 2>/dev/null; then
        echo "local"
        return 0
    fi
    echo "auto"
}

# stop_nyxbot: 停止正在运行的实例（systemd / docker / pidfile）
stop_nyxbot() {
    log_step "Stopping running NyxBot..." "停止运行中的 NyxBot..."
    local stopped=false

    if have_systemd && systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        as_root systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        stopped=true
    fi

    if command -v docker &>/dev/null \
        && as_root docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
        as_root docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        stopped=true
    fi

    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && ps -p "$pid" &>/dev/null; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            ps -p "$pid" &>/dev/null && kill -9 "$pid" 2>/dev/null || true
            stopped=true
        fi
        rm -f "$PID_FILE" 2>/dev/null || true
    fi

    # 兜底：直接匹配二进制路径的遗留进程（排除本脚本自身）
    local pids
    pids=$(pgrep -f "$BINARY_PATH" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "$pids" | xargs kill 2>/dev/null || true
        stopped=true
    fi

    if [[ "$stopped" == "true" ]]; then
        log_success "NyxBot stopped" "NyxBot 已停止"
    fi
}

# ============================================================================
# Utility / 工具函数
# ============================================================================
format_speed() {
    local bps="$1"
    if (( bps > 1048576 )); then
        echo "$((bps / 1048576)) MB/s"
    elif (( bps > 1024 )); then
        echo "$((bps / 1024)) KB/s"
    else
        echo "${bps} B/s"
    fi
}

format_size() {
    local bytes="$1"
    if (( bytes > 1048576 )); then
        echo "$((bytes / 1048576)) MB"
    elif (( bytes > 1024 )); then
        echo "$((bytes / 1024)) KB"
    else
        echo "${bytes} B"
    fi
}

# GET 请求获取文件大小
get_file_size() {
    local url="$1"
    curl -k -sI --connect-timeout 10 -L "$url" 2>/dev/null \
        | grep -i 'content-length' | tail -1 | awk '{print $2}' | tr -d '\r' \
        || echo "0"
}

# 计算文件 SHA256（sha256sum / shasum；file 为 "-" 时读 stdin）
file_sha256() {
    local file="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" 2>/dev/null | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" 2>/dev/null | awk '{print $1}'
    else
        echo ""
    fi
}

# 计算已安装二进制的 SHA256（/opt/nyxbot 目录 750，普通用户读不到，经 root cat 后本地哈希）
binary_sha256() {
    as_root cat "$BINARY_PATH" 2>/dev/null | file_sha256 -
}

# 读取文件 uid:gid:mode（GNU/BSD stat 兼容；/opt/nyxbot 为 750，需 root 读取）
file_meta() {
    if as_root stat -c '%u:%g:%a' "$1" >/dev/null 2>&1; then
        as_root stat -c '%u:%g:%a' "$1"
    else
        as_root stat -f '%u:%g:%Lp' "$1"
    fi
}

restore_meta() {
    local file="$1" meta="$2"
    local uid gid mode
    uid="${meta%%:*}"; meta="${meta#*:}"
    gid="${meta%%:*}"; mode="${meta#*:}"
    as_root chown "$uid:$gid" "$file" 2>/dev/null || true
    as_root chmod "$mode" "$file" 2>/dev/null || true
}

# YAML 双引号标量（转义 \ " 及控制字符）
yaml_quote() {
    local value="${1:-}"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '"%s"' "$value"
}

validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

# ============================================================================
# Network Speed Test / 网络测速
# ============================================================================
test_network() {
    log_step "Network speed test" "网络测速..."
    local check_url="https://raw.githubusercontent.com/KingPrimes/DataSource/main/warframe/state_translation.json"
    local timeout=5
    local best_speed=0
    local best_proxy=""
    local output code speed

    # 直连测试
    echo -ne "  Testing: Direct / 直连..."
    output=$(curl -k -L --connect-timeout "$timeout" --max-time $((timeout * 2)) \
        -o /dev/null -s -w "%{http_code}:%{speed_download}" "$check_url" 2>/dev/null || true)
    code=$(echo "$output" | cut -d: -f1)
    speed=$(echo "$output" | cut -d: -f2 | cut -d. -f1)
    if [[ "$code" == "200" && "${speed:-0}" -gt 0 ]]; then
        echo -e " ${GREEN}$(format_speed "$speed")${NC}"
        best_speed="$speed"
    else
        echo -e " ${RED}unreachable / 不可达${NC}"
    fi

    # 串行测所有代理
    local proxy label
    for proxy in "${PROXY_LIST[@]}"; do
        label=$(echo "$proxy" | sed 's|https://||')
        echo -ne "  Testing: ${label}..."
        output=$(curl -k -L --connect-timeout "$timeout" --max-time $((timeout * 2)) \
            -o /dev/null -s -w "%{http_code}:%{speed_download}" \
            "${proxy}/${check_url}" 2>/dev/null || true)
        code=$(echo "$output" | cut -d: -f1)
        speed=$(echo "$output" | cut -d: -f2 | cut -d. -f1)
        if [[ "$code" == "200" && "${speed:-0}" -gt 0 ]]; then
            echo -e " ${GREEN}$(format_speed "$speed")${NC}"
            if (( speed > best_speed )); then
                best_speed="$speed"
                best_proxy="$proxy"
            fi
        else
            echo -e " ${RED}unreachable / 不可达${NC}"
        fi
    done

    if [[ -n "$best_proxy" ]]; then
        GITHUB_PROXY="$best_proxy"
        log_success "Best: ${best_proxy} ($(format_speed "$best_speed"))" \
            "最快: ${best_proxy} ($(format_speed "$best_speed"))"
    elif (( best_speed > 0 )); then
        GITHUB_PROXY=""
        log_success "Direct connection fastest ($(format_speed "$best_speed"))" \
            "直连最快 ($(format_speed "$best_speed"))"
    else
        log_warn "All unreachable, will try direct" "全部不可达，将尝试直连"
        GITHUB_PROXY=""
    fi
}

# ============================================================================
# Config (config.yaml) / 配置读写
# ============================================================================
# 说明：Go 端以程序生成的 /opt/nyxbot/config.yaml 为唯一事实来源。
# 程序首启会自行生成完整配置（含随机 JWT 密钥），脚本只在需要时修改少数键，
# 不预写占位文件（空文件不会被回填，JWT 只驻内存，重启后 token 全失效）。

# read_config_value <section> <key>：读取分节内键值（去掉外层双引号）
read_config_value() {
    local section="$1" key="$2"
    as_root awk -v section="$section" -v key="$key" '
        /^[A-Za-z_][A-Za-z0-9_]*:/ { insec = ($0 ~ "^" section ":") }
        insec && $0 ~ "^[[:space:]]+" key ":" {
            sub("^[[:space:]]+" key ":[[:space:]]*", "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }
    ' "$CONFIG_FILE" 2>/dev/null | sed -E 's/^"(.*)"$/\1/' | head -1
}

# yaml_set <section> <key> <yaml_value>：替换分节内键值行；键不存在时插入到分节末尾。
# yaml_value 是已构造好的 YAML 标量文本（调用方负责引号与转义），经临时文件传给 awk 避免转义歧义。
yaml_set() {
    local section="$1" key="$2" value="$3"

    if ! as_root test -f "$CONFIG_FILE"; then
        log_error "config.yaml not found: ${CONFIG_FILE}" "配置文件不存在: ${CONFIG_FILE}"
    fi

    local tmp_val tmp_out rc
    tmp_val=$(mktemp /tmp/nyxbot_godeploy_val.XXXXXX) || return 1
    printf '%s' "$value" > "$tmp_val"
    tmp_out=$(mktemp /tmp/nyxbot_godeploy_out.XXXXXX) || { rm -f "$tmp_val"; return 1; }

    as_root awk -v section="$section" -v key="$key" -v vfile="$tmp_val" '
        BEGIN { getline wantval < vfile; close(vfile); insec = 0; done = 0 }
        # 顶层键名行（无缩进，形如 server:）——切换分节状态；离开目标分节前补插缺失键
        /^[A-Za-z_][A-Za-z0-9_]*:/ {
            if (insec && !done) { print "  " key ": " wantval; done = 1 }
            insec = ($0 ~ "^" section ":")
        }
        {
            if (insec && !done && $0 ~ "^[[:space:]]+" key ":") {
                match($0, /^[[:space:]]+/)
                print substr($0, 1, RLENGTH) key ": " wantval
                done = 1
                next
            }
            print
        }
        END {
            if (insec && !done) { print "  " key ": " wantval; done = 1 }
            if (!done) exit 3
        }
    ' "$CONFIG_FILE" > "$tmp_out" 2>/dev/null
    rc=$?
    rm -f "$tmp_val"

    if (( rc == 3 )); then
        # 分节缺失（老版本配置）：追加整个分节
        printf '%s:\n  %s: %s\n' "$section" "$key" "$value" >> "$tmp_out"
    elif (( rc != 0 )); then
        rm -f "$tmp_out"
        log_error "Failed to edit ${CONFIG_FILE} (section=${section} key=${key})" \
            "修改 ${CONFIG_FILE} 失败 (section=${section} key=${key})"
    fi

    # 保留原属主/权限（本地模式属主为 nyxbot，Docker 模式为 root）
    local meta
    meta=$(file_meta "$CONFIG_FILE")
    as_root cp "$tmp_out" "$CONFIG_FILE" 2>/dev/null || { rm -f "$tmp_out"; return 1; }
    restore_meta "$CONFIG_FILE" "$meta"
    rm -f "$tmp_out"

    # 回读校验（含转义序列的值跳过严格比对，避免解码差异误报）
    if [[ "$value" != *\\* ]]; then
        local now want
        now=$(read_config_value "$section" "$key")
        want="${value#\"}"; want="${want%\"}"
        if [[ "$now" != "$want" ]]; then
            log_warn "Config verify mismatch: ${section}.${key} expect '${want}' got '${now}'" \
                "配置回读不一致: ${section}.${key} 期望 '${want}' 实际 '${now}'"
            return 1
        fi
    fi
    return 0
}

# apply_config: 把脚本当前目标值写入 config.yaml（仅在有差异时修改）
apply_config() {
    local changed=0 cur

    cur=$(read_config_value server port)
    if [[ "$cur" != "$PORT" ]]; then
        yaml_set server port "$(yaml_quote "$PORT")" || log_error "Failed to set server.port" "写入 server.port 失败"
        log_info "server.port: ${cur:-<none>} -> ${PORT}" "server.port: ${cur:-<none>} -> ${PORT}"
        changed=1
    fi

    cur=$(read_config_value bot mode)
    if [[ "$cur" != "$WS_MODE" ]]; then
        yaml_set bot mode "$WS_MODE" || log_error "Failed to set bot.mode" "写入 bot.mode 失败"
        log_info "bot.mode: ${cur:-<none>} -> ${WS_MODE}" "bot.mode: ${cur:-<none>} -> ${WS_MODE}"
        changed=1
    fi

    cur=$(read_config_value bot access_token)
    if [[ "$cur" != "$TOKEN" ]]; then
        yaml_set bot access_token "$(yaml_quote "$TOKEN")" || log_error "Failed to set bot.access_token" "写入 bot.access_token 失败"
        log_info "bot.access_token: $(mask_secret "$cur") -> $(mask_secret "$TOKEN")" \
            "bot.access_token: $(mask_secret "$cur") -> $(mask_secret "$TOKEN")"
        changed=1
    fi

    if [[ "$WS_MODE" == "client" && -n "$WS_CLIENT_URL" ]]; then
        cur=$(read_config_value bot ws_client_url)
        if [[ "$cur" != "$WS_CLIENT_URL" ]]; then
            yaml_set bot ws_client_url "$(yaml_quote "$WS_CLIENT_URL")" || log_error "Failed to set bot.ws_client_url" "写入 bot.ws_client_url 失败"
            log_info "bot.ws_client_url: ${cur:-<none>} -> ${WS_CLIENT_URL}" \
                "bot.ws_client_url: ${cur:-<none>} -> ${WS_CLIENT_URL}"
            changed=1
        fi
    fi

    if (( changed == 0 )); then
        log_info "Config unchanged (config.yaml)" "配置无变化 (config.yaml)"
    else
        log_success "Config applied to ${CONFIG_FILE}" "配置已写入 ${CONFIG_FILE}"
    fi
    return 0
}

# show_config_summary: 展示当前生效配置（读 config.yaml）
show_config_summary() {
    local port mode token wsurl pingpong
    port=$(read_config_value server port)
    mode=$(read_config_value bot mode)
    token=$(read_config_value bot access_token)
    wsurl=$(read_config_value bot ws_client_url)
    if curl -sf --connect-timeout 2 "http://127.0.0.1:${port:-$PORT}/api/health" 2>/dev/null | grep -q '"status":"ok"'; then
        pingpong="${GREEN}OK${NC}"
    else
        pingpong="${YELLOW}unreachable / 不可达${NC}"
    fi

    echo -e "  Port / 端口:        ${GREEN}${port:-$PORT}${NC}"
    echo -e "  Mode / 通讯模式:    ${GREEN}${mode:-$WS_MODE}${NC}"
    if [[ "${mode:-$WS_MODE}" == "client" ]]; then
        echo -e "  OneBot WS 地址:     ${CYAN}${wsurl:-$DEFAULT_WS_CLIENT_URL}${NC}"
    else
        echo -e "  WS 挂载路径:        ${CYAN}${DEFAULT_WS_SERVER_PATH}${NC}"
    fi
    echo -e "  Token:              ${GREEN}$(mask_secret "$token")${NC}"
    echo -e "  Health / 探活:      $(echo -e "$pingpong")"
}

# ============================================================================
# Version & Download / 版本获取 & 下载
# ============================================================================
# resolve_release: 优先稳定版（releases/latest）；无稳定版时回退最新预览版（releases.atom 首个条目）。
# 注意：NyxBot-Go 的 Release 目前均为 prerelease，GitHub 的 releases/latest 与
# releases/latest/download 对预发布版会返回 404，必须按解析出的 tag 拼下载地址。
resolve_release() {
    log_step "Fetching latest version..." "获取最新版本..."

    # 1) 稳定版
    local resp tag
    resp=$(curl -sL --connect-timeout 10 \
        -H "User-Agent: Mozilla/5.0" -H "Accept: application/vnd.github.v3+json" \
        "$API_LATEST_URL" 2>/dev/null || true)
    tag=$(echo "$resp" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    if [[ -n "$tag" && "$tag" != "null" ]]; then
        RELEASE_TAG="$tag"
        RELEASE_CHANNEL="stable"
    else
        # 2) 回退：atom feed 首条 = 最新非草稿发布（含预览版）
        log_info "No stable release found, falling back to latest pre-release" \
            "未找到稳定版，回退到最新预览版"
        local feed
        feed=$(curl -sL --connect-timeout 10 -H "User-Agent: Mozilla/5.0" "$RELEASES_ATOM_URL" 2>/dev/null || true)
        tag=$(echo "$feed" | grep -o "${REPO}/releases/tag/[^\"]*" | head -1 | sed 's|.*/tag/||')
        if [[ -z "$tag" ]]; then
            log_error "Failed to fetch version info" "无法获取版本信息"
        fi
        RELEASE_TAG="$tag"
        RELEASE_CHANNEL="prerelease"
    fi

    ASSET_URL="${GITHUB_URL}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
    SHA_URL="${GITHUB_URL}/releases/download/${RELEASE_TAG}/SHA256SUMS.txt"

    if [[ "$RELEASE_CHANNEL" == "stable" ]]; then
        log_success "Version: ${RELEASE_TAG} (stable)" "版本: ${RELEASE_TAG} (稳定版)"
    else
        log_success "Version: ${RELEASE_TAG} (pre-release / 预览版)" "版本: ${RELEASE_TAG} (预览版)"
    fi
}

# get_expected_digest: 从 Release 的 SHA256SUMS.txt 取本资产期望哈希
get_expected_digest() {
    EXPECTED_DIGEST=""
    local sums_url="$1"
    local dl="$sums_url"
    [[ -n "${GITHUB_PROXY:-}" ]] && dl="${GITHUB_PROXY}/${sums_url#https://}"

    local body
    body=$(curl -sL --connect-timeout 10 --max-time 60 -H "User-Agent: Mozilla/5.0" "$dl" 2>/dev/null || true)
    EXPECTED_DIGEST=$(echo "$body" | awk -v name="$ASSET_NAME" '$2 == name { print $1; exit }')

    if [[ -z "$EXPECTED_DIGEST" ]]; then
        log_warn "SHA256SUMS.txt not usable, skip checksum" "SHA256SUMS.txt 不可用，跳过校验"
    else
        log_info "Expected SHA256: ${EXPECTED_DIGEST:0:16}..." "期望 SHA256: ${EXPECTED_DIGEST:0:16}..."
    fi
}

# SHA256 校验
verify_sha256() {
    local file="$1"
    local expected="$2"

    echo -ne "  Verifying SHA256 / 校验完整性..."
    local hash
    hash=$(file_sha256 "$file")
    if [[ -z "$hash" ]]; then
        echo -e " ${YELLOW}Skipped (no sha256sum/shasum)${NC}"
        return 0
    fi

    if [[ "$hash" == "$expected" ]]; then
        echo -e " ${GREEN}OK / 通过${NC}"
    else
        echo ""
        log error "SHA256 mismatch! File may be corrupted. / SHA256 校验失败！文件可能损坏。"
        log error "  Expected / 期望: ${expected}"
        log error "  Got / 实际:      ${hash}"
        rm -f "$file"
        log_error "File deleted, please retry." "文件已删除，请重试。"
    fi
}

# 单线程下载
single_download() {
    local url="$1"
    local dest="$2"
    local total_size="$3"
    local tmp_dest="${dest}.tmp"

    if [[ -n "$total_size" && "$total_size" -gt 0 ]]; then
        log_info "File size: $(format_size "$total_size")" "文件大小: $(format_size "$total_size")"
    fi

    log_step "Downloading NyxBot ${RELEASE_TAG}..." "下载 NyxBot ${RELEASE_TAG}..."
    rm -f "$tmp_dest"
    if ! curl -L -# --connect-timeout 10 --max-time 3600 --speed-time 30 --speed-limit 1 --retry 3 \
        -H "User-Agent: Mozilla/5.0" \
        -o "$tmp_dest" \
        "$url"; then
        echo ""
        rm -f "$tmp_dest"
        log_warn "Download failed" "下载失败"
        return 1
    fi
    echo ""
    [[ -s "$tmp_dest" ]] || { rm -f "$tmp_dest"; log_warn "Downloaded file is empty" "下载文件为空"; return 1; }
    mv -f "$tmp_dest" "$dest"
    log_success "Download complete ($(du -h "$dest" 2>/dev/null | cut -f1))" \
        "下载完成 ($(du -h "$dest" 2>/dev/null | cut -f1))"
}

# 分块下载 (>10MB 文件)
chunked_download() {
    local url="$1"
    local dest="$2"
    local total_size="$3"
    local num_chunks=4
    local chunk_size=$(( (total_size + num_chunks - 1) / num_chunks ))
    local tmpdir
    tmpdir=$(mktemp -d /tmp/nyxbot_godeploy_chunks.XXXXXX)

    log_step "Chunked download (${num_chunks} chunks)" "分块下载 (${num_chunks} 块)..."

    # 测试 Range 支持，小探测避免慢代理下看起来卡死
    echo -ne "  Testing Range support / 测试 Range 支持..."
    local start0=0
    local end0=$((total_size > 1048576 ? 1048575 : total_size - 1))
    local expected0=$((end0 - start0 + 1))
    local http_code
    http_code=$(curl -L --connect-timeout 10 --max-time 60 --speed-time 30 --speed-limit 1 \
        -H "User-Agent: Mozilla/5.0" \
        -r "$start0-$end0" \
        -o "$tmpdir/range_probe" \
        -w "%{http_code}" \
        -s "$url" 2>/dev/null || echo "000")

    local actual_size=0
    [[ -f "$tmpdir/range_probe" ]] && actual_size=$(wc -c < "$tmpdir/range_probe" | tr -d ' ')
    rm -f "$tmpdir/range_probe"

    local chunk0_ok=false
    if [[ "$http_code" == "206" && "$actual_size" -eq "$expected0" ]]; then
        echo -e " ${GREEN}OK${NC}"
        chunk0_ok=true
    else
        echo -e " ${RED}Failed (HTTP $http_code, got $actual_size bytes)${NC}"
    fi

    if [[ "$chunk0_ok" != "true" ]]; then
        rm -rf "$tmpdir"
        return 1
    fi

    log_success "Range supported, downloading chunks" "Range 支持，逐块下载"

    # 计算实际需要下载的分块数
    local actual_chunks=0 i
    for ((i = 0; i < num_chunks; i++)); do
        local start=$((i * chunk_size))
        [[ $start -ge $total_size ]] && break
        ((actual_chunks++))
    done

    # 串行下载分块
    local all_ok=true
    for ((i = 0; i < num_chunks; i++)); do
        local start=$((i * chunk_size))
        [[ $start -ge $total_size ]] && break
        local end=$(( (i + 1) * chunk_size - 1 ))
        [[ $end -ge $total_size ]] && end=$((total_size - 1))
        local expected=$((end - start + 1))

        local chunk_file="$tmpdir/chunk_${i}"
        echo -ne "  Chunk $((i + 1))/${actual_chunks} / 分块 $((i + 1))/${actual_chunks}..."
        local code
        code=$(curl -L --connect-timeout 10 --max-time 1800 --speed-time 30 --speed-limit 1 \
            -H "User-Agent: Mozilla/5.0" \
            -r "$start-$end" \
            -o "$chunk_file" \
            -w "%{http_code}" \
            -s "$url" 2>/dev/null || echo "000")
        local size=0
        [[ -f "$chunk_file" ]] && size=$(wc -c < "$chunk_file" | tr -d ' ')

        if [[ "$code" == "206" && "$size" -eq "$expected" ]]; then
            echo -e " ${GREEN}Done / 完成${NC}"
        else
            echo -e " ${RED}Failed (HTTP $code, got $size, expected $expected)${NC}"
            all_ok=false
            break
        fi
    done

    if [[ "$all_ok" != "true" ]]; then
        rm -rf "$tmpdir"
        return 1
    fi

    # 合并分块
    echo -ne "  Assembling & verifying / 合并并校验..."
    {
        for ((i = 0; i < num_chunks; i++)); do
            local chunk_file="$tmpdir/chunk_${i}"
            [[ -f "$chunk_file" ]] && cat "$chunk_file"
        done
    } > "$dest"
    local assembled_size
    assembled_size=$(wc -c < "$dest" | tr -d ' ')

    rm -rf "$tmpdir"

    if [[ "$assembled_size" -eq "$total_size" ]]; then
        echo -e " ${GREEN}OK${NC}"
        log_success "Download complete ($(format_size "$assembled_size"))" \
            "下载完成 ($(format_size "$assembled_size"))"
    else
        echo -e " ${RED}Size mismatch: expected $(format_size "$total_size"), got $(format_size "$assembled_size")${NC}"
        rm -f "$dest"
        return 1
    fi
}

# 下载入口（>10MB 走分块，失败回退单线程）
download_from_url() {
    local dl_url="$1"
    local dest="$2"

    local total_size
    total_size=$(get_file_size "$dl_url")
    if [[ -n "$total_size" && "$total_size" -gt 10485760 ]]; then
        chunked_download "$dl_url" "$dest" "$total_size" || {
            log_warn "Chunked download failed, fallback to single-thread" \
                "分块下载失败，回退单线程"
            single_download "$dl_url" "$dest" "$total_size" || return 1
        }
    else
        single_download "$dl_url" "$dest" "$total_size" || return 1
    fi
}

# download_binary: 下载二进制到指定路径，按代理候选线路逐条尝试
download_binary() {
    local dest="$1"

    local dl_url="$ASSET_URL"
    [[ -n "${GITHUB_PROXY:-}" ]] && dl_url="${GITHUB_PROXY}/${ASSET_URL#https://}"

    local candidates=("$dl_url" "$ASSET_URL")
    local proxy
    for proxy in "${PROXY_LIST[@]}"; do
        candidates+=("${proxy}/${ASSET_URL#https://}")
    done

    local ok=false candidate tried=""
    for candidate in "${candidates[@]}"; do
        [[ -z "$candidate" ]] && continue
        [[ "$tried" == *"|$candidate|"* ]] && continue
        tried+="|$candidate|"
        log_step "Trying download route: ${candidate}" "尝试下载线路: ${candidate}"
        if download_from_url "$candidate" "$dest"; then
            ok=true
            break
        fi
        log_warn "Download route failed, trying next" "当前线路失败，尝试下一条"
    done

    [[ "$ok" == "true" ]] || log_error "All download routes failed" "所有下载线路均失败"
}

# ============================================================================
# Layout & Service / 目录布局与服务
# ============================================================================
# ensure_layout: 创建安装目录；Linux+systemd 下创建系统用户并设置属主
ensure_layout() {
    if ! as_root test -d "$INSTALL_DIR"; then
        log_step "Creating ${INSTALL_DIR}..." "创建 ${INSTALL_DIR}..."
        as_root mkdir -p "$INSTALL_DIR" || log_error "Failed to create ${INSTALL_DIR}" "创建 ${INSTALL_DIR} 失败"
    fi

    if have_systemd; then
        if ! id "$SERVICE_USER" &>/dev/null; then
            log_step "Creating system user: ${SERVICE_USER}..." "创建系统用户: ${SERVICE_USER}..."
            as_root useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null \
                || as_root adduser --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER" 2>/dev/null \
                || log_warn "Cannot create system user ${SERVICE_USER}, will run as root" \
                    "无法创建系统用户 ${SERVICE_USER}，将以 root 运行"
        fi
        if id "$SERVICE_USER" &>/dev/null; then
            RUN_USER="$SERVICE_USER"
        else
            RUN_USER="root"
        fi
    else
        # macOS / 无 systemd：以当前用户运行为准，目录归属当前用户
        RUN_USER="$(id -un)"
    fi

    local owner="$RUN_USER"
    local group
    group=$(id -gn "$owner" 2>/dev/null || echo "$owner")
    log_step "Setting ${INSTALL_DIR} owner to ${owner}:${group}..." "设置 ${INSTALL_DIR} 属主为 ${owner}:${group}..."
    as_root chown -R "$owner:$group" "$INSTALL_DIR" 2>/dev/null || true
    as_root chmod 750 "$INSTALL_DIR" 2>/dev/null || true
}

# guard_conflicts: 检测同名 Java 版部署（service/容器/目录），避免误覆盖
confirm_overwrite() {
    local prompt="$1"
    if [[ "$FORCE" == "true" ]]; then
        log_warn "Force mode, skip confirmation" "强制模式，跳过确认"
        return 0
    fi
    if [[ ! -t 0 ]]; then
        log_error "Conflicting installation detected; re-run with --force to replace" \
            "检测到冲突的既有安装；确认替换请加 --force"
    fi
    local input
    read -r -t 30 -p "  ${prompt} [y/N]: " input || true
    [[ "$input" =~ ^[Yy]$ ]] || { log_error "Cancelled" "已取消"; }
}

guard_conflicts() {
    # 1) 同名 systemd 单元不是本脚本创建的（大概率是 Java 版 nyxbot.service）
    if as_root test -f "$SERVICE_UNIT" 2>/dev/null \
        && ! as_root grep -q "$BINARY_PATH" "$SERVICE_UNIT" 2>/dev/null; then
        log_warn "Existing ${SERVICE_UNIT} was NOT created by this script (possibly Java NyxBot)" \
            "已存在的 ${SERVICE_UNIT} 并非本脚本创建（可能是 Java 版 NyxBot）"
        confirm_overwrite "Overwrite it? / 是否覆盖？"
    fi

    # 2) 同名容器不是 nyxbot-go 镜像
    if command -v docker &>/dev/null; then
        local img
        img=$(as_root docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || true)
        if [[ -n "$img" && "$img" != *"nyxbot-go"* ]]; then
            log_warn "Existing container '${CONTAINER_NAME}' uses image: ${img}" \
                "已存在同名容器 '${CONTAINER_NAME}'，镜像: ${img}"
            confirm_overwrite "Replace it? / 是否替换？"
        fi
    fi

    # 3) 目录内是 Java 版安装（NyxBot.jar）
    if as_root test -f "$INSTALL_DIR/NyxBot.jar" 2>/dev/null; then
        log_warn "Found Java NyxBot.jar in ${INSTALL_DIR}" \
            "在 ${INSTALL_DIR} 发现 Java 版 NyxBot.jar"
        confirm_overwrite "Continue in the same directory? / 是否继续使用该目录？"
    fi
}

# write_service_unit: 写入 systemd 单元（对齐官方文档：WorkingDirectory 决定 config.yaml/data 落点）
write_service_unit() {
    log_step "Creating systemd service..." "创建 systemd 服务..."
    as_root tee "$SERVICE_UNIT" >/dev/null <<EOF
[Unit]
Description=NyxBot Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BINARY_PATH}
Restart=on-failure
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
    as_root systemctl daemon-reload || log_error "systemd daemon-reload failed" "systemd 重载失败"
}

# wait_for_config_files: 首启生成 config.yaml / admin-credentials.txt 的等待
wait_for_config_files() {
    local timeout="${1:-60}"
    local deadline=$((SECONDS + timeout))
    echo -ne "  Waiting for config generation / 等待生成配置..."
    while (( SECONDS < deadline )); do
        if as_root test -s "$CONFIG_FILE" 2>/dev/null; then
            echo -e " ${GREEN}OK${NC}"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    echo ""
    return 1
}

# generate_config_local: 首启生成配置（config.yaml 缺失时）。
# 必须由程序自己生成：空/占位文件不会被回填默认值，且 JWT 密钥只驻内存（重启后 token 全失效）。
generate_config_local() {
    if as_root test -s "$CONFIG_FILE" 2>/dev/null; then
        return 0
    fi
    log_step "First run to generate config.yaml..." "首次启动以生成 config.yaml..."

    # 先验证二进制可执行（musl 环境会在此暴露 "no such file or directory"）
    if ! as_root "$BINARY_PATH" --version &>/dev/null; then
        log_error "Binary cannot be executed (musl/Alpine? use --docker instead)" \
            "二进制无法执行（musl/Alpine 环境？请改用 --docker）"
    fi

    if have_systemd; then
        as_root systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
        as_root systemctl start "$SERVICE_NAME" 2>/dev/null || true
        if ! wait_for_config_files 60; then
            as_root journalctl -u "$SERVICE_NAME" -n 60 --no-pager 2>/dev/null || true
            as_root systemctl stop "$SERVICE_NAME" 2>/dev/null || true
            log_error "Config generation failed (service did not create ${CONFIG_FILE})" \
                "配置生成失败（服务未创建 ${CONFIG_FILE}）"
        fi
        as_root systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    else
        # exec 让子 shell 直接被二进制替换，$! 才是真实进程 PID（否则 kill 打不到进程）
        ( cd "$INSTALL_DIR" && exec nohup ./"$BINARY_NAME" >/dev/null 2>&1 ) &
        echo $! > "$PID_FILE"
        if ! wait_for_config_files 60; then
            stop_nyxbot
            log_error "Config generation failed (process did not create ${CONFIG_FILE})" \
                "配置生成失败（进程未创建 ${CONFIG_FILE}）"
        fi
        stop_nyxbot
    fi
    log_success "config.yaml generated" "config.yaml 已生成"
}

# generate_config_docker: 用一次性容器生成 config.yaml，并取出初始管理员凭据
generate_config_docker() {
    if as_root test -s "$CONFIG_FILE" 2>/dev/null; then
        return 0
    fi
    log_step "First run to generate config.yaml (container)..." "首次启动以生成 config.yaml (容器)..."

    as_root docker rm -f "$GEN_CONTAINER_NAME" >/dev/null 2>&1 || true
    as_root docker run -d --rm --name "$GEN_CONTAINER_NAME" \
        -v "${INSTALL_DIR}:/work" -w /work \
        "${IMAGE_NAME}:latest" >/dev/null || log_error "Generator container failed to start" "生成容器启动失败"

    if ! wait_for_config_files 60; then
        as_root docker logs "$GEN_CONTAINER_NAME" 2>/dev/null | tail -n 60 || true
        as_root docker stop "$GEN_CONTAINER_NAME" >/dev/null 2>&1 || true
        log_error "Config generation failed (container did not create ${CONFIG_FILE})" \
            "配置生成失败（容器未创建 ${CONFIG_FILE}）"
    fi

    # 初始管理员凭据写在容器内 /app/admin-credentials.txt，容器重建后会丢——立即取出保存
    local tmp_cred
    tmp_cred=$(mktemp /tmp/nyxbot_godeploy_cred.XXXXXX) || true
    if [[ -n "${tmp_cred:-}" ]] \
        && as_root docker exec "$GEN_CONTAINER_NAME" cat /app/admin-credentials.txt > "$tmp_cred" 2>/dev/null \
        && [[ -s "$tmp_cred" ]]; then
        as_root cp "$tmp_cred" "$CRED_FILE"
        as_root chmod 600 "$CRED_FILE" 2>/dev/null || true
        log_success "Initial admin credentials saved to ${CRED_FILE}" \
            "初始管理员凭据已保存到 ${CRED_FILE}"
    else
        log_warn "admin-credentials.txt not captured (may already exist in DB)" \
            "未能取出 admin-credentials.txt（数据库中可能已有管理员）"
    fi
    [[ -n "${tmp_cred:-}" ]] && rm -f "$tmp_cred"

    as_root docker stop "$GEN_CONTAINER_NAME" >/dev/null 2>&1 || true
    log_success "config.yaml generated" "config.yaml 已生成"
}

# ============================================================================
# Local Install / 本地安装
# ============================================================================
install_local() {
    if is_musl && [[ "$FORCE" != "true" ]]; then
        log_error "musl system detected (Alpine?). Official Linux binaries are glibc-linked; use --docker instead" \
            "检测到 musl 系统（Alpine？）官方 Linux 产物依赖 glibc，请改用 --docker 部署"
    fi

    # 停止旧实例（替换运行中二进制会 ETXTBSY）
    if check_nyxbot_running; then
        stop_nyxbot
    fi

    # 获取版本 + 按需下载
    resolve_release
    get_expected_digest "$SHA_URL"

    local need_dl=true
    if as_root test -s "$BINARY_PATH" 2>/dev/null && [[ -n "$EXPECTED_DIGEST" ]]; then
        echo -ne "  Checking installed binary / 检测已安装二进制..."
        local local_hash
        local_hash=$(binary_sha256)
        if [[ -n "$local_hash" && "$local_hash" == "$EXPECTED_DIGEST" ]]; then
            echo -e " ${GREEN}Up-to-date / 已是最新${NC}"
            log_success "Already latest, skip download (${RELEASE_TAG})" "已是最新，跳过下载 (${RELEASE_TAG})"
            need_dl=false
        else
            echo -e " ${YELLOW}Outdated / 版本过旧${NC}"
        fi
    fi

    ensure_layout
    guard_conflicts

    if [[ "$need_dl" == "true" ]]; then
        [[ -z "${PROXY_ADDR:-}" ]] && test_network
        local tmp_bin="/tmp/nyxbot_godeploy_${ASSET_NAME}"
        download_binary "$tmp_bin"
        if [[ -n "$EXPECTED_DIGEST" ]]; then
            verify_sha256 "$tmp_bin" "$EXPECTED_DIGEST"
        fi
        as_root chmod +x "$tmp_bin"

        # 备份旧版本（存在时），安装完成后删除
        if as_root test -f "$BINARY_PATH" 2>/dev/null; then
            as_root cp -f "$BINARY_PATH" "${BINARY_PATH}.bak" 2>/dev/null || true
        fi
        if ! as_root install -m 0755 -o "$RUN_USER" -g "$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")" \
            "$tmp_bin" "$BINARY_PATH" 2>/dev/null; then
            # 系统用户创建失败回退 root 时，install -o 可能失败——退化为普通拷贝
            as_root cp -f "$tmp_bin" "$BINARY_PATH" || {
                as_root mv -f "${BINARY_PATH}.bak" "$BINARY_PATH" 2>/dev/null || true
                log_error "Failed to install binary" "安装二进制失败"
            }
            as_root chmod 0755 "$BINARY_PATH" 2>/dev/null || true
        fi
        rm -f "$tmp_bin"
    fi

    # 服务单元（systemd）
    if have_systemd; then
        write_service_unit
    fi

    # 首启生成配置 + 应用配置
    generate_config_local
    apply_config

    # 启动 + 探活
    if have_systemd; then
        as_root systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
        as_root systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
        if ! as_root systemctl restart "$SERVICE_NAME"; then
            as_root systemctl status "$SERVICE_NAME" -l --no-pager 2>/dev/null || true
            log_error "systemd service start failed" "systemd 服务启动失败"
        fi
    else
        # exec 让子 shell 直接被二进制替换，$! 才是真实进程 PID
        ( cd "$INSTALL_DIR" && exec nohup ./"$BINARY_NAME" > "$LOG_FILE" 2>&1 ) &
        echo $! > "$PID_FILE"
    fi

    if ! wait_nyxbot_started 90; then
        if have_systemd; then
            as_root journalctl -u "$SERVICE_NAME" -n 80 --no-pager 2>/dev/null || true
        else
            tail -n 80 "$LOG_FILE" 2>/dev/null || true
        fi
        log_error "NyxBot failed to become ready" "NyxBot 启动后未就绪"
    fi

    # 上机复核实际版本（发布为草稿制时 releases/latest 会静默返回旧版本）
    local ver
    ver=$(as_root "$BINARY_PATH" --version 2>/dev/null | head -1 || true)
    [[ -n "$ver" ]] && log_info "Installed: ${ver}" "已安装: ${ver}"

    rm -f "${BINARY_PATH}.bak" 2>/dev/null || as_root rm -f "${BINARY_PATH}.bak" 2>/dev/null || true

    show_post_install "local"
    if [[ "$INSTALL_CMD" == "true" ]]; then install_command; fi
}

# ============================================================================
# Docker Install / Docker 安装
# ============================================================================
# 镜像拉取：Docker Hub → 国内镜像源 → GHCR
pull_image() {
    log_step "Pulling image: ${IMAGE_NAME}:latest" "拉取镜像: ${IMAGE_NAME}:latest"
    if as_root docker pull "${IMAGE_NAME}:latest" 2>/dev/null; then
        log_success "Image pulled (Docker Hub)" "镜像拉取成功 (Docker Hub)"
        return 0
    fi
    log_warn "Docker Hub unreachable, trying mirrors..." "Docker Hub 不可达，尝试国内镜像源..."

    local mirror mirror_image
    for mirror in "${DOCKER_MIRRORS[@]}"; do
        mirror_image="${mirror}/${IMAGE_NAME}:latest"
        log_step "  Trying: ${mirror_image}" "  尝试: ${mirror_image}"
        if as_root docker pull "$mirror_image" 2>/dev/null; then
            as_root docker tag "$mirror_image" "${IMAGE_NAME}:latest" 2>/dev/null
            as_root docker rmi "$mirror_image" 2>/dev/null || true
            log_success "Image pulled (via ${mirror})" "镜像拉取成功 (via ${mirror})"
            return 0
        fi
    done

    log_step "  Trying: ${GHCR_IMAGE}:latest" "  尝试: ${GHCR_IMAGE}:latest"
    if as_root docker pull "${GHCR_IMAGE}:latest" 2>/dev/null; then
        as_root docker tag "${GHCR_IMAGE}:latest" "${IMAGE_NAME}:latest" 2>/dev/null
        as_root docker rmi "${GHCR_IMAGE}:latest" 2>/dev/null || true
        log_success "Image pulled (GHCR)" "镜像拉取成功 (GHCR)"
        return 0
    fi

    log_error "All registries unavailable. Check network or configure registry mirror" \
        "所有镜像源不可用，请检查网络或配置镜像加速"
}

install_docker() {
    log_step "Docker mode install..." "Docker 模式安装..."

    if ! check_docker || ! check_docker_running; then
        log_error "Docker is required for --docker mode" "Docker 模式需要可用的 Docker"
    fi

    # 目录（容器以 root 运行，宿主目录用于挂载 /work）
    if ! as_root test -d "$INSTALL_DIR"; then
        as_root mkdir -p "$INSTALL_DIR" || log_error "Failed to create ${INSTALL_DIR}" "创建 ${INSTALL_DIR} 失败"
    fi
    as_root chmod 700 "$INSTALL_DIR" 2>/dev/null || true

    guard_conflicts

    # 拉取镜像
    pull_image

    # 首启生成配置 + 取出初始凭据（凭据写在容器内 /app，重建即丢，必须此时保存）
    generate_config_docker
    apply_config

    # 重建并启动正式容器
    # 注意：必须「目录挂载 + -w /work」。单独挂载 config.yaml 文件会因 os.Rename 报
    # "device or resource busy"，接口改配置直接失效（官方文档硬约束）。
    as_root docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    log_step "Starting container..." "启动容器..."
    as_root docker run -d --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${PORT}:${PORT}" \
        -e TZ=Asia/Shanghai \
        -v "${INSTALL_DIR}:/work" -w /work \
        "${IMAGE_NAME}:latest" >/dev/null || log_error "Container start failed" "容器启动失败"

    if ! wait_nyxbot_started 90; then
        as_root docker logs --tail 80 "$CONTAINER_NAME" 2>/dev/null || true
        log_error "NyxBot failed to become ready" "NyxBot 启动后未就绪"
    fi

    local ver
    ver=$(as_root docker exec "$CONTAINER_NAME" /app/NyxBot --version 2>/dev/null | head -1 || true)
    [[ -n "$ver" ]] && log_info "Installed: ${ver}" "已安装: ${ver}"

    show_post_install "docker"
    if [[ "$INSTALL_CMD" == "true" ]]; then install_command; fi
}

# ============================================================================
# Post Install Display / 安装后提示
# ============================================================================
show_admin_credentials() {
    if as_root test -s "$CRED_FILE" 2>/dev/null; then
        local user pass
        user=$(as_root grep -E '^username:' "$CRED_FILE" 2>/dev/null | head -1 | sed 's/^username:[[:space:]]*//')
        pass=$(as_root grep -E '^password:' "$CRED_FILE" 2>/dev/null | head -1 | sed 's/^password:[[:space:]]*//')
        if [[ -n "$user" || -n "$pass" ]]; then
            echo -e "${GREEN}│${NC}  Admin / 初始管理员: ${CYAN}${user}${NC} / ${CYAN}${pass}${NC}"
            echo -e "${GREEN}│${NC}  ${YELLOW}Login and change password immediately! / 登录后请立即改密!${NC}"
        fi
        echo -e "${GREEN}│${NC}  Credentials / 凭据文件: ${CRED_FILE}"
    else
        echo -e "${GREEN}│${NC}  Credentials / 凭据: ${YELLOW}${CRED_FILE} 不存在（仅首启生成）${NC}"
    fi
}

show_post_install() {
    local mode="$1"
    echo ""
    echo -e "${GREEN}┌──────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│      NyxBot-Go Install Complete!          │${NC}"
    echo -e "${GREEN}│      NyxBot-Go 安装完成！                  │${NC}"
    echo -e "${GREEN}├──────────────────────────────────────────┤${NC}"
    echo -e "${GREEN}│${NC}  Dashboard / 管理页面: ${CYAN}http://localhost:${PORT}${NC}"
    echo -e "${GREEN}│${NC}  Data / 数据目录: ${INSTALL_DIR}"
    show_admin_credentials
    if [[ "$mode" == "docker" ]]; then
        echo -e "${GREEN}│${NC}  Logs / 日志:    ${CYAN}docker logs -f ${CONTAINER_NAME}${NC}"
        echo -e "${GREEN}│${NC}  Restart / 重启: ${CYAN}docker restart ${CONTAINER_NAME}${NC}"
        echo -e "${GREEN}│${NC}  Stop / 停止:    ${CYAN}docker stop ${CONTAINER_NAME}${NC}"
    else
        if have_systemd; then
            echo -e "${GREEN}│${NC}  Logs / 日志:    ${CYAN}journalctl -u ${SERVICE_NAME} -f${NC}"
            echo -e "${GREEN}│${NC}  Restart / 重启: ${CYAN}systemctl restart ${SERVICE_NAME}${NC}"
            echo -e "${GREEN}│${NC}  Status / 状态:  ${CYAN}systemctl status ${SERVICE_NAME}${NC}"
        else
            echo -e "${GREEN}│${NC}  Logs / 日志:    ${CYAN}tail -f ${LOG_FILE}${NC}"
        fi
    fi
    echo -e "${GREEN}└──────────────────────────────────────────┘${NC}"
    echo -e "${YELLOW}  安全提示: 服务为明文 HTTP/WS，不要把 ${PORT} 直接暴露公网（远程访问请走 TLS 反向代理）${NC}"
    echo ""
}

# ============================================================================
# System Command / 系统命令注册
# ============================================================================
# 安装为系统命令（命令名 nyxbot-go，避免与 Java 版 nyxbot 命令冲突）
install_command() {
    local script_file="${BASH_SOURCE[0]:-}"
    if [[ ! -f "$script_file" ]]; then
        log_warn "Cannot install command (script not a file, likely piped from curl)" \
            "无法安装为系统命令 (脚本非文件形式，可能通过 curl 管道执行)"
        log_info "Download the script first, then re-run." \
            "请先下载脚本文件再运行。"
        return 1
    fi

    log_step "Installing system command to ${SYSTEM_CMD_PATH}..." \
        "安装系统命令到 ${SYSTEM_CMD_PATH}..."
    as_root cp "$script_file" "$SYSTEM_CMD_PATH" || {
        log_warn "Failed to install command" "安装命令失败"
        return 1
    }
    as_root chmod +x "$SYSTEM_CMD_PATH"
    log_success "Command installed: nyxbot-go" "命令已安装: nyxbot-go"
    log_info "Usage: nyxbot-go --help" "用法: nyxbot-go --help"
}

uninstall_command() {
    if ! as_root test -f "$SYSTEM_CMD_PATH" 2>/dev/null; then
        log_warn "Command not found: ${SYSTEM_CMD_PATH}" "命令未找到: ${SYSTEM_CMD_PATH}"
        return 0
    fi

    log_step "Removing system command: ${SYSTEM_CMD_PATH}..." \
        "移除系统命令: ${SYSTEM_CMD_PATH}..."
    as_root rm -f "$SYSTEM_CMD_PATH" || {
        log_warn "Failed to remove command" "移除命令失败"
        return 1
    }
    log_success "Command removed: nyxbot-go" "命令已移除: nyxbot-go"
}

# ============================================================================
# Service Ops / 服务操作
# ============================================================================
start_nyxbot() {
    if [[ "$INSTALL_MODE" == "docker" ]]; then
        log_step "Starting container..." "启动容器..."
        if as_root docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q true; then
            as_root docker restart "$CONTAINER_NAME" >/dev/null 2>&1 || true
        else
            as_root docker start "$CONTAINER_NAME" >/dev/null 2>&1 || \
                log_error "Container start failed (re-run the script to recreate it)" \
                    "容器启动失败（请重新运行脚本重建容器）"
        fi
        wait_nyxbot_started 60 || true
        log_success "NyxBot started" "NyxBot 已启动"
    elif have_systemd; then
        log_step "Starting NyxBot via systemd..." "通过 systemd 启动..."
        as_root systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
        as_root systemctl start "$SERVICE_NAME" 2>/dev/null || true
        wait_nyxbot_started 60 || true
        log_success "NyxBot started" "NyxBot 已启动"
    else
        log_step "Starting NyxBot via nohup..." "通过 nohup 启动..."
        ( cd "$INSTALL_DIR" && exec nohup ./"$BINARY_NAME" > "$LOG_FILE" 2>&1 ) &
        echo $! > "$PID_FILE"
        wait_nyxbot_started 60 || true
        log_success "NyxBot started (PID: $(cat "$PID_FILE" 2>/dev/null || echo 'n/a'))" \
            "NyxBot 已启动 (PID: $(cat "$PID_FILE" 2>/dev/null || echo 'n/a'))"
    fi
}

follow_logs() {
    echo ""
    echo -e "${BOLD}── NyxBot Logs / NyxBot 实时日志 ──${NC}"
    echo -e "  Dashboard / 管理页面: ${CYAN}http://localhost:${PORT}${NC}"
    echo -e "  Exit / 退出日志: ${YELLOW}Ctrl+C${NC}"
    echo ""

    if [[ "$INSTALL_MODE" == "docker" ]] || as_root docker inspect "$CONTAINER_NAME" &>/dev/null; then
        as_root docker logs -f --tail 80 "$CONTAINER_NAME"
        return
    fi

    if have_systemd && systemctl list-unit-files "${SERVICE_NAME}.service" &>/dev/null; then
        as_root journalctl -u "$SERVICE_NAME" -n 80 -f --no-pager
        return
    fi

    if [[ ! -f "$LOG_FILE" ]]; then
        log_warn "Log file not found: ${LOG_FILE}" "日志文件不存在: ${LOG_FILE}"
        return 1
    fi
    tail -n 80 -f "$LOG_FILE"
}

show_status() {
    echo ""
    echo -e "${BOLD}── NyxBot Status / NyxBot 状态 ──${NC}"
    if check_nyxbot_running; then
        log_success "NyxBot is running" "NyxBot 正在运行"
    else
        log_warn "NyxBot is not running" "NyxBot 未运行"
    fi
    echo -e "  Mode / 部署方式:    ${GREEN}${INSTALL_MODE}${NC}"
    echo -e "  Install / 安装目录: ${INSTALL_DIR}"
    show_config_summary
    if [[ "$INSTALL_MODE" == "local" ]] && have_systemd; then
        as_root systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -12 || true
    elif [[ "$INSTALL_MODE" == "docker" ]]; then
        as_root docker ps -a --filter "name=^/${CONTAINER_NAME}$" 2>/dev/null || true
    fi
}

# ============================================================================
# Management Menu / 管理菜单
# ============================================================================
show_menu() {
    while true; do
        INSTALL_MODE="$(detect_install_mode)"
        [[ "$INSTALL_MODE" == "auto" ]] && INSTALL_MODE="local"

        local running=false
        check_nyxbot_running && running=true

        echo ""
        echo -e "${BOLD}── NyxBot-Go Management / NyxBot-Go 管理 ──${NC}"
        echo -e "  Mode / 方式:   ${GREEN}${INSTALL_MODE}${NC}"
        echo -e "  Status / 状态: $(if [[ "$running" == "true" ]]; then echo -e "${GREEN}Running / 运行中${NC}"; else echo -e "${YELLOW}Stopped / 未运行${NC}"; fi)"
        echo ""
        echo "  1) Update / 更新 (download latest + restart)"
        echo "  2) $(if [[ "$running" == "true" ]]; then echo 'Restart / 重启'; else echo 'Start / 启动'; fi)"
        if [[ "$running" == "true" ]]; then echo "  3) Stop / 停止"; fi
        echo "  4) Status / 查看状态"
        echo "  5) Logs / 实时日志"
        echo "  6) Reconfigure / 重新配置"
        echo "  7) Remove system command / 移除系统命令"
        echo "  8) Quit / 退出"
        echo ""

        local choice
        read -r -p "  Select / 选择 [1]: " choice
        choice="${choice:-1}"

        case "$choice" in
            2)
                if [[ "$running" == "true" ]]; then stop_nyxbot; sleep 1; fi
                start_nyxbot
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
            3)
                if [[ "$running" == "true" ]]; then stop_nyxbot; fi
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
            4)
                show_status
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
            5)
                follow_logs
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
            6)
                # 读取当前值作为默认，收集新值后应用
                PORT=$(read_config_value server port); PORT="${PORT:-$DEFAULT_PORT}"
                TOKEN=$(read_config_value bot access_token)
                WS_MODE=$(read_config_value bot mode); WS_MODE="${WS_MODE:-server}"
                WS_CLIENT_URL=$(read_config_value bot ws_client_url)
                text_config
                apply_config
                if check_nyxbot_running; then
                    local input
                    read -r -t 30 -p "  Restart to apply changes? / 是否重启以应用配置? [Y/n]: " input || true
                    if [[ ! "$input" =~ ^[Nn]$ ]]; then
                        stop_nyxbot; sleep 1; start_nyxbot
                    else
                        log_warn "Config saved, restart required later" "配置已保存，稍后需重启生效"
                    fi
                fi
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
            7)
                uninstall_command
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
            8)
                log_info "Bye / 再见"
                exit 0
                ;;
            1|*)
                # Update
                if [[ "$INSTALL_MODE" == "docker" ]]; then
                    install_docker
                else
                    install_local
                fi
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
        esac
    done
}

# ============================================================================
# Interactive Config / 交互配置
# ============================================================================
text_config() {
    local input
    echo ""
    echo -e "${BOLD}── Basic Config / 基础配置 ──${NC}"
    while true; do
        read -r -t 30 -p "  Port / 端口 [${PORT}]: " input || true
        PORT="${input:-$PORT}"
        if validate_port "$PORT"; then break; fi
        log_warn "Invalid port / 端口无效: ${PORT}"
    done

    read -r -s -p "  Token (required / 必填): " TOKEN; echo ""
    while [[ -z "$TOKEN" ]]; do
        read -r -s -p "  Token cannot be empty / Token 不能为空: " TOKEN; echo ""
    done

    echo ""
    echo -e "${BOLD}── Mode / 通讯模式 ──${NC}"
    echo "  1) Server / 服务端 (recommended / 推荐)  2) Client / 客户端"
    read -r -t 30 -p "  Select / 选择 [1]: " input || true
    if [[ "$input" == "2" ]]; then
        WS_MODE="client"
        read -r -t 30 -p "  OneBot WS URL / 正向 WS 地址 [${WS_CLIENT_URL:-$DEFAULT_WS_CLIENT_URL}]: " input || true
        WS_CLIENT_URL="${input:-${WS_CLIENT_URL:-$DEFAULT_WS_CLIENT_URL}}"
    else
        WS_MODE="server"
    fi

    echo ""
    echo -e "${BOLD}── Download Proxy / 下载代理 (Enter to skip / 回车跳过) ──${NC}"
    echo "  Only affects this script's GitHub downloads / 仅影响脚本自身的 GitHub 下载"
    read -r -t 30 -p "  Proxy URL / 代理地址 (e.g. http://127.0.0.1:7890): " PROXY_ADDR || true

    echo ""
    echo -e "${BOLD}── System Command / 系统命令 ──${NC}"
    echo "  Install 'nyxbot-go' command to PATH? / 是否安装 'nyxbot-go' 命令到系统路径?"
    echo "  After install, use 'nyxbot-go' anywhere to manage. / 安装后可在任意位置使用 'nyxbot-go' 管理。"
    read -r -t 30 -p "  Install command? / 安装命令? [Y/n]: " input || true
    if [[ ! "$input" =~ ^[Nn]$ ]]; then
        INSTALL_CMD="true"
    else
        INSTALL_CMD="false"
    fi

    echo ""
    echo -e "${BOLD}── Confirm / 确认 ──${NC}"
    echo -e "  Port / 端口: ${GREEN}${PORT}${NC} | Mode / 模式: ${GREEN}${WS_MODE}${NC} | Token: ${GREEN}$(mask_secret "$TOKEN")${NC}"
    if [[ "$WS_MODE" == "client" ]]; then
        echo -e "  OneBot WS URL: ${CYAN}${WS_CLIENT_URL}${NC}"
    fi
    echo -e "  Proxy / 代理: ${YELLOW}${PROXY_ADDR:-None / 无}${NC}"
    read -r -t 30 -p "  Proceed? / 确认安装? [Y/n]: " input || true
    [[ "$input" =~ ^[Nn]$ ]] && { log_warn "Cancelled" "已取消"; exit 0; }
    return 0
}

# ============================================================================
# TUI Config (dialog: 多字段表单) / TUI 配置 (dialog)
# ============================================================================
tui_dialog() {
    local tmpfile; tmpfile=$(mktemp /tmp/nyxbot_godeploy_dialog.XXXXXX)

    dialog --backtitle "NyxBot-Go Deploy v${SCRIPT_VERSION}" \
        --title "Config / 配置" \
        --form "Please fill in / 请填写以下配置:" 12 60 0 \
        "Port / 端口:"      1 1 "$PORT"       1 22 20 0 \
        "Mode / 模式 (server/client):" 2 1 "$WS_MODE"    2 22 12 0 \
        "OneBot WS URL (client):" 3 1 "${WS_CLIENT_URL:-$DEFAULT_WS_CLIENT_URL}" 3 22 36 0 \
        "Download Proxy / 下载代理:" 4 1 "${PROXY_ADDR:-}"  4 22 30 0 \
        2>"$tmpfile" || { rm -f "$tmpfile"; return 1; }

    local i=0
    while IFS= read -r line; do
        case $i in
            0) PORT="${line:-$DEFAULT_PORT}" ;;
            1) WS_MODE="${line:-server}" ;;
            2) WS_CLIENT_URL="$line" ;;
            3) PROXY_ADDR="$line" ;;
        esac
        ((i++))
    done < "$tmpfile"
    rm -f "$tmpfile"

    if ! validate_port "$PORT"; then
        dialog --title "Error / 错误" --msgbox "Invalid port / 端口无效: $PORT" 8 40
        return 1
    fi

    while true; do
        TOKEN=$(dialog --backtitle "NyxBot-Go Deploy v${SCRIPT_VERSION}" --title "Token" \
            --passwordbox "Token (required) / Token (必填)" 8 50 3>&1 1>&2 2>&3) || return 1
        [[ -n "$TOKEN" ]] && break
        dialog --title "Error / 错误" --msgbox "Token cannot be empty / Token 不能为空" 8 40
    done

    # 是否安装系统命令
    if dialog --backtitle "NyxBot-Go Deploy v${SCRIPT_VERSION}" --title "System Command / 系统命令" \
        --yesno "Install 'nyxbot-go' command to PATH?\n是否安装 'nyxbot-go' 命令到系统路径？" 8 50; then
        INSTALL_CMD="true"
    else
        INSTALL_CMD="false"
    fi

    dialog --backtitle "NyxBot-Go Deploy v${SCRIPT_VERSION}" --title "Confirm / 确认" \
        --yesno "Port / 端口: $PORT\nToken: $(mask_secret "$TOKEN")\nMode / 模式: $WS_MODE\nProxy / 代理: ${PROXY_ADDR:-None / 无}\n\nProceed? / 确认安装?" 12 55 \
        || { log_warn "Cancelled" "已取消"; exit 0; }
    return 0
}

# ============================================================================
# TUI Config (whiptail: 分步单问) / TUI 配置 (whiptail)
# ============================================================================
tui_whiptail() {
    local input

    # 1. Port
    while true; do
        if input=$(whiptail --title "NyxBot-Go Deploy v${SCRIPT_VERSION}" \
            --inputbox "Port / 端口" 8 50 "$PORT" 3>&1 1>&2 2>&3); then
            [[ -n "$input" ]] && PORT="$input"
            if validate_port "$PORT"; then break; fi
            whiptail --title "Error / 错误" --msgbox "Invalid port / 端口无效: $PORT" 8 40 3>&1 1>&2 2>&3
        else
            return 1
        fi
    done

    # 2. Token (required, loop until filled)
    while true; do
        if input=$(whiptail --title "NyxBot-Go Deploy v${SCRIPT_VERSION}" \
            --passwordbox "Token (required) / Token (必填)" 8 50 3>&1 1>&2 2>&3); then
            if [[ -n "${input// /}" ]]; then
                TOKEN="$input"
                break
            fi
            whiptail --title "Error / 错误" --msgbox "Token cannot be empty / Token 不能为空" 8 40 3>&1 1>&2 2>&3
        else
            return 1
        fi
    done

    # 3. Mode
    local mode_choice
    if mode_choice=$(whiptail --title "NyxBot-Go Deploy v${SCRIPT_VERSION}" \
        --menu "Mode / 通讯模式" 12 45 2 \
        "server" "Server / 服务端 (recommended / 推荐)" \
        "client" "Client / 客户端" \
        3>&1 1>&2 2>&3); then
        WS_MODE="$mode_choice"
    else
        return 1
    fi

    # 4. 客户端模式需要 OneBot WS 地址
    if [[ "$WS_MODE" == "client" ]]; then
        if input=$(whiptail --title "NyxBot-Go Deploy v${SCRIPT_VERSION}" \
            --inputbox "OneBot WS URL / 正向 WS 地址" 10 60 "${WS_CLIENT_URL:-$DEFAULT_WS_CLIENT_URL}" 3>&1 1>&2 2>&3); then
            WS_CLIENT_URL="${input:-${WS_CLIENT_URL:-$DEFAULT_WS_CLIENT_URL}}"
        else
            return 1
        fi
    fi

    # 5. Download proxy（仅影响脚本自身下载）
    if input=$(whiptail --title "NyxBot-Go Deploy v${SCRIPT_VERSION}" \
        --inputbox "Download Proxy (Enter to skip, script only) / 下载代理地址 (回车跳过，仅脚本自身使用)\n\ne.g. http://127.0.0.1:7890" 12 60 "${PROXY_ADDR:-}" 3>&1 1>&2 2>&3); then
        PROXY_ADDR="$input"
    else
        return 1
    fi

    # 6. System command
    if whiptail --title "NyxBot-Go Deploy v${SCRIPT_VERSION}" \
        --yesno "Install 'nyxbot-go' command to PATH?\n是否安装 'nyxbot-go' 命令到系统路径？" 8 50; then
        INSTALL_CMD="true"
    else
        INSTALL_CMD="false"
    fi

    # 7. Confirm
    local confirm_text="Port / 端口: $PORT\nToken: $(mask_secret "$TOKEN")\nMode / 模式: $WS_MODE\nProxy / 代理: ${PROXY_ADDR:-None / 无}\nInstall command / 安装命令: $INSTALL_CMD\n\nProceed? / 确认安装?"
    if ! whiptail --title "NyxBot-Go Deploy v${SCRIPT_VERSION}" \
        --yesno "$confirm_text" 14 55; then
        log_warn "Cancelled" "已取消"
        exit 0
    fi
    return 0
}

# ============================================================================
# Help / 帮助
# ============================================================================
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] / 用法: $SCRIPT_NAME [选项]

Mode / 模式:
  --docker          Docker install / 容器安装 (musl/Alpine 环境必须用此项)
  --local           Local binary install / 本地二进制安装

UI / 界面:
  --tui             Terminal dialog form / 终端表单 (requires dialog)
  --text            Line-by-line Q&A / 逐行问答模式
  --quiet           Fully automated / 静默自动化 (requires --token=xxx)

Config / 配置 (for --quiet):
  --port=8080            Service port / 服务端口
  --token=xxx            OneBot access token (required / 必填)
  --server               Server mode / 服务端模式 (default)
  --client               Client mode / 客户端模式
  --ws-url=ws://host:3001  OneBot WS URL for client mode / 客户端模式的正向 WS 地址
  --proxy=URL            Download proxy for this script / 脚本下载代理

System Command / 系统命令:
  --inc      Install 'nyxbot-go' to /usr/local/bin
                         安装为系统命令，全局可用
  --noc   Skip command installation
                         跳过系统命令安装
  --unc    Remove 'nyxbot-go' from system
                         从系统中移除 nyxbot-go 命令

Other / 其他:
  --force   Replace conflicting existing installations without asking
                         检测到冲突安装时直接覆盖（不再询问）
  -h, --help             Show this help / 显示帮助

Notes / 说明:
  - Install layout / 安装布局: ${INSTALL_DIR} + system user '${SERVICE_USER}' + systemd
  - Config is stored in ${CONFIG_FILE} (managed by the app itself)
    配置以程序生成的 config.yaml 为准，脚本只修改端口/模式/Token 等少数键
  - Downloads prefer the latest stable release; if none exists,
    the latest pre-release is used / 下载优先稳定版，无稳定版时用最新预览版

Examples / 示例:
  $SCRIPT_NAME                          # Interactive / 交互
  $SCRIPT_NAME --docker --tui           # Docker + dialog form
  $SCRIPT_NAME --quiet --token=abc123   # Silent / 静默
  $SCRIPT_NAME --local --text           # Local + text Q&A
  $SCRIPT_NAME --inc --quiet --token=abc123  # Install + register command
  $SCRIPT_NAME --unc      # Remove system command
EOF
    exit 0
}

# ============================================================================
# Reconfigure Flow / 重新配置流程 (--tui/--text + 已安装时)
# ============================================================================
reconfigure_flow() {
    log_step "Applying configuration / 应用配置..."
    apply_config

    echo ""
    if check_nyxbot_running; then
        local input
        read -r -t 30 -p "  NyxBot is running. Restart now? / 服务在运行，是否重启? [Y/n]: " input || true
        if [[ ! "$input" =~ ^[Nn]$ ]]; then
            stop_nyxbot
            sleep 1
            start_nyxbot
            log_success "NyxBot restarted" "NyxBot 已重启"
        else
            log_warn "Config saved but service not restarted" "配置已保存，服务未重启"
        fi
    else
        local input
        read -r -t 30 -p "  Start NyxBot now? / 是否立即启动? [Y/n]: " input || true
        if [[ ! "$input" =~ ^[Nn]$ ]]; then
            start_nyxbot
        else
            log_info "Config saved. Start later with: $SCRIPT_NAME" \
                "配置已保存，可稍后运行 '$SCRIPT_NAME' 启动"
        fi
    fi

    exit 0
}

# ============================================================================
# Main / 主入口
# ============================================================================
main() {
    # 默认值
    INSTALL_MODE="auto"
    UI_MODE="auto"
    PORT="$DEFAULT_PORT"
    TOKEN=""
    WS_MODE="server"
    WS_CLIENT_URL=""
    PROXY_ADDR=""
    GITHUB_PROXY=""
    EXPECTED_DIGEST=""
    QUIET=false
    INSTALL_CMD="auto"
    FORCE=false

    # 命令行覆盖标记
    local port_set=false token_set=false mode_set=false wsurl_set=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            --docker) INSTALL_MODE="docker"; shift ;;
            --local)  INSTALL_MODE="local"; shift ;;
            --tui)    UI_MODE="tui"; shift ;;
            --text)   UI_MODE="text"; shift ;;
            --quiet)  QUIET=true; UI_MODE="text"; shift ;;
            --port=*) PORT="${1#*=}"; port_set=true; shift ;;
            --token=*) TOKEN="${1#*=}"; token_set=true; shift ;;
            --server) WS_MODE="server"; mode_set=true; shift ;;
            --client) WS_MODE="client"; mode_set=true; shift ;;
            --ws-url=*) WS_CLIENT_URL="${1#*=}"; wsurl_set=true; shift ;;
            --proxy=*) PROXY_ADDR="${1#*=}"; shift ;;
            --inc) INSTALL_CMD="true"; shift ;;
            --unc) ensure_privilege; uninstall_command; exit 0 ;;
            --noc) INSTALL_CMD="false"; shift ;;
            --force) FORCE=true; shift ;;
            *) log_error "Unknown option: $1" "未知参数: $1"; usage ;;
        esac
    done

    # 静默模式必须提供 token
    if [[ "$QUIET" == "true" && -z "$TOKEN" ]]; then
        log_error "--quiet requires --token=xxx" "--quiet 模式必须提供 --token=xxx"
    fi
    if ! validate_port "$PORT"; then
        log_error "Invalid port: $PORT" "端口无效: $PORT"
    fi

    banner
    detect_os
    ensure_privilege

    # 读取现有 config.yaml 作为默认值（优先级：命令行 > config.yaml > 内置默认）
    if as_root test -s "$CONFIG_FILE" 2>/dev/null; then
        local cur
        if [[ "$port_set" != "true" ]]; then
            cur=$(read_config_value server port)
            [[ -n "$cur" ]] && PORT="$cur"
        fi
        if [[ "$token_set" != "true" ]]; then
            cur=$(read_config_value bot access_token)
            [[ -n "$cur" ]] && TOKEN="$cur"
        fi
        if [[ "$mode_set" != "true" ]]; then
            cur=$(read_config_value bot mode)
            [[ -n "$cur" ]] && WS_MODE="$cur"
        fi
        if [[ "$wsurl_set" != "true" ]]; then
            cur=$(read_config_value bot ws_client_url)
            [[ -n "$cur" ]] && WS_CLIENT_URL="$cur"
        fi
    fi
    WS_CLIENT_URL="${WS_CLIENT_URL:-$DEFAULT_WS_CLIENT_URL}"

    # 如果指定了代理，应用到脚本自身的 curl 请求
    if [[ -n "$PROXY_ADDR" ]]; then
        export http_proxy="$PROXY_ADDR"
        export https_proxy="$PROXY_ADDR"
        log_info "Using proxy for script: $PROXY_ADDR" "脚本使用代理: $PROXY_ADDR"
    fi

    # 自动选择安装模式
    if [[ "$INSTALL_MODE" == "auto" ]]; then
        local detected
        detected="$(detect_install_mode)"
        if [[ "$detected" != "auto" ]]; then
            INSTALL_MODE="$detected"
        elif is_musl; then
            if check_docker &>/dev/null; then
                INSTALL_MODE="docker"
                log_info "musl system detected, using Docker mode" "检测到 musl 系统，使用 Docker 模式"
            else
                log_error "musl system without Docker; official binaries need glibc" \
                    "musl 系统且无 Docker；官方二进制依赖 glibc，无法安装"
            fi
        else
            INSTALL_MODE="local"
        fi
    fi

    # 显示安装方式
    if [[ "$INSTALL_MODE" == "docker" ]]; then
        log_info "Mode: Docker container" "安装方式: Docker 容器"
    else
        log_info "Mode: Local install ($OS_NAME)" "安装方式: 本地安装 ($OS_NAME)"
    fi
    log_info "Directory: ${INSTALL_DIR}" "目录: ${INSTALL_DIR}"
    echo ""

    # 无参数自动模式 + 已安装 + 交互终端 → 管理菜单
    if [[ "$QUIET" != "true" && "$UI_MODE" == "auto" && -t 0 ]] && is_installation_complete; then
        show_menu
    fi

    # --tui/--text + 已安装 → 仅重新配置（--quiet 不触发）
    local reconfigure_only=false
    if [[ "$QUIET" != "true" && ( "$UI_MODE" == "tui" || "$UI_MODE" == "text" ) ]] && is_installation_complete; then
        reconfigure_only=true
    fi

    # 已有有效 Token（来自 config.yaml 或参数）→ 确认是否沿用（--tui/--text 显式时跳过）
    if [[ "$QUIET" != "true" && -n "$TOKEN" && ! "$reconfigure_only" == "true" && "$UI_MODE" != "tui" && "$UI_MODE" != "text" ]]; then
        echo ""
        log_info "Saved config found / 发现已保存配置"
        echo -e "  Port / 端口: ${GREEN}${PORT}${NC}  Mode / 模式: ${GREEN}${WS_MODE}${NC}  Token: ${GREEN}$(mask_secret "$TOKEN")${NC}"
        echo ""
        local input
        read -r -t 30 -p "  Use saved config? / 使用已保存配置? [Y/n]: " input || true
        if [[ ! "$input" =~ ^[Nn]$ ]]; then
            log_info "Using saved config, run --text to reconfigure" "使用已保存配置, 运行 --text 重新配置"
            echo ""
        else
            TOKEN=""  # 清空触发重新配置
        fi
    fi

    # 非交互安装必须显式 --quiet
    if [[ "$QUIET" != "true" && -z "$TOKEN" && ! -t 0 ]] && [[ "$reconfigure_only" != "true" ]]; then
        log_error "Non-interactive install requires --quiet --token=xxx" \
            "非交互安装需要提供 --quiet --token=xxx"
    fi

    # 收集配置
    if [[ "$QUIET" != "true" && "$reconfigure_only" != "true" && ( -z "$TOKEN" || "$UI_MODE" == "tui" || "$UI_MODE" == "text" ) ]]; then
        # 自动检测最佳 TUI 引擎 (SSH 环境下 whiptail/dialog 可能无法显示)
        local tui_failed=false
        if [[ "$UI_MODE" == "auto" ]]; then
            if [[ -t 0 ]]; then
                if command -v dialog &>/dev/null; then
                    UI_MODE="dialog"
                elif command -v whiptail &>/dev/null; then
                    UI_MODE="whiptail"
                else
                    UI_MODE="text"
                fi
            else
                UI_MODE="text"
            fi
        fi

        case "$UI_MODE" in
            dialog|tui)
                if [[ ! -t 0 ]]; then
                    log_error "--tui requires an interactive terminal." "--tui 需要交互式终端。"
                fi
                if command -v dialog &>/dev/null; then
                    tui_dialog || { tui_failed=true; }
                elif command -v whiptail &>/dev/null; then
                    log_warn "dialog not found, falling back to whiptail" "dialog 未找到，降级到 whiptail"
                    tui_whiptail || { tui_failed=true; }
                else
                    tui_failed=true
                fi
                if [[ "$tui_failed" == "true" ]]; then
                    log_warn "TUI not available, falling back to text" "TUI 不可用，降级到文本模式"
                    text_config
                fi
                ;;
            whiptail)
                if [[ ! -t 0 ]]; then
                    log_error "--tui requires an interactive terminal." "--tui 需要交互式终端。"
                fi
                tui_whiptail || {
                    log_warn "whiptail failed, falling back to text" "whiptail 失败，降级到文本模式"
                    text_config
                }
                ;;
            text|*)
                text_config
                ;;
        esac
    fi

    # --tui/--text + 已安装 → 仅重新配置，不走完整安装
    if [[ "$reconfigure_only" == "true" ]]; then
        reconfigure_flow
    fi

    # 执行安装
    case "$INSTALL_MODE" in
        docker) install_docker ;;
        local)  install_local ;;
        *)      log_error "Unknown mode: $INSTALL_MODE" "未知安装模式: $INSTALL_MODE" ;;
    esac
}

main "$@"
