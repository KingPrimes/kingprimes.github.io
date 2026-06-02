#!/usr/bin/env bash
# Script: nyxbot-deploy.sh
# Description: NyxBot One-Click Deploy Script (Linux/macOS) / NyxBot 一键部署脚本
# Usage: curl -fsSL <url> | bash -s -- [options]

set -uo pipefail  # -e disabled: don't exit on non-zero return (handled explicitly)
IFS=$'\n\t'

readonly SCRIPT_NAME="nyxbot-deploy.sh"
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Constants / 常量
# ============================================================================
readonly API_URL="https://api.github.com/repos/KingPrimes/NyxBot/releases/latest"
readonly IMAGE_NAME="kingprimes/nyxbot"
readonly INSTALL_BASE="${NYXBOT_HOME:-$HOME}/NyxBot"
readonly DOWNLOAD_DIR="$INSTALL_BASE"
readonly DEFAULT_PORT="8080"
readonly CONFIG_FILE="$DOWNLOAD_DIR/.nyxbot_config.json"

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

banner() {
    echo -e "${GREEN}"
    echo ".__   __. ____    ____ ___   ___ .______     ______   .___________."
    echo "|  \\ |  | \\   \\  /   / \\  \\ /  / |   _  \\   /  __  \\  |           |"
    echo "|   \\|  |  \\   \\/   /   \\  V  /  |  |_)  | |  |  |  | \`---|  |----\`"
    echo "|  . \`  |   \\_    _/     >   <   |   _  <  |  |  |  |     |  |     "
    echo "|  |\\   |     |  |      /  .  \\  |  |_)  | |  \`--'  |     |  |     "
    echo "|__| \\__|     |__|     /__/ \\__\\ |______/   \\______/      |__|     "
    echo -e "${NC}"
    echo -e "  ${BOLD}NyxBot Deploy v${SCRIPT_VERSION} / NyxBot 一键部署脚本${NC}"
    echo ""
}

cleanup() {
    rm -rf /tmp/nyxbot_deploy_* 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================================
# Environment Detection / 环境检测
# ============================================================================
detect_os() {
    case "$(uname -s)" in
        Linux)  OS="linux";  OS_NAME="$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')" ;;
        Darwin) OS="macos";  OS_NAME="macOS $(sw_vers -productVersion 2>/dev/null)" ;;
        *)      log_error "Unsupported system: $(uname -s)" "不支持的系统: $(uname -s)" ;;
    esac
    ARCH="$(uname -m)"
    log_success "System: ${OS_NAME} ${ARCH}" "系统: ${OS_NAME} ${ARCH}"
}

check_java() {
    if command -v java &>/dev/null; then
        local v
        v=$(java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -1 || true)
        if [[ -n "$v" && "$v" -ge 21 ]]; then
            log_success "Java $v: installed" "Java $v: 已安装"
            return 0
        fi
        log_warn "Java $v: need >= 21" "Java $v: 需要 >= 21"
        return 1
    fi
    log_warn "Java: not installed" "Java: 未安装"
    return 1
}

install_java() {
    log_step "Installing Java 21..." "安装 Java 21..."
    case "$OS" in
        linux)
            if command -v apt &>/dev/null; then
                log_info "This may take a minute..." "可能需要几分钟，请耐心等待..."
                sudo apt update -qq && sudo apt install -y openjdk-21-jre-headless
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y java-21-openjdk-headless
            elif command -v apk &>/dev/null; then
                sudo apk add openjdk21-jre
            else
                log_error "Cannot auto-install Java. Please install JDK 21 manually" \
                    "无法自动安装 Java，请手动安装 JDK 21"
            fi
            ;;
        macos)
            if command -v brew &>/dev/null; then
                brew install openjdk@21
            else
                log_error "Please install Homebrew first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"" \
                    "请先安装 Homebrew"
            fi
            ;;
    esac
    log_success "Java 21 installed" "Java 21 安装完成"
}

check_docker() {
    command -v docker &>/dev/null \
        && log_success "Docker: installed ($(docker --version | awk '{print $3}' | tr -d ','))" \
            "Docker: 已安装 ($(docker --version | awk '{print $3}' | tr -d ','))" \
        && return 0
    return 1
}

# 检查 Docker 守护进程是否运行
check_docker_running() {
    if docker info &>/dev/null 2>&1; then
        return 0
    fi
    log_warn "Docker daemon not running" "Docker 守护进程未运行"
    return 1
}

# 检查 NyxBot 是否正在运行 (HTTP 探活 + 进程检测)
check_nyxbot_running() {
    if curl -s --connect-timeout 2 "http://localhost:${PORT}" &>/dev/null; then
        return 0
    fi
    if pgrep -f "NyxBot.jar" &>/dev/null; then
        return 0
    fi
    return 1
}

# 停止运行中的 NyxBot
stop_nyxbot() {
    log_step "Stopping running NyxBot..." "停止运行中的 NyxBot..."
    local stopped=false

    if command -v systemctl &>/dev/null && systemctl is-active --quiet nyxbot 2>/dev/null; then
        sudo systemctl stop nyxbot 2>/dev/null || true
        stopped=true
    fi

    local pids
    pids=$(pgrep -f "NyxBot.jar" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "$pids" | xargs kill 2>/dev/null || true
        sleep 1
        pids=$(pgrep -f "NyxBot.jar" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            echo "$pids" | xargs kill -9 2>/dev/null || true
        fi
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
        local mbps
        mbps=$(echo "scale=1; $bps / 1048576" | bc 2>/dev/null || echo $((bps / 1048576)))
        echo "${mbps} MB/s"
    elif (( bps > 1024 )); then
        local kbps
        kbps=$(echo "scale=1; $bps / 1024" | bc 2>/dev/null || echo $((bps / 1024)))
        echo "${kbps} KB/s"
    else
        echo "${bps} B/s"
    fi
}

format_size() {
    local bytes="$1"
    if (( bytes > 1048576 )); then
        local mb
        mb=$(echo "scale=1; $bytes / 1048576" | bc 2>/dev/null || echo $((bytes / 1048576)))
        echo "${mb} MB"
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
    if [[ "$code" == "200" && "$speed" -gt 0 ]]; then
        echo -e " ${GREEN}$(format_speed $speed)${NC}"
        best_speed="$speed"
    else
        echo -e " ${RED}unreachable / 不可达${NC}"
    fi

    # 串行测所有代理
    for proxy in "${PROXY_LIST[@]}"; do
        local label; label=$(echo "$proxy" | sed 's|https://||')
        echo -ne "  Testing: ${label}..."
        output=$(curl -k -L --connect-timeout "$timeout" --max-time $((timeout * 2)) \
            -o /dev/null -s -w "%{http_code}:%{speed_download}" \
            "${proxy}/${check_url}" 2>/dev/null || true)
        code=$(echo "$output" | cut -d: -f1)
        speed=$(echo "$output" | cut -d: -f2 | cut -d. -f1)
        if [[ "$code" == "200" && "$speed" -gt 0 ]]; then
            echo -e " ${GREEN}$(format_speed $speed)${NC}"
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
        log_success "Best: ${best_proxy} ($(format_speed $best_speed))" \
            "最快: ${best_proxy} ($(format_speed $best_speed))"
    elif (( best_speed > 0 )); then
        GITHUB_PROXY=""
        log_success "Direct connection fastest ($(format_speed $best_speed))" \
            "直连最快 ($(format_speed $best_speed))"
    else
        log_warn "All unreachable, will try direct" "全部不可达，将尝试直连"
        GITHUB_PROXY=""
    fi
}

# ============================================================================
# Config Persistence / 配置持久化
# ============================================================================
save_config() {
    mkdir -p "$DOWNLOAD_DIR"
    local config_json
    config_json=$(cat <<CONFEOF
{
  "port": "${PORT}",
  "token": "${TOKEN}",
  "ws_mode": "${WS_MODE}",
  "proxy_addr": "${PROXY_ADDR}",
  "proxy_user": "${PROXY_USER}",
  "proxy_pass": "${PROXY_PASS}",
  "debug": "${DEBUG}"
}
CONFEOF
)
    echo "$config_json" > "$CONFIG_FILE"
    log_info "Config saved to ${CONFIG_FILE}" "配置已保存到 ${CONFIG_FILE}"
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || return 0

    if command -v jq &>/dev/null; then
        [[ "$PORT" == "$DEFAULT_PORT" ]] && PORT=$(jq -r '.port // empty' "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_PORT")
        [[ -z "$TOKEN" ]] && TOKEN=$(jq -r '.token // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        [[ "$WS_MODE" == "server" && -z "$WS_MODE_OVERRIDE" ]] && \
            WS_MODE=$(jq -r '.ws_mode // "server"' "$CONFIG_FILE" 2>/dev/null || echo "server")
        [[ -z "$PROXY_ADDR" ]] && PROXY_ADDR=$(jq -r '.proxy_addr // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        [[ -z "$PROXY_USER" ]] && PROXY_USER=$(jq -r '.proxy_user // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        [[ -z "$PROXY_PASS" ]] && PROXY_PASS=$(jq -r '.proxy_pass // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    else
        local val
        [[ "$PORT" == "$DEFAULT_PORT" ]] && { val=$(grep -o '"port": *"[^"]*"' "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true); [[ -n "$val" ]] && PORT="$val"; }
        [[ -z "$TOKEN" ]] && { val=$(grep -o '"token": *"[^"]*"' "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true); [[ -n "$val" ]] && TOKEN="$val"; }
    fi
}

# ============================================================================
# Version & Download / 版本获取 & 下载
# ============================================================================
get_latest_release() {
    log_step "Fetching latest version..." "获取最新版本..."
    local resp
    resp=$(curl -sL --connect-timeout 10 \
        -H "User-Agent: Mozilla/5.0" -H "Accept: application/vnd.github.v3+json" \
        "$API_URL" 2>/dev/null)
    if [[ -z "$resp" || "$resp" == *"Not Found"* ]]; then
        log_error "Failed to fetch version info" "无法获取版本信息"
    fi

    if command -v jq &>/dev/null; then
        local jar_info
        jar_info=$(echo "$resp" | jq -r '.assets[] | select(.name | endswith(".jar"))')
        DOWNLOAD_URL=$(echo "$jar_info" | jq -r '.browser_download_url' | head -1)
        RELEASE_TAG=$(echo "$resp" | jq -r '.tag_name')
        EXPECTED_DIGEST=$(echo "$jar_info" | jq -r 'select(.digest != null) | .digest' 2>/dev/null | head -1 || echo "")
        EXPECTED_DIGEST="${EXPECTED_DIGEST#sha256:}"
    else
        DOWNLOAD_URL=$(echo "$resp" | grep -o '"browser_download_url": *"[^"]*\.jar"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        RELEASE_TAG=$(echo "$resp" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
        EXPECTED_DIGEST=""
    fi

    [[ -z "$DOWNLOAD_URL" || "$DOWNLOAD_URL" == "null" ]] && \
        log_error "No download URL found" "未找到下载地址"
    log_success "Version: ${RELEASE_TAG}" "版本: ${RELEASE_TAG}"
}

# SHA256 校验
verify_sha256() {
    local file="$1"
    local expected="$2"

    echo -ne "  Verifying SHA256 / 校验完整性..."
    local hash=""
    if command -v sha256sum &>/dev/null; then
        hash=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        hash=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        echo -e " ${YELLOW}Skipped (no sha256sum/shasum)${NC}"
        return 0
    fi

    if [[ "$hash" == "$expected" ]]; then
        echo -e " ${GREEN}OK / 通过${NC}"
    else
        echo ""
        log_error "SHA256 mismatch! File may be corrupted." \
            "SHA256 校验失败！文件可能损坏。"
        log_error "  Expected / 期望: ${expected}" \
            "  Expected / 期望: ${expected}"
        log_error "  Got / 实际:      ${hash}" \
            "  Got / 实际:      ${hash}"
        rm -f "$file"
        log_error "File deleted, please retry." "文件已删除，请重试。"
    fi
}

# 单线程下载
single_download() {
    local url="$1"
    local dest="$2"
    local total_size="$3"

    if [[ -n "$total_size" && "$total_size" -gt 0 ]]; then
        log_info "File size: $(format_size $total_size)" "文件大小: $(format_size $total_size)"
    fi

    log_step "Downloading NyxBot ${RELEASE_TAG}..." "下载 NyxBot ${RELEASE_TAG}..."
    curl -L -# --connect-timeout 10 --max-time 600 --retry 3 \
        -H "User-Agent: Mozilla/5.0" \
        -o "$dest" \
        "$url"
    echo ""
    log_success "Download complete ($(du -h "$dest" | cut -f1))" \
        "下载完成 ($(du -h "$dest" | cut -f1))"
}

# 分块下载 (>10MB 文件)
chunked_download() {
    local url="$1"
    local dest="$2"
    local total_size="$3"
    local num_chunks=4
    local chunk_size=$(( (total_size + num_chunks - 1) / num_chunks ))
    tmpdir=$(mktemp -d /tmp/nyxbot_deploy_chunks.XXXXXX)

    log_step "Chunked download (${num_chunks} chunks)" "分块下载 (${num_chunks} 块)..."

    # 测试 Range 支持
    echo -ne "  Testing Range support with chunk 0 / 测试首块 Range 支持..."
    local start0=0
    local end0=$((chunk_size - 1))
    local expected0=$((end0 - start0 + 1))
    local http_code
    http_code=$(curl -k -L --connect-timeout 10 --max-time 60 \
        -H "User-Agent: Mozilla/5.0" \
        -r "$start0-$end0" \
        -o "$tmpdir/chunk_0" \
        -w "%{http_code}" \
        -s "$url" 2>/dev/null || echo "000")

    local actual_size=0
    [[ -f "$tmpdir/chunk_0" ]] && actual_size=$(wc -c < "$tmpdir/chunk_0" | tr -d ' ')

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

    log_success "Range supported, downloading chunks" \
        "Range 支持，逐块下载"

    # 计算实际需要下载的剩余分块数
    local actual_chunks=1
    for ((i = 1; i < num_chunks; i++)); do
        local start=$((i * chunk_size))
        [[ $start -ge $total_size ]] && break
        ((actual_chunks++))
    done

    # 串行下载剩余分块
    local total_remaining=$((actual_chunks - 1))
    local all_ok=true
    for ((i = 1; i < num_chunks; i++)); do
        local start=$((i * chunk_size))
        [[ $start -ge $total_size ]] && break
        local end=$(( (i + 1) * chunk_size - 1 ))
        [[ $end -ge $total_size ]] && end=$((total_size - 1))
        local expected=$((end - start + 1))

        local chunk_file="$tmpdir/chunk_${i}"
        echo -ne "  Chunk ${i}/${total_remaining} / 分块 ${i}/${total_remaining}..."
        local code
        code=$(curl -k -L --connect-timeout 10 --max-time 120 \
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
        log_success "Download complete ($(format_size $assembled_size))" \
            "下载完成 ($(format_size $assembled_size))"
    else
        echo -e " ${RED}Size mismatch: expected $(format_size $total_size), got $(format_size $assembled_size)${NC}"
        rm -f "$dest"
        return 1
    fi
}

# 下载入口
download_jar() {
    local url="$1"
    mkdir -p "$DOWNLOAD_DIR"
    local dest="$DOWNLOAD_DIR/NyxBot.jar"

    # 更新检测：已有文件且 hash 一致则跳过
    if [[ -f "$dest" && -n "$EXPECTED_DIGEST" && "$EXPECTED_DIGEST" != "null" ]]; then
        echo -ne "  Checking existing JAR / 检测已有文件..."
        local local_hash=""
        if command -v sha256sum &>/dev/null; then
            local_hash=$(sha256sum "$dest" | awk '{print $1}')
        elif command -v shasum &>/dev/null; then
            local_hash=$(shasum -a 256 "$dest" | awk '{print $1}')
        fi
        if [[ -n "$local_hash" && "$local_hash" == "$EXPECTED_DIGEST" ]]; then
            echo -e " ${GREEN}Up-to-date / 已是最新${NC}"
            log_success "Already latest, skip download" "已是最新版本，跳过下载"
            log_info "Current version: ${RELEASE_TAG}" "当前版本: ${RELEASE_TAG}"
            return 0
        else
            echo -e " ${YELLOW}Outdated / 版本过旧${NC}"
            if [[ -n "$local_hash" ]]; then
                log_warn "  Current / 当前: ${local_hash:0:16}..." \
                    "  Current / 当前: ${local_hash:0:16}..."
                log_warn "  Latest  / 最新: ${EXPECTED_DIGEST:0:16}..." \
                    "  Latest  / 最新: ${EXPECTED_DIGEST:0:16}..."
            fi
            if [[ "$QUIET" != "true" ]]; then
                read -r -t 10 -p "  Update now? / 是否更新? [Y/n]: " confirm || true
                if [[ "$confirm" =~ ^[Nn]$ ]]; then
                    log_warn "Skipping update, using existing version" \
                        "跳过更新，使用现有版本"
                    return 0
                fi
            fi
        fi
    fi

    # 拼接代理 URL
    local dl_url="$url"
    [[ -n "$GITHUB_PROXY" ]] && dl_url="${GITHUB_PROXY}/$(echo "$url" | sed 's|^https://||')"

    # 探测文件大小
    local total_size
    total_size=$(get_file_size "$dl_url")
    local use_chunked=false
    if [[ -n "$total_size" && "$total_size" -gt 10485760 ]]; then
        use_chunked=true
    fi

    # 下载
    if [[ "$use_chunked" == "true" ]]; then
        chunked_download "$dl_url" "$dest" "$total_size" || {
            log_warn "Chunked download failed, fallback to single-thread" \
                "分块下载失败，回退单线程"
            single_download "$dl_url" "$dest" "$total_size"
        }
    else
        single_download "$dl_url" "$dest" "$total_size"
    fi

    # SHA256 校验
    if [[ -n "$EXPECTED_DIGEST" && "$EXPECTED_DIGEST" != "null" ]]; then
        verify_sha256 "$dest" "$EXPECTED_DIGEST"
    fi
}

# ============================================================================
# Docker Image Pull / Docker 镜像拉取
# ============================================================================
pull_image() {
    local image="$1"

    log_step "Pulling image: ${image}" "拉取镜像: ${image}"
    if docker pull "${image}" 2>/dev/null; then
        log_success "Image pulled (Docker Hub)" "镜像拉取成功 (Docker Hub)"
        return 0
    fi
    log_warn "Docker Hub unreachable, trying mirrors..." \
        "Docker Hub 不可达，尝试国内镜像源..."

    for mirror in "${DOCKER_MIRRORS[@]}"; do
        local mirror_image="${mirror}/${image}"
        log_step "  Trying: ${mirror_image}" "  尝试: ${mirror_image}"
        if docker pull "${mirror_image}" 2>/dev/null; then
            docker tag "${mirror_image}" "${image}" 2>/dev/null
            docker rmi "${mirror_image}" 2>/dev/null || true
            log_success "Image pulled (via ${mirror})" \
                "镜像拉取成功 (via ${mirror})"
            return 0
        fi
    done

    log_error "All mirrors unavailable. Check network or configure /etc/docker/daemon.json" \
        "所有镜像源不可用，请检查网络或手动配置 /etc/docker/daemon.json"
}

# ============================================================================
# Docker Install / Docker 安装
# ============================================================================
install_docker() {
    log_step "Docker mode install..." "Docker 模式安装..."

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

    if [[ "$WS_MODE" == "server" ]]; then
        docker_args+=("-e" "SHIRO_WS_SERVER_ENABLE=true")
    else
        docker_args+=("-e" "SHIRO_WS_SERVER_ENABLE=false")
        docker_args+=("-e" "SHIRO_WS_CLIENT_ENABLE=true")
    fi

    [[ -n "${PROXY_ADDR:-}" ]] && docker_args+=("-e" "HTTP_PROXY=${PROXY_ADDR}")
    [[ -n "${PROXY_USER:-}" ]] && docker_args+=("-e" "PROXY_USER=${PROXY_USER}")
    [[ -n "${PROXY_PASS:-}" ]] && docker_args+=("-e" "PROXY_PASSWORD=${PROXY_PASS}")

    docker_args+=("${IMAGE_NAME}:latest")

    # 停止旧容器
    docker stop nyxbot 2>/dev/null && docker rm nyxbot 2>/dev/null || true

    # 拉取镜像
    pull_image "${IMAGE_NAME}:latest" || exit 1

    log_step "Starting container..." "启动容器..."
    docker "${docker_args[@]}" || log_error "Container start failed" "容器启动失败"

    log_success "NyxBot started (container: nyxbot)" \
        "NyxBot 已启动 (容器: nyxbot)"
    show_post_install "docker"
    if [[ "$INSTALL_CMD" == "true" ]]; then install_command; fi
}

# ============================================================================
# Local Install / 本地安装
# ============================================================================
install_local() {
    # Java 检查
    if ! check_java; then install_java; fi

    # 停止旧实例
    if check_nyxbot_running; then
        stop_nyxbot
    fi

    # 获取版本 + 按需下载
    get_latest_release
    # 先判断是否需要下载，避免在 jar 已最新时跑测速
    local need_dl=true
    local dest="$DOWNLOAD_DIR/NyxBot.jar"
    if [[ -f "$dest" && -n "$EXPECTED_DIGEST" && "$EXPECTED_DIGEST" != "null" ]]; then
        local local_hash
        if command -v sha256sum &>/dev/null; then
            local_hash=$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')
        elif command -v shasum &>/dev/null; then
            local_hash=$(shasum -a 256 "$dest" 2>/dev/null | awk '{print $1}')
        fi
        if [[ -n "$local_hash" && "$local_hash" == "$EXPECTED_DIGEST" ]]; then
            log_success "Already latest, skip download (${RELEASE_TAG})" "已是最新，跳过下载 (${RELEASE_TAG})"
            need_dl=false
        fi
    fi
    if [[ "$need_dl" == "true" ]]; then
        [[ -z "$PROXY_ADDR" ]] && test_network
        download_jar "$DOWNLOAD_URL"
    fi

    # 构建启动参数
    build_launch_args

    # 配置服务
    if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null; then
        install_systemd
    else
        install_nohup
    fi

    if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null; then
        log_success "NyxBot started (systemd)" "NyxBot 已启动 (systemd)"
    else
        log_success "NyxBot started (PID: $(cat "$DOWNLOAD_DIR/nyxbot.pid" 2>/dev/null || echo 'n/a'))" \
            "NyxBot 已启动 (PID: $(cat "$DOWNLOAD_DIR/nyxbot.pid" 2>/dev/null || echo 'n/a'))"
    fi
    show_post_install "local"
    if [[ "$INSTALL_CMD" == "true" ]]; then install_command; fi
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
    log_step "Creating systemd service..." "创建 systemd 服务..."
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
    log_success "systemd service installed and started" "systemd 服务已安装并启动"
}

install_nohup() {
    log_step "Starting with nohup..." "nohup 模式启动..."
    cd "$DOWNLOAD_DIR"
    nohup java $LAUNCH_ARGS > nyxbot.log 2>&1 &
    echo $! > nyxbot.pid
}

# ============================================================================
# Post Install Display / 安装后提示
# ============================================================================
show_post_install() {
    local mode="$1"
    echo ""
    echo -e "${GREEN}┌──────────────────────────────────────────┐${NC}"
    echo -e "${GREEN}│        NyxBot Install Complete!           │${NC}"
    echo -e "${GREEN}│        NyxBot 安装完成！                   │${NC}"
    echo -e "${GREEN}├──────────────────────────────────────────┤${NC}"
    echo -e "${GREEN}│${NC}  Dashboard / 管理页面: ${CYAN}http://localhost:${PORT}${NC}"
    echo -e "${GREEN}│${NC}  Data / 数据目录: ${DOWNLOAD_DIR}"
    if [[ "$mode" == "docker" ]]; then
        echo -e "${GREEN}│${NC}  Logs / 日志:    ${CYAN}docker logs -f nyxbot${NC}"
        echo -e "${GREEN}│${NC}  Restart / 重启: ${CYAN}docker restart nyxbot${NC}"
        echo -e "${GREEN}│${NC}  Stop / 停止:    ${CYAN}docker stop nyxbot${NC}"
    else
        echo -e "${GREEN}│${NC}  Logs / 日志:    ${CYAN}tail -f ${DOWNLOAD_DIR}/nyxbot.log${NC}"
        if command -v systemctl &>/dev/null; then
            echo -e "${GREEN}│${NC}  Restart / 重启: ${CYAN}systemctl restart nyxbot${NC}"
            echo -e "${GREEN}│${NC}  Status / 状态:  ${CYAN}systemctl status nyxbot${NC}"
        fi
    fi
    echo -e "${GREEN}└──────────────────────────────────────────┘${NC}"
}

# ============================================================================
# System Command / 系统命令注册
# ============================================================================
readonly SYSTEM_CMD_PATH="/usr/local/bin/nyxbot"

# 安装为系统命令 (直接复制)
install_command() {
    local script_file="${BASH_SOURCE[0]}"
    if [[ ! -f "$script_file" ]]; then
        log_warn "Cannot install command (script not a file, likely piped from curl)" \
            "无法安装为系统命令 (脚本非文件形式，可能通过 curl 管道执行)"
        log_info "Download the script first, then re-run." \
            "请先下载脚本文件再运行。"
        return 1
    fi

    log_step "Installing system command to ${SYSTEM_CMD_PATH}..." \
        "安装系统命令到 ${SYSTEM_CMD_PATH}..."
    sudo cp "$script_file" "$SYSTEM_CMD_PATH" || {
        log_warn "Failed to install command" "安装命令失败"
        return 1
    }
    sudo chmod +x "$SYSTEM_CMD_PATH"
    log_success "Command installed: nyxbot" "命令已安装: nyxbot"
    log_info "Usage: nyxbot --help" "用法: nyxbot --help"
}

# 从系统中移除命令
uninstall_command() {
    if [[ ! -f "$SYSTEM_CMD_PATH" ]]; then
        log_warn "Command not found: ${SYSTEM_CMD_PATH}" \
            "命令未找到: ${SYSTEM_CMD_PATH}"
        return 0
    fi

    log_step "Removing system command: ${SYSTEM_CMD_PATH}..." \
        "移除系统命令: ${SYSTEM_CMD_PATH}..."
    sudo rm -f "$SYSTEM_CMD_PATH" || {
        log_warn "Failed to remove command" "移除命令失败"
        return 1
    }
    log_success "Command removed: nyxbot" "命令已移除: nyxbot"
}

# ============================================================================
# Management Menu / 管理菜单
# ============================================================================
show_menu() {
    while true; do
        local running=false
        check_nyxbot_running && running=true

        echo ""
        echo -e "${BOLD}── NyxBot Management / NyxBot 管理 ──${NC}"
        echo -e "  Status / 状态: $(if [[ "$running" == "true" ]]; then echo -e "${GREEN}Running / 运行中${NC}"; else echo -e "${YELLOW}Stopped / 未运行${NC}"; fi)"
        echo ""
        echo "  1) Update / 更新 (download latest + restart)"
        echo "  2) $(if [[ "$running" == "true" ]]; then echo 'Restart / 重启'; else echo 'Start / 启动'; fi)"
        if [[ "$running" == "true" ]]; then echo "  3) Stop / 停止"; fi
        echo "  4) Status / 查看状态"
        echo "  5) Reconfigure / 重新配置"
        echo "  6) Remove system command / 移除系统命令"
        echo "  7) Quit / 退出"
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
                local key
                while true; do
                    clear 2>/dev/null || true
                    echo -e "${BOLD}┌──────────────────────────────────────────────────────────┐${NC}"
                    echo -e "${BOLD}│${NC}  ${BOLD}NyxBot Live Status / 实时状态${NC}   ${CYAN}$(date '+%H:%M:%S')${NC}   ${BOLD}Esc=Exit${NC}"
                    echo -e "${BOLD}├──────────────────────────────────────────────────────────┤${NC}"
                    if check_nyxbot_running; then
                        echo -e "${BOLD}│${NC}  Status / 状态: ${GREEN}● Running / 运行中${NC}"
                        echo -e "${BOLD}│${NC}  Dashboard:      ${CYAN}http://localhost:${PORT}${NC}"
                        echo -e "${BOLD}│${NC}  JAR:            ${DOWNLOAD_DIR}/NyxBot.jar"
                        if [[ -f "$DOWNLOAD_DIR/nyxbot.pid" ]]; then
                            echo -e "${BOLD}│${NC}  PID:            $(cat "$DOWNLOAD_DIR/nyxbot.pid" 2>/dev/null || echo 'n/a')"
                        fi
                        echo -e "${BOLD}├──────────────────────────────────────────────────────────┤${NC}"
                        if command -v systemctl &>/dev/null; then
                            systemctl status nyxbot --no-pager -l -n 50 2>/dev/null
                        fi
                    else
                        echo -e "${BOLD}│${NC}  Status / 状态: ${YELLOW}● Stopped / 未运行${NC}"
                        echo -e "${BOLD}│${NC}  Run './nyxbot-deploy' to start / 启动以查看详情"
                        echo -e "${BOLD}├──────────────────────────────────────────────────────────┤${NC}"
                    fi
                    echo -e "${BOLD}└──────────────────────────────────────────────────────────┘${NC}"
                    echo -e "  ${CYAN}Auto-refresh 2s${NC}"
                    read -n 1 -s -t 2 key 2>/dev/null || true
                    if [[ "$key" == $'\033' ]]; then
                        read -n 2 -s -t 0.01 _ 2>/dev/null || true
                        break
                    fi
                done
                ;;
            5)
                text_config
                save_config
                echo ""; read -r -p "  Config saved. Press Enter to continue / 配置已保存，按回车继续..."
                ;;
            6)
                uninstall_command
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
            7)
                log_info "Bye / 再见"
                exit 0
                ;;
            1|*)
                # Update
                save_config
                install_local
                echo ""; read -r -p "  Press Enter to continue / 按回车继续..."
                ;;
        esac
    done
}

# 启动 NyxBot 服务
start_nyxbot() {
    if [[ "$OS" == "linux" ]] && command -v systemctl &>/dev/null; then
        log_step "Starting NyxBot via systemd..." "通过 systemd 启动..."
        sudo systemctl start nyxbot 2>/dev/null || true
        log_success "NyxBot started" "NyxBot 已启动"
    else
        log_step "Starting NyxBot via nohup..." "通过 nohup 启动..."
        cd "$DOWNLOAD_DIR"
        build_launch_args
        nohup java $LAUNCH_ARGS > nyxbot.log 2>&1 &
        echo $! > nyxbot.pid
        log_success "NyxBot started (PID: $(cat nyxbot.pid))" "NyxBot 已启动 (PID: $(cat nyxbot.pid))"
    fi
}

# ============================================================================
# Interactive Config / 交互配置
# ============================================================================
text_config() {
    echo ""
    echo -e "${BOLD}── Basic Config / 基础配置 ──${NC}"
    read -r -t 10 -p "  Port / 端口 [${PORT}]: " input; PORT="${input:-$PORT}"
    read -r -p "  Token (required / 必填): " TOKEN
    while [[ -z "$TOKEN" ]]; do
        read -r -p "  Token cannot be empty / Token 不能为空: " TOKEN
    done

    echo ""
    echo -e "${BOLD}── Mode / 通讯模式 ──${NC}"
    echo "  1) Server / 服务端 (recommended / 推荐)  2) Client / 客户端"
    read -r -t 10 -p "  Select / 选择 [1]: " input
    if [[ "$input" == "2" ]]; then WS_MODE="client"; else WS_MODE="server"; fi
    WS_MODE_OVERRIDE="true"

    echo ""
    echo -e "${BOLD}── Proxy / 代理 (Enter to skip / 回车跳过) ──${NC}"
    read -r -p "  Proxy URL / 代理地址 (e.g. http://127.0.0.1:7890): " PROXY_ADDR
    if [[ -n "$PROXY_ADDR" ]]; then
        read -r -p "  Username / 代理用户名: " PROXY_USER
        read -r -p "  Password / 代理密码: " PROXY_PASS
    fi

    echo ""
    echo -e "${BOLD}── System Command / 系统命令 ──${NC}"
    echo "  Install 'nyxbot' command to PATH? / 是否安装 'nyxbot' 命令到系统路径?"
    echo "  After install, use 'nyxbot' anywhere to manage. / 安装后可在任意位置使用 'nyxbot' 管理。"
    read -r -t 10 -p "  Install command? / 安装命令? [Y/n]: " input
    if [[ ! "$input" =~ ^[Nn]$ ]]; then
        INSTALL_CMD="true"
    else
        INSTALL_CMD="false"
    fi

    echo ""
    echo -e "${BOLD}── Confirm / 确认 ──${NC}"
    echo -e "  Port / 端口: ${GREEN}${PORT}${NC} | Mode / 模式: ${GREEN}${WS_MODE}${NC} | Token: ${GREEN}${TOKEN}${NC}"
    echo -e "  Proxy / 代理: ${YELLOW}${PROXY_ADDR:-None / 无}${NC}"
    read -r -t 10 -p "  Proceed? / 确认安装? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && { log_warn "Cancelled" "已取消"; exit 0; }
}

# ============================================================================
# TUI Config (dialog: 多字段表单) / TUI 配置 (dialog)
# ============================================================================
tui_dialog() {
    local tmpfile; tmpfile=$(mktemp /tmp/nyxbot_deploy_dialog.XXXXXX)

    dialog --backtitle "NyxBot Deploy v${SCRIPT_VERSION}" \
        --title "Config / 配置" \
        --form "Please fill in / 请填写以下配置:" 15 55 0 \
        "Port / 端口:"      1 1 "$PORT"       1 20 20 0 \
        "Token:"            2 1 "$TOKEN"      2 20 30 0 \
        "Mode / 模式 (server/client):" 3 1 "$WS_MODE"    3 20 10 0 \
        "Proxy / 代理:"     4 1 "$PROXY_ADDR"  4 20 30 0 \
        "Proxy User / 用户名:" 5 1 "$PROXY_USER"  5 20 20 0 \
        "Proxy Pass / 密码:" 6 1 "$PROXY_PASS"  6 20 20 0 \
        2>"$tmpfile" || { rm -f "$tmpfile"; return 1; }

    local i=0
    while IFS= read -r line; do
        case $i in
            0) PORT="${line:-$DEFAULT_PORT}" ;;
            1) TOKEN="$line" ;;
            2) WS_MODE="${line:-server}"; WS_MODE_OVERRIDE="true" ;;
            3) PROXY_ADDR="$line" ;;
            4) PROXY_USER="$line" ;;
            5) PROXY_PASS="$line" ;;
        esac
        ((i++))
    done < "$tmpfile"
    rm -f "$tmpfile"

    # 是否安装系统命令
    if dialog --backtitle "NyxBot Deploy v${SCRIPT_VERSION}" --title "System Command / 系统命令" \
        --yesno "Install 'nyxbot' command to PATH?\n是否安装 'nyxbot' 命令到系统路径？" 8 50; then
        INSTALL_CMD="true"
    else
        INSTALL_CMD="false"
    fi

    dialog --backtitle "NyxBot Deploy v${SCRIPT_VERSION}" --title "Confirm / 确认" \
        --yesno "Port / 端口: $PORT\nToken: ${TOKEN:-Not set / 未设置}\nMode / 模式: $WS_MODE\nProxy / 代理: ${PROXY_ADDR:-None / 无}\n\nProceed? / 确认安装?" 12 50 \
        || { log_warn "Cancelled" "已取消"; exit 0; }
}

# ============================================================================
# TUI Config (whiptail: 分步单问) / TUI 配置 (whiptail)
# ============================================================================
tui_whiptail() {
    local input

    # 1. Port
    if input=$(whiptail --title "NyxBot Deploy v${SCRIPT_VERSION}" \
        --inputbox "Port / 端口" 8 50 "$PORT" 3>&1 1>&2 2>&3); then
        [[ -n "$input" ]] && PORT="$input"
    else
        return 1
    fi

    # 2. Token (required, loop until filled)
    while true; do
        if input=$(whiptail --title "NyxBot Deploy v${SCRIPT_VERSION}" \
            --inputbox "Token (required) / Token (必填)" 8 50 "$TOKEN" 3>&1 1>&2 2>&3); then
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
    if mode_choice=$(whiptail --title "NyxBot Deploy v${SCRIPT_VERSION}" \
        --menu "Mode / 通讯模式" 12 45 2 \
        "server" "Server / 服务端 (recommended / 推荐)" \
        "client" "Client / 客户端" \
        3>&1 1>&2 2>&3); then
        WS_MODE="$mode_choice"
        WS_MODE_OVERRIDE="true"
    else
        return 1
    fi

    # 4. Proxy
    if input=$(whiptail --title "NyxBot Deploy v${SCRIPT_VERSION}" \
        --inputbox "Proxy (Enter to skip) / 代理地址 (回车跳过)\n\ne.g. http://127.0.0.1:7890" 10 55 "$PROXY_ADDR" 3>&1 1>&2 2>&3); then
        PROXY_ADDR="$input"
    else
        return 1
    fi

    if [[ -n "$PROXY_ADDR" ]]; then
        if input=$(whiptail --title "NyxBot Deploy v${SCRIPT_VERSION}" \
            --inputbox "Proxy Username / 代理用户名" 8 50 "$PROXY_USER" 3>&1 1>&2 2>&3); then
            PROXY_USER="$input"
        else
            return 1
        fi

        if input=$(whiptail --title "NyxBot Deploy v${SCRIPT_VERSION}" \
            --passwordbox "Proxy Password / 代理密码" 8 50 3>&1 1>&2 2>&3); then
            PROXY_PASS="$input"
        else
            return 1
        fi
    fi

    # 5. System command
    if whiptail --title "NyxBot Deploy v${SCRIPT_VERSION}" \
        --yesno "Install 'nyxbot' command to PATH?\n是否安装 'nyxbot' 命令到系统路径？" 8 50; then
        INSTALL_CMD="true"
    else
        INSTALL_CMD="false"
    fi

    # 6. Confirm
    local confirm_text="Port / 端口: $PORT\nToken: $TOKEN\nMode / 模式: $WS_MODE\nProxy / 代理: ${PROXY_ADDR:-None / 无}\nInstall command / 安装命令: $INSTALL_CMD\n\nProceed? / 确认安装?"
    if ! whiptail --title "NyxBot Deploy v${SCRIPT_VERSION}" \
        --yesno "$confirm_text" 14 50; then
        log_warn "Cancelled" "已取消"
        exit 0
    fi
}

# ============================================================================
# Help / 帮助
# ============================================================================
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [options] / 用法: $SCRIPT_NAME [选项]

Mode / 模式:
  --docker          Docker install / 容器安装
  --local           Local JAR install / 本地 jar 安装

UI / 界面:
  --tui             Terminal dialog form / 终端表单 (requires dialog)
  --text            Line-by-line Q&A / 逐行问答模式
  --quiet           Fully automated / 静默自动化 (requires --token=xxx)

Config / 配置 (for --quiet):
  --port=8080            Service port / 服务端口
  --token=xxx            OneBot Token (required / 必填)
  --server               Server mode / 服务端模式 (default)
  --client               Client mode / 客户端模式
  --proxy=URL            Proxy address / 代理地址
  --pu=xxx       Proxy username / 代理用户名
  --pp=xxx       Proxy password / 代理密码
  --debug                Enable debug / 调试模式

System Command / 系统命令:
  --inc      Install 'nyxbot' to /usr/local/bin
                         安装为系统命令，全局可用
  --noc   Skip command installation
                         跳过系统命令安装
  --unc    Remove 'nyxbot' from system
                         从系统中移除 nyxbot 命令

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
# Reconfigure Flow / 重新配置流程 (--tui/--text + jar 存在时)
# ============================================================================
reconfigure_flow() {
    local jar_file="$DOWNLOAD_DIR/NyxBot.jar"
    local need_restart=false
    local need_download=false

    # 1. 检查 JAR 是否存在
    if [[ ! -f "$jar_file" ]]; then
        echo ""
        log_warn "JAR not found / JAR 文件不存在"
        need_download=true
    else
        # 2. JAR 存在 → 获取远程 digest 用于校验
        get_latest_release

        if [[ -n "$EXPECTED_DIGEST" && "$EXPECTED_DIGEST" != "null" ]]; then
            echo -ne "  Checking JAR / 校验 JAR..."
            local local_hash=""
            if command -v sha256sum &>/dev/null; then
                local_hash=$(sha256sum "$jar_file" | awk '{print $1}')
            elif command -v shasum &>/dev/null; then
                local_hash=$(shasum -a 256 "$jar_file" | awk '{print $1}')
            fi

            if [[ -n "$local_hash" && "$local_hash" == "$EXPECTED_DIGEST" ]]; then
                echo -e " ${GREEN}OK / 完整${NC}"
                log_success "JAR is complete and up-to-date (${RELEASE_TAG})" \
                    "JAR 完整且为最新版本 (${RELEASE_TAG})"
            else
                echo -e " ${YELLOW}Mismatch / 不匹配${NC}"
                need_download=true
                if [[ -n "$local_hash" ]]; then
                    log_warn "Expected / 期望: ${EXPECTED_DIGEST:0:16}..." ""
                    log_warn "Got / 实际:      ${local_hash:0:16}..." ""
                fi
                log_warn "JAR is corrupted or outdated / JAR 不完整或版本过旧" \
                    "Latest / 最新: ${RELEASE_TAG}"
            fi
        else
            log_warn "Cannot verify JAR (no digest from release)" \
                "Release 未提供 SHA256，无法校验"
        fi
    fi

    # 3. 需要下载 → 获取版本信息 + 询问用户
    if [[ "$need_download" == "true" ]]; then
        # 如果还没获取过版本信息(如 Jar 不存在的情况)
        [[ -z "$DOWNLOAD_URL" ]] && get_latest_release
        echo ""
        read -r -t 10 -p "  Download latest JAR (${RELEASE_TAG})? / 下载最新 JAR (${RELEASE_TAG})? [Y/n]: " input || true
        if [[ ! "$input" =~ ^[Nn]$ ]]; then
            if [[ -z "$PROXY_ADDR" ]]; then
                test_network
            fi
            download_jar "$DOWNLOAD_URL"
            need_restart=true
        else
            log_warn "Skipped download / 跳过下载"
        fi
    fi

    # 4. 服务管理
    echo ""
    if check_nyxbot_running; then
        read -r -t 10 -p "  NyxBot is running. Restart now? / 服务在运行，是否重启? [Y/n]: " input || true
        if [[ ! "$input" =~ ^[Nn]$ ]]; then
            stop_nyxbot
            sleep 1
            start_nyxbot
            log_success "NyxBot restarted" "NyxBot 已重启"
        else
            log_warn "Config saved but service not restarted" "配置已保存，服务未重启"
        fi
    elif [[ "$need_restart" == "true" ]]; then
        read -r -t 10 -p "  Start NyxBot now? / 是否立即启动? [Y/n]: " input || true
        if [[ ! "$input" =~ ^[Nn]$ ]]; then
            start_nyxbot
        fi
    else
        log_info "Config saved. Run './nyxbot-deploy' to start" \
            "配置已保存，运行 './nyxbot-deploy' 启动"
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
    WS_MODE_OVERRIDE=""
    PROXY_ADDR=""
    PROXY_USER=""
    PROXY_PASS=""
    DEBUG="false"
    GITHUB_PROXY=""
    EXPECTED_DIGEST=""
    QUIET=false
    INSTALL_CMD="auto"

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
            --server) WS_MODE="server"; WS_MODE_OVERRIDE="true"; shift ;;
            --client) WS_MODE="client"; WS_MODE_OVERRIDE="true"; shift ;;
            --proxy=*) PROXY_ADDR="${1#*=}"; shift ;;
            --pu=*) PROXY_USER="${1#*=}"; shift ;;
            --pp=*) PROXY_PASS="${1#*=}"; shift ;;
            --debug) DEBUG="true"; shift ;;
            --inc) INSTALL_CMD="true"; shift ;;
            --unc) uninstall_command; exit 0 ;;
            --noc) INSTALL_CMD="false"; shift ;;
            *) log_error "Unknown option: $1" "未知参数: $1"; usage ;;
        esac
    done

    # 静默模式必须提供 token
    if [[ "$QUIET" == "true" && -z "$TOKEN" ]]; then
        log_error "--quiet requires --token=xxx" "--quiet 模式必须提供 --token=xxx"
    fi

    banner
    detect_os

    # 加载已保存的配置 (仅填充未通过命令行指定的值)
    load_config

    # 如果指定了代理，应用到脚本自身的 curl 请求
    if [[ -n "$PROXY_ADDR" ]]; then
        export http_proxy="$PROXY_ADDR"
        export https_proxy="$PROXY_ADDR"
        log_info "Using proxy for script: $PROXY_ADDR" "脚本使用代理: $PROXY_ADDR"
    fi

    # 自动选择安装模式
    if [[ "$INSTALL_MODE" == "auto" ]]; then
        if check_docker; then
            if check_docker_running; then
                INSTALL_MODE="docker"
            else
                log_warn "Docker installed but not running, fallback to local" \
                    "Docker 已安装但未运行，降级到本地安装"
                INSTALL_MODE="local"
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
    log_info "Directory: ${DOWNLOAD_DIR}" "目录: ${DOWNLOAD_DIR}"
    echo ""

    # 已安装：
    local jar_file="$DOWNLOAD_DIR/NyxBot.jar"
    local jar_exists=false
    [[ -f "$jar_file" ]] && jar_exists=true

    # 无参数自动模式 → 显示管理菜单
    if [[ "$QUIET" != "true" && "$jar_exists" == "true" && "$UI_MODE" == "auto" ]]; then
        show_menu
    fi

    # --tui/--text + jar 存在 → 仅重新配置，标记跳过完整安装 (--quiet 不触发)
    local reconfigure_only=false
    if [[ "$QUIET" != "true" && "$jar_exists" == "true" && ( "$UI_MODE" == "tui" || "$UI_MODE" == "text" ) ]]; then
        reconfigure_only=true
    fi

    # 已有有效配置 → 确认是否使用已保存配置 (--tui/--text 显式时跳过)
    if [[ "$QUIET" != "true" && -n "$TOKEN" && "$UI_MODE" != "tui" && "$UI_MODE" != "text" ]]; then
        echo ""
        log_info "Saved config found / 发现已保存配置"
        echo -e "  Port / 端口: ${GREEN}${PORT}${NC}  Mode / 模式: ${GREEN}${WS_MODE}${NC}  Token: ${GREEN}${TOKEN:0:4}***${NC}"
        if [[ -n "$PROXY_ADDR" ]]; then
            echo -e "  Proxy / 代理: ${YELLOW}${PROXY_ADDR}${NC}"
        fi
        echo ""
        read -r -t 10 -p "  Use saved config? / 使用已保存配置? [Y/n]: " input
        if [[ ! "$input" =~ ^[Nn]$ ]]; then
            log_info "Using saved config, run --text to reconfigure" "使用已保存配置, 运行 --text 重新配置"
            echo ""
        else
            TOKEN=""  # 清空触发重新配置
        fi
    fi

    # 收集配置 (TOKEN 为空 或 --tui/--text 显式指定)
    if [[ "$QUIET" != "true" && ( -z "$TOKEN" || "$UI_MODE" == "tui" || "$UI_MODE" == "text" ) ]]; then
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

        # 执行对应的配置模式 (TUI 失败自动降级 text)
        case "$UI_MODE" in
            dialog|tui)
                if [[ ! -t 0 ]]; then
                    log_error "--tui requires an interactive terminal." \
                        "--tui 需要交互式终端。"
                fi
                if command -v dialog &>/dev/null; then
                    tui_dialog || { tui_failed=true; }
                elif command -v whiptail &>/dev/null; then
                    log_warn "dialog not found, falling back to whiptail" \
                        "dialog 未找到，降级到 whiptail"
                    tui_whiptail || { tui_failed=true; }
                else
                    tui_failed=true
                fi
                # TUI 失败 → text 兜底 (SSH 等环境)
                if [[ "$tui_failed" == "true" ]]; then
                    log_warn "TUI not available, falling back to text" \
                        "TUI 不可用，降级到文本模式"
                    text_config
                fi
                ;;
            whiptail)
                if [[ ! -t 0 ]]; then
                    log_error "--tui requires an interactive terminal." \
                        "--tui 需要交互式终端。"
                fi
                tui_whiptail || {
                    log_warn "whiptail failed, falling back to text" \
                        "whiptail 失败，降级到文本模式"
                    text_config
                }
                ;;
            text|*)
                text_config
                ;;
        esac
    fi

    # 保存配置供下次运行
    save_config

    # --tui/--text + jar 存在 → 仅重新配置，不走完整安装
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
