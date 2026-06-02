# nyxbot-deploy.ps1
# NyxBot 一键部署脚本 (Windows)
# 用法: .\nyxbot-deploy.ps1 [options]
# 或: irm <url> | iex

param(
    [switch]$Docker,
    [switch]$Local,
    [switch]$Quiet,
    [switch]$Help,
    [string]$Port = "8080",
    [string]$Token = "",
    [switch]$Server,
    [switch]$Client,
    [string]$ProxyAddr = "",
    [string]$ProxyUser = "",
    [string]$ProxyPass = "",
    [switch]$Debug
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================================
# 常量
# ============================================================================
$SCRIPT_VERSION = "1.0.0"
$API_URL = "https://api.github.com/repos/KingPrimes/NyxBot/releases/latest"
$IMAGE_NAME = "kingprimes/nyxbot"
$DOWNLOAD_DIR = Join-Path (Split-Path $PSCommandPath -Parent) "NyxBot"
$TASK_NAME = "NyxBot"

# ============================================================================
# 颜色 & 日志
# ============================================================================
function Write-Step   { Write-Host "[>] " -ForegroundColor Cyan   -NoNewline; Write-Host $args[0] }
function Write-Success { Write-Host "[?] " -ForegroundColor Green  -NoNewline; Write-Host $args[0] }
function Write-Warn   { Write-Host "[!] " -ForegroundColor Yellow -NoNewline; Write-Host $args[0] }
function Write-Error  { Write-Host "[?] " -ForegroundColor Red    -NoNewline; Write-Host $args[0]; exit 1 }

function Show-Banner {
    Write-Host @"
  _   _           ____        _
 | \ | |_  ___  _| __ )  ___ | |_
 |  \| \ \/ / | | |  _ \ / _ \| __|
 | |\  |>  <| |_| | |_) | (_) | |_
 |_| \_/_/\_\\__, |____/ \___/ \__|
             |___/

"@ -ForegroundColor Green
    Write-Host "  NyxBot 部署脚本 v$SCRIPT_VERSION`n"
}

# ============================================================================
# 环境检测
# ============================================================================
function Test-Environment {
    Write-Success "系统: Windows $((Get-CimInstance Win32_OperatingSystem).Caption -replace 'Microsoft ', '')"
    Write-Success "架构: $(if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' })"

    if (-not [Environment]::Is64BitOperatingSystem) {
        Write-Warn "32 位系统可能无法正常运行 NyxBot"
    }
}

function Test-Java {
    try {
        $v = & java -version 2>&1 | Select-Object -First 1
        if ($v -match 'version "21\.') {
            Write-Success "Java 21: 已安装"
            return $true
        }
        Write-Warn "Java: 已安装但非版本 21"
    } catch {
        Write-Warn "Java 21: 未安装"
    }
    return $false
}

function Install-Java {
    Write-Step "安装 Java 21..."
    Write-Warn "请手动下载安装 JDK 21: https://www.oracle.com/java/technologies/downloads/#jdk21-windows"
    $confirm = Read-Host "安装完成后按回车继续，或输入 q 退出"
    if ($confirm -eq "q") { exit 0 }
    if (-not (Test-Java)) {
        Write-Error "Java 安装验证失败，请确认 JDK 21 已正确安装并加入 PATH"
    }
}

function Test-Docker {
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        Write-Success "Docker: 已安装 ($(docker --version))"
        return $true
    }
    return $false
}

# ============================================================================
# 网络测速
# ============================================================================
function Test-Network {
    Write-Step "网络测速（选择最快路线）..."
    $check_url = "https://raw.githubusercontent.com/KingPrimes/DataSource/main/warframe/state_translation.json"
    $proxies = @(
        @{ Name = "直连"; Url = $null }
        @{ Name = "ghfast.top"; Url = "https://ghfast.top" }
        @{ Name = "gh-proxy.com"; Url = "https://gh-proxy.com" }
        @{ Name = "gh-proxy.net"; Url = "https://gh-proxy.net" }
        @{ Name = "ghproxy.vip"; Url = "https://ghproxy.vip" }
        @{ Name = "gh-proxy.org"; Url = "https://gh-proxy.org" }
        @{ Name = "edgeone.gh-proxy.org"; Url = "https://edgeone.gh-proxy.org" }
        @{ Name = "ghm.078465.xyz"; Url = "https://ghm.078465.xyz" }
        @{ Name = "git.yylx.win"; Url = "https://git.yylx.win" }
    )
    $bestSpeed = 0
    $bestName = ""

    foreach ($p in $proxies) {
        $testUrl = if ($p.Url) { "$($p.Url)/$check_url" } else { $check_url }
        try {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $req = [System.Net.HttpWebRequest]::Create($testUrl)
            $req.Timeout = 10000
            $req.UserAgent = "Mozilla/5.0"
            $resp = $req.GetResponse()
            $stream = $resp.GetResponseStream()
            $buf = New-Object byte[] 65536
            $total = 0
            while ($total -lt 524288) {
                $n = $stream.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                $total += $n
            }
            $sw.Stop()
            $stream.Close(); $resp.Close()
            $speed = if ($sw.Elapsed.TotalSeconds -gt 0) { $total / $sw.Elapsed.TotalSeconds } else { 0 }
            Write-Host "  $($p.Name): $(Format-Speed $speed)" -ForegroundColor $(if ($speed -gt 0) { 'Green' } else { 'Red' })
            if ($speed -gt $bestSpeed) { $bestSpeed = $speed; $bestName = $p.Url }
        } catch {
            Write-Host "  $($p.Name): 不可用" -ForegroundColor Red
        }
    }
    $script:GITHUB_PROXY = $bestName
    if ($bestSpeed -gt 0) { Write-Success "选择: $(if ($bestName) { $bestName } else { '直连' }) ($(Format-Speed $bestSpeed))" }
    else { Write-Warn "所有连接方式不可用" }
}

function Format-Speed($bps) {
    if ($bps -gt 1048576) { return "$([math]::Round($bps/1048576,1)) MB/s" }
    if ($bps -gt 1024) { return "$([math]::Round($bps/1024,1)) KB/s" }
    return "$([math]::Round($bps)) B/s"
}

# ============================================================================
# 获取版本 & 下载
# ============================================================================
function Get-Release {
    Write-Step "获取最新版本..."
    try {
        $resp = Invoke-RestMethod -Uri $API_URL -Headers @{
            "User-Agent" = "Mozilla/5.0"
            "Accept" = "application/vnd.github.v3+json"
        } -TimeoutSec 10
        $jar = $resp.assets | Where-Object { $_.name -like "*.jar" } | Select-Object -First 1
        $script:DOWNLOAD_URL = $jar.browser_download_url
        $script:RELEASE_TAG = $resp.tag_name
        Write-Success "版本: $RELEASE_TAG"
    } catch {
        Write-Error "无法获取版本信息: $_"
    }
}

function Download-Jar {
    $url = $DOWNLOAD_URL
    if ($GITHUB_PROXY) { $url = "$GITHUB_PROXY/$($url -replace '^https://', '')" }

    if (-not (Test-Path $DOWNLOAD_DIR)) { New-Item -ItemType Directory -Path $DOWNLOAD_DIR -Force | Out-Null }
    $dest = "$DOWNLOAD_DIR\NyxBot.jar"

    Write-Step "下载 NyxBot $RELEASE_TAG..."
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0")

    # 下载事件：显示进度
    $global:lastPct = -1
    Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -Action {
        $pct = $EventArgs.ProgressPercentage
        if ($pct -gt $global:lastPct) {
            $global:lastPct = $pct
            $bar = "#" * [math]::Floor($pct / 2) + "-" * (50 - [math]::Floor($pct / 2))
            Write-Host "`r  [$bar] $pct%" -NoNewline
        }
    } | Out-Null

    Register-ObjectEvent -InputObject $wc -EventName DownloadFileCompleted -Action { Write-Host "" } | Out-Null

    $wc.DownloadFileAsync($url, $dest)
    while ($wc.IsBusy) { Start-Sleep -Milliseconds 200 }

    Get-EventSubscriber | Unregister-Event -Force -ErrorAction SilentlyContinue
    $wc.Dispose()
    Write-Success "下载完成 ($([math]::Round(((Get-Item $dest).Length)/1MB, 1)) MB)"
}

# ============================================================================
# 配置（文本交互）
# ============================================================================
function Get-Config {
    if (-not $Quiet) {
        Write-Host "`n── 基础配置 ──" -ForegroundColor White
        $input = Read-Host "  端口 [$Port]"
        if ($input) { $Port = $input }

        if (-not $Token) {
            while (-not $Token) { $Token = Read-Host "  Token (必填)" }
        }

        if (-not $Server -and -not $Client) {
            Write-Host "  模式: 1) 服务端  2) 客户端"
            $mode = Read-Host "  选择 [1]"
            if ($mode -eq "2") { $Client = $true } else { $Server = $true }
        }

        Write-Host "── 代理（回车跳过）──" -ForegroundColor White
        if (-not $ProxyAddr) { $ProxyAddr = Read-Host "  代理地址" }
        if ($ProxyAddr) { $ProxyUser = Read-Host "  用户名"; $ProxyPass = Read-Host "  密码" }

        Write-Host "`n── 确认 ──" -ForegroundColor White
        Write-Host "  端口: $Port | 模式: $(if ($Client) { '客户端' } else { '服务端' }) | Token: $Token"
        $confirm = Read-Host "  确认安装? [Y/n]"
        if ($confirm -match "^[Nn]") { Write-Warn "已取消"; exit 0 }
    }
}

# ============================================================================
# Docker 镜像拉取（国内镜像源自动切换）
# ============================================================================
# 国内 Docker Hub 代理列表（已测试连通性）
$DOCKER_MIRRORS = @(
    "docker.1panel.live"
    "docker.m.daocloud.io"
    "hub.rat.dev"
)

function Invoke-DockerPull {
    param($Image)

    Write-Step "拉取镜像: ${Image}"
    docker pull $Image 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "镜像拉取成功（直连 Docker Hub）"
        return
    }

    Write-Warn "Docker Hub 直连失败，尝试国内镜像源..."
    foreach ($mirror in $DOCKER_MIRRORS) {
        $mirrorImage = "${mirror}/${Image}"
        Write-Step "  尝试: ${mirrorImage}"
        docker pull $mirrorImage 2>$null
        if ($LASTEXITCODE -eq 0) {
            docker tag $mirrorImage $Image 2>$null
            docker rmi $mirrorImage 2>$null
            Write-Success "镜像拉取成功（via ${mirror}）"
            return
        }
    }
    Write-Error "所有镜像源均不可用，请检查网络或手动配置 Docker 镜像加速器"
}

# ============================================================================
# Docker 安装
# ============================================================================
function Install-Docker {
    Write-Step "Docker 模式安装..."

    # 停止旧容器
    docker stop nyxbot 2>$null; docker rm nyxbot 2>$null

    $envArgs = @(
        "-e", "SERVER_PORT=$Port"
        "-e", "SHIRO_TOKEN=$Token"
        "-e", "TZ=Asia/Shanghai"
    )
    if ($Debug) { $envArgs += "-e"; $envArgs += "DEBUG=true" }
    if ($Client) {
        $envArgs += "-e"; $envArgs += "SHIRO_WS_SERVER_ENABLE=false"
        $envArgs += "-e"; $envArgs += "SHIRO_WS_CLIENT_ENABLE=true"
    }
    if ($ProxyAddr) { $envArgs += "-e"; $envArgs += "HTTP_PROXY=$ProxyAddr" }
    if ($ProxyUser) { $envArgs += "-e"; $envArgs += "PROXY_USER=$ProxyUser" }
    if ($ProxyPass) { $envArgs += "-e"; $envArgs += "PROXY_PASSWORD=$ProxyPass" }

    Invoke-DockerPull "${IMAGE_NAME}:latest"

    Write-Step "启动容器..."
    docker run -d --name nyxbot --restart unless-stopped `
        -p "${Port}:8080" `
        -v "${DOWNLOAD_DIR}\data:/app/data" `
        -v "${DOWNLOAD_DIR}\logs:/app/logs" `
        $envArgs `
        "${IMAGE_NAME}:latest"

    Write-Success "NyxBot 已启动 (容器: nyxbot)"
    Show-PostInstall -Docker
}

# ============================================================================
# 本地安装
# ============================================================================
function Install-Local {
    if (-not (Test-Java)) { Install-Java }
    Test-Network
    Get-Release
    Download-Jar

    # 构建启动参数
    $javaArgs = @("-jar", "$DOWNLOAD_DIR\NyxBot.jar", "-serverPort=$Port")
    if ($Debug) { $javaArgs += "-debug" }
    if ($Server) { $javaArgs += "-wsServerEnable" }
    if ($Client) { $javaArgs += "-wsClientEnable" }
    $javaArgs += "-shiroToken=$Token"
    if ($ProxyAddr) { $javaArgs += "-httpProxy=$ProxyAddr" }
    if ($ProxyUser) { $javaArgs += "-proxyUser=$ProxyUser" }
    if ($ProxyPass) { $javaArgs += "-proxyPassword=$ProxyPass" }

    # 创建计划任务
    Write-Step "创建 Windows 计划任务..."
    $action = New-ScheduledTaskAction -Execute "java.exe" `
        -Argument ($javaArgs -join " ") `
        -WorkingDirectory $DOWNLOAD_DIR

    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    # 删除旧任务
    Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue

    Register-ScheduledTask -TaskName $TASK_NAME `
        -Action $action -Trigger $trigger -Settings $settings `
        -Description "NyxBot 服务" -RunLevel Highest | Out-Null

    Start-ScheduledTask -TaskName $TASK_NAME
    Write-Success "NyxBot 已启动 (计划任务: $TASK_NAME)"
    Show-PostInstall -Local
}

# ============================================================================
# 安装后提示
# ============================================================================
function Show-PostInstall {
    param([switch]$Docker, [switch]$Local)
    Write-Host ""
    Write-Host "┌──────────────────────────────────────────┐" -ForegroundColor Green
    Write-Host "│              NyxBot 安装完成！            │" -ForegroundColor Green
    Write-Host "├──────────────────────────────────────────┤" -ForegroundColor Green
    Write-Host "│  管理页面: http://localhost:${Port}" -ForegroundColor Green
    Write-Host "│  数据目录: ${DOWNLOAD_DIR}" -ForegroundColor Green
    if ($Docker) {
        Write-Host "│  查看日志: docker logs -f nyxbot" -ForegroundColor Green
        Write-Host "│  重启: docker restart nyxbot" -ForegroundColor Green
    } else {
        Write-Host "│  查看状态: Get-ScheduledTask -TaskName '$TASK_NAME'" -ForegroundColor Green
        Write-Host "│  日志: ${DOWNLOAD_DIR}\nyxbot.log" -ForegroundColor Green
    }
    Write-Host "└──────────────────────────────────────────┘" -ForegroundColor Green
}

# ============================================================================
# 帮助
# ============================================================================
function Show-Help {
    Write-Host @"
用法: .\nyxbot-deploy.ps1 [选项]

模式选择:
  -Docker           Docker 安装
  -Local            本地安装

运行模式:
  -Quiet            静默模式（不交互）
  -Help             显示帮助

配置参数:
  -Port 8080        服务端口
  -Token xxx        OneBot Token
  -Server           服务端模式
  -Client           客户端模式
  -ProxyAddr URL    代理地址
  -Debug            开启 Debug

示例:
  .\nyxbot-deploy.ps1                                     # 交互式
  .\nyxbot-deploy.ps1 -Docker -Quiet -Token abc123       # Docker 静默
  .\nyxbot-deploy.ps1 -Local -Port 9090 -Token abc123    # 本地安装
"@
}

# ============================================================================
# 主入口
# ============================================================================
function Main {
    if ($Help) { Show-Help; return }

    # 静默模式校验
    if ($Quiet -and -not $Token) { Write-Error "--quiet 模式必须提供 --token=xxx" }

    Show-Banner
    Test-Environment

    # 选择安装模式
    if (-not $Docker -and -not $Local) {
        if (Test-Docker) {
            $Docker = $true
        } else {
            $Local = $true
        }
    }

    # 显示安装方式 & 路径
    if ($Docker) {
        Write-Step "安装方式: Docker 容器模式"
        Write-Step "数据目录: ${DOWNLOAD_DIR} (映射至容器 /app/data)"
    } else {
        Write-Step "安装方式: 本地安装 (Windows)"
        Write-Step "安装目录: ${DOWNLOAD_DIR}"
    }
    Write-Host ""

    Get-Config

    if ($Docker) { Install-Docker } else { Install-Local }
}

Main
