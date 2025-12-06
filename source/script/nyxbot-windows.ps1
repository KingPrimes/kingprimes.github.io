# nyxbot-windows.ps1
# ============================================================================ 
# NyxBot 安装脚本 (Windows)
# 版本: 3.0.0
# 要求: 需要JDK 21环境以运行新版NyxBot程序
# ============================================================================

# 设置UTF-8编码支持
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# 设置变量
$SCRIPT_VERSION = "3.0.0"
$API_URL = "https://api.github.com/repos/KingPrimes/NyxBot/releases/latest"
$DOWNLOAD_DIR = "$PSScriptRoot\nyxbot_data"
$NYXBOT_JAR = "$DOWNLOAD_DIR\NyxBot.jar"
$VERSION_FILE = "$DOWNLOAD_DIR\.version"
$LOG_FILE = "$DOWNLOAD_DIR\install.log"
$CONFIG_FILE = "$DOWNLOAD_DIR\config.ini"
$TASK_NAME = "NyxBotTask"
$ORACLE_JDK_URL = "https://download.oracle.com/java/21/latest/jdk-21_windows-x64_bin.zip"
$ORACLE_JDK_DIR = "$env:ProgramFiles\Oracle\jdk-21"

# 配置文件默认值
$DEFAULT_PORT = "8080"
$DEFAULT_PROXY_USERNAME = ""
$DEFAULT_PROXY_PASSWORD = ""
$DEFAULT_DEBUG = "false"
$DEFAULT_WS_MODE = "server"
$DEFAULT_WS_SERVER_ENABLE = "true"
$DEFAULT_WS_SERVER_URL = "/ws/shiro"
$DEFAULT_WS_CLIENT_ENABLE = "false"
$DEFAULT_WS_CLIENT_URL = "ws://localhost:3001"
$DEFAULT_SHIRO_TOKEN = ""

# 全局变量
$FORCE_UPDATE = $false
$SKIP_JAVA_INSTALL = $false
$GITHUB_PROXY = ""
$PROXY_NUM = ""

# 创建下载目录
if (-not (Test-Path $DOWNLOAD_DIR)) {
    New-Item -ItemType Directory -Path $DOWNLOAD_DIR -Force | Out-Null
}

# 初始化日志文件
"=== NyxBot安装日志 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content $LOG_FILE

function LogInfo {
    param($message)
    Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline
    Write-Host $message
    "[INFO] $message" | Add-Content $LOG_FILE
}

function LogSuccess {
    param($message)
    Write-Host "[SUCCESS] " -ForegroundColor Green -NoNewline
    Write-Host $message
    "[SUCCESS] $message" | Add-Content $LOG_FILE
}

function LogWarning {
    param($message)
    Write-Host "[WARNING] " -ForegroundColor Yellow -NoNewline
    Write-Host $message
    "[WARNING] $message" | Add-Content $LOG_FILE
}

function LogError {
    param($message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $message
    "[ERROR] $message" | Add-Content $LOG_FILE
}

# 显示帮助信息
function Show-Help {
    Write-Host @"
用法: .\nyxbot-windows.ps1 [选项]

选项:
 --force-update    强制更新，忽略已安装的版本
 --skip-java       跳过Java环境检查
 --proxy <number>  使用指定的代理镜像
 --version         显示脚本版本
 --help            显示此帮助信息

示例:
 .\nyxbot-windows.ps1          # 正常安装
 .\nyxbot-windows.ps1 --force-update  # 强制更新到最新版本
 .\nyxbot-windows.ps1 --skip-java     # 跳过Java检查
 .\nyxbot-windows.ps1 --proxy 0       # 使用代理直接连接
 .\nyxbot-windows.ps1 --proxy 1       # 使用第1个代理镜像
"@
}

# 解析命令行参数
function ParseArguments {
    param($Arguments)
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            "--force-update" {
                $script:FORCE_UPDATE = $true
            }
            "--skip-java" {
                $script:SKIP_JAVA_INSTALL = $true
            }
            "--proxy" {
                if ($i + 1 -lt $Arguments.Count) {
                    $script:PROXY_NUM = $Arguments[$i + 1]
                    $i++
                }
            }
            "--version" {
                Write-Host "NyxBot安装脚本版本: $SCRIPT_VERSION"
                exit 0
            }
            "--help" {
                Show-Help
                exit 0
            }
            default {
                if ($Arguments[$i] -notmatch "^-") {
                    continue
                }
                LogError "未知参数: $($Arguments[$i])"
                Show-Help
                exit 1
            }
        }
    }
}

# 读取配置文件
function Read-Config {
    param($Key, $Default)
    $Value = $Default
    if (Test-Path $CONFIG_FILE) {
        $content = Get-Content $CONFIG_FILE
        $matchingLine = $content | Where-Object { $_ -match "^$Key=" }
        if ($matchingLine) {
            $Value = ($matchingLine -split "=", 2)[1].Trim()
            if ([string]::IsNullOrWhiteSpace($Value)) {
                $Value = $Default
            }
        }
    }
    return $Value
}

# 写入配置文件
function Write-Config {
    param($Key, $Value)
    # 如果配置文件不存在，先创建
    if (-not (Test-Path $CONFIG_FILE)) {
        New-Item $CONFIG_FILE -Force | Out-Null
    }
    $content = Get-Content $CONFIG_FILE
    # 检查是否已存在该键
    $keyExists = $false
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match "^$Key=") {
            $content[$i] = "$Key=$Value"
            $keyExists = $true
            break
        }
    }
    # 如果不存在，添加新行
    if (-not $keyExists) {
        $content += "$Key=$Value"
    }
    # 写入文件
    $content | Set-Content $CONFIG_FILE -Encoding UTF8
}

# 初始化配置文件
function InitConfigFile {
    if (-not (Test-Path $CONFIG_FILE)) {
        # 创建默认配置
        Write-Config "PORT" $DEFAULT_PORT
        Write-Config "PROXY_URL" ""
        Write-Config "PROXY_PROTOCOL" ""
        Write-Config "PROXY_USERNAME" $DEFAULT_PROXY_USERNAME
        Write-Config "PROXY_PASSWORD" $DEFAULT_PROXY_PASSWORD
        Write-Config "DEBUG" $DEFAULT_DEBUG
        Write-Config "WS_MODE" $DEFAULT_WS_MODE
        Write-Config "WS_SERVER_ENABLE" $DEFAULT_WS_SERVER_ENABLE
        Write-Config "WS_SERVER_URL" $DEFAULT_WS_SERVER_URL
        Write-Config "WS_CLIENT_ENABLE" $DEFAULT_WS_CLIENT_ENABLE
        Write-Config "WS_CLIENT_URL" $DEFAULT_WS_CLIENT_URL
        Write-Config "SHIRO_TOKEN" $DEFAULT_SHIRO_TOKEN
        LogInfo "已创建默认配置文件"
    }
}

# 显示NyxBot当前配置
function Show-NyxBotConfig {
    LogInfo "NyxBot 当前配置："
    Write-Host "端口：" -ForegroundColor Yellow -NoNewline
    Write-Host $(Read-Config "PORT" $DEFAULT_PORT)
    Write-Host "Debug模式：" -ForegroundColor Yellow -NoNewline
    Write-Host $(Read-Config "DEBUG" $DEFAULT_DEBUG)
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host " OneBot 配置 " -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "通讯模式：" -ForegroundColor Yellow -NoNewline
    Write-Host $(Read-Config "WS_MODE" $DEFAULT_WS_MODE)
    Write-Host "服务器启用：" -ForegroundColor Yellow -NoNewline
    Write-Host $(Read-Config "WS_SERVER_ENABLE" $DEFAULT_WS_SERVER_ENABLE)
    Write-Host "服务器地址：" -ForegroundColor Yellow -NoNewline
    Write-Host $(Read-Config "WS_SERVER_URL" $DEFAULT_WS_SERVER_URL)
    Write-Host "客户端启用：" -ForegroundColor Yellow -NoNewline
    Write-Host $(Read-Config "WS_CLIENT_ENABLE" $DEFAULT_WS_CLIENT_ENABLE)
    Write-Host "客户端地址：" -ForegroundColor Yellow -NoNewline
    Write-Host $(Read-Config "WS_CLIENT_URL" $DEFAULT_WS_CLIENT_URL)
    $shiro_token = $(Read-Config "SHIRO_TOKEN" $DEFAULT_SHIRO_TOKEN)
    Write-Host "Shiro Token：" -ForegroundColor Yellow -NoNewline
    if ($DEFAULT_SHIRO_TOKEN -eq $shiro_token) {
        Write-Host "未设置"
    }
    else {
        Write-Host "****"
    }
    $proxy_url = $(Read-Config "PROXY_URL" "")
    if ([string]::IsNullOrWhiteSpace($proxy_url)) {
        $proxy_url = "无"
    }
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host " 代理设置 " -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "代理URL：" -ForegroundColor Yellow -NoNewline
    Write-Host $proxy_url
    if (-not ([string]::IsNullOrWhiteSpace($proxy_url)) -and $proxy_url -ne "无") {
        # 提取代理显示的主机和端口
        if ($proxy_url -match "^(http|socks|socks5)://([0-9a-zA-Z\.-]+):([0-9]+)$") {
            $proxy_host = $matches[2]
            $proxy_port = $matches[3]
            Write-Host "代理主机：" -ForegroundColor Yellow -NoNewline
            Write-Host $proxy_host
            Write-Host "代理端口：" -ForegroundColor Yellow -NoNewline
            Write-Host $proxy_port
        }
    }
    $proxy_user = $(Read-Config "PROXY_USERNAME" $DEFAULT_PROXY_USERNAME)
    Write-Host "代理用户名：" -ForegroundColor Yellow -NoNewline
    if ([string]::IsNullOrWhiteSpace($proxy_user)) {
        Write-Host "无"
    }
    else {
        Write-Host $proxy_user
    }
    Write-Host "代理密码：" -ForegroundColor Yellow -NoNewline
    if ([string]::IsNullOrWhiteSpace($proxy_user)) {
        Write-Host "无"
    }
    else {
        Write-Host "****"
    }
}

# 设置NyxBot配置项
function Set-NyxBotConfig {
    param($Key, $Prompt, $Default)
    $current_value = Read-Config $Key $Default
    $new_value = $current_value
    Write-Host $Prompt -ForegroundColor Cyan -NoNewline
    Write-Host " (当前: $current_value, 留空使用默认值): " -NoNewline
    $input = Read-Host
    if (-not [string]::IsNullOrWhiteSpace($input)) {
        $new_value = $input
    }
    Write-Config $Key $new_value
    LogSuccess "已更新 $Key 为: $new_value"
}
# ====== Java环境检测与安装 START ======

# 验证当前Java环境
function Test-JavaEnvironment { 
    try { 
        $javaVersionOutput = & java -version 2>&1
        $javaVersionText = $javaVersionOutput -join "`n"
        if ($javaVersionText -match 'version "21\.' -or $javaVersionText -match 'openjdk 21\.') { 
            LogSuccess "JRE 21已安装"
            $javaVersionText | Add-Content $LOG_FILE -ErrorAction SilentlyContinue
            return $true
        }
    }
    catch { 
        LogError "Java 未安装或不在 PATH 中"
    }
    return $false
}

# 创建临时目录
function New-TempInstallationDirectory { 
    param(
        [string]$Prefix = "java_install"
    )
    
    # 使用兼容的日期格式
    $tempDirTimestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $tempDir = Join-Path $env:TEMP "$Prefix_$tempDirTimestamp"
    
    try { 
        $null = New-Item -Path $tempDir -ItemType Directory -Force -ErrorAction Stop
        LogInfo "临时安装目录: $tempDir"
        return $tempDir
    }
    catch { 
        LogError "无法创建临时目录: $_"
        return $null
    }
}

# 使用底层.NET API下载Oracle JDK
function Download-OracleJDK { 
    param(
        [string]$Url,
        [string]$OutputFile
    )
    
    LogInfo "使用专用下载器获取 Oracle JDK..."
    try { 
        # 创建HTTP请求
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = "GET"
        $request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        $request.Accept = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
        $request.Timeout = 300000 # 5分钟超时
        $request.AllowAutoRedirect = $true
        $request.MaximumAutomaticRedirections = 5
        $request.KeepAlive = $true
        
        # 处理系统代理
        $proxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($proxy -and $proxy.GetProxy($Url).AbsoluteUri -ne $Url) { 
            $request.Proxy = $proxy
            $request.Proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
            LogInfo "使用系统代理: $($proxy.GetProxy($Url).AbsoluteUri)"
        }
        
        # 手动设置Accept-Encoding以避免压缩问题
        $request.Headers.Add("Accept-Encoding", "identity")
        
        # 获取响应
        $response = $request.GetResponse()
        $contentLength = $response.ContentLength
        
        # 准备流
        $responseStream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($OutputFile)
        
        # 缓冲区设置
        $bufferSize = 64KB
        $buffer = New-Object byte[] $bufferSize
        $totalRead = 0
        $lastPercent = -1
        
        LogInfo "开始下载 Oracle JDK (大小: $([math]::Round($contentLength/1MB, 2)) MB)..."
        
        # 读取并写入文件
        do { 
            $bytesRead = $responseStream.Read($buffer, 0, $bufferSize)
            if ($bytesRead -gt 0) { 
                $fileStream.Write($buffer, 0, $bytesRead)
                $totalRead += $bytesRead
                
                # 每10%显示一次进度
                if ($contentLength -gt 0) { 
                    $percentComplete = [math]::Floor(($totalRead / $contentLength) * 100)
                    if ($percentComplete -ge ($lastPercent + 10) -or $percentComplete -eq 100) { 
                        LogInfo "下载进度: $percentComplete%"
                        $lastPercent = $percentComplete - ($percentComplete % 10)
                    }
                }
            }
        } while ($bytesRead -gt 0)
        
        # 清理资源
        $fileStream.Close()
        $responseStream.Close()
        $response.Close()
        
        # 验证下载
        $downloadedSize = (Get-Item $OutputFile).Length
        if ($downloadedSize -lt 150MB) { 
            throw "下载文件太小，可能不完整 (实际: $([math]::Round($downloadedSize/1MB,2)) MB, 期望: >150MB)"
        }
        
        LogSuccess "Oracle JDK 下载成功! (大小: $([math]::Round($downloadedSize/1MB,2)) MB)"
        return $true
    }
    catch { 
        LogError "Oracle JDK 专用下载器失败: $($_.Exception.Message)"
        # 清理可能的不完整文件
        if (Test-Path $OutputFile) { 
            Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
    finally { 
        if ($fileStream) { $fileStream.Dispose() }
        if ($responseStream) { $responseStream.Dispose() }
        if ($response) { $response.Dispose() }
    }
}
# 解压ZIP文件
function Expand-ZipFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($FilePath, $DestinationPath)
        return $true
    }
    catch {
        LogError "解压文件失败: $($_.Exception.Message)"
        return $false
    }
}

# 安装Oracle JDK
function Install-OracleJDK {
    param(
        [string]$zipFilePath
    )
    
    LogInfo "开始安装 Oracle JDK 21..."
    
    # 创建安装目录
    $installDir = Split-Path $ORACLE_JDK_DIR -Parent
    if (-not (Test-Path $installDir)) {
        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
        LogInfo "创建安装目录: $installDir"
    }
    
    # 临时解压目录
    $tempExtractDir = New-TempInstallationDirectory -Prefix "jdk_extract"
    if (-not $tempExtractDir) {
        return $false
    }
    
    try {
        # 解压ZIP文件
        LogInfo "解压 JDK 文件到临时目录..."
        if (-not (Expand-ZipFile -FilePath $zipFilePath -DestinationPath $tempExtractDir)) {
            return $false
        }
        
        # 获取解压后的JDK目录（通常是 jdk-21.x.x）
        $extractedJdkDir = Get-ChildItem $tempExtractDir -Directory | Select-Object -First 1
        if (-not $extractedJdkDir) {
            throw "未找到解压后的JDK目录"
        }
        
        LogInfo "找到JDK目录: $($extractedJdkDir.FullName)"
        
        # 复制到最终位置
        LogInfo "将JDK复制到安装目录: $ORACLE_JDK_DIR"
        if (Test-Path $ORACLE_JDK_DIR) {
            Remove-Item $ORACLE_JDK_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Move-Item $extractedJdkDir.FullName $ORACLE_JDK_DIR -Force
        
        # 验证安装
        $javaExe = "$ORACLE_JDK_DIR\bin\java.exe"
        if (-not (Test-Path $javaExe)) {
            throw "未找到 java.exe，安装可能失败"
        }
        
        LogSuccess "Oracle JDK 21 安装成功! (路径: $ORACLE_JDK_DIR)"
        return $true
    }
    finally {
        # 清理临时目录
        if (Test-Path $tempExtractDir) {
            Remove-Item $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# 配置Java环境变量
function Set-JavaEnvironmentVariables {
    try {
        # 设置 JAVA_HOME
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $ORACLE_JDK_DIR, "Machine")
        $env:JAVA_HOME = $ORACLE_JDK_DIR
        
        # 更新 PATH
        $binPath = "$ORACLE_JDK_DIR\bin"
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        
        if ($currentPath -notlike "*$binPath*") {
            $newPath = "$binPath;$currentPath"
            [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
            $env:Path = "$binPath;" + $env:Path
        }
        
        LogInfo "设置系统环境变量 JAVA_HOME=$ORACLE_JDK_DIR"
        LogInfo "更新系统 PATH 包含: $binPath"
        
        return $true
    }
    catch {
        LogError "设置环境变量失败: $($_.Exception.Message)"
        return $false
    }
}



# 验证Java安装
function Test-JavaInstallation {
    param(
        [int]$maxRetries = 12
    )
    
    $retryCount = 0
    $javaVerified = $false
    $javaExe = "$ORACLE_JDK_DIR\bin\java.exe"
    
    # 先检查文件是否存在
    if (-not (Test-Path $javaExe)) {
        LogError "Java 可执行文件不存在: $javaExe"
        return $false
    }
    
    while (-not $javaVerified -and $retryCount -lt $maxRetries) {
        $retryCount++
        try {
            Start-Sleep -Seconds 2
            
            # 清除错误变量
            $Error.Clear()
            $javaVersion = & $javaExe -version 2>&1
            $javaVersionText = $javaVersion -join "`n"
            
            if ($LASTEXITCODE -eq 0 -and (
                    $javaVersionText -match 'version "21\.' -or 
                    $javaVersionText -match 'openjdk version "21' -or 
                    $javaVersionText -match 'openjdk 21\.?'
                )) {
                $javaVerified = $true
                LogSuccess "JRE 21 验证成功!"
                $javaVersionText | ForEach-Object { LogInfo $_ }
                $javaVersionText | Add-Content $LOG_FILE -ErrorAction SilentlyContinue
                break
            }
            else {
                LogWarning "验证尝试 $($retryCount)/$($maxRetries): 无效的 Java 版本或命令失败"
                if ($javaVersionText) {
                    LogInfo "版本输出: $($javaVersionText -split "`n")[0]"
                }
            }
        }
        catch {
            LogWarning "验证尝试 $($retryCount)/$($maxRetries): $($_.Exception.Message)"
        }
    }
    
    return $javaVerified
}

# 检查并安装 Java 环境
function CheckJavaEnvironment {
    # 1. 检查是否已安装合适的Java
    if (Test-JavaEnvironment) {
        return $true
    }
    
    LogInfo "未检测到合适的Java 21环境，开始安装Oracle JDK 21..."
    
    # 2. 创建临时目录
    $tempDir = New-TempInstallationDirectory -Prefix "oracle_jdk"
    if (-not $tempDir) {
        return $false
    }
    
    try {
        # 3. 下载JDK ZIP包
        $zipFilePath = Join-Path $tempDir "jdk-21_windows-x64_bin.zip"
        LogInfo "下载路径: $zipFilePath"
        
        $downloadSuccess = Download-OracleJDK -Url $ORACLE_JDK_URL -OutputFile $zipFilePath
        if (-not $downloadSuccess) {
            return $false
        }
        
        # 4. 安装JDK
        $installSuccess = Install-OracleJDK -zipFilePath $zipFilePath
        if (-not $installSuccess) {
            return $false
        }
        
        # 5. 配置环境变量
        $envSuccess = Set-JavaEnvironmentVariables
        if (-not $envSuccess) {
            LogWarning "环境变量设置失败，可能需要手动配置"
        }
        
        # 6. 验证安装
        $isVerified = Test-JavaInstallation
        if (-not $isVerified) {
            LogWarning "Java安装验证失败，但安装可能成功。可能需要重启会话"
        }
        
        if ($isVerified) {
            LogSuccess "Oracle JDK 21 安装和配置完成!"
            return $true
        }
        else {
            LogWarning "Java 21 已安装，但验证失败。请重启系统或重新登录后重试。"
            return $true # 安装成功，只是验证失败
        }
    }
    finally {
        # 7. 清理
        try {
            if (Test-Path $tempDir) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
        }
    }
}

# ====== Java环境检测与安装 END ======



function Test-Network {
    # 创建统一的测试目标数组，包含直连和所有代理
    $test_targets = @(
        @{ Name = "直连"; Url = $null; IsDirect = $true },  # 直连特殊处理
        @{ Name = "ghproxy.vip"; Url = "https://ghproxy.vip"; IsDirect = $false },
        @{ Name = "gh-proxy.org"; Url = "https://gh-proxy.org"; IsDirect = $false },
        @{ Name = "edgeone.gh-proxy.org"; Url = "https://edgeone.gh-proxy.org"; IsDirect = $false },
        @{ Name = "ghfast.top"; Url = "https://ghfast.top"; IsDirect = $false },
        @{ Name = "git.yylx.win"; Url = "https://git.yylx.win"; IsDirect = $false },
        @{ Name = "gh-proxy.com"; Url = "https://gh-proxy.com"; IsDirect = $false },
        @{ Name = "ghfile.geekertao.top"; Url = "https://ghfile.geekertao.top"; IsDirect = $false },
        @{ Name = "gh-proxy.net"; Url = "https://gh-proxy.net"; IsDirect = $false },
        @{ Name = "j.1win.ggff.net"; Url = "https://j.1win.ggff.net"; IsDirect = $false },
        @{ Name = "ghm.078465.xyz"; Url = "https://ghm.078465.xyz"; IsDirect = $false },
        @{ Name = "gh.xxooo.cf"; Url = "https://gh.xxooo.cf"; IsDirect = $false },
        @{ Name = "gh.5050net.cn"; Url = "https://gh.5050net.cn"; IsDirect = $false },
        @{ Name = "github.chenc.dev"; Url = "https://github.chenc.dev"; IsDirect = $false },
        @{ Name = "gitproxy.127731.xyz"; Url = "https://gitproxy.127731.xyz"; IsDirect = $false }
    )
    
    $check_url = "https://raw.githubusercontent.com/KingPrimes/DataSource/refs/heads/main/warframe/state_translation.json"
    $timeout = 10  # 测试使用10秒超时
    $maxBytes = 1048576  # 1MB
    $bufferSize = 8192  # 8KB缓冲区
    
    LogInfo "开始测试网络..."
    LogInfo "自动选择最快镜像，这可能需要一些时间(测试数据量: $([math]::Round($maxBytes/1024/1024, 0))MB)..."
    
    # 创建测试脚本块
    $scriptBlock = {
        param($target, $check_url, $timeout, $maxBytes, $bufferSize)
        
        $target_name = $target.Name
        try {
            # 构建正确的测试URL
            $test_url = if ($target.IsDirect) {
                $check_url  # 直连使用原始URL
            }
            else {
                $proxy_url = $target.Url.TrimEnd('/')
                # 根据代理类型构建正确的URL
                if ($proxy_url -match "j\.1win\.ggff\.net|gitproxy\.127731\.xyz|jiashu\.127731\.xyz") {
                    "${proxy_url}/?url=${check_url}"
                }
                elseif ($proxy_url -match "gh-proxy\.com|gh-proxy\.net|ghfile\.geekertao\.top|ghproxy\.vip|gh-proxy\.org") {
                    "${proxy_url}/${check_url}"
                }
                else {
                    "${proxy_url}/${check_url}"
                }
            }
            
            # 创建Web客户端
            $client = New-Object System.Net.WebClient
            $client.Headers.Add("User-Agent", "Mozilla/5.0")
            
            # 开始计时
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # 打开流并开始读取
            $stream = $client.OpenRead($test_url)
            $totalBytesRead = 0
            $buffer = New-Object byte[] $bufferSize
            
            # 读取数据直到达到最大字节数或超时
            while ($totalBytesRead -lt $maxBytes) {
                $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -le 0 -or $stopwatch.Elapsed.TotalSeconds -ge $timeout) {
                    break
                }
                $totalBytesRead += $bytesRead
            }
            
            # 计算速度
            $stopwatch.Stop()
            $elapsedTime = $stopwatch.Elapsed.TotalSeconds
            $downloadSpeed = if ($elapsedTime -gt 0) { $totalBytesRead / $elapsedTime } else { 0 }
            
            # 返回结果
            [PSCustomObject]@{
                TargetName = $target_name
                Speed      = $downloadSpeed
                BytesRead  = $totalBytesRead
                Time       = $elapsedTime
                Success    = $true
            }
        }
        catch {
            [PSCustomObject]@{
                TargetName = $target_name
                Speed      = 0
                BytesRead  = 0
                Time       = $timeout
                Success    = $false
                Error      = $_.Exception.Message
            }
        }
        finally {
            if ($null -ne $stream) { 
                try { $stream.Close() } catch {}
            }
            if ($null -ne $client) { 
                try { $client.Dispose() } catch {}
            }
        }
    }
    
    # 设置最大并行度为6
    $maxParallelJobs = 6
    $jobs = @()
    $results = @()
    
    # 启动作业
    foreach ($target in $test_targets) {
        # 等待直到有空闲的作业槽
        while ((Get-Job -State Running).Count -ge $maxParallelJobs) {
            Start-Sleep -Milliseconds 200
        }
        
        $job = Start-Job -ScriptBlock $scriptBlock -ArgumentList $target, $check_url, $timeout, $maxBytes, $bufferSize
        $jobs += $job
        LogInfo "已启动测试任务: $($target.Name)"
    }
    
    # 等待所有作业完成，并收集结果
    $completedCount = 0
    $totalCount = $jobs.Count
    
    while ($completedCount -lt $totalCount) {
        $completedJobs = Get-Job | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' }
        
        foreach ($job in $completedJobs) {
            $result = Receive-Job $job
            $results += $result
            
            if ($result.Success) {
                $formattedSpeed = if ($result.Speed -gt 0) { Format-Speed $result.Speed } else { "0 B/s" }
                $actualMB = [math]::Round($result.BytesRead / 1024 / 1024, 2)
                $targetMB = [math]::Round($maxBytes / 1024 / 1024, 2)
                LogInfo "完成测试 [$($completedCount+1)/$totalCount]: $($result.TargetName) - $formattedSpeed (实际下载: ${actualMB}MB / 目标: ${targetMB}MB)"
            }
            else {
                LogInfo "完成测试 [$($completedCount+1)/$totalCount]: $($result.TargetName) - 失败: $($result.Error)"
            }
            
            Remove-Job $job
            $completedCount++
        }
        
        Start-Sleep -Milliseconds 500
    }
    
    # 处理结果
    $bestResult = $null
    $bestSpeed = 0
    
    foreach ($result in $results) {
        if ($result.Success -and $result.Speed -gt $bestSpeed) {
            $bestSpeed = $result.Speed
            $bestResult = $result
        }
    }
    
    # 根据测试结果设置最终使用的代理
    if ($bestSpeed -gt 0 -and $null -ne $bestResult) {
        $bestTarget = $test_targets | Where-Object { $_.Name -eq $bestResult.TargetName } | Select-Object -First 1
        
        if ($bestTarget.IsDirect) {
            $script:GITHUB_PROXY = ""
            $formattedBestSpeed = Format-Speed $bestSpeed
            LogInfo "测试完成, 直连速度最快 (速度: $formattedBestSpeed), 将使用直连"
        }
        else {
            $script:GITHUB_PROXY = $bestTarget.Url
            $formattedBestSpeed = Format-Speed $bestSpeed
            LogInfo "测试完成, 将使用最快的代理: $($bestTarget.Name) (速度: $formattedBestSpeed)"
        }
    }
    else {
        LogWarning "测试: 无法找到可用的连接方式。"
        $script:GITHUB_PROXY = ""
    }
}

# 格式化速度显示
function Format-Speed {
    param($SpeedBps)
    if ($SpeedBps -gt 1048576) {
        $speed_mbs = [math]::Round($SpeedBps / 1048576, 2)
        return "${speed_mbs} MB/s"
    }
    elseif ($SpeedBps -gt 1024) {
        $speed_kbs = [math]::Round($SpeedBps / 1024, 2)
        return "${speed_kbs} KB/s"
    }
    else {
        return "${SpeedBps} B/s"
    }
}

# 获取最新release信息
function Get-LatestRelease {
    LogInfo "获取最新release信息..."
    $api_url = $API_URL
    if (-not [string]::IsNullOrWhiteSpace($GITHUB_PROXY)) {
        $api_url = "$GITHUB_PROXY/$($API_URL.Substring(8))"
        LogInfo "使用代理: $GITHUB_PROXY"
    }
    try {
        $ProgressPreference = 'SilentlyContinue'
        $headers = @{
            "User-Agent" = "Mozilla/5.0"
            "Accept"     = "application/vnd.github.v3+json"
        }
        $apiResponse = Invoke-RestMethod -Uri $api_url -Headers $headers -TimeoutSec 10
        $ProgressPreference = 'Continue'
        # 获取JAR文件信息
        $jarAsset = $apiResponse.assets | Where-Object { $_.name.EndsWith(".jar") } | Select-Object -First 1
        if (-not $jarAsset) {
            throw "未找到JAR文件"
        }
        # 获取发布说明
        $releaseNotes = $apiResponse.body
        $script:DOWNLOAD_URL = $jarAsset.browser_download_url
        $script:ASSET_NAME = $jarAsset.name
        $script:RELEASE_TAG = $apiResponse.tag_name
        $script:EXPECTED_SHA256 = $jarAsset.digest
        # 去除sha256:前缀如果存在
        if (-not [string]::IsNullOrWhiteSpace($EXPECTED_SHA256) -and $EXPECTED_SHA256.StartsWith("sha256:")) {
            $script:EXPECTED_SHA256 = $EXPECTED_SHA256.Substring(7)
        }
        $script:RELEASE_NOTES = $releaseNotes
        LogSuccess "找到最新版本: $ASSET_NAME (版本: $RELEASE_TAG)"
        "下载URL: $DOWNLOAD_URL" | Add-Content $LOG_FILE
        # 显示发布说明
        if (-not [string]::IsNullOrWhiteSpace($RELEASE_NOTES)) {
            LogInfo "更新说明:"
            Write-Host $RELEASE_NOTES -ForegroundColor Yellow
        }
        return $true
    }
    catch {
        LogError "无法获取最新release信息: $($_.Exception.Message)"
        $_.Exception.Message | Add-Content $LOG_FILE
        return $false
    }
}

# 检查已安装版本
function CheckVersion {
    if ($FORCE_UPDATE) {
        LogInfo "强制更新模式开启，将忽略已安装版本"
        return $false # 需要更新
    }
    if (-not (Test-Path $VERSION_FILE)) {
        LogInfo "未找到版本信息，将安装最新版本"
        return $false # 需要更新
    }
    $current_version = Get-Content $VERSION_FILE -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($current_version)) {
        $current_version = "unknown"
    }
    if ($current_version -eq $RELEASE_TAG) {
        LogSuccess "已安装版本 ($current_version) 与最新版本相同"
        return $true # 不需要更新
    }
    else {
        LogInfo "检测到新版本: $RELEASE_TAG (当前: $current_version)"
        return $false # 需要更新
    }
}

# 下载文件并验证SHA256
function DownloadFile {
    param($Url, $Destination, $Description, $ExpectedSha256)
    LogInfo "下载 $Description..."
    $download_url = $Url
    if (-not [string]::IsNullOrWhiteSpace($GITHUB_PROXY)) {
        $download_url = "$GITHUB_PROXY/$($Url.Substring(8))"
        LogInfo "使用代理: $GITHUB_PROXY"
    }
    try {
        $ProgressPreference = 'SilentlyContinue'
        # 创建临时文件
        $tempFile = "$Destination.tmp"
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0")
        $webClient.DownloadFile($download_url, $tempFile)
        $ProgressPreference = 'Continue'
        # 验证SHA256如果提供
        if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
            if (-not (VerifySha256 $tempFile $ExpectedSha256 $Description)) {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                return $false
            }
        }
        # 移动到目标位置
        if (Test-Path $Destination) {
            Remove-Item $Destination -Force
        }
        Move-Item $tempFile $Destination
        LogSuccess "$Description 下载完成"
        return $true
    }
    catch {
        LogError "无法下载 $($Description): $($_.Exception.Message)"
        $_.Exception.Message | Add-Content $LOG_FILE
        # 清理临时文件
        if (Test-Path "$Destination.tmp") {
            Remove-Item "$Destination.tmp" -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

# 验证文件SHA256
function VerifySha256 {
    param($File, $ExpectedSha256, $Description)
    LogInfo "验证 $Description 的SHA256校验和..."
    try {
        $actualSha256 = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToLower()
        if ($actualSha256 -eq $ExpectedSha256.ToLower()) {
            LogSuccess "SHA256校验通过"
            return $true
        }
        else {
            LogError "SHA256校验失败,"
            LogError "期望: $ExpectedSha256"
            LogError "实际: $actualSha256"
            LogWarning "文件可能已被篡改，删除已下载的文件"
            return $false
        }
    }
    catch {
        LogWarning "无法验证SHA256: $($_.Exception.Message)"
        return $true # 跳过验证
    }
}

# 创建并启动计划任务
function Install-NyxBotTask {
    param($JavaArgs)
    LogInfo "创建并启动 Windows 计划任务..."
    
    try {
        # 检查任务是否已存在
        $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        if ($task) {
            # 停止并删除现有任务
            Stop-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
            Start-Sleep -Seconds 2
        }
        
        # 准备Java命令
        $jarPath = Join-Path $DOWNLOAD_DIR "NyxBot.jar"
        
        # 创建任务操作 - 直接执行Java程序
        $action = New-ScheduledTaskAction -Execute "$env:JAVA_HOME\bin\java.exe" `
            -Argument "-jar `"$jarPath`"$JavaArgs" `
            -WorkingDirectory $DOWNLOAD_DIR
        
        # 创建触发器 - 系统启动时触发
        $trigger = New-ScheduledTaskTrigger -AtStartup
        
        # 创建设置 - 兼容不同Windows版本
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew `
            -Hidden `
            -ExecutionTimeLimit ([System.TimeSpan]::Zero)  # 确保任务永不因超时被终止
        
        # 注册任务 - 以系统权限运行
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName $TASK_NAME `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "NyxBot - 一个支持QQ机器人的框架" | Out-Null
        
        LogSuccess "计划任务创建成功"
        
        # 立即启动任务
        Start-ScheduledTask -TaskName $TASK_NAME
        
        # 增加重试机制检查任务状态
        $maxRetries = 5
        $retryCount = 0
        $taskRunning = $false
        
        while ($retryCount -lt $maxRetries -and -not $taskRunning) {
            Start-Sleep -Seconds 2
            
            try {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $TASK_NAME -ErrorAction Stop
                $taskState = $taskInfo.State
                
                if ($taskState -eq "Running") {
                    $taskRunning = $true
                    LogSuccess "NyxBot 计划任务已启动并正在运行"
                } else {
                    LogInfo "任务状态检查 $($retryCount+1)/($maxRetries): 状态为 '$taskState'"
                }
            }
            catch {
                LogInfo "任务状态检查 $($retryCount+1)/($maxRetries): 无法获取任务信息 ($_)"
            }
            
            $retryCount++
        }
        
        if (-not $taskRunning) {
            # 尝试另一种检查方式 - 查看进程
            $javaProcess = Get-Process -Name "java" -ErrorAction SilentlyContinue | 
                Where-Object { $_.Path -like "*java.exe" -and $_.CommandLine -like "*$jarPath*" } | 
                Select-Object -First 1
            
            if ($javaProcess) {
                LogSuccess "检测到NyxBot Java进程正在运行 (PID: $($javaProcess.Id))"
                return $true
            } else {
                LogWarning "无法确认计划任务是否正常运行，但任务已创建成功。您可以通过任务计划程序查看任务状态。"
                return $true
            }
        }
        
        return $taskRunning
    }
    catch {
        LogError "创建计划任务失败: $($_.Exception.Message)"
        return $false
    }
}

# 启动NyxBot服务
function Start-NyxBotService {
    try {
        # 获取配置
        $port = Read-Config "PORT" $DEFAULT_PORT
        $debug = Read-Config "DEBUG" $DEFAULT_DEBUG
        $wsServerEnable = Read-Config "WS_SERVER_ENABLE" $DEFAULT_WS_SERVER_ENABLE
        $wsServerUrl = Read-Config "WS_SERVER_URL" $DEFAULT_WS_SERVER_URL
        $wsClientEnable = Read-Config "WS_CLIENT_ENABLE" $DEFAULT_WS_CLIENT_ENABLE
        $wsClientUrl = Read-Config "WS_CLIENT_URL" $DEFAULT_WS_CLIENT_URL
        $shiroToken = Read-Config "SHIRO_TOKEN" $DEFAULT_SHIRO_TOKEN
        $proxyUrl = Read-Config "PROXY_URL" ""
        $proxyProtocol = Read-Config "PROXY_PROTOCOL" ""
        $proxyUser = Read-Config "PROXY_USERNAME" $DEFAULT_PROXY_USERNAME
        $proxyPassword = Read-Config "PROXY_PASSWORD" $DEFAULT_PROXY_PASSWORD
        
        # 构建Java参数
        $javaArgs = ""
        
        # 添加Debug参数
        if ($debug -eq "true") {
            $javaArgs += " -debug"
        }
        
        # 添加端口参数
        $javaArgs += " -serverPort=$port"
        
        # 添加OneBot配置
        if ($wsServerEnable -eq "true") {
            $javaArgs += " -wsServerEnable"
        }
        $javaArgs += " -wsServerUrl=$wsServerUrl"
        if ($wsClientEnable -eq "true") {
            $javaArgs += " -wsClientEnable"
        }
        $javaArgs += " -wsClientUrl=$wsClientUrl"
        $javaArgs += " -shiroToken=$shiroToken"
        
        # 添加代理设置
        if (-not [string]::IsNullOrWhiteSpace($proxyUrl) -and -not [string]::IsNullOrWhiteSpace($proxyProtocol)) {
            # 从URL提取主机和端口
            if ($proxyUrl -match "^(http|socks|socks5)://([0-9a-zA-Z\.-]+):([0-9]+)$") {
                $proxyHost = $matches[2]
                $proxyPort = $matches[3]
                
                # 根据代理协议设置参数
                switch ($proxyProtocol) {
                    "http" { $javaArgs += " -httpProxy=$($proxyProtocol)://$($proxyHost):$($proxyPort)" }
                    { $_ -in "socks", "socks5" } { $javaArgs += " -socksProxy=$($proxyProtocol)://$($proxyHost):$($proxyPort)" }
                }
                
                # 添加代理认证
                if (-not [string]::IsNullOrWhiteSpace($proxyUser) -and -not [string]::IsNullOrWhiteSpace($proxyPassword)) {
                    $javaArgs += " -proxyUser=$proxyUser"
                    $javaArgs += " -proxyPassword=$proxyPassword"
                }
            }
        }
        
        # 创建并启动计划任务
        Install-NyxBotTask $javaArgs
        return $true
    }
    catch {
        LogError "启动NyxBot失败: $($_.Exception.Message)"
        return $false
    }
}

# 停止NyxBot服务
function Stop-NyxBotService {
    try {
        $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        if ($task) {
            # 停止正在运行的任务实例
            Stop-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
            
            LogSuccess "NyxBot 任务已停止"
            return $true
        }
        else {
            LogWarning "NyxBot 任务不存在"
            return $false
        }
    }
    catch {
        LogError "停止任务失败: $($_.Exception.Message)"
        return $false
    }
}

# 重启NyxBot服务
function Restart-NyxBotService {
    Stop-NyxBotService
    Start-Sleep -Seconds 2
    Start-NyxBotService
}

# 获取NyxBot服务状态
function Get-ServiceStatus {
    try {
        $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
        if ($task) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TASK_NAME
            $lastRunTime = $taskInfo.LastRunTime
            $lastTaskResult = $taskInfo.LastTaskResult
            $state = $taskInfo.State
            
            if ($state -eq "Running") {
                LogSuccess "NyxBot 任务正在运行 (状态: $state)"
            }
            elseif ($state -eq "Ready") {
                LogInfo "NyxBot 任务已创建但未运行 (状态: $state)"
            }
            else {
                LogWarning "NyxBot 任务状态: $state"
            }
            
            if ($lastRunTime -ne [DateTime]::MinValue) {
                LogInfo "最后运行时间: $lastRunTime"
                if ($lastTaskResult -eq 0) {
                    LogInfo "最后运行结果: 成功"
                }
                else {
                    LogWarning "最后运行结果: 失败 (代码: $lastTaskResult)"
                }
            }
        }
        else {
            LogWarning "NyxBot 任务不存在"
        }
    }
    catch {
        LogError "获取任务状态失败: $($_.Exception.Message)"
    }
}

# 安装NyxBot
function Install-NyxBot {
    LogInfo "开始安装 NyxBot..."

    # 检查Java环境
    if (-not $SKIP_JAVA_INSTALL) {
        if (-not (CheckJavaEnvironment)) {
            $confirm = Read-Host "是否继续安装?(Y/N)"
            if ($confirm -notmatch "^[Yy]") {
                LogInfo "安装已取消"
                return $false
            }
        }
    }

    # 测试网络
    Test-Network
   
    # 获取最新版本
    if (-not (Get-LatestRelease)) {
        LogError "获取最新版本信息失败"
        return $false
    }
    # 检查是否已安装
    if (Test-Path $NYXBOT_JAR) {
        $current_version = Get-Content $VERSION_FILE -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($current_version)) {
            $current_version = "unknown"
        }
        LogWarning "NyxBot 已安装 (版本: $current_version)"
        $confirm = Read-Host "是否覆盖当前安装?(Y/N)"
        if ($confirm -notmatch "^[Yy]") {
            LogInfo "安装已取消"
            return $false
        }
    }
    # 备份旧版本
    if (Test-Path $NYXBOT_JAR) {
        $backup_file = "$NYXBOT_JAR.bak"
        LogInfo "备份旧版本到 $backup_file"
        Copy-Item $NYXBOT_JAR $backup_file -Force
    }
    # 下载NyxBot.jar
    if (-not (DownloadFile $DOWNLOAD_URL $NYXBOT_JAR "NyxBot.jar" $EXPECTED_SHA256)) {
        LogError "下载失败"
        # 恢复旧版本
        if (Test-Path "$NYXBOT_JAR.bak") {
            LogInfo "恢复备份版本..."
            Move-Item "$NYXBOT_JAR.bak" $NYXBOT_JAR -Force
        }
        return $false
    }
    # 保存版本信息
    $RELEASE_TAG | Set-Content $VERSION_FILE
    LogSuccess "NyxBot 安装成功 (版本: $RELEASE_TAG)"
    # 删除备份
    if (Test-Path "$NYXBOT_JAR.bak") {
        Remove-Item "$NYXBOT_JAR.bak" -Force
    }
    return $true
}

# 更新NyxBot
function Update-NyxBot {
    LogInfo "开始更新 NyxBot..."
    # 检查是否已安装
    if (-not (Test-Path $NYXBOT_JAR)) {
        LogWarning "NyxBot 未安装，将执行安装操作"
        return Install-NyxBot
    }

    # 测试网络
    Test-Network

    # 检查Java环境
    if (-not $SKIP_JAVA_INSTALL) {
        CheckJavaEnvironment | Out-Null
    }
    
    # 获取最新版本
    if (-not (Get-LatestRelease)) {
        LogError "获取最新版本信息失败"
        return $false
    }
    # 检查是否需要更新
    if (CheckVersion) {
        # 已是最新版本
        return $true
    }
    # 备份旧版本
    $backup_file = "$NYXBOT_JAR.bak"
    LogInfo "备份旧版本到 $backup_file"
    Copy-Item $NYXBOT_JAR $backup_file -Force
    # 下载NyxBot.jar
    if (-not (DownloadFile $DOWNLOAD_URL $NYXBOT_JAR "NyxBot.jar" $EXPECTED_SHA256)) {
        LogError "下载失败"
        # 恢复旧版本
        LogInfo "恢复备份版本..."
        Move-Item $backup_file $NYXBOT_JAR -Force
        return $false
    }
    # 保存版本信息
    $RELEASE_TAG | Set-Content $VERSION_FILE
    LogSuccess "NyxBot 更新成功 (版本: $RELEASE_TAG)"
    # 检查服务是否运行，如果运行则重启
    $service = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        LogInfo "重启 NyxBot 服务..."
        Restart-NyxBotService
    }
    # 删除备份
    Remove-Item $backup_file -Force
    return $true
}

# 配置 OneBot 通讯模式
function ConfigureOneBot {
    while ($true) {
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host " OneBot 通讯模式选择 " -ForegroundColor Cyan
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host "1. 服务器模式 (wsServerEnable=true)" -ForegroundColor Green
        Write-Host "2. 客户端模式 (wsClientEnable=true)" -ForegroundColor Green
        Write-Host "3. 保留当前设置" -ForegroundColor Green
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host "请选择 OneBot 通讯模式 (1-3): " -ForegroundColor Cyan -NoNewline
        $ws_choice = Read-Host
        switch ($ws_choice) {
            "1" {
                Write-Config "WS_MODE" "server"
                Write-Config "WS_SERVER_ENABLE" "true"
                Write-Config "WS_CLIENT_ENABLE" "false"
                Set-NyxBotConfig "WS_SERVER_URL" "设置服务器监听地址" $DEFAULT_WS_SERVER_URL
                break
            }
            "2" {
                Write-Config "WS_MODE" "client"
                Write-Config "WS_SERVER_ENABLE" "false"
                Write-Config "WS_CLIENT_ENABLE" "true"
                Set-NyxBotConfig "WS_CLIENT_URL" "设置服务端连接地址" $DEFAULT_WS_CLIENT_URL
                break
            }
            "3" {
                return
            }
            default {
                LogError "无效的选择，请输入 1-3 之间的数字"
                continue
            }
        }
        Set-NyxBotConfig "SHIRO_TOKEN" "设置OneBot协议连接的Token" $DEFAULT_SHIRO_TOKEN
        break
    }
}

# 配置NyxBot运行参数
function ConfigureNyxBot {
    LogInfo "配置 NyxBot 运行参数..."
    # 初始化配置文件
    InitConfigFile
    # 设置端口
    Set-NyxBotConfig "PORT" "设置程序监听端口" $DEFAULT_PORT
    # 设置 Debug 模式
    Write-Host "是否启用 Debug 模式?(y/N): " -ForegroundColor Cyan -NoNewline
    $use_debug = Read-Host
    if ($use_debug -match "^[Yy]") {
        Write-Config "DEBUG" "true"
    }
    else {
        Write-Config "DEBUG" "false"
    }
    # 配置 OneBot 通讯
    ConfigureOneBot
    # 设置代理
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host " 代理设置 " -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "是否需要使用代理?(y/N): " -ForegroundColor Cyan -NoNewline
    $use_proxy = Read-Host
    if ($use_proxy -match "^[Yy]") {
        Write-Host "请按如下格式输入代理URL：http://127.0.0.1:7890|socks://127.0.0.1:7890|socks5://127.0.0.1:7890" -ForegroundColor Yellow
        Write-Host "代理URL: " -ForegroundColor Cyan -NoNewline
        $proxy_url = Read-Host
        # 验证代理URL格式
        if ($proxy_url -match "^(http|socks|socks5)://[0-9a-zA-Z\.-]+:[0-9]+$") {
            $proxy_protocol = $matches[1]
            # 保存代理设置
            Write-Config "PROXY_URL" $proxy_url
            Write-Config "PROXY_PROTOCOL" $proxy_protocol
            Write-Host "是否需要代理认证?(y/N): " -ForegroundColor Cyan -NoNewline
            $use_auth = Read-Host
            if ($use_auth -match "^[Yy]") {
                Set-NyxBotConfig "PROXY_USERNAME" "设置代理用户名" ""
                Set-NyxBotConfig "PROXY_PASSWORD" "设置代理密码" ""
            }
            else {
                Write-Config "PROXY_USERNAME" ""
                Write-Config "PROXY_PASSWORD" ""
            }
        }
        else {
            LogError "代理URL格式不正确，将不使用代理"
            Write-Config "PROXY_URL" ""
            Write-Config "PROXY_PROTOCOL" ""
            Write-Config "PROXY_USERNAME" ""
            Write-Config "PROXY_PASSWORD" ""
        }
    }
    else {
        Write-Config "PROXY_URL" ""
        Write-Config "PROXY_PROTOCOL" ""
        Write-Config "PROXY_USERNAME" ""
        Write-Config "PROXY_PASSWORD" ""
    }
    LogSuccess "NyxBot 运行参数配置完成"
    Show-NyxBotConfig
}

# 显示NyxBot当前配置
function Show-RunMenu {
    while ($true) {
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host " NyxBot 运行选项 " -ForegroundColor Cyan
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host "1. 启动 NyxBot (使用当前配置)" -ForegroundColor Green
        Write-Host "2. 重新配置运行参数" -ForegroundColor Green
        Write-Host "3. 查看当前配置" -ForegroundColor Green
        Write-Host "4. 返回主菜单" -ForegroundColor Green
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host "请选择操作 (1-4): " -ForegroundColor Cyan -NoNewline
        $run_choice = Read-Host
        switch ($run_choice) {
            "1" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 启动 NyxBot " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                # 检查是否已安装
                if (-not (Test-Path $NYXBOT_JAR)) {
                    LogWarning "NyxBot 未安装，将执行安装"
                    if (-not (Install-NyxBot)) {
                        LogError "安装失败，无法启动"
                        return
                    }
                }
                # 检查计划任务状态
                $task = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
                if ($task) {
                    $taskInfo = Get-ScheduledTaskInfo -TaskName $TASK_NAME
                    $taskState = $taskInfo.State
    
                    if ($taskState -eq "Running") {
                        LogWarning "NyxBot 计划任务已经在运行"
                        $confirm = Read-Host "是否重启任务?(y/N)"
                        if ($confirm -match "^[Yy]") {
                            Restart-NyxBotService
                        }
                        else {
                            LogInfo "操作已取消"
                        }
                    }
                    else {
                        Start-NyxBotService
                    }
                }
                else {
                    Start-NyxBotService
                }
                break
            }
            "2" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 重新配置运行参数 " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                ConfigureNyxBot
                break
            }
            "3" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 当前配置信息 " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                Show-NyxBotConfig
                break
            }
            "4" {
                LogInfo "返回主菜单"
                return
            }
            default {
                LogError "无效的选择，请输入 1-4 之间的数字"
            }
        }
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host " 按回车继续... " -ForegroundColor Cyan -NoNewline
        Read-Host
    }
}

# 显示主菜单
function Show-MainMenu {
    while ($true) {
        Write-Host "`n===========================================" -ForegroundColor Cyan
        Write-Host " NyxBot 安装脚本 (v$SCRIPT_VERSION) " -ForegroundColor Cyan
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host "1. 安装 NyxBot" -ForegroundColor Green
        Write-Host "2. 更新 NyxBot" -ForegroundColor Green
        Write-Host "3. 运行 NyxBot (管理界面)" -ForegroundColor Green
        Write-Host "4. 重启 NyxBot" -ForegroundColor Green
        Write-Host "5. 停止 NyxBot" -ForegroundColor Green
        Write-Host "6. 查看服务状态" -ForegroundColor Green
        Write-Host "7. 退出" -ForegroundColor Green
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host "请选择操作 (1-7): " -ForegroundColor Cyan -NoNewline
        $choice = Read-Host
        switch ($choice) {
            "1" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 安装 NyxBot " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                Install-NyxBot
                break
            }
            "2" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 更新 NyxBot " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                Update-NyxBot
                break
            }
            "3" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 运行 NyxBot (控制台) " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                Show-RunMenu
                break
            }
            "4" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 重启 NyxBot " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                Restart-NyxBotService
                break
            }
            "5" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 停止 NyxBot " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                Stop-NyxBotService
                break
            }
            "6" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 查看服务状态 " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                Get-ServiceStatus
                break
            }
            "7" {
                Write-Host "===========================================" -ForegroundColor Cyan
                Write-Host " 退出程序 " -ForegroundColor Cyan
                Write-Host "===========================================" -ForegroundColor Cyan
                LogInfo "感谢使用 NyxBot 安装脚本"
                exit 0
            }
            default {
                LogError "无效的选择，请输入 1-7 之间的数字"
            }
        }
        Write-Host "===========================================" -ForegroundColor Cyan
        Write-Host " 按回车继续... " -ForegroundColor Cyan -NoNewline
        Read-Host
    }
}

# 开始日志
LogInfo "=== NyxBot安装脚本(Windows) v$SCRIPT_VERSION ==="

# 检查管理员权限
$currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    LogWarning "此脚本需要管理员权限才能安装服务和检查Java环境"
    $confirm = Read-Host "是否要以管理员身份重新运行此脚本?(Y/N)"
    if ($confirm -match "^[Yy]") {
        $arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($FORCE_UPDATE) {
            $arguments += " --force-update"
        }
        if ($SKIP_JAVA_INSTALL) {
            $arguments += " --skip-java"
        }
        if ($PROXY_NUM) {
            $arguments += " --proxy $PROXY_NUM"
        }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
        exit 0
    }
}

# 解析命令行参数
ParseArguments $args

# 显示主菜单
Show-MainMenu