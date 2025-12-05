# ============================================================================
# NyxBot 启动脚本 (Windows) - 改进版
# 版本: 2.0.0
# 功能: 自动安装JDK 21、下载最新版本NyxBot并启动
# 改进: SHA256校验、版本检查、增强错误处理
# ============================================================================

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$ForceUpdate,
    [switch]$SkipJava,
    [string]$Proxy = "",
    [switch]$Version,
    [switch]$Help
)

# 严格模式
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# 设置变量
$SCRIPT_VERSION = "2.0.0"
$API_URL = "https://api.github.com/repos/KingPrimes/depot/releases/latest"
$DOWNLOAD_DIR = Join-Path $PSScriptRoot "nyxbot_data"
$NYXBOT_JAR = "$DOWNLOAD_DIR\NyxBot.jar"
$VERSION_FILE = "$DOWNLOAD_DIR\.version"
$LOG_FILE = "$DOWNLOAD_DIR\install.log"

# 全局变量
$DOWNLOAD_URL = ""
$ASSET_NAME = ""
$RELEASE_TAG = ""
$SHA256_URL = ""
$EXPECTED_SHA256 = ""
$GITHUB_PROXY = ""

# 错误处理
trap {
    Write-Host "错误: $_" -ForegroundColor Red
    Write-Host "详细日志请查看: $LOG_FILE" -ForegroundColor Yellow
    exit 1
}

# 日志函数
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LOG_FILE -Value $logMessage -ErrorAction SilentlyContinue
    
    switch ($Level) {
        "INFO" { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
        "SUCCESS" { Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
        "WARNING" { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
        "ERROR" { Write-Host "[ERROR] $Message" -ForegroundColor Red }
    }
}

# 显示帮助信息
function Show-Help {
    @"
用法: .\nyxbot-windows.ps1 [选项]

选项:
  -ForceUpdate    强制更新，即使本地已是最新版本
  -SkipJava       跳过Java环境检查和安装
  -Proxy <num>    指定代理序号（0=不使用代理，1-N=使用第N个代理）
  -Version        显示脚本版本
  -Help           显示此帮助信息

示例:
  .\nyxbot-windows.ps1                      # 正常安装（自动选择最快代理）
  .\nyxbot-windows.ps1 -ForceUpdate         # 强制更新到最新版本
  .\nyxbot-windows.ps1 -SkipJava            # 跳过Java安装
  .\nyxbot-windows.ps1 -Proxy 0             # 不使用代理（直连）
  .\nyxbot-windows.ps1 -Proxy 1             # 使用第1个代理服务器
"@
}

# 处理命令行参数
if ($Help) {
    Show-Help
    exit 0
}

if ($Version) {
    Write-Host "NyxBot启动脚本版本: $SCRIPT_VERSION"
    exit 0
}

# 创建下载目录和日志文件
if (-not (Test-Path $DOWNLOAD_DIR)) {
    New-Item -ItemType Directory -Path $DOWNLOAD_DIR | Out-Null
    Write-Log "创建下载目录: $DOWNLOAD_DIR" "SUCCESS"
}

# 初始化日志文件
$logHeader = "=== NyxBot安装日志 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
Set-Content -Path $LOG_FILE -Value $logHeader

Write-Host "=== NyxBot启动脚本(Windows) v$SCRIPT_VERSION ===" -ForegroundColor Cyan

# 检查Java版本，如果没有安装JRE 21则尝试安装
function CheckAndInstallJRE21 {
    if ($SkipJava) {
        Write-Log "跳过Java环境检查" "WARNING"
        return
    }

    Write-Log "检查JRE 21环境..." "INFO"

    try {
        $javaVersionOutput = & java -version 2>&1
        $javaVersionLine = $javaVersionOutput[0]
        Write-Log "检测到Java: $javaVersionLine" "INFO"

        if ($javaVersionLine -match '"21\.|openjdk 21\.') {
            Write-Log "JRE 21已安装" "SUCCESS"
            return
        } else {
            Write-Log "检测到Java，但不是版本21" "WARNING"
        }
    } catch {
        Write-Log "未检测到Java安装" "WARNING"
    }

    Write-Log "未检测到JRE 21，尝试自动安装..." "INFO"

    # 检查是否安装了winget
    $wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

    if ($wingetAvailable) {
        Write-Log "检测到Windows Package Manager (winget)，使用它安装OpenJRE 21..." "INFO"

        # 尝试安装Microsoft Build of OpenJRE 21
        try {
            Write-Log "尝试安装 Microsoft Build of OpenJRE 21..." "INFO"
            winget install --id Microsoft.OpenJDK.21.JRE -e --accept-source-agreements --accept-package-agreements --silent
            Write-Log "Microsoft OpenJRE 21安装成功" "SUCCESS"
            
            # 刷新环境变量
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            return
        } catch {
            Write-Log "Microsoft OpenJRE安装失败: $($_.Exception.Message)" "WARNING"
        }

        # 尝试安装Adoptium Temurin OpenJRE 21
        try {
            Write-Log "尝试安装 Eclipse Temurin OpenJRE 21..." "INFO"
            winget install --id EclipseAdoptium.Temurin.21.JRE -e --accept-source-agreements --accept-package-agreements --silent
            Write-Log "Eclipse Temurin OpenJRE 21安装成功" "SUCCESS"
            
            # 刷新环境变量
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            return
        } catch {
            Write-Log "Eclipse Temurin OpenJRE安装失败: $($_.Exception.Message)" "WARNING"
        }
    }

    # 检查是否安装了Chocolatey
    $chocoInstalled = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)

    if ($chocoInstalled) {
        Write-Log "检测到Chocolatey，使用它安装OpenJRE 21..." "INFO"
        try {
            choco install -y openjre --version=21
            Write-Log "OpenJRE 21安装成功" "SUCCESS"
            
            # 刷新环境变量
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            return
        } catch {
            Write-Log "Chocolatey安装OpenJRE失败: $($_.Exception.Message)" "ERROR"
        }
    }

    # 无法自动安装，提供手动安装指导
    Write-Log "无法自动安装OpenJRE 21。请手动安装：" "ERROR"
    Write-Host "1. 访问 https://learn.microsoft.com/java/openjdk/download 下载Microsoft Build of OpenJRE 21" -ForegroundColor Yellow
    Write-Host "2. 或访问 https://adoptium.net/ 下载Eclipse Temurin OpenJRE 21" -ForegroundColor Yellow

    if ($wingetAvailable) {
        Write-Host "3. 或使用winget安装: winget install --id Microsoft.OpenJDK.21.JRE -e" -ForegroundColor Yellow
    }

    if ($chocoInstalled) {
        Write-Host "4. 或使用Chocolatey安装: choco install -y openjre --version=21" -ForegroundColor Yellow
    }

    pause
    exit 1
}
# 显示安装菜单
function Show-OneBotInstallMenu {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "               OneBot 协议实现安装引导                            " -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "请选择要安装的实现："
    Write-Host ""
    Write-Host "  1) " -NoNewline -ForegroundColor Green
    Write-Host "LLOneBot " -NoNewline
    Write-Host "(推荐 - 适合已有 QQ 的用户)" -ForegroundColor Yellow
    Write-Host "     ├─ 作为 QQ 插件运行"
    Write-Host "     ├─ 无需额外客户端"
    Write-Host "     ├─ 使用已有 QQ 账号"
    Write-Host "     └─ 文档：" -NoNewline
    Write-Host "https://llonebot.com/guide/getting-started" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2) " -NoNewline -ForegroundColor Green
    Write-Host "NapCatQQ " -NoNewline
    Write-Host "(推荐 - 独立运行)" -ForegroundColor Yellow
    Write-Host "     ├─ 独立的 QQ 客户端"
    Write-Host "     ├─ 适合服务器部署"
    Write-Host "     ├─ 支持 Docker"
    Write-Host "     └─ 文档：" -NoNewline
    Write-Host "https://napneko.github.io/guide/boot/Shell" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  3) " -NoNewline -ForegroundColor Green
    Write-Host "我已安装，跳过此步骤"
    Write-Host ""
    Write-Host "  4) " -NoNewline -ForegroundColor Green
    Write-Host "退出脚本"
    Write-Host ""
    
    $choice = Read-Host "请选择 [1-4]"
    
    switch ($choice) {
        "1" { Show-LLOneBotGuide }
        "2" { Show-NapCatGuide }
        "3" {
            Write-Log "跳过 OneBot 检测" "INFO"
            return
        }
        "4" {
            Write-Log "退出脚本" "INFO"
            exit 0
        }
        default {
            Write-Log "无效选择，请重新选择" "ERROR"
            Show-OneBotInstallMenu
        }
    }
}
# 网络测试和代理选择函数
function Test-GitHubProxy {
    $proxyArr = @(
        "https://ghfast.top",
        "https://git.yylx.win/",
        "https://gh-proxy.com",
        "https://ghfile.geekertao.top",
        "https://gh-proxy.net",
        "https://j.1win.ggff.net",
        "https://ghm.078465.xyz",
        "https://gitproxy.127731.xyz",
        "https://jiashu.1win.eu.org",
        "https://github.tbedu.top"
    )
    $checkUrl = "https://raw.githubusercontent.com/KingPrimes/depot/main/README.md"
    $timeout = 10
    
    Write-Log "开始 GitHub 代理网络测试..." "INFO"
    
    # 如果指定了代理序号
    if ($Proxy -ne "") {
        if ($Proxy -eq "0") {
            Write-Log "已指定不使用代理（直连）" "INFO"
            $script:GITHUB_PROXY = ""
            return $true
        } elseif ($Proxy -match '^\d+$' -and [int]$Proxy -ge 1 -and [int]$Proxy -le $proxyArr.Count) {
            $script:GITHUB_PROXY = $proxyArr[[int]$Proxy - 1]
            Write-Log "已指定使用代理: $GITHUB_PROXY" "INFO"
            return $true
        } else {
            Write-Log "无效的代理序号: $Proxy，将自动选择" "WARNING"
        }
    }
    
    # 自动测速选择最快代理
    $bestProxy = ""
    $bestSpeed = 0
    
    # 测试直连
    Write-Log "测速: 直连..." "INFO"
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri $checkUrl -TimeoutSec $timeout -UseBasicParsing -ErrorAction Stop
        $stopwatch.Stop()
        
        if ($response.StatusCode -eq 200) {
            $speed = $response.Content.Length / $stopwatch.Elapsed.TotalSeconds
            $speedMB = [math]::Round($speed / 1MB, 2)
            Write-Log "测速: 直连 - $speedMB MB/s" "INFO"
            $bestSpeed = $speed
        }
    } catch {
        Write-Log "直连测试失败" "INFO"
    }
    
    # 测试所有代理
    foreach ($proxyCandidate in $proxyArr) {
        $testUrl = "$proxyCandidate/$checkUrl"
        
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-WebRequest -Uri $testUrl -TimeoutSec $timeout -UseBasicParsing -ErrorAction Stop
            $stopwatch.Stop()
            
            if ($response.StatusCode -eq 200) {
                $speed = $response.Content.Length / $stopwatch.Elapsed.TotalSeconds
                $speedMB = [math]::Round($speed / 1MB, 2)
                Write-Log "测速: $proxyCandidate - $speedMB MB/s" "INFO"
                
                if ($speed -gt $bestSpeed) {
                    $bestSpeed = $speed
                    $bestProxy = $proxyCandidate
                }
            }
        } catch {
            # 忽略失败的代理
        }
    }
    
    if ($bestSpeed -gt 0) {
        $script:GITHUB_PROXY = $bestProxy
        if ($bestProxy -ne "") {
            Write-Log "将使用最快的代理: $GITHUB_PROXY" "SUCCESS"
        } else {
            Write-Log "直连速度最快，不使用代理" "SUCCESS"
        }
        return $true
    } else {
        Write-Log "所有代理和直连均失败，将尝试直连" "WARNING"
        $script:GITHUB_PROXY = ""
        return $false
    }
}

# 下载文件函数（带重试和校验）
function DownloadFile {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Description,
        [string]$ExpectedSHA256 = ""
    )

    Write-Log "下载 $Description..." "INFO"
    
    # 构建下载URL
    $downloadUrl = $Url
    if ($GITHUB_PROXY -ne "") {
        $downloadUrl = "$GITHUB_PROXY/" + $Url.Substring("https://".Length)
        Write-Log "使用代理: $GITHUB_PROXY" "INFO"
    }
    
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        $webClient.DownloadFile($downloadUrl, $Destination)
        Write-Log "$Description 下载完成" "SUCCESS"
        
        # 验证SHA256（如果提供）
        if ($ExpectedSHA256) {
            if (-not (VerifySHA256 -File $Destination -ExpectedSHA256 $ExpectedSHA256 -Description $Description)) {
                return $false
            }
        }
        return $true
    } catch {
        Write-Log "无法下载 $Description`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# SHA256校验函数
function VerifySHA256 {
    param(
        [string]$File,
        [string]$ExpectedSHA256,
        [string]$Description
    )

    Write-Log "验证 $Description 的SHA256校验和..." "INFO"
    
    try {
        $actualSHA256 = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToLower()
        $expectedLower = $ExpectedSHA256.ToLower()
        
        if ($actualSHA256 -eq $expectedLower) {
            Write-Log "SHA256校验通过" "SUCCESS"
            return $true
        } else {
            Write-Log "SHA256校验失败！" "ERROR"
            Write-Log "期望: $expectedLower" "ERROR"
            Write-Log "实际: $actualSHA256" "ERROR"
            Write-Log "文件可能已被篡改，删除下载的文件" "WARNING"
            Remove-Item -Path $File -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        Write-Log "SHA256校验时出错: $($_.Exception.Message)" "WARNING"
        return $true  # 即使校验失败也继续
    }
}

# 从API获取最新release信息
function Get-LatestRelease {
    Write-Log "获取最新release信息..." "INFO"
    
    # 构建API URL
    $apiUrl = $API_URL
    if ($GITHUB_PROXY -ne "") {
        $apiUrl = "$GITHUB_PROXY/" + $API_URL.Substring("https://".Length)
    }
    
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            "Accept" = "application/vnd.github.v3+json"
        }

        $apiResponse = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 10
        $jarAsset = $apiResponse.assets | Where-Object { $_.name -like "*.jar" } | Select-Object -First 1

        if (-not $jarAsset) {
            throw "未找到JAR文件"
        }

        $script:DOWNLOAD_URL = $jarAsset.browser_download_url
        $script:ASSET_NAME = $jarAsset.name
        $script:RELEASE_TAG = $apiResponse.tag_name
        
        # 尝试获取SHA256
        $sha256Asset = $apiResponse.assets | Where-Object { $_.name -like "*.jar.sha256" } | Select-Object -First 1
        if ($sha256Asset) {
            $script:SHA256_URL = $sha256Asset.browser_download_url
        }

        Write-Log "找到最新构建: $ASSET_NAME (版本: $RELEASE_TAG)" "SUCCESS"
        Add-Content -Path $LOG_FILE -Value "下载URL: $DOWNLOAD_URL"
    } catch {
        Write-Log "API请求失败: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

# 检查版本是否需要更新
function Test-NeedUpdate {
    if ($ForceUpdate) {
        Write-Log "强制更新模式，将重新下载" "INFO"
        return $true
    }

    if (-not (Test-Path $VERSION_FILE)) {
        Write-Log "未找到版本信息，将下载最新版本" "INFO"
        return $true
    }

    $currentVersion = Get-Content $VERSION_FILE -ErrorAction SilentlyContinue
    
    if ($currentVersion -eq $RELEASE_TAG) {
        Write-Log "本地版本 ($currentVersion) 已是最新版本" "SUCCESS"
        return $false
    } else {
        Write-Log "发现新版本: $RELEASE_TAG (当前: $currentVersion)" "INFO"
        return $true
    }
}

# 下载SHA256校验和
function Get-SHA256File {
    if (-not $SHA256_URL) {
        Write-Log "Release中未提供SHA256文件，跳过校验" "WARNING"
        return $false
    }

    $sha256File = "$DOWNLOAD_DIR\NyxBot.jar.sha256"
    
    if (DownloadFile -Url $SHA256_URL -Destination $sha256File -Description "SHA256校验文件") {
        # 读取SHA256值
        $content = Get-Content $sha256File
        $script:EXPECTED_SHA256 = ($content -split '\s+')[0]
        Write-Log "获取到SHA256: $EXPECTED_SHA256" "INFO"
        return $true
    } else {
        Write-Log "无法下载SHA256文件，将跳过校验" "WARNING"
        return $false
    }
}

# 主流程
function Main {
    CheckAndInstallJRE21
    
    # 测试网络和选择代理
    Test-GitHubProxy
    
    Get-LatestRelease
    
    # 检查是否需要更新
    if ((Test-Path $NYXBOT_JAR) -and -not (Test-NeedUpdate)) {
        Write-Log "使用现有版本，直接启动..." "INFO"
    } else {
        # 下载SHA256（如果存在）
        $script:EXPECTED_SHA256 = ""
        Get-SHA256File | Out-Null
        
        # 备份旧版本（如果存在）
        if (Test-Path $NYXBOT_JAR) {
            $backupFile = "$NYXBOT_JAR.bak"
            Write-Log "备份旧版本到 $backupFile" "INFO"
            Move-Item -Path $NYXBOT_JAR -Destination $backupFile -Force
        }
        
        # 下载NyxBot.jar
        if (-not (DownloadFile -Url $DOWNLOAD_URL -Destination $NYXBOT_JAR -Description "NyxBot.jar" -ExpectedSHA256 $EXPECTED_SHA256)) {
            Write-Log "下载失败" "ERROR"
            
            # 如果有备份，恢复备份
            if (Test-Path "$NYXBOT_JAR.bak") {
                Write-Log "恢复备份版本..." "INFO"
                Move-Item -Path "$NYXBOT_JAR.bak" -Destination $NYXBOT_JAR -Force
            }
            exit 1
        }
        
        # 验证JAR文件完整性（简单检查文件大小）
        $jarInfo = Get-Item $NYXBOT_JAR
        if ($jarInfo.Length -lt 1KB) {
            Write-Log "下载的文件太小，可能不是有效的JAR文件" "ERROR"
            Remove-Item -Path $NYXBOT_JAR -Force
            
            # 恢复备份
            if (Test-Path "$NYXBOT_JAR.bak") {
                Write-Log "恢复备份版本..." "INFO"
                Move-Item -Path "$NYXBOT_JAR.bak" -Destination $NYXBOT_JAR -Force
            }
            exit 1
        }
        
        # 保存版本信息
        Set-Content -Path $VERSION_FILE -Value $RELEASE_TAG
        Write-Log "版本信息已保存: $RELEASE_TAG" "SUCCESS"
        
        # 删除备份
        if (Test-Path "$NYXBOT_JAR.bak") {
            Remove-Item -Path "$NYXBOT_JAR.bak" -Force
        }
    }
    
    # 启动程序
    Write-Log "启动 NyxBot..." "INFO"
    try {
        java -jar $NYXBOT_JAR
    } catch {
        Write-Log "启动失败: $($_.Exception.Message)" "ERROR"

        # 尝试重新检查Java环境
        Write-Log "重新检查Java环境..." "WARNING"
        try {
            $javaPath = (Get-Command java -ErrorAction Stop).Path
            Write-Log "Java路径: $javaPath" "INFO"
            $javaVersion = & java -version 2>&1
            Write-Log "Java版本: $($javaVersion[0])" "INFO"
        } catch {
            Write-Log "Java环境异常，可能需要重新安装" "ERROR"
        }

        exit 1
    }
    
    Write-Log "脚本执行完成" "SUCCESS"
}

# 执行主函数
Main