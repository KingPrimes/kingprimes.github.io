#!/usr/bin/env bash
# Script: nyxbot-deploy.sh
# Description: NyxBot 一键部署脚本 (Linux/macOS)
# Usage: curl -fsSL <url> | bash -s -- [options]

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="nyxbot-deploy.sh"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# 常量
# ============================================================================
readonly API_URL="https://api.github.com/repos/KingPrimes/NyxBot/releases/latest"
readonly IMAGE_NAME="kingprimes/nyxbot"
readonly DOWNLOAD_DIR="$SCRIPT_DIR/NyxBot"
readonly DEFAULT_PORT="8080"
readonly DEFAULT_WS_URL="/ws/shiro"
# GitHub 代理列表（测速选最快）
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

# ============================================================================
# 颜色 & 日志
# ============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

log() {
    local msg="${*:2}"
    case "$1" in
        info)    echo -e "${BLUE}[ ]${NC} ${msg}" ;;
        success) echo -e "${GREEN}[✔]${NC} ${msg}" ;;
        warn)    echo -e "${YELLOW}[!]${NC} ${msg}" ;;
        error)   echo -e "${RED}[✘]${NC} ${msg}" ;;
        step)    echo -e "${CYAN}[>]${NC} ${msg}" ;;
        *)       echo -e "${msg}" ;;
    esac
}

banner() {
    echo -e "${GREEN}"
    echo "  _   _           ____        _   "
    echo " | \ | |_  ___  _| __ )  ___ | |_ "
    echo " |  \| \ \/ / | | |  _ \ / _ \| __|"
    echo " | |\  |>  <| |_| | |_) | (_) | |_ "
    echo " |_| \_/_/\_\\__, |____/ \___/ \__|"
    echo "             |___/                  "
    echo -e "${NC}"
    echo -e "  ${BOLD}NyxBot 一键部署脚本${NC}"
    echo ""
}

cleanup() { rm -f /tmp/nyxbot_progress; }
trap cleanup EXIT

# ============================================================================
# 环境检测
# ============================================================================
detect_os() {
    case "$(uname -s)" in
        Linux)  OS="linux";  OS_NAME="$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')" ;;
        Darwin) OS="macos";  OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null)" ;;
        *)      log error "不支持的系统: $(uname -s)"; exit 1 ;;
    esac
    ARCH="$(uname -m)"
    log success "系统: ${OS_NAME} ${ARCH}"
}

check_java() {
    if command -v java &>/dev/null && java -version 2>&1 | grep -qE 'version "21\.'; then
        log success "Java 21: 已安装"
        return 0
    fi
    log warn "Java 21: 未安装"
    return 1
}

install_java() {
    log step "安装 Java 21..."
    case "$OS" in
        linux)
            if command -v apt &>/dev/null; then
                sudo apt update -qq && sudo apt install -y openjdk-21-jre-headless
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y java-21-openjdk-headless
            elif command -v apk &>/dev/null; then
                sudo apk add openjdk21-jre
            else
                log error "无法自动安装 Java，请手动安装 JDK 21"; exit 1
            fi
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install openjdk@21
            else
                log error "请先安装 Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""; exit 1
            fi
            ;;
    esac
    log success "Java 21 安装完成"
}

check_docker() {
    command -v docker &>/dev/null && log success "Docker: 已安装 ($(docker --version | awk '{print $3}' | tr -d ','))" && return 0
    return 1
}

# ============================================================================
# 网络测速
# ============================================================================
format_speed() {
    local bps="$1"
    if (( bps > 1048576 )); then echo "$((bps / 1048576)) MB/s"
    elif (( bps > 1024 )); then echo "$((bps / 1024)) KB/s"
    else echo "${bps} B/s"; fi
}

test_network() {
    log step "网络测速（选择最快路线）..."
    local check_url="https://raw.githubusercontent.com/KingPrimes/DataSource/main/warframe/state_translation.json"
    local best_speed=0
    local best_proxy=""
    local timeout=10

    # 测直连
    local output
    output=$(curl -k -L --connect-timeout "$timeout" --max-time $((timeout * 3)) \
        -o /dev/null -s -w "%{http_code}:%{exitcode}:%{speed_download}" "$check_url" 2>/dev/null || true)
    local code; code=$(echo "$output" | cut -d: -f1)
    local ec; ec=$(echo "$output" | cut -d: -f2)
    local speed; speed=$(echo "$output" | cut -d: -f3 | cut -d. -f1)
    if [[ "$ec" == "0" && "$code" == "200" ]]; then
        best_speed="$speed"
        echo -e "  直连: ${GREEN}$(format_speed $speed)${NC}"
    else
        echo -e "  直连: ${RED}不可用${NC}"
    fi

    # 测代理
    for proxy in "${PROXY_LIST[@]}"; do
        output=$(curl -k -L --connect-timeout "$timeout" --max-time $((timeout * 3)) \
            -o /dev/null -s -w "%{http_code}:%{exitcode}:%{speed_download}" \
            "${proxy}/${check_url}" 2>/dev/null || true)
        code=$(echo "$output" | cut -d: -f1)
        ec=$(echo "$output" | cut -d: -f2)
        speed=$(echo "$output" | cut -d: -f3 | cut -d. -f1)
        local label; label=$(echo "$proxy" | sed 's|https://||')
        if [[ "$ec" == "0" && "$code" == "200" ]]; then
            if (( speed > best_speed )); then
                best_speed="$speed"
                best_proxy="$proxy"
            fi
            echo -e "  ${label}: ${GREEN}$(format_speed $speed)${NC}"
        else
            echo -e "  ${label}: ${RED}不可用${NC}"
        fi
    done

    if [[ -n "$best_proxy" ]]; then
        GITHUB_PROXY="$best_proxy"
        log success "选择: ${best_proxy} ($(format_speed $best_speed))"
    elif (( best_speed > 0 )); then
        GITHUB_PROXY=""
        log success "直连最快 ($(format_speed $best_speed))"
    else
        log warn "所有连接方式不可用，将尝试直连下载"
        GITHUB_PROXY=""
    fi
}

# ============================================================================
# 下载
# ============================================================================
get_latest_release() {
    log step "获取最新版本..."
    local resp; resp=$(curl -sL --connect-timeout 10 \
        -H "User-Agent: Mozilla/5.0" -H "Accept: application/vnd.github.v3+json" \
        "$API_URL" 2>/dev/null)
    if [[ -z "$resp" || "$resp" == *"Not Found"* ]]; then
        log error "无法获取版本信息"; exit 1
    fi
    local jar
    if command -v jq &>/dev/null; then
        jar=$(echo "$resp" | jq -r '.assets[] | select(.name | endswith(".jar"))')
        DOWNLOAD_URL=$(echo "$jar" | jq -r '.browser_download_url' | head -1)
        RELEASE_TAG=$(echo "$resp" | jq -r '.tag_name')
    else
        DOWNLOAD_URL=$(echo "$resp" | grep -o '"browser_download_url": *"[^"]*\.jar"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        RELEASE_TAG=$(echo "$resp" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
    fi
    [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]] && { log error "未找到下载地址"; exit 1; }
    log success "版本: ${RELEASE_TAG}"
}

download_jar() {
    local url="$DOWNLOAD_URL"
    [[ -n "$GITHUB_PROXY" ]] && url="${GITHUB_PROXY}/$(echo "$url" | sed 's|^https://||')"

    mkdir -p "$DOWNLOAD_DIR"
    log step "下载 NyxBot ${RELEASE_TAG}..."
    curl -L -# --connect-timeout 10 --max-time 300 --retry 3 \
        -H "User-Agent: Mozilla/5.0" \
        -o "$DOWNLOAD_DIR/NyxBot.jar" \
        "$url"
    echo "" # curl -# 后换行
    log success "下载完成 ($(du -h "$DOWNLOAD_DIR/NyxBot.jar" | cut -f1))"
}

# ============================================================================
# TUI 配置表单（dialog）
# ============================================================================
tui_config() {
    local tmpfile; tmpfile=$(mktemp /tmp/nyxbot_dialog.XXXXXX)

    dialog --backtitle "NyxBot 部署向导" \
        --title "配置" \
        --form "请填写以下配置，回车继续：" 15 55 0 \
        "端口:"      1 1 "$PORT"       1 15 20 0 \
        "Token:"     2 1 "$TOKEN"      2 15 30 0 \
        "WS模式:"    3 1 "$WS_MODE"    3 15 10 0 \
        "代理地址:"   4 1 "$PROXY_ADDR"  4 15 30 0 \
        "代理用户名:" 5 1 "$PROXY_USER"  5 15 20 0 \
        "代理密码:"   6 1 "$PROXY_PASS"  6 15 20 0 \
        2>"$tmpfile" || { rm -f "$tmpfile"; return 1; }

    # 读取表单返回值
    local i=0
    while IFS= read -r line; do
        case $i in
            0) PORT="${line:-$DEFAULT_PORT}" ;;
            1) TOKEN="$line" ;;
            2) WS_MODE="${line:-server}" ;;
            3) PROXY_ADDR="$line" ;;
            4) PROXY_USER="$line" ;;
            5) PROXY_PASS="$line" ;;
        esac
        ((i++))
    done < "$tmpfile"
    rm -f "$tmpfile"

    # 确认
    dialog --backtitle "NyxBot 部署向导" --title "确认配置" \
        --yesno "端口: $PORT\nToken: ${TOKEN:-未设置}\n模式: $WS_MODE\n代理: ${PROXY_ADDR:-无}\n\n确认开始安装?" 12 50 \
        || { log warn "已取消"; exit 0; }
}

# ============================================================================
# 文本交互配置
# ============================================================================
text_config() {
    echo ""
    echo -e "${BOLD}── 基础配置 ──${NC}"
    read -r -t 10 -p "  端口 [${PORT}]: " input; PORT="${input:-$PORT}"
    read -r -p "  Token (必填): " TOKEN
    while [[ -z "$TOKEN" ]]; do
        read -r -p "  Token 不能为空，请重新输入: " TOKEN
    done

    echo ""
    echo -e "${BOLD}── 通讯模式 ──${NC}"
    echo "  1) 服务端（推荐）  2) 客户端"
    read -r -t 10 -p "  选择 [1]: " input
    if [[ "$input" == "2" ]]; then WS_MODE="client"; else WS_MODE="server"; fi

    echo ""
    echo -e "${BOLD}── 代理（可选，回车跳过）──${NC}"
    read -r -p "  代理地址 (如 http://127.0.0.1:7890): " PROXY_ADDR
    if [[ -n "$PROXY_ADDR" ]]; then
        read -r -p "  代理用户名: " PROXY_USER
        read -r -p "  代理密码: " PROXY_PASS
    fi

    echo ""
    echo -e "${BOLD}── 确认 ──${NC}"
    echo -e "  端口: ${GREEN}${PORT}${NC} | 模式: ${GREEN}${WS_MODE}${NC} | Token: ${GREEN}${TOKEN}${NC}"
    echo -e "  代理: ${YELLOW}${PROXY_ADDR:-无}${NC}"
    read -r -t 10 -p "  确认开始安装? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && { log warn "已取消"; exit 0; }
}

# ============================================================================
# Docker 镜像拉取（国内镜像源自动切换）
# ============================================================================
# 国内 Docker Hub 代理列表（按优先级）
# 国内 Docker Hub 代理列表（已测试连通性）
readonly DOCKER_MIRRORS=(
    "docker.1panel.live"
    "docker.m.daocloud.io"
    "hub.rat.dev"
)

pull_image() {
    local image="$1"

    # 先尝试直连 Docker Hub
    log step "拉取镜像: ${image}"
    if docker pull "${image}" 2>/dev/null; then
        log success "镜像拉取成功（直连 Docker Hub）"
        return 0
    fi
    log warn "Docker Hub 直连失败，尝试国内镜像源..."

    # 逐个尝试镜像源
    for mirror in "${DOCKER_MIRRORS[@]}"; do
        local mirror_image="${mirror}/${image}"
        log step "  尝试: ${mirror_image}"
        if docker pull "${mirror_image}" 2>/dev/null; then
            # 拉取成功后 tag 成原名
            docker tag "${mirror_image}" "${image}" 2>/dev/null
            docker rmi "${mirror_image}" 2>/dev/null || true
            log success "镜像拉取成功（via ${mirror}）"
            return 0
        fi
    done

    log error "所有镜像源均不可用，请检查网络或手动配置 Docker 镜像加速器"
    log info "手动配置: 编辑 /etc/docker/daemon.json → 添加 registry-mirrors → systemctl restart docker"
    return 1
}

# ============================================================================
# Docker 安装
# ============================================================================
install_docker() {
    log step "Docker 模式安装..."

    local docker_args=(
        "run" "-d" "--name" "nyxbot"
        "--restart" "unless-stopped"
        "-p" "${PORT}:8080"
        "-e" "SERVER_PORT=${PORT}"
        "-e" "DEBUG=${DEBUG:-false}"
        "-e" "SHIRO_TOKEN=${TOKEN}"
        "-e" "TZ=Asia/Shanghai"
        "-v" "${DOWNLOAD_DIR}/data:/app/data"
        "-v" "${DOWNLOAD_DIR}/logs:/app/logs"
    )

    # WebSocket 配置
    if [[ "$WS_MODE" == "server" ]]; then
        docker_args+=("-e" "SHIRO_WS_SERVER_ENABLE=true")
    else
        docker_args+=("-e" "SHIRO_WS_SERVER_ENABLE=false")
        docker_args+=("-e" "SHIRO_WS_CLIENT_ENABLE=true")
    fi

    # 代理配置
    [[ -n "${PROXY_ADDR:-}" ]] && docker_args+=("-e" "HTTP_PROXY=${PROXY_ADDR}")
    [[ -n "${PROXY_USER:-}" ]] && docker_args+=("-e" "PROXY_USER=${PROXY_USER}")
    [[ -n "${PROXY_PASS:-}" ]] && docker_args+=("-e" "PROXY_PASSWORD=${PROXY_PASS}")

    docker_args+=("${IMAGE_NAME}:latest")

    # 停止旧容器
    docker stop nyxbot 2>/dev/null && docker rm nyxbot 2>/dev/null || true

    # 拉取镜像（国内镜像源自动切换）
    pull_image "${IMAGE_NAME}:latest" || exit 1

    log step "启动容器..."
    docker "${docker_args[@]}" || { log error "容器启动失败"; exit 1; }

    log success "NyxBot 已启动 (容器: nyxbot)"
    show_post_install "docker"
}

# ============================================================================
# 本地安装
# ============================================================================
install_local() {
    # Java 检查
    if ! check_java; then install_java; fi

    # 下载
    test_network
    get_latest_release
    download_jar

    # 构建启动参数
    build_launch_args

    # 配置服务
    if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null; then
        install_systemd
    else
        install_nohup
    fi

    log success "NyxBot 已启动 (PID: $(cat "$DOWNLOAD_DIR/nyxbot.pid" 2>/dev/null || echo 'nohup'))"
    show_post_install "local"
}

build_launch_args() {
    LAUNCH_ARGS="-jar $DOWNLOAD_DIR/NyxBot.jar -serverPort=${PORT}"
    [[ "$WS_MODE" == "server" ]] && LAUNCH_ARGS="$LAUNCH_ARGS -wsServerEnable"
    LAUNCH_ARGS="$LAUNCH_ARGS -shiroToken=${TOKEN}"
    [[ -n "${PROXY_ADDR:-}" ]] && LAUNCH_ARGS="$LAUNCH_ARGS -httpProxy=${PROXY_ADDR}"
    [[ -n "${PROXY_USER:-}" ]] && LAUNCH_ARGS="$LAUNCH_ARGS -proxyUser=${PROXY_USER}"
    [[ -n "${PROXY_PASS:-}" ]] && LAUNCH_ARGS="$LAUNCH_ARGS -proxyPassword=${PROXY_PASS}"
}

install_systemd() {
    log step "创建 systemd 服务..."
    local service_file="/etc/systemd/system/nyxbot.service"
    sudo tee "$service_file" >/dev/null <<EOF
[Unit]
Description=NyxBot Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/java $LAUNCH_ARGS
WorkingDirectory=$DOWNLOAD_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now nyxbot
}

install_nohup() {
    log step "nohup 模式启动..."
    cd "$DOWNLOAD_DIR"
    nohup java $LAUNCH_ARGS > nyxbot.log 2>&1 &
    echo $! > nyxbot.pid
}

# ============================================================================
# 安装后提示
# ============================================================================
show_post_install() {
    local mode="$1"
    echo ""
    echo -e "${GREEN}┌──────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│        NyxBot 安装完成！                   │${NC}"
    echo -e "${GREEN}├──────────────────────────────────────────┤${NC}"
    echo -e "${GREEN}│${NC}  管理页面: ${CYAN}http://localhost:${PORT}${NC}"
    echo -e "${GREEN}│${NC}  数据目录: ${DOWNLOAD_DIR}"
    if [[ "$mode" == "docker" ]]; then
        echo -e "${GREEN}│${NC}  查看日志: ${CYAN}docker logs -f nyxbot${NC}"
        echo -e "${GREEN}│${NC}  重启:     ${CYAN}docker restart nyxbot${NC}"
        echo -e "${GREEN}│${NC}  停止:     ${CYAN}docker stop nyxbot${NC}"
    else
        echo -e "${GREEN}│${NC}  查看日志: ${CYAN}tail -f ${DOWNLOAD_DIR}/nyxbot.log${NC}"
        if command -v systemctl &>/dev/null; then
            echo -e "${GREEN}│${NC}  重启:     ${CYAN}systemctl restart nyxbot${NC}"
            echo -e "${GREEN}│${NC}  状态:     ${CYAN}systemctl status nyxbot${NC}"
        fi
    fi
    echo -e "${GREEN}└──────────────────────────────────────────┘${NC}"
}

# ============================================================================
# 帮助
# ============================================================================
usage() {
    cat <<EOF
用法: $SCRIPT_NAME [选项]

模式选择:
  --docker          Docker 安装（拉取镜像启动）
  --local           本地安装（下载 jar 运行）

界面选择:
  --tui             可视化表单（需要 dialog，默认）
  --text            逐行问答模式
  --quiet           静默模式（配合下面的参数完全自动化）

配置参数（--quiet 时使用）:
  --port=8080       服务端口
  --token=xxx       OneBot Token（必填）
  --server          服务端模式（默认）
  --client          客户端模式
  --proxy=URL       代理地址
  --debug            开启 Debug

示例:
  $SCRIPT_NAME                          # 交互式部署
  $SCRIPT_NAME --docker --tui           # Docker + 可视化表单
  $SCRIPT_NAME --quiet --token=abc123   # 静默安装
  $SCRIPT_NAME --local --text           # 本地 + 文本问答
EOF
    exit 0
}

# ============================================================================
# 主入口
# ============================================================================
main() {
    # 默认值
    local INSTALL_MODE="auto"
    local UI_MODE="auto"
    PORT="$DEFAULT_PORT"
    TOKEN=""
    WS_MODE="server"
    PROXY_ADDR=""
    PROXY_USER=""
    PROXY_PASS=""
    DEBUG="false"
    GITHUB_PROXY=""
    QUIET=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage ;;
            --docker) INSTALL_MODE="docker"; shift ;;
            --local)  INSTALL_MODE="local"; shift ;;
            --tui)    UI_MODE="tui"; shift ;;
            --text)   UI_MODE="text"; shift ;;
            --quiet)  QUIET=true; UI_MODE="text"; shift ;;
            --port=*) PORT="${1#*=}"; shift ;;
            --token=*) TOKEN="${1#*=}"; shift ;;
            --server) WS_MODE="server"; shift ;;
            --client) WS_MODE="client"; shift ;;
            --proxy=*) PROXY_ADDR="${1#*=}"; shift ;;
            --proxy-user=*) PROXY_USER="${1#*=}"; shift ;;
            --proxy-pass=*) PROXY_PASS="${1#*=}"; shift ;;
            --debug) DEBUG="true"; shift ;;
            *) log error "未知参数: $1"; usage ;;
        esac
    done

    # 静默模式必须提供 token
    if [[ "$QUIET" == "true" && -z "$TOKEN" ]]; then
        log error "--quiet 模式必须提供 --token=xxx"; exit 1
    fi

    banner
    detect_os

    # 自动选择安装模式
    if [[ "$INSTALL_MODE" == "auto" ]]; then
        if check_docker; then
            INSTALL_MODE="docker"
        else
            INSTALL_MODE="local"
        fi
    fi

    # 显示安装方式 & 路径
    if [[ "$INSTALL_MODE" == "docker" ]]; then
        log info "安装方式: Docker 容器模式"
        log info "数据目录: ${DOWNLOAD_DIR} (映射至容器 /app/data)"
    else
        log info "安装方式: 本地安装 (${OS_NAME})"
        log info "安装目录: ${DOWNLOAD_DIR}"
    fi
    echo ""

    # 配置收集
    if [[ "$QUIET" != "true" ]]; then
        if [[ "$UI_MODE" == "auto" ]]; then
            if command -v dialog &>/dev/null; then UI_MODE="tui"; else UI_MODE="text"; fi
        fi
        if [[ "$UI_MODE" == "tui" ]]; then
            tui_config || { log error "表单取消"; exit 1; }
        else
            text_config
        fi
    fi

    # 执行安装
    case "$INSTALL_MODE" in
        docker) install_docker ;;
        local)  install_local ;;
        *) log error "未知安装模式: $INSTALL_MODE"; exit 1 ;;
    esac
}

main "$@"
