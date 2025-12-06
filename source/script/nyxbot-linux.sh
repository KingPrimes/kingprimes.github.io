#!/bin/bash

# ============================================================================
# NyxBot 启动脚本 (Linux) - 改进版
# 版本: 3.0.0
# 功能: 自动安装JDK 21、下载最新版本NyxBot并启动
# 改进: SHA256校验、版本检查、增强错误处理
# ============================================================================

# set -euo pipefail  # 严格模式：遇到错误立即退出

# 设置变量
readonly SCRIPT_VERSION="3.0.0"
readonly API_URL="https://api.github.com/repos/KingPrimes/NyxBot/releases/latest"
readonly DOWNLOAD_DIR="./nyxbot_data"
readonly NYXBOT_JAR="$DOWNLOAD_DIR/NyxBot.jar"
readonly VERSION_FILE="$DOWNLOAD_DIR/.version"
readonly LOG_FILE="$DOWNLOAD_DIR/install.log"
readonly CONFIG_FILE="$DOWNLOAD_DIR/config.ini"

# 配置文件默认值
DEFAULT_PORT="8080"
DEFAULT_PROXY_HOST=""
DEFAULT_PROXY_PORT=""
DEFAULT_PROXY_USERNAME=""
DEFAULT_PROXY_PASSWORD=""
DEFAULT_DEBUG="false"
DEFAULT_WS_MODE="server"
DEFAULT_WS_SERVER_ENABLE="true"
DEFAULT_WS_SERVER_URL="/ws/shiro"
DEFAULT_WS_CLIENT_ENABLE="false"
DEFAULT_WS_CLIENT_URL="ws://localhost:3001"
DEFAULT_SHIRO_TOKEN=""

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# 命令行参数
FORCE_UPDATE=false
SKIP_JAVA_INSTALL=false
PROXY_NUM=""
GITHUB_PROXY=""

# 错误处理
trap 'error_handler $? $LINENO' ERR

error_handler() {
    local exit_code=$1
    local line_number=$2
    echo -e "${RED}✗ 错误发生在第 ${line_number} 行，退出码: ${exit_code}${NC}" | tee -a "$LOG_FILE"
    echo "详细日志请查看: $LOG_FILE"
    exit "$exit_code"
}

# 日志函数
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# 读取配置文件
function read_config() {
    local key="$1"
    local default="$2"
    local value="$default"
    
    if [ -f "$CONFIG_FILE" ]; then
        value=$(grep -E "^${key}=" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d '[:space:]')
        value=${value:-$default}
    fi
    
    echo "$value"
}

# 写入配置文件
function write_config() {
    local key="$1"
    local value="$2"
    
    # 创建配置文件（如果不存在）
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
    fi
    
    # 更新或添加配置项
    if grep -E "^${key}=" "$CONFIG_FILE" > /dev/null; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

# 初始化配置文件
function init_config_file() {
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
        write_config "PORT" "$DEFAULT_PORT"
        write_config "PROXY_URL" ""
        write_config "PROXY_PROTOCOL" ""
        write_config "PROXY_USERNAME" "$DEFAULT_PROXY_USERNAME"
        write_config "PROXY_PASSWORD" "$DEFAULT_PROXY_PASSWORD"
        write_config "DEBUG" "$DEFAULT_DEBUG"
        write_config "WS_MODE" "$DEFAULT_WS_MODE"
        write_config "WS_SERVER_ENABLE" "$DEFAULT_WS_SERVER_ENABLE"
        write_config "WS_SERVER_URL" "$DEFAULT_WS_SERVER_URL"
        write_config "WS_CLIENT_ENABLE" "$DEFAULT_WS_CLIENT_ENABLE"
        write_config "WS_CLIENT_URL" "$DEFAULT_WS_CLIENT_URL"
        write_config "SHIRO_TOKEN" "$DEFAULT_SHIRO_TOKEN"
    fi
}

# 显示当前配置
function show_nyxbot_config() {
    log_info "NyxBot 当前配置："
    echo -e "${YELLOW}端口：$(read_config PORT $DEFAULT_PORT)${NC}"
    echo -e "${YELLOW}Debug模式：$(read_config DEBUG $DEFAULT_DEBUG)${NC}"
    
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}             OneBot 设置             ${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${YELLOW}通讯模式：$(read_config WS_MODE $DEFAULT_WS_MODE)${NC}"
    echo -e "${YELLOW}服务端启用：$(read_config WS_SERVER_ENABLE $DEFAULT_WS_SERVER_ENABLE)${NC}"
    echo -e "${YELLOW}服务端地址：$(read_config WS_SERVER_URL $DEFAULT_WS_SERVER_URL)${NC}"
    echo -e "${YELLOW}客户端启用：$(read_config WS_CLIENT_ENABLE $DEFAULT_WS_CLIENT_ENABLE)${NC}"
    echo -e "${YELLOW}客户端地址：$(read_config WS_CLIENT_URL $DEFAULT_WS_CLIENT_URL)${NC}"
    echo -e "${YELLOW}Shiro Token：$(read_config SHIRO_TOKEN $DEFAULT_SHIRO_TOKEN)${NC}"
    
    local proxy_url=$(read_config PROXY_URL "无")
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}              代理设置              ${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${YELLOW}代理URL：$proxy_url${NC}"
    
    if [ -n "$proxy_url" ] && [ "$proxy_url" != "无" ]; then
        # 提取并显示代理主机和端口
        local proxy_host=$(echo "$proxy_url" | sed -E 's/^(http|socks|socks5):\/\/([0-9a-zA-Z.-]+):([0-9]+)$/\2/')
        local proxy_port=$(echo "$proxy_url" | sed -E 's/^(http|socks|socks5):\/\/([0-9a-zA-Z.-]+):([0-9]+)$/\3/')
        echo -e "${YELLOW}代理主机：$proxy_host${NC}"
        echo -e "${YELLOW}代理端口：$proxy_port${NC}"
    fi
    
    echo -e "${YELLOW}代理用户名：$(read_config PROXY_USERNAME $DEFAULT_PROXY_USERNAME)${NC}"
    echo -e "${YELLOW}代理密码：$(read_config PROXY_PASSWORD "****")${NC}"
}

# 设置单个配置参数
function set_nyxbot_config() {
    local key="$1"
    local prompt="$2"
    local default="$3"
    local current_value=$(read_config "$key" "$default")
    
    echo -e -n "${CYAN}$prompt${NC} (当前: ${current_value}, 回车保持默认): "
    read -r new_value
    new_value=${new_value:-$current_value}
    
    write_config "$key" "$new_value"
    log_success "已更新 ${key} 为: ${new_value}"
}

# 创建下载目录和日志文件
mkdir -p "$DOWNLOAD_DIR"
echo "=== NyxBot安装日志 $(date '+%Y-%m-%d %H:%M:%S') ===" > "$LOG_FILE"

echo -e "${CYAN}=== NyxBot启动脚本(Linux) v${SCRIPT_VERSION} ===${NC}"

# 解析命令行参数
function parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-update)
                FORCE_UPDATE=true
                shift
            ;;
            --skip-java)
                SKIP_JAVA_INSTALL=true
                shift
            ;;
            --proxy)
                PROXY_NUM="$2"
                shift 2
            ;;
            --version)
                echo "NyxBot启动脚本版本: $SCRIPT_VERSION"
                exit 0
            ;;
            --help)
                show_help
                exit 0
            ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
            ;;
        esac
    done
}

function show_help() {
    cat << EOF
用法: $0 [选项]

选项:
  --force-update    强制更新，即使本地已是最新版本
  --skip-java       跳过Java环境检查和安装
  --mirror <url>    使用自定义镜像前缀
  --version         显示脚本版本
  --help            显示此帮助信息

示例:
  $0                          # 正常安装
  $0 --force-update           # 强制更新到最新版本
  $0 --skip-java              # 跳过Java安装（假设已安装JDK 21）
  $0 --proxy 0                # 不使用代理（直连）
  $0 --proxy 1                # 使用第1个代理服务器
EOF
}

# 检查Java版本，如果没有安装JRE 21则自动安装
function check_and_install_jre21() {
    if [ "$SKIP_JAVA_INSTALL" = true ]; then
        log_warning "跳过Java环境检查"
        return 0
    fi
    
    log_info "检查JRE 21环境..."
    
    if command -v java &> /dev/null; then
        local java_version_output
        java_version_output=$(java -version 2>&1)
        
        # 检查是否为Java 21
        if echo "$java_version_output" | grep -qE '(openjdk|java) version "21\.|openjdk 21\.'; then
            log_success "JRE 21已安装"
            java -version 2>&1 | head -1 | tee -a "$LOG_FILE"
            return 0
        else
            log_warning "检测到Java，但不是版本21:"
            echo "$java_version_output" | head -1 | tee -a "$LOG_FILE"
        fi
    fi
    
    # 未安装JRE 21，尝试自动安装
    log_info "未检测到JRE 21，尝试自动安装..."
    
    # 检查网络连接
    if command -v apt &> /dev/null && ! ping -c 2 archive.ubuntu.com &> /dev/null; then
        log_warning "无法连接到官方Ubuntu源，尝试更换为国内镜像源..."
        
        # 检测是否为中国大陆用户
        if (timedatectl 2>/dev/null | grep -qi "asia/shanghai\|asia/beijing") ||
        (curl -s https://ipinfo.io/country 2>/dev/null | grep -q "CN"); then
            log_info "检测到可能位于中国大陆，配置国内镜像源"
            
            # 备份原有源列表
            sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup
            
            # 获取Ubuntu版本代号
            UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")
            
            # 根据版本选择合适镜像
            if grep -q "22.04" /etc/os-release 2>/dev/null; then
                UBUNTU_CODENAME="jammy"
                elif grep -q "20.04" /etc/os-release 2>/dev/null; then
                UBUNTU_CODENAME="focal"
            fi
            
            # 使用清华源
            cat <<EOF | sudo tee /etc/apt/sources.list
            deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_CODENAME main restricted universe multiverse
            deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_CODENAME-updates main restricted universe multiverse
            deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_CODENAME-backports main restricted universe multiverse
            deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
            
            log_info "已切换到清华镜像源，更新软件包列表..."
            sudo apt-get clean
        fi
    fi
    
    # 检查是否有sudo权限
    if ! sudo -n true 2>/dev/null; then
        log_warning "需要sudo权限来安装JRE 21，可能会要求输入密码"
    fi
    
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu系统
        log_info "检测到Debian/Ubuntu系统，使用apt安装OpenJRE 21..."
        
        # 带错误重试的apt update
        attempt=0
        max_attempts=3
        while [ $attempt -lt $max_attempts ]; do
            if sudo apt update; then
                break
            else
                attempt=$((attempt+1))
                log_warning "apt update 失败 (尝试 $attempt/$max_attempts)"
                if [ $attempt -eq $max_attempts ]; then
                    log_error "无法更新软件包列表，检查网络连接或尝试手动配置镜像源"
                    log_info "手动配置国内源命令示例:"
                    log_info "  sudo sed -i 's|archive.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list"
                    log_info "  sudo sed -i 's|security.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list"
                    exit 1
                fi
                sleep 5
            fi
        done
        
        # 安装OpenJRE 21而非JDK
        sudo apt install -y openjdk-21-jre-headless || {
            log_warning "安装openjdk-21-jre-headless失败，尝试安装完整版openjdk-21-jre"
            sudo apt install -y openjdk-21-jre
        }
        
        elif [ -f /etc/redhat-release ]; then
        # RHEL/CentOS/Fedora系统
        log_info "检测到RHEL/CentOS/Fedora系统，使用dnf/yum安装OpenJRE 21..."
        if command -v dnf &> /dev/null; then
            sudo dnf install -y java-21-openjdk-headless || {
                log_warning "安装java-21-openjdk-headless失败，尝试安装完整版"
                sudo dnf install -y java-21-openjdk
            }
        else
            sudo yum install -y java-21-openjdk-headless || {
                log_warning "安装java-21-openjdk-headless失败，尝试安装完整版"
                sudo yum install -y java-21-openjdk
            }
        fi
        elif [ -f /etc/arch-release ]; then
        # Arch Linux
        log_info "检测到Arch Linux，使用pacman安装OpenJRE 21..."
        sudo pacman -Syu --noconfirm jre-openjdk
        elif [ -f /etc/alpine-release ]; then
        # Alpine Linux
        log_info "检测到Alpine Linux，使用apk安装OpenJRE 21..."
        sudo apk add openjdk21-jre
    else
        log_error "无法确定Linux发行版，无法自动安装JRE 21"
        log_info "请手动安装OpenJRE 21，或参考以下命令："
        echo "  Ubuntu/Debian: sudo apt install openjdk-21-jre-headless"
        echo "  CentOS/RHEL: sudo yum install java-21-openjdk-headless"
        echo "  Fedora: sudo dnf install java-21-openjdk-headless"
        exit 1
    fi
    
    # 验证安装
    if command -v java &> /dev/null && java -version 2>&1 | grep -qE '(openjdk|java) version "21\.|openjdk 21\.'; then
        log_success "OpenJRE 21安装成功"
        java -version 2>&1 | head -1 | tee -a "$LOG_FILE"
    else
        log_error "OpenJRE 21安装失败，请手动安装"
        log_info "手动安装选项:"
        echo "1. 配置国内镜像源后重试"
        echo "   Ubuntu: sudo sed -i 's|archive.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list"
        echo "   然后: sudo apt update && sudo apt install openjdk-21-jre-headless"
        echo ""
        echo "2. 下载预编译JRE包:"
        echo "   wget https://github.com/adoptium/temurin21-binaries/releases/latest/download/OpenJDK21U-jre_x64_linux_hotspot_*.tar.gz"
        echo "   tar xzf OpenJDK21U-jre*.tar.gz"
        echo "   export PATH=\$PWD/jdk-21.0.*/bin:\$PATH"
        exit 1
    fi
}

function network_test() {
    local found=0
    local timeout=10
    local status=0
    
    log_info "开始网络测试: ..."
    
    proxy_arr=("https://ghfast.top" "https://git.yylx.win/" "https://gh-proxy.com" "https://ghfile.geekertao.top" "https://gh-proxy.net" "https://j.1win.ggff.net" "https://ghm.078465.xyz" "https://gitproxy.127731.xyz" "https://ghproxy.vip" "https://gh-proxy.org" "https://edgeone.gh-proxy.org")
    check_url="https://raw.githubusercontent.com/KingPrimes/DataSource/refs/heads/main/warframe/state_translation.json"
    
    log_info "自动测试代理, 正在检查代理可用性并测速..."
    
    local best_proxy="" # 空字符串代表直连
    local best_speed=0
    
    # 首先测试直连 (仅当有 check_url 时)
    if [ -n "${check_url}" ]; then
        log_info "测速: 直连..."
        local curl_output
        curl_output=$(curl -k -L --connect-timeout ${timeout} --max-time $((timeout * 3)) -o /dev/null -s -w "%{http_code}:%{exitcode}:%{speed_download}" "${check_url}")
        local status=$(echo "${curl_output}" | cut -d: -f1)
        local curl_exit_code=$(echo "${curl_output}" | cut -d: -f2)
        local download_speed=$(echo "${curl_output}" | cut -d: -f3 | cut -d. -f1)
        
        if [ "${curl_exit_code}" -eq 0 ] && [ "${status}" -eq 200 ]; then
            local formatted_speed=$(format_speed "${download_speed}")
            log_info "测速: 直连 - ${formatted_speed}"
            best_speed=${download_speed}
        else
            log_info "直连测试失败或超时。"
        fi
    fi
    
    # 遍历并测试所有代理
    if [ -n "${check_url}" ]; then
        for proxy_candidate in "${proxy_arr[@]}"; do
            local test_target_url
            if [ -n "${check_url}" ]; then
                test_target_url="${proxy_candidate}/${check_url}"
            else
                test_target_url="${proxy_candidate}/"
            fi
            
            local curl_output
            curl_output=$(curl -k -L --connect-timeout ${timeout} --max-time $((timeout * 3)) -o /dev/null -s -w "%{http_code}:%{exitcode}:%{speed_download}" "${test_target_url}")
            local status=$(echo "${curl_output}" | cut -d: -f1)
            local curl_exit_code=$(echo "${curl_output}" | cut -d: -f2)
            local download_speed=$(echo "${curl_output}" | cut -d: -f3 | cut -d. -f1)
            
            if [ "${curl_exit_code}" -ne 0 ]; then
                continue
            fi
            if ([ "${status}" -eq 200 ]); then
                local formatted_speed=$(format_speed "${download_speed}")
                log_info "测速: ${proxy_candidate} - ${formatted_speed}"
                
                if [[ ${download_speed} -gt ${best_speed} ]]; then
                    best_speed=${download_speed}
                    best_proxy=${proxy_candidate}
                fi
            fi
        done
    else
        log_warning "警告: 代理测试缺少有效的检查URL, 无法自动选择代理。"
    fi
    
    # 根据测速结果做出最终决定
    if [[ ${best_speed} -gt 0 ]]; then
        found=1
        GITHUB_PROXY="${best_proxy}"
        local formatted_best_speed=$(format_speed "${best_speed}")
        if [ -n "${best_proxy}" ]; then
            log_info "测试完成, 将使用最快的代理: ${GITHUB_PROXY} (速度: ${formatted_best_speed})"
        else
            log_info "测试完成, 直连速度最快 (速度: ${formatted_best_speed}), 将不使用代理。"
        fi
    fi
    
    if [ ${found} -eq 0 ]; then
        log_warning "警告: 无法找到可用的代理且直连失败。"
        GITHUB_PROXY="" # 不使用代理
    fi
}

function format_speed() {
    local speed_bps=$1
    if (( speed_bps > 1048576 )); then
        # MB/s
        local speed_mbs=$((speed_bps / 1048576))
        echo "${speed_mbs} MB/s"
        elif (( speed_bps > 1024 )); then
        # KB/s
        local speed_kbs=$((speed_bps / 1024))
        echo "${speed_kbs} KB/s"
    else
        # B/s
        echo "${speed_bps} B/s"
    fi
}

# 下载文件函数（带重试和校验）
function download_file() {
    local url=$1
    local destination=$2
    local description=$3
    local expected_sha256=$4  # 可选参数
    
    log_info "下载 $description..."
    
    # 构建下载URL
    local download_url="$url"
    if [ -n "$GITHUB_PROXY" ]; then
        download_url="${GITHUB_PROXY}/${url#https://}"
        log_info "使用代理: $GITHUB_PROXY"
    fi
    
    # 尝试下载
    if curl -L -o "$destination" "$download_url" --connect-timeout 10 --max-time 300 --retry 3 -H "User-Agent: Mozilla/5.0" 2>> "$LOG_FILE"; then
        log_success "$description 下载完成"
        
        # 验证SHA256（如果提供）
        if [ -n "$expected_sha256" ]; then
            verify_sha256 "$destination" "$expected_sha256" "$description"
        fi
        return 0
    else
        log_error "无法下载 $description"
        return 1
    fi
}

# SHA256校验函数
function verify_sha256() {
    local file=$1
    local expected_sha256=$2
    local description=$3
    
    log_info "验证 $description 的SHA256校验和..."
    
    if command -v sha256sum &> /dev/null; then
        local actual_sha256
        actual_sha256=$(sha256sum "$file" | awk '{print $1}')
        
        if [ "$actual_sha256" = "$expected_sha256" ]; then
            log_success "SHA256校验通过"
            return 0
        else
            log_error "SHA256校验失败！"
            log_error "期望: $expected_sha256"
            log_error "实际: $actual_sha256"
            log_warning "文件可能已被篡改，删除下载的文件"
            rm -f "$file"
            return 1
        fi
    else
        log_warning "sha256sum命令不可用，跳过校验"
        return 0
    fi
}

# 从API获取最新release信息
function get_latest_release() {
    log_info "获取最新release信息..."
    
    # 构建API URL
    local api_url="$API_URL"
    if [ -n "$GITHUB_PROXY" ]; then
        api_url="${GITHUB_PROXY}/${API_URL#https://}"
    fi
    
    local api_response
    api_response=$(curl -s -H "User-Agent: Mozilla/5.0" -H "Accept: application/vnd.github.v3+json" "$api_url" --connect-timeout 10 --retry 3 2>> "$LOG_FILE")
    
    if [ -z "$api_response" ] || [[ "$api_response" == *"Not Found"* ]]; then
        log_error "无法获取最新release信息"
        echo "$api_response" >> "$LOG_FILE"
        exit 1
    fi
    
    # 解析JSON获取信息
    if command -v jq &> /dev/null; then
        DOWNLOAD_URL=$(echo "$api_response" | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -1)
        ASSET_NAME=$(echo "$api_response" | jq -r '.assets[] | select(.name | endswith(".jar")) | .name' | head -1)
        RELEASE_TAG=$(echo "$api_response" | jq -r '.tag_name')
        
        # 从assets的digest字段获取SHA256
        EXPECTED_SHA256=$(echo "$api_response" | jq -r '.assets[] | select(.name | endswith(".jar")) | .digest' | head -1)
        # 移除sha256:前缀（如果存在）
        EXPECTED_SHA256=$(echo "$EXPECTED_SHA256" | sed -E 's/^sha256://')
        
        # 获取更新日志
        RELEASE_NOTES=$(echo "$api_response" | jq -r '.body')
    else
        # 备用方法解析JSON
        DOWNLOAD_URL=$(echo "$api_response" | grep -o '"browser_download_url":\s*"[^"]*\.jar"' | head -1 | sed -E 's/.*"([^"]+\.jar)".*/\1/')
        ASSET_NAME=$(echo "$api_response" | grep -o '"name":\s*"[^"]*\.jar"' | head -1 | sed -E 's/.*"([^"]+\.jar)".*/\1/')
        RELEASE_TAG=$(echo "$api_response" | grep -o '"tag_name":\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
        
        # 从digest字段获取SHA256
        EXPECTED_SHA256=$(echo "$api_response" | grep -o '"digest":\s*"[^"]*"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' | sed -E 's/^sha256://')
        
        # 获取更新日志（简化版）
        RELEASE_NOTES=$(echo "$api_response" | grep -A 20 '"body":' | grep -v '"body":' | head -20)
    fi
    
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
        log_error "无法解析下载URL"
        echo "$api_response" >> "$LOG_FILE"
        exit 1
    fi
    
    log_success "找到最新构建: $ASSET_NAME (版本: $RELEASE_TAG)"
    echo "下载URL: $DOWNLOAD_URL" >> "$LOG_FILE"
    
    # 显示更新日志
    if [ -n "$RELEASE_NOTES" ] && [ "$RELEASE_NOTES" != "null" ]; then
        log_info "更新日志:"
        echo -e "${YELLOW}$RELEASE_NOTES${NC}"
    fi
}

# 检查版本是否需要更新
function check_version() {
    if [ "$FORCE_UPDATE" = true ]; then
        log_info "强制更新模式，将重新下载"
        return 1  # 需要更新
    fi
    
    if [ ! -f "$VERSION_FILE" ]; then
        log_info "未找到版本信息，将下载最新版本"
        return 1  # 需要更新
    fi
    
    local current_version
    current_version=$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")
    
    if [ "$current_version" = "$RELEASE_TAG" ]; then
        log_success "本地版本 ($current_version) 已是最新版本"
        return 0  # 不需要更新
    else
        log_info "发现新版本: $RELEASE_TAG (当前: $current_version)"
        return 1  # 需要更新
    fi
}

# 下载SHA256校验和（备用方法）
function download_sha256() {
    # 现在主要使用API返回的digest字段获取SHA256，这个函数作为备用
    if [ -z "$EXPECTED_SHA256" ] || [ "$EXPECTED_SHA256" = "null" ]; then
        if [ -z "$SHA256_URL" ] || [ "$SHA256_URL" = "null" ]; then
            log_warning "Release中未提供SHA256文件，跳过校验"
            return 1
        fi
        
        local sha256_file="$DOWNLOAD_DIR/NyxBot.jar.sha256"
        
        if download_file "$SHA256_URL" "$sha256_file" "SHA256校验文件" ""; then
            # 读取SHA256值
            EXPECTED_SHA256=$(cat "$sha256_file" | awk '{print $1}')
            log_info "从SHA256文件获取到校验值: $EXPECTED_SHA256"
            return 0
        else
            log_warning "无法下载SHA256文件，将跳过校验"
            return 1
        fi
    else
        log_info "已从API获取SHA256校验值: $EXPECTED_SHA256"
        return 0
    fi
}

# 显示主菜单
function show_main_menu() {
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}        NyxBot 管理脚本 (v${SCRIPT_VERSION})        ${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${GREEN}1.${NC} 安装 NyxBot"
    echo -e "${GREEN}2.${NC} 更新 NyxBot"
    echo -e "${GREEN}3.${NC} 运行 NyxBot (后台服务)"
    echo -e "${GREEN}4.${NC} 重启 NyxBot"
    echo -e "${GREEN}5.${NC} 停止 NyxBot"
    echo -e "${GREEN}6.${NC} 查看运行状态"
    echo -e "${GREEN}7.${NC} 退出"
    echo -e "${CYAN}===========================================${NC}"
    echo -e -n "请选择操作 (1-7): "
}

# 显示运行选项二级菜单
function show_run_menu() {
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}          NyxBot 运行选项          ${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${GREEN}1.${NC} 启动 NyxBot (使用当前配置)"
    echo -e "${GREEN}2.${NC} 配置启动参数"
    echo -e "${GREEN}3.${NC} 查看当前配置"
    echo -e "${GREEN}4.${NC} 返回主菜单"
    echo -e "${CYAN}===========================================${NC}"
    echo -e -n "请选择操作 (1-4): "
}

# 显示 OneBot 配置二级菜单
function show_onebot_menu() {
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}           OneBot 通讯模式选择           ${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${GREEN}1.${NC} 服务端模式 (wsServerEnable=true)"
    echo -e "${GREEN}2.${NC} 客户端模式 (wsClientEnable=true)"
    echo -e "${GREEN}3.${NC} 返回上一级菜单"
    echo -e "${CYAN}===========================================${NC}"
    echo -e -n "请选择 OneBot 通讯模式 (1-3): "
}

# 配置 OneBot 通讯参数
function configure_onebot() {
    while true;
    do
        show_onebot_menu
        read -r ws_choice
        
        case "$ws_choice" in
            1)
                write_config "WS_MODE" "server"
                write_config "WS_SERVER_ENABLE" "true"
                write_config "WS_CLIENT_ENABLE" "false"
                
                set_nyxbot_config "WS_SERVER_URL" "请输入服务端地址" "$DEFAULT_WS_SERVER_URL"
                break
                ;;
            2)
                write_config "WS_MODE" "client"
                write_config "WS_SERVER_ENABLE" "false"
                write_config "WS_CLIENT_ENABLE" "true"
                
                set_nyxbot_config "WS_CLIENT_URL" "请输入客户端地址" "$DEFAULT_WS_CLIENT_URL"
                break
                ;;
            3)
                return 0
                ;;
            *)
                log_error "无效的选择，请输入 1-3 之间的数字"
                ;;
        esac
    done
    
    set_nyxbot_config "SHIRO_TOKEN" "请输入OneBot协议链接的Token" "$DEFAULT_SHIRO_TOKEN"
    return 0
}

# 配置 NyxBot 运行参数
function configure_nyxbot() {
    log_info "配置 NyxBot 运行参数..."
    
    # 初始化配置文件
    init_config_file
    
    # 设置端口
    set_nyxbot_config "PORT" "请输入启动端口" "$DEFAULT_PORT"
    
    # 设置 Debug 模式
    local use_debug
    echo -e -n "${CYAN}是否开启 Debug 模式？(y/N): ${NC}"
    read -r use_debug
    
    if [[ "$use_debug" =~ ^[Yy]$ ]]; then
        write_config "DEBUG" "true"
    else
        write_config "DEBUG" "false"
    fi
    
    # 配置 OneBot 通讯参数
    configure_onebot
    
    # 设置代理
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}              代理设置              ${NC}"
    echo -e "${CYAN}===========================================${NC}"
    
    local use_proxy
    echo -e -n "${CYAN}是否需要设置代理？(y/N): ${NC}"
    read -r use_proxy
    
    if [[ "$use_proxy" =~ ^[Yy]$ ]]; then
        # 要求用户按照特定格式输入代理URL
        echo -e "${YELLOW}请按照以下格式输入代理URL：http://127.0.0.1:7890|socks://127.0.0.1:7890|socks5://127.0.0.1:7890${NC}"
        local proxy_url
        echo -e -n "${CYAN}请输入代理URL: ${NC}"
        read -r proxy_url
        
        # 验证代理URL格式
        if [[ "$proxy_url" =~ ^(http|socks|socks5)://[0-9a-zA-Z.-]+:[0-9]+$ ]]; then
            # 提取协议、主机和端口
            local proxy_protocol=$(echo "$proxy_url" | sed -E 's/^(http|socks|socks5):\/\/.*/\1/')
            local proxy_host=$(echo "$proxy_url" | sed -E 's/^(http|socks|socks5):\/\/([0-9a-zA-Z.-]+):([0-9]+)$/\2/')
            local proxy_port=$(echo "$proxy_url" | sed -E 's/^(http|socks|socks5):\/\/([0-9a-zA-Z.-]+):([0-9]+)$/\3/')
            
            # 保存代理配置
            write_config "PROXY_URL" "$proxy_url"
            write_config "PROXY_PROTOCOL" "$proxy_protocol"
            
            local use_auth
            echo -e -n "${CYAN}是否需要代理认证？(y/N): ${NC}"
            read -r use_auth
            
            if [[ "$use_auth" =~ ^[Yy]$ ]]; then
                set_nyxbot_config "PROXY_USERNAME" "请输入代理用户名" ""
                set_nyxbot_config "PROXY_PASSWORD" "请输入代理密码" ""
            else
                write_config "PROXY_USERNAME" ""
                write_config "PROXY_PASSWORD" ""
            fi
        else
            log_error "代理URL格式不正确，请重新配置"
            write_config "PROXY_URL" ""
            write_config "PROXY_PROTOCOL" ""
            write_config "PROXY_USERNAME" ""
            write_config "PROXY_PASSWORD" ""
        fi
    else
        write_config "PROXY_URL" ""
        write_config "PROXY_PROTOCOL" ""
        write_config "PROXY_USERNAME" ""
        write_config "PROXY_PASSWORD" ""
    fi
    
    log_success "NyxBot 运行参数配置完成"
    show_nyxbot_config
    return 0
}

# 安装 NyxBot
function install_nyxbot() {
    log_info "开始安装 NyxBot..."
    
    check_and_install_jre21
    network_test
    get_latest_release
    
    # 检查是否已安装
    if [ -f "$NYXBOT_JAR" ]; then
        local current_version
        current_version=$(cat "$VERSION_FILE" 2>/dev/null || echo "unknown")
        log_warning "NyxBot 已安装 (版本: $current_version)"
        echo -e -n "是否覆盖安装？(y/N): "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "安装已取消"
            return 0
        fi
    fi
    
    # 使用API获取的SHA256值进行校验（如果未获取到则尝试下载SHA256文件）
    download_sha256 && true  # 即使失败也继续
    
    # 备份旧版本（如果存在）
    if [ -f "$NYXBOT_JAR" ]; then
        local backup_file="${NYXBOT_JAR}.bak"
        log_info "备份旧版本到 $backup_file"
        mv "$NYXBOT_JAR" "$backup_file"
    fi
    
    # 下载NyxBot.jar
    if ! download_file "$DOWNLOAD_URL" "$NYXBOT_JAR" "NyxBot.jar" "$EXPECTED_SHA256"; then
        log_error "下载失败"
        
        # 如果有备份，恢复备份
        if [ -f "${NYXBOT_JAR}.bak" ]; then
            log_info "恢复备份版本..."
            mv "${NYXBOT_JAR}.bak" "$NYXBOT_JAR"
        fi
        return 1
    fi
    
    # 验证JAR文件完整性
    if command -v file &> /dev/null; then
        if ! file "$NYXBOT_JAR" | grep -q "Java archive data"; then
            log_error "下载的文件不是有效的JAR文件"
            rm -f "$NYXBOT_JAR"
            
            # 恢复备份
            if [ -f "${NYXBOT_JAR}.bak" ]; then
                log_info "恢复备份版本..."
                mv "${NYXBOT_JAR}.bak" "$NYXBOT_JAR"
            fi
            return 1
        fi
    fi
    
    # 保存版本信息
    echo "$RELEASE_TAG" > "$VERSION_FILE"
    log_success "NyxBot 安装成功 (版本: $RELEASE_TAG)"
    
    # 删除备份
    rm -f "${NYXBOT_JAR}.bak"
    return 0
}

# 更新 NyxBot
function update_nyxbot() {
    log_info "开始更新 NyxBot..."
    
    # 检查是否已安装
    if [ ! -f "$NYXBOT_JAR" ]; then
        log_warning "NyxBot 尚未安装，将执行安装操作"
        install_nyxbot
        return $?
    fi
    
    check_and_install_jre21
    network_test
    get_latest_release
    
    # 检查是否需要更新
    if check_version; then
        log_success "NyxBot 已是最新版本 (版本: $RELEASE_TAG)"
        return 0
    fi
    
    # 使用API获取的SHA256值进行校验（如果未获取到则尝试下载SHA256文件）
    download_sha256 && true  # 即使失败也继续
    
    # 备份旧版本
    local backup_file="${NYXBOT_JAR}.bak"
    log_info "备份旧版本到 $backup_file"
    mv "$NYXBOT_JAR" "$backup_file"
    
    # 下载NyxBot.jar
    if ! download_file "$DOWNLOAD_URL" "$NYXBOT_JAR" "NyxBot.jar" "$EXPECTED_SHA256"; then
        log_error "下载失败"
        
        # 恢复备份
        log_info "恢复备份版本..."
        mv "${NYXBOT_JAR}.bak" "$NYXBOT_JAR"
        return 1
    fi
    
    # 验证JAR文件完整性
    if command -v file &> /dev/null; then
        if ! file "$NYXBOT_JAR" | grep -q "Java archive data"; then
            log_error "下载的文件不是有效的JAR文件"
            rm -f "$NYXBOT_JAR"
            
            # 恢复备份
            log_info "恢复备份版本..."
            mv "${NYXBOT_JAR}.bak" "$NYXBOT_JAR"
            return 1
        fi
    fi
    
    # 保存版本信息
    echo "$RELEASE_TAG" > "$VERSION_FILE"
    log_success "NyxBot 更新成功 (版本: $RELEASE_TAG)"
    
    # 重启服务（如果正在运行）
    if is_service_running; then
        log_info "重启 NyxBot 服务..."
        restart_service
    fi
    
    # 删除备份
    rm -f "${NYXBOT_JAR}.bak"
    return 0
}

# 检查系统服务管理器
function get_service_manager() {
    if command -v systemctl &> /dev/null; then
        echo "systemd"
    elif command -v service &> /dev/null; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

# 创建 systemd 服务文件
function create_systemd_service() {
    local java_args="$1"
    local service_name="nyxbot"
    local service_file="/etc/systemd/system/${service_name}.service"
    local current_user=$(whoami)
    local jar_path="$(realpath "$NYXBOT_JAR")"
    local working_dir="$(dirname "$jar_path")"
    local jar_filename="$(basename "$jar_path")"
    
    log_info "创建 systemd 服务文件..."
    
    # 如果没有传递java_args参数，则使用默认参数
    if [ -z "$java_args" ]; then
        java_args="-jar ./$jar_filename"
    fi
    
    cat <<EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=NyxBot Service
After=network.target

[Service]
Type=simple
User=$current_user
WorkingDirectory=$working_dir
ExecStart=/usr/bin/java $java_args
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载 systemd 配置
    sudo systemctl daemon-reload
    
    log_success "systemd 服务文件已创建"
    return 0
}

# 启动服务
function start_service() {
    local service_manager=$(get_service_manager)
    
    # 获取jar文件名
    local jar_path="$(realpath "$NYXBOT_JAR")"
    local jar_filename="$(basename "$jar_path")"
    
    # 读取配置文件
    local NYXBOT_PORT=$(read_config "PORT" "$DEFAULT_PORT")
    local NYXBOT_DEBUG=$(read_config "DEBUG" "$DEFAULT_DEBUG")
    local NYXBOT_WS_SERVER_ENABLE=$(read_config "WS_SERVER_ENABLE" "$DEFAULT_WS_SERVER_ENABLE")
    local NYXBOT_WS_SERVER_URL=$(read_config "WS_SERVER_URL" "$DEFAULT_WS_SERVER_URL")
    local NYXBOT_WS_CLIENT_ENABLE=$(read_config "WS_CLIENT_ENABLE" "$DEFAULT_WS_CLIENT_ENABLE")
    local NYXBOT_WS_CLIENT_URL=$(read_config "WS_CLIENT_URL" "$DEFAULT_WS_CLIENT_URL")
    local NYXBOT_SHIRO_TOKEN=$(read_config "SHIRO_TOKEN" "$DEFAULT_SHIRO_TOKEN")
    local NYXBOT_PROXY_URL=$(read_config "PROXY_URL" "")
    local NYXBOT_PROXY_PROTOCOL=$(read_config "PROXY_PROTOCOL" "")
    local NYXBOT_PROXY_USER=$(read_config "PROXY_USERNAME" "$DEFAULT_PROXY_USERNAME")
    local NYXBOT_PROXY_PASSWORD=$(read_config "PROXY_PASSWORD" "$DEFAULT_PROXY_PASSWORD")
    
    # 构建Java启动参数
    local java_args="-jar ./$jar_filename"
    
    # 添加 Debug 参数
    if [ "$NYXBOT_DEBUG" = "true" ]; then
        java_args="$java_args -debug"
    fi
    
    # 添加端口参数
    java_args="$java_args -serverPort=$NYXBOT_PORT"
    
    # 添加 OneBot 参数
    if [ "$NYXBOT_WS_SERVER_ENABLE" = "true" ]; then
        java_args="$java_args -wsServerEnable"
    fi
    java_args="$java_args -wsServerUrl=$NYXBOT_WS_SERVER_URL"
    if [ "$NYXBOT_WS_CLIENT_ENABLE" = "true" ]; then
        java_args="$java_args -wsClientEnable"
    fi
    java_args="$java_args -wsClientUrl=$NYXBOT_WS_CLIENT_URL"
    java_args="$java_args -shiroToken=$NYXBOT_SHIRO_TOKEN"
    
    # 添加代理参数
    if [ -n "$NYXBOT_PROXY_URL" ] && [ -n "$NYXBOT_PROXY_PROTOCOL" ]; then
        # 从URL中提取主机和端口
        local NYXBOT_PROXY_HOST=$(echo "$NYXBOT_PROXY_URL" | sed -E 's/^(http|socks|socks5):\/\/([0-9a-zA-Z.-]+):([0-9]+)$/\2/')
        local NYXBOT_PROXY_PORT=$(echo "$NYXBOT_PROXY_URL" | sed -E 's/^(http|socks|socks5):\/\/([0-9a-zA-Z.-]+):([0-9]+)$/\3/')
        
        # 根据代理协议设置相应的Java系统属性
        case "$NYXBOT_PROXY_PROTOCOL" in
            http)
                java_args="$java_args -httpProxy=$NYXBOT_PROXY_PROTOCOL://$NYXBOT_PROXY_HOST:$NYXBOT_PROXY_PORT"
                ;;
            socks|socks5)
                java_args="$java_args -socksProxy=$NYXBOT_PROXY_PROTOCOL://$NYXBOT_PROXY_HOST:$NYXBOT_PROXY_PORT"
                ;;
        esac
        
        # 添加代理认证参数
        if [ -n "$NYXBOT_PROXY_USER" ] && [ -n "$NYXBOT_PROXY_PASSWORD" ]; then
            java_args="$java_args -proxyUser=$NYXBOT_PROXY_USER"
            java_args="$java_args -proxyPassword=$NYXBOT_PROXY_PASSWORD"
        fi
    fi
    
    case "$service_manager" in
        "systemd")
            # 检查服务文件是否存在
            if [ ! -f "/etc/systemd/system/nyxbot.service" ]; then
                create_systemd_service "$java_args"
            else
                # 更新systemd服务文件
                create_systemd_service "$java_args"
                sudo systemctl daemon-reload
            fi
            
            sudo systemctl start nyxbot
            sudo systemctl enable nyxbot  # 设置开机自启
            ;;
        "sysvinit")
            log_warning "sysvinit 支持有限，将使用 nohup 后台运行"
            nohup java $java_args > "$DOWNLOAD_DIR/nyxbot.log" 2>&1 &
            echo $! > "$DOWNLOAD_DIR/nyxbot.pid"
            ;;
        *)
            log_warning "未知的服务管理器，将使用 nohup 后台运行"
            nohup java $java_args > "$DOWNLOAD_DIR/nyxbot.log" 2>&1 &
            echo $! > "$DOWNLOAD_DIR/nyxbot.pid"
            ;;
    esac
    
    log_success "NyxBot 服务已启动"
    return 0
}

# 停止服务
function stop_service() {
    local service_manager=$(get_service_manager)
    
    case "$service_manager" in
        "systemd")
            sudo systemctl stop nyxbot
            ;;
        "sysvinit")
            if [ -f "$DOWNLOAD_DIR/nyxbot.pid" ]; then
                local pid=$(cat "$DOWNLOAD_DIR/nyxbot.pid")
                kill "$pid" 2>/dev/null || true
                rm -f "$DOWNLOAD_DIR/nyxbot.pid"
            fi
            ;;
        *)
            if [ -f "$DOWNLOAD_DIR/nyxbot.pid" ]; then
                local pid=$(cat "$DOWNLOAD_DIR/nyxbot.pid")
                kill "$pid" 2>/dev/null || true
                rm -f "$DOWNLOAD_DIR/nyxbot.pid"
            fi
            ;;
    esac
    
    log_success "NyxBot 服务已停止"
    return 0
}

# 重启服务
function restart_service() {
    stop_service
    sleep 2
    start_service
    return 0
}

# 检查服务是否运行
function is_service_running() {
    local service_manager=$(get_service_manager)
    
    case "$service_manager" in
        "systemd")
            if sudo systemctl is-active nyxbot > /dev/null 2>&1; then
                return 0
            fi
            ;;
        "sysvinit"|"unknown")
            if [ -f "$DOWNLOAD_DIR/nyxbot.pid" ]; then
                local pid=$(cat "$DOWNLOAD_DIR/nyxbot.pid")
                if ps -p "$pid" > /dev/null 2>&1; then
                    return 0
                fi
                # PID 文件存在但进程不存在，清理 PID 文件
                rm -f "$DOWNLOAD_DIR/nyxbot.pid"
            fi
            ;;
    esac
    
    return 1
}

# 查看服务状态
function check_service_status() {
    local service_manager=$(get_service_manager)
    
    if is_service_running; then
        log_success "NyxBot 服务正在运行"
        
        case "$service_manager" in
            "systemd")
                sudo systemctl status nyxbot --no-pager
                ;;
            "sysvinit"|"unknown")
                local pid=$(cat "$DOWNLOAD_DIR/nyxbot.pid")
                log_info "PID: $pid"
                log_info "日志文件: $DOWNLOAD_DIR/nyxbot.log"
                ;;
        esac
    else
        log_warning "NyxBot 服务未运行"
    fi
    
    return 0
}

# 运行 NyxBot（后台服务）
function run_nyxbot() {
    # 检查是否已安装
    if [ ! -f "$NYXBOT_JAR" ]; then
        log_warning "NyxBot 尚未安装，将先执行安装"
        if ! install_nyxbot; then
            log_error "安装失败，无法运行"
            return 1
        fi
    fi
    
    # 检查是否已在运行
    if is_service_running; then
        log_warning "NyxBot 服务已经在运行"
        echo -e -n "是否重启服务？(y/N): "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            restart_service
        else
            log_info "操作已取消"
        fi
        return 0
    fi
    
    # 初始化配置文件
    init_config_file
    
    # 显示二级菜单
    while true; do
        show_run_menu
        read -r run_choice
        
        case "$run_choice" in
            1)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}            启动 NyxBot            ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                start_service
                return 0
                ;;
            2)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}          配置运行参数          ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                configure_nyxbot
                ;;
            3)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}          当前运行配置          ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                show_nyxbot_config
                ;;
            4)
                log_info "返回主菜单"
                return 0
                ;;
            *)
                log_error "无效的选择，请输入 1-4 之间的数字"
                ;;
        esac
        
        echo -e "${CYAN}===========================================${NC}"
        echo -e "${CYAN}              按回车键继续...              ${NC}"
        echo -e "${CYAN}===========================================${NC}"
        read -r
    done
}

# 主流程
function main() {
    parse_arguments "$@"
    
    while true; do
        show_main_menu
        read -r choice
        
        case "$choice" in
            1)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}                安装 NyxBot                ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                install_nyxbot
                ;;
            2)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}                更新 NyxBot                ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                update_nyxbot
                ;;
            3)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}              运行 NyxBot (后台)            ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                run_nyxbot
                ;;
            4)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}                重启 NyxBot                ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                restart_service
                ;;
            5)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}                停止 NyxBot                ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                stop_service
                ;;
            6)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}              查看运行状态                ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                check_service_status
                ;;
            7)
                echo -e "${CYAN}===========================================${NC}"
                echo -e "${CYAN}                退出程序                ${NC}"
                echo -e "${CYAN}===========================================${NC}"
                log_info "感谢使用 NyxBot 管理脚本"
                exit 0
                ;;
            *)
                log_error "无效的选择，请输入 1-7 之间的数字"
                ;;
        esac
        
        echo -e "${CYAN}===========================================${NC}"
        echo -e "${CYAN}              按回车键继续...              ${NC}"
        echo -e "${CYAN}===========================================${NC}"
        read -r
    done
}

# 执行主函数
main "$@"