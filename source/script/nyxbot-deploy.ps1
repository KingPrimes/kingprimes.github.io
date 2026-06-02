# nyxbot-deploy.ps1
# NyxBot One-Click Deploy Script (Windows)
# NyxBot 一键部署脚本

param(
    [switch]$Docker,
    [switch]$Local,
    [switch]$Quiet,
    [switch]$Help,
    [switch]$Text,
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

$ScriptVersion = "1.0.0"
$ApiUrl = "https://api.github.com/repos/KingPrimes/NyxBot/releases/latest"
$ImageName = "kingprimes/nyxbot"
if ($PSCommandPath) {
    $DownloadDir = Join-Path (Split-Path $PSCommandPath -Parent) "NyxBot"
} else {
    $DownloadDir = Join-Path $PWD "NyxBot"
}
$TaskName = "NyxBot"

$DockerMirrors = @("docker.1panel.live", "docker.m.daocloud.io", "hub.rat.dev")
$GithubProxy = ""
$DownloadUrl = ""
$ReleaseTag = ""
$ExpectedDigest = ""
$IsGui = $false

$Proxies = @(
    @{ Name = "Direct"; Url = $null }
    @{ Name = "ghfast.top"; Url = "https://ghfast.top" }
    @{ Name = "gh-proxy.com"; Url = "https://gh-proxy.com" }
    @{ Name = "gh-proxy.net"; Url = "https://gh-proxy.net" }
    @{ Name = "ghproxy.vip"; Url = "https://ghproxy.vip" }
    @{ Name = "gh-proxy.org"; Url = "https://gh-proxy.org" }
    @{ Name = "edgeone.gh-proxy.org"; Url = "https://edgeone.gh-proxy.org" }
    @{ Name = "ghm.078465.xyz"; Url = "https://ghm.078465.xyz" }
    @{ Name = "git.yylx.win"; Url = "https://git.yylx.win" }
)

# ============================================================================
# Helper functions
# ============================================================================
function Write-Step   {
    Write-Host "[>] " -NoNewline -ForegroundColor Cyan
    Write-Host $args[0]
}
function Write-Success {
    Write-Host "[+] " -NoNewline -ForegroundColor Green
    Write-Host $args[0]
}
function Write-Warn   {
    Write-Host "[!] " -NoNewline -ForegroundColor Yellow
    Write-Host $args[0]
}
function Write-Fail   {
    Write-Host "[-] " -NoNewline -ForegroundColor Red
    Write-Host $args[0]
    exit 1
}

function Format-Speed($Bps) {
    if ($Bps -gt 1048576) { return "$([math]::Round($Bps/1048576,1)) MB/s" }
    if ($Bps -gt 1024)    { return "$([math]::Round($Bps/1024,1)) KB/s" }
    return "$([math]::Round($Bps)) B/s"
}

function Show-Banner {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  NyxBot Deploy v$ScriptVersion" -ForegroundColor Green
    Write-Host "  NyxBot 一键部署脚本" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
}

# ============================================================================
# Environment detection
# ============================================================================
function Test-JavaInstalled {
    if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
        Write-Warn "Java: not installed / 未安装"
        return $false
    }
    # java -version writes to stderr, capture via .NET Process
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'java'
        $psi.Arguments = '-version'
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $v = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        if ($v -match 'version "(\d+)\.') {
            $major = [int]$Matches[1]
            if ($major -ge 21) {
                Write-Success "Java $major : installed / 已安装"
                return $true
            }
            Write-Warn "Java $major : need >= 21 / 需要 21 或更高"
            return $false
        }
        Write-Warn "Java: version unknown / 版本未知"
        return $false
    } catch {
        Write-Warn "Java: not installed / 未安装"
        return $false
    }
}

function Test-DockerInstalled {
    try {
        $v = docker --version 2>$null
        Write-Success "Docker: installed / 已安装 ($v)"
        return $true
    } catch { return $false }
}

function Test-System {
    $os = (Get-CimInstance Win32_OperatingSystem).Caption -replace 'Microsoft ', ''
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    Write-Success "System / 系统: Windows $os ($arch)"
}

function Test-NyxBotRunning {
    try {
        # Primary: HTTP check — most reliable, no permission issues
        $req = [System.Net.HttpWebRequest]::Create("http://localhost:$Port")
        $req.Timeout = 2000
        $req.UserAgent = "NyxBot-Deploy"
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch {
        try {
            # Fallback: WMI process check
            $proc = Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*NyxBot.jar*" }
            return ($null -ne $proc)
        } catch { return $false }
    }
}

function Stop-NyxBot {
    $stopped = $false
    try {
        # Primary: WMI to find and kill NyxBot java processes
        $procs = Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*NyxBot.jar*" }
        foreach ($p in $procs) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
            $stopped = $true
        }
    } catch { }
    # Fallback: kill any java process listening on NyxBot port
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Listen' -and $_.OwningProcess }
        foreach ($c in $conns) {
            Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
            $stopped = $true
        }
    } catch { }
    if ($stopped) { Start-Sleep -Milliseconds 500 }
    return $stopped
}

function Test-ScheduledTaskExists {
    try {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        schtasks /query /tn $TaskName 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Remove-NyxBotTask {
    try {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        schtasks /delete /tn $TaskName /f 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

# ============================================================================
# Network speed test (parallel)
# ============================================================================
function Test-Network {
    Write-Step "Network speed test / 网络测速 (parallel / 并行)..."
    $checkUrl = "https://raw.githubusercontent.com/KingPrimes/DataSource/main/warframe/state_translation.json"
    $jobs = @()

    foreach ($p in $Proxies) {
        $testUrl = if ($p.Url) { "$($p.Url)/$checkUrl" } else { $checkUrl }
        $name = $p.Name
        $job = Start-Job -Name $name -ScriptBlock {
            param($url, $label)
            try {
                $req = [System.Net.HttpWebRequest]::Create($url)
                $req.Timeout = 10000
                $req.UserAgent = "Mozilla/5.0"
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $resp = $req.GetResponse()
                $s = $resp.GetResponseStream()
                $buf = New-Object byte[] 65536
                $total = 0
                while ($total -lt 524288) {
                    $n = $s.Read($buf, 0, $buf.Length)
                    if ($n -le 0) { break }
                    $total += $n
                }
                $sw.Stop()
                $s.Close(); $resp.Close()
                $speed = if ($sw.Elapsed.TotalSeconds -gt 0) { $total / $sw.Elapsed.TotalSeconds } else { 0 }
                return @{ Name = $label; Speed = $speed; Success = $true }
            } catch {
                return @{ Name = $label; Speed = 0; Success = $false }
            }
        } -ArgumentList $testUrl, $name
        $jobs += $job
    }

    # Wait for all jobs with progress dots
    Write-Host "  Testing $($jobs.Count) proxies / 正在测试 $($jobs.Count) 个代理..." -NoNewline
    while ($jobs | Where-Object { $_.State -eq 'Running' }) {
        Write-Host "." -NoNewline
        Start-Sleep -Milliseconds 500
    }
    Write-Host ""
    $bestSpeed = 0
    $bestProxyName = ""

    foreach ($job in $jobs) {
        $result = $job | Receive-Job
        $color = if ($result.Success) { 'Green' } else { 'Red' }
        $label = if ($result.Success) { Format-Speed $result.Speed } else { "unreachable / 不可达" }
        Write-Host "  $($result.Name): $label" -ForegroundColor $color
        if ($result.Success -and $result.Speed -gt $bestSpeed) {
            $bestSpeed = $result.Speed
            $bestProxyName = ($Proxies | Where-Object { $_.Name -eq $result.Name }).Url
        }
        $job | Remove-Job
    }

    $script:GithubProxy = $bestProxyName
    if ($bestSpeed -gt 0) {
        $label = if ($bestProxyName) { $bestProxyName } else { "Direct / 直连" }
        Write-Success "Best / 最快: $label ($(Format-Speed $bestSpeed))"
    } else {
        Write-Warn "All unreachable / 全部不可达, trying direct / 尝试直连"
    }
}

# ============================================================================
# Version & download
# ============================================================================
function Get-Release {
    Write-Step "Get latest version / 获取最新版本..."
    try {
        $headers = @{ "User-Agent" = "Mozilla/5.0"; "Accept" = "application/vnd.github.v3+json" }
        $resp = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 10
        $jar = $resp.assets | Where-Object { $_.name -like "*.jar" } | Select-Object -First 1
        $script:DownloadUrl = $jar.browser_download_url
        $script:ReleaseTag = $resp.tag_name
        # Extract SHA256 digest if available (format: "sha256:...")
        if ($jar.digest -match 'sha256:([a-f0-9]{64})') {
            $script:ExpectedDigest = $Matches[1]
        }
        Write-Success "Version / 版本: $ReleaseTag"
    } catch {
        Write-Fail "Failed to fetch release / 获取失败: $_"
    }
}

function Download-Jar {
    $url = $DownloadUrl
    if ($GithubProxy) { $url = "$GithubProxy/$($url -replace '^https://', '')" }
    if (-not (Test-Path $DownloadDir)) {
        New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    }
    $dest = Join-Path $DownloadDir "NyxBot.jar"

    Write-Step "Downloading NyxBot $ReleaseTag / 正在下载..."

    # Probe: get total size via HEAD, files >10MB may use chunked download
    $useChunked = $false
    $totalSize = 0
    try {
        $headReq = [System.Net.HttpWebRequest]::Create($url)
        $headReq.Method = "HEAD"
        $headReq.UserAgent = "Mozilla/5.0"
        $headReq.Timeout = 10000
        $headResp = $headReq.GetResponse()
        $totalSize = $headResp.ContentLength
        $headResp.Close()
        $useChunked = ($totalSize -gt 10485760)
    } catch {
        $useChunked = $false
    }

    if ($useChunked) {
        Write-Host "  File size / 文件大小: $([math]::Round($totalSize/1MB, 1)) MB"
        $numChunks = 4
        $chunkSize = [math]::Ceiling($totalSize / $numChunks)

        $chunkDir = Join-Path $DownloadDir ".dl_chunks"
        if (-not (Test-Path $chunkDir)) {
            New-Item -ItemType Directory -Path $chunkDir -Force | Out-Null
        }

        # Download chunk 0 synchronously first as a real Range probe
        Write-Host "  Testing Range support with chunk 0 / 使用首个分块测试 Range 支持..."
        $start0 = 0
        $end0 = $chunkSize - 1
        $expected0 = $end0 - $start0 + 1
        $chunk0File = Join-Path $chunkDir "chunk_0"
        $chunk0Ok = $false
        try {
            $req = [System.Net.HttpWebRequest]::Create($url)
            $req.Method = "GET"
            $req.UserAgent = "Mozilla/5.0"
            $req.Timeout = 60000
            $req.AddRange($start0, $end0)
            $resp = $req.GetResponse()
            if ([int]$resp.StatusCode -eq 206 -and $resp.ContentLength -eq $expected0) {
                $stream = $resp.GetResponseStream()
                $fs = [System.IO.File]::Create($chunk0File)
                $buf = New-Object byte[] 262144
                $totalRead = 0
                while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                    $fs.Write($buf, 0, $n)
                    $totalRead += $n
                }
                $fs.Close()
                if ($totalRead -eq $expected0) {
                    $chunk0Ok = $true
                    Write-Success "  Range supported, downloading remaining chunks in parallel / Range 支持，并行下载剩余分块"
                }
            }
            $stream.Close(); $resp.Close()
        } catch { }

        if (-not $chunk0Ok) {
            Write-Warn "  Range not supported or chunk 0 failed, falling back to single-thread / Range 不支持，回退单线程"
            Remove-Item $chunkDir -Recurse -Force -ErrorAction SilentlyContinue
            $useChunked = $false
        } else {
            # Download remaining chunks sequentially (avoids proxy concurrency limits)
            $allOk = $true
            for ($i = 1; $i -lt $numChunks; $i++) {
                $start = $i * $chunkSize
                $end = [math]::Min(($i + 1) * $chunkSize - 1, $totalSize - 1)
                if ($start -ge $totalSize) { break }
                $expectedSize = $end - $start + 1
                $chunkFile = Join-Path $chunkDir "chunk_$i"

                Write-Host "  Chunk $i/$($numChunks - 1) / 分块 $i/$($numChunks - 1)..." -NoNewline
                try {
                    $req = [System.Net.HttpWebRequest]::Create($url)
                    $req.Method = "GET"
                    $req.UserAgent = "Mozilla/5.0"
                    $req.Timeout = 60000
                    $req.AddRange($start, $end)
                    $resp = $req.GetResponse()
                    $statusCode = [int]$resp.StatusCode
                    $respLen = $resp.ContentLength
                    if ($statusCode -ne 206 -or $respLen -ne $expectedSize) {
                        $resp.Close()
                        Write-Host " Failed (status: $statusCode) / 失败"
                        $allOk = $false
                        break
                    }
                    $stream = $resp.GetResponseStream()
                    $fs = [System.IO.File]::Create($chunkFile)
                    $buf = New-Object byte[] 262144
                    $totalRead = 0
                    while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                        $fs.Write($buf, 0, $n)
                        $totalRead += $n
                    }
                    $fs.Close(); $stream.Close(); $resp.Close()
                    if ($totalRead -ne $expectedSize) {
                        Write-Host " Failed (incomplete) / 失败(不完整)"
                        $allOk = $false
                        break
                    }
                    Write-Host " Done / 完成"
                } catch {
                    Write-Host " Failed / 失败"
                    Write-Warn "  Chunk $i error: $($_.Exception.Message)"
                    $allOk = $false
                    break
                }
            }

            if ($allOk) {
                # Assemble all chunks and verify total size
                $actualChunks = $numChunks
                Write-Host "  Assembling & verifying / 正在合并并校验..." -NoNewline
                $assembledSize = 0
                $fs = [System.IO.File]::Create($dest)
                for ($i = 0; $i -lt $actualChunks; $i++) {
                    $chunkFile = Join-Path $chunkDir "chunk_$i"
                    if (Test-Path $chunkFile) {
                        $bytes = [System.IO.File]::ReadAllBytes($chunkFile)
                        $fs.Write($bytes, 0, $bytes.Length)
                        $assembledSize += $bytes.Length
                    }
                }
                $fs.Close()
                Remove-Item $chunkDir -Recurse -Force

                if ($assembledSize -ne $totalSize) {
                    Write-Host ""
                    Write-Warn "Size mismatch after assembly / 合并后大小不一致: expected $totalSize, got $assembledSize"
                    Remove-Item $dest -Force -ErrorAction SilentlyContinue
                    $useChunked = $false
                } else {
                    Write-Host " Done / 完成"
                }
            } else {
                Remove-Item $chunkDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Warn "Chunked download failed, falling back to single-thread / 分块下载失败，回退到单线程"
                $useChunked = $false
            }
        }
    }

    if (-not $useChunked) {
        try {
            $ProgressPreference = 'Continue'
            Invoke-WebRequest -Uri $url -OutFile $dest -Headers @{"User-Agent"="Mozilla/5.0"} -UseBasicParsing
        } catch {
            Write-Fail "Download failed / 下载失败: $_"
        }
    }

    $size = [math]::Round(((Get-Item $dest).Length)/1MB, 1)
    Write-Success "Download complete / 下载完成 ($size MB)"

    # Integrity check: verify SHA256 if digest is available from release
    if ($ExpectedDigest) {
        Write-Host "  Verifying SHA256 / 正在校验完整性..." -NoNewline
        $localHash = (Get-FileHash -Algorithm SHA256 $dest).Hash.ToLower()
        if ($localHash -eq $ExpectedDigest) {
            Write-Host " OK / 通过"
        } else {
            Write-Host ""
            Write-Warn "SHA256 mismatch! / 校验失败！"
            Write-Warn "  Expected / 期望: $ExpectedDigest"
            Write-Warn "  Got / 实际:      $localHash"
            Remove-Item $dest -Force
            Write-Fail "Integrity check failed, file deleted / 完整性校验失败，文件已删除，请重试"
        }
    }
}

# ============================================================================
# Config persistence
# ============================================================================
function Save-Config {
    $configFile = Join-Path $DownloadDir ".nyxbot_config.json"
    $config = @{
        Port      = $script:Port
        Token     = $script:Token
        Server    = $script:Server
        Client    = $script:Client
        Docker    = $script:Docker
        Local     = $script:Local
        ProxyAddr = $script:ProxyAddr
        ProxyUser = $script:ProxyUser
        ProxyPass = $script:ProxyPass
        Debug     = $script:Debug
    } | ConvertTo-Json
    Set-Content -Path $configFile -Value $config -Force
}

function Load-Config {
    $configFile = Join-Path $DownloadDir ".nyxbot_config.json"
    if (Test-Path $configFile) {
        try {
            $saved = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($saved) {
                if ($saved.Port -and $script:Port -eq "8080")      { $script:Port = $saved.Port }
                if ($saved.Token -and -not $script:Token)           { $script:Token = $saved.Token }
                if ($saved.Server)                                  { $script:Server = $saved.Server }
                if ($saved.Client)                                  { $script:Client = $saved.Client }
                if ($saved.Docker)                                  { $script:Docker = $saved.Docker }
                if ($saved.Local)                                   { $script:Local = $saved.Local }
                if ($saved.ProxyAddr)                               { $script:ProxyAddr = $saved.ProxyAddr }
                if ($saved.ProxyUser)                               { $script:ProxyUser = $saved.ProxyUser }
                if ($saved.ProxyPass)                               { $script:ProxyPass = $saved.ProxyPass }
                if ($saved.Debug)                                   { $script:Debug = $saved.Debug }
            }
        } catch { }
    }
}

# ============================================================================
# Interactive config
# ============================================================================
function Get-UserConfig {
    if ($Quiet) {
        if (-not $Token) { Write-Fail "--quiet requires --token=xxx" }
        return
    }

    Write-Host ""
    Write-Host "--- Basic Config / 基础配置 ---"
    $input = Read-Host "  Port / 端口 [$Port]"
    if ($input) { $Port = $input }

    while (-not $Token) {
        $Token = Read-Host "  Token (required / 必填)"
        if (-not $Token) { Write-Warn "Token cannot be empty / 不能为空" }
    }

    if (-not $Server -and -not $Client) {
        Write-Host "  Mode / 模式: 1) Server/服务端  2) Client/客户端"
        $mode = Read-Host "  Select / 选择 [1]"
        if ($mode -eq "2") { $Client = $true } else { $Server = $true }
    }

    Write-Host ""
    Write-Host "--- Proxy / 代理 (Enter=skip/回车跳过) ---"
    if (-not $ProxyAddr) { $ProxyAddr = Read-Host "  Proxy URL / 代理地址" }
    if ($ProxyAddr) {
        $ProxyUser = Read-Host "  Username / 用户名"
        $ProxyPass = Read-Host "  Password / 密码"
    }

    Write-Host ""
    Write-Host "--- Confirm / 确认 ---"
    Write-Host "  Port/端口: $Port | Mode/模式: $(if ($Client) { 'Client/客户端' } else { 'Server/服务端' }) | Token: $Token"
    $resp = Read-Host "  Proceed / 确认安装? [Y/n]"
    if ($resp -match "^[Nn]") { Write-Warn "Cancelled / 已取消"; exit 0 }
}

# ============================================================================
# Docker install
# ============================================================================
function Invoke-DockerPull($Image) {
    Write-Step "Pulling image / 拉取镜像: $Image"
    docker pull $Image 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Success "Image pulled / 拉取成功 (Docker Hub)"; return }

    Write-Warn "Docker Hub unreachable / 不可达, trying mirrors / 尝试镜像源..."
    foreach ($mirror in $DockerMirrors) {
        $mi = "${mirror}/${Image}"
        Write-Step "  $mi"
        docker pull $mi 2>$null
        if ($LASTEXITCODE -eq 0) {
            docker tag $mi $Image 2>$null
            docker rmi $mi 2>$null
            Write-Success "Image pulled / 拉取成功 (via $mirror)"
            return
        }
    }
    Write-Fail "All mirrors unavailable / 所有镜像源不可用"
}

function Install-DockerMode {
    Write-Step "Docker mode / Docker 模式安装..."
    # Check Docker is actually running (temporarily relax ErrorAction to handle docker's non-zero exit)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    docker info 2>$null | Out-Null
    $ErrorActionPreference = $prevEAP
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Docker is not running, falling back to local install / Docker 未运行，回退到本地安装"
        Install-LocalMode
        return
    }
    docker stop nyxbot 2>$null; docker rm nyxbot 2>$null

    $ea = @("-e", "SERVER_PORT=$Port", "-e", "SHIRO_TOKEN=$Token", "-e", "TZ=Asia/Shanghai")
    if ($Debug) { $ea += "-e"; $ea += "DEBUG=true" }
    if ($Client) {
        $ea += "-e"; $ea += "SHIRO_WS_SERVER_ENABLE=false"
        $ea += "-e"; $ea += "SHIRO_WS_CLIENT_ENABLE=true"
    }
    if ($ProxyAddr) { $ea += "-e"; $ea += "HTTP_PROXY=$ProxyAddr" }
    if ($ProxyUser) { $ea += "-e"; $ea += "PROXY_USER=$ProxyUser" }
    if ($ProxyPass) { $ea += "-e"; $ea += "PROXY_PASSWORD=$ProxyPass" }

    Invoke-DockerPull "${ImageName}:latest"

    Write-Step "Starting container / 启动容器..."
    docker run -d --name nyxbot --restart unless-stopped `
        -p "${Port}:8080" `
        -v "${DownloadDir}\data:/app/data" `
        -v "${DownloadDir}\logs:/app/logs" `
        $ea `
        "${ImageName}:latest"

    Write-Success "NyxBot started / 已启动 (container: nyxbot)"
    Show-PostInstall -Docker
}

# ============================================================================
# Local install
# ============================================================================
function Install-LocalMode {
    if (-not (Test-JavaInstalled)) {
        Write-Step "Please install JDK 21 / 请手动安装 JDK 21:"
        Write-Step "  https://www.oracle.com/java/technologies/downloads/#jdk21-windows"
        $r = Read-Host "  Press Enter when done / 装完后按回车, q=quit"
        if ($r -eq "q") { exit 0 }
        if (-not (Test-JavaInstalled)) { Write-Fail "Java 21 not found / 未找到 Java 21" }
    }

    # Get release info first (fast, no download) to check if we need to update
    Get-Release
    $dest = Join-Path $DownloadDir "NyxBot.jar"

    # Check if already installed with correct version
    $skipDownload = $false
    if ((Test-Path $dest) -and $ExpectedDigest) {
        Write-Host "  Checking existing JAR / 检测已有文件..." -NoNewline
        $localHash = (Get-FileHash -Algorithm SHA256 $dest).Hash.ToLower()
        if ($localHash -eq $ExpectedDigest) {
            Write-Host " Up-to-date / 已是最新"
            Write-Host "  Current version / 当前版本: $ReleaseTag"
            $skipDownload = $true
        } else {
            Write-Host " Outdated / 版本过旧"
            Write-Host "  Current / 当前: $localHash"
            Write-Host "  Latest  / 最新:  $ExpectedDigest"
            # Popup or prompt for update confirmation
            $doUpdate = $false
            if ($script:IsGui) {
                $updateResult = [System.Windows.MessageBox]::Show(
                    "New version $ReleaseTag available!`n`nUpdate now? / 发现新版本 $ReleaseTag ！`n`n是否立即更新？",
                    "NyxBot Update / 更新",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question
                )
                $doUpdate = ($updateResult -eq 'Yes')
            } else {
                $choice = Read-Host "  Update now? / 是否更新? [Y/n]"
                $doUpdate = (-not ($choice -match "^[Nn]"))
            }
            if ($doUpdate) {
                Write-Step "Updating / 正在更新..."
            } else {
                $skipDownload = $true
                Write-Warn "Skipping update, using existing version / 跳过更新，使用现有版本"
            }
        }
    }

    if (-not $skipDownload) {
        Test-Network
        Download-Jar
    }

    $ja = @("-jar", $dest, "-serverPort=$Port")
    if ($Debug) { $ja += "-debug" }
    if ($Server) { $ja += "-wsServerEnable" }
    if ($Client) { $ja += "-wsClientEnable" }
    $ja += "-shiroToken=$Token"
    if ($ProxyAddr) { $ja += "-httpProxy=$ProxyAddr" }
    if ($ProxyUser) { $ja += "-proxyUser=$ProxyUser" }
    if ($ProxyPass) { $ja += "-proxyPassword=$ProxyPass" }
    $tr = "java $($ja -join ' ')"

    # Create scheduled task via schtasks (works without admin for user-level tasks)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    Write-Step "Creating scheduled task / 创建计划任务..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Remove existing task first
    schtasks /delete /tn $TaskName /f 2>&1 | Out-Null

    if ($isAdmin) {
        Write-Host "  Executing: schtasks /create /tn $TaskName /tr `"$tr`" /sc onstart /ru SYSTEM /f"
        schtasks /create /tn $TaskName /tr $tr /sc onstart /ru SYSTEM /f
        $taskOk = ($LASTEXITCODE -eq 0) -and (Test-ScheduledTaskExists)
    } else {
        Write-Host "  Executing: schtasks /create /tn $TaskName /tr `"$tr`" /sc onlogon /f"
        schtasks /create /tn $TaskName /tr $tr /sc onlogon /f
        $taskOk = ($LASTEXITCODE -eq 0) -and (Test-ScheduledTaskExists)
    }

    if (-not $taskOk) {
        Write-Warn "  Failed to create scheduled task, starting directly / 计划任务创建失败，直接启动..."
        $proc = Start-Process -FilePath "java.exe" -ArgumentList ($ja -join ' ') -WorkingDirectory $DownloadDir -PassThru -WindowStyle Hidden
        Write-Success "NyxBot started / 已启动 (PID: $($proc.Id))"
    } else {
        if ($isAdmin) {
            Write-Success "  Task level: System (auto-start on boot) / 系统级(开机自启)"
        } else {
            Write-Success "  Task level: User (auto-start on logon) / 用户级(登录自启)"
        }
        schtasks /run /tn $TaskName 2>&1 | Out-Null
        Write-Success "NyxBot started / 已启动 (task: $TaskName)"
    }
    $ErrorActionPreference = $prevEAP
    Show-PostInstall -Local
}

# ============================================================================
# Post-install
# ============================================================================
function Show-PostInstall {
    param([switch]$Docker, [switch]$Local)
    Write-Host ""
    Write-Host "+------------------------------------------+" -ForegroundColor Green
    Write-Host "|  NyxBot Installed / NyxBot 安装完成!      |" -ForegroundColor Green
    Write-Host "+------------------------------------------+" -ForegroundColor Green
    Write-Host "  Dashboard / 管理页面: http://localhost:${Port}"
    Write-Host "  Data / 数据目录: ${DownloadDir}"
    if ($Docker) {
        Write-Host "  Logs / 日志: docker logs -f nyxbot"
        Write-Host "  Restart / 重启: docker restart nyxbot"
    } else {
        Write-Host "  Status / 状态: Get-ScheduledTask '$TaskName'"
    }
    Write-Host ""
}

# ============================================================================
# GUI form
# ============================================================================
function Show-GuiForm {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NyxBot Deploy" Width="440" Height="560"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        WindowStyle="None" AllowsTransparency="True"
        Background="Transparent">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="BorderBrush" Value="#CCCCCC"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Background" Value="White"/>
        </Style>
        <Style TargetType="RadioButton">
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Margin" Value="0,4,20,4"/>
        </Style>
        <Style TargetType="Button" x:Key="PrimaryBtn">
            <Setter Property="Background" Value="#2D875A"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="30,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="Button" x:Key="DangerBtn">
            <Setter Property="Background" Value="#DC3545"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="16,6"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>
    <Border Background="White" CornerRadius="12" BorderBrush="#E0E0E0" BorderThickness="1">
    <Border.Effect><DropShadowEffect BlurRadius="20" ShadowDepth="4" Opacity="0.2"/></Border.Effect>
    <Grid Margin="0">
        <Grid.RowDefinitions>
            <RowDefinition Height="56"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Title bar -->
        <Border CornerRadius="12,12,0,0" Background="#2D875A" Grid.Row="0">
        <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBlock Text="  NyxBot One-Click Deploy" FontSize="16" FontWeight="Bold" Foreground="White" VerticalAlignment="Center" Margin="16,0,0,0"/>
            <Button Grid.Column="1" Content="X" Name="BtnClose" Background="Transparent" Foreground="White"
                    BorderThickness="0" FontSize="16" Width="40" Cursor="Hand" Margin="0,0,8,0"/>
        </Grid>
        </Border>

        <!-- Port -->
        <StackPanel Grid.Row="1" Margin="24,20,24,0">
            <TextBlock Text="Port / 端口" FontSize="12" Foreground="#666" Margin="0,0,0,2"/>
            <TextBox Name="TxtPort"/>
        </StackPanel>

        <!-- Token -->
        <StackPanel Grid.Row="2" Margin="24,12,24,0">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="Token" FontSize="12" Foreground="#666" Margin="0,0,0,2"/>
                <TextBlock Text=" *" FontSize="12" Foreground="Red" FontWeight="Bold"/>
            </StackPanel>
            <TextBox Name="TxtToken"/>
        </StackPanel>

        <!-- Mode -->
        <StackPanel Grid.Row="3" Margin="24,12,24,0">
            <TextBlock Text="Mode / 模式" FontSize="12" Foreground="#666" Margin="0,0,0,2"/>
            <StackPanel Orientation="Horizontal">
                <RadioButton Name="RadServer" Content="Server / 服务端" IsChecked="True"/>
                <RadioButton Name="RadClient" Content="Client / 客户端"/>
            </StackPanel>
        </StackPanel>

        <!-- Proxy -->
        <StackPanel Grid.Row="4" Margin="24,12,24,0">
            <TextBlock Text="Proxy / 代理" FontSize="12" Foreground="#666" Margin="0,0,0,2"/>
            <TextBox Name="TxtProxy"/>
        </StackPanel>

        <!-- Install mode -->
        <StackPanel Grid.Row="5" Margin="24,12,24,12">
            <TextBlock Text="Install / 安装方式" FontSize="12" Foreground="#666" Margin="0,0,0,2"/>
            <StackPanel Orientation="Horizontal">
                <RadioButton Name="RadDocker" Content="Docker" IsChecked="True"/>
                <RadioButton Name="RadLocal" Content="Local / 本地"/>
            </StackPanel>
        </StackPanel>

        <!-- Status & Maintenance -->
        <Border Grid.Row="6" Margin="24,8,24,4" Padding="12,10" Background="#F8F9FA" CornerRadius="6" BorderBrush="#E0E0E0" BorderThickness="1">
        <StackPanel>
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Grid.Column="0" Text="NyxBot: " FontSize="12" Foreground="#666" VerticalAlignment="Center"/>
                <TextBlock Grid.Row="0" Grid.Column="1" Name="TxtBotStatus" Text="Not installed / 未安装" FontSize="12" Foreground="#999" VerticalAlignment="Center" Margin="4,0,0,0"/>
                <TextBlock Grid.Row="1" Grid.Column="0" Text="Task: " FontSize="12" Foreground="#666" VerticalAlignment="Center"/>
                <TextBlock Grid.Row="1" Grid.Column="1" Name="TxtTaskStatus" Text="None / 无" FontSize="12" Foreground="#999" VerticalAlignment="Center" Margin="4,0,0,0"/>
            </Grid>
            <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                <Button Content="Stop / 停止" Name="BtnStop" Style="{StaticResource DangerBtn}" Margin="0,0,8,0" Visibility="Collapsed"/>
                <Button Content="Remove Task / 移除计划任务" Name="BtnRemoveTask" Background="#FFC107" Foreground="#333"
                        FontWeight="Bold" FontSize="13" Padding="16,6" BorderThickness="0" Cursor="Hand" Visibility="Collapsed"/>
            </StackPanel>
        </StackPanel>
        </Border>

        <!-- Buttons -->
        <StackPanel Grid.Row="7" Margin="24,4,24,20" VerticalAlignment="Bottom" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Content="Cancel / 取消" Name="BtnCancel" Margin="0,0,12,0"
                    Background="#F0F0F0" Foreground="#333" BorderThickness="1" BorderBrush="#CCC"
                    FontSize="13" Padding="20,8" Cursor="Hand"/>
            <Button Content="Deploy / 开始安装" Name="BtnDeploy" Style="{StaticResource PrimaryBtn}"/>
        </StackPanel>
    </Grid>
    </Border>
</Window>
'@

    # Parse XAML from string
    try {
        $reader = New-Object System.IO.StringReader($xaml)
        $xmlReader = [System.Xml.XmlReader]::Create($reader)
        $window = [Windows.Markup.XamlReader]::Load($xmlReader)
        $xmlReader.Close()
        $reader.Close()
    } catch {
        Write-Host "XAML Error: $_" -ForegroundColor Red
        exit 1
    }
    if (-not $window) {
        Write-Host "XAML Load returned null!" -ForegroundColor Red
        exit 1
    }

    # Set default values (can't use PowerShell vars in single-quoted XAML here-string)
    $window.Title = "NyxBot Deploy v$ScriptVersion"
    $window.FindName("TxtPort").Text = $Port
    $window.FindName("TxtToken").Text = $Token
    $window.FindName("TxtProxy").Text = $ProxyAddr

    # Bind controls
    $txtPort = $window.FindName("TxtPort")
    $txtToken = $window.FindName("TxtToken")
    $txtProxy = $window.FindName("TxtProxy")
    $radServer = $window.FindName("RadServer")
    $radClient = $window.FindName("RadClient")
    $radDocker = $window.FindName("RadDocker")
    $radLocal = $window.FindName("RadLocal")
    $btnDeploy = $window.FindName("BtnDeploy")
    $btnCancel = $window.FindName("BtnCancel")
    $btnClose = $window.FindName("BtnClose")
    $txtBotStatus = $window.FindName("TxtBotStatus")
    $txtTaskStatus = $window.FindName("TxtTaskStatus")
    $btnStop = $window.FindName("BtnStop")
    $btnRemoveTask = $window.FindName("BtnRemoveTask")

    # Refresh status display
    function Update-Status {
        $isRunning = Test-NyxBotRunning
        $hasTask = Test-ScheduledTaskExists
        if ($isRunning) {
            $txtBotStatus.Text = "Running / 运行中"
            $txtBotStatus.Foreground = "#28A745"
            $txtBotStatus.FontWeight = "Bold"
            $btnStop.Visibility = "Visible"
        } else {
            $txtBotStatus.Text = "Not running / 未运行"
            $txtBotStatus.Foreground = "#999"
            $txtBotStatus.FontWeight = "Normal"
            $btnStop.Visibility = "Collapsed"
        }
        if ($hasTask) {
            $txtTaskStatus.Text = "Active / 已注册"
            $txtTaskStatus.Foreground = "#28A745"
            $txtTaskStatus.FontWeight = "Bold"
            $btnRemoveTask.Visibility = "Visible"
        } else {
            $txtTaskStatus.Text = "None / 无"
            $txtTaskStatus.Foreground = "#999"
            $txtTaskStatus.FontWeight = "Normal"
            $btnRemoveTask.Visibility = "Collapsed"
        }
    }
    Update-Status

    # Stop NyxBot and disable scheduled task to prevent auto-restart
    $btnStop.Add_Click({
        Write-Host "[>] Stopping NyxBot / 正在停止 NyxBot..."
        if (Stop-NyxBot) {
            # Also unregister task so it won't auto-restart
            if (Test-ScheduledTaskExists) {
                if (Remove-NyxBotTask) {
                    Write-Host "[+] Stopped & task removed / 已停止并移除计划任务" -ForegroundColor Green
                } else {
                    Write-Host "[+] Stopped / 已停止 (task removal failed / 计划任务移除失败)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "[+] Stopped / 已停止" -ForegroundColor Green
            }
        } else {
            Write-Host "[-] No NyxBot process found / 未找到 NyxBot 进程" -ForegroundColor Yellow
        }
        Update-Status
    })

    # Remove scheduled task only (keep process running if it is)
    $btnRemoveTask.Add_Click({
        Write-Host "[>] Removing scheduled task / 正在移除计划任务..."
        if (Remove-NyxBotTask) {
            Write-Host "[+] Task removed / 计划任务已移除" -ForegroundColor Green
        } else {
            Write-Host "[-] Failed to remove task / 移除失败" -ForegroundColor Red
        }
        Update-Status
    })

    $btnDeploy.Add_Click({
        if (-not $txtToken.Text.Trim()) {
            # Modern alert popup
            $alertXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="NyxBot" Width="300" Height="130" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="White">
    <StackPanel Margin="15,20">
        <TextBlock Text="Token is required!" FontSize="14" FontWeight="Bold"
                   Foreground="#333" HorizontalAlignment="Center"/>
        <TextBlock Text="Token 不能为空" FontSize="13"
                   Foreground="#666" HorizontalAlignment="Center" Margin="0,5,0,0"/>
        <Button Content="OK" Name="BtnOk" Width="60" HorizontalAlignment="Center" Margin="0,15,0,0"
                Background="#2D875A" Foreground="White" BorderThickness="0"
                FontSize="13" Padding="10,5"/>
    </StackPanel>
</Window>
"@
            $ar = New-Object System.IO.StringReader($alertXaml)
            $axr = [System.Xml.XmlReader]::Create($ar)
            $alert = [Windows.Markup.XamlReader]::Load($axr)
            $axr.Close(); $ar.Close()
            $okBtn = $alert.FindName("BtnOk")
            if ($okBtn) {
                $okBtn.Add_Click({ $alert.Close() })
            }
            $alert.ShowDialog() | Out-Null
            $txtToken.Focus()
            return
        }
        $window.DialogResult = $true
        $window.Close()
    })
    $btnCancel.Add_Click({ $window.Close() })
    $btnClose.Add_Click({ $window.Close() })

    # Drag via title bar area
    $window.Add_MouseLeftButtonDown({ if ($_.GetPosition($window).Y -lt 56) { $window.DragMove() } })

    $result = $window.ShowDialog()

    if (-not $result) {
        Write-Warn "Cancelled / 已取消"
        exit 0
    }

    $script:Port = $txtPort.Text.Trim()
    $script:Token = $txtToken.Text.Trim()
    if ($radClient.IsChecked) { $script:Client = $true; $script:Server = $false } else { $script:Server = $true }
    if ($txtProxy.Text.Trim()) { $script:ProxyAddr = $txtProxy.Text.Trim() }
    if ($radLocal.IsChecked) { $script:Local = $true } else { $script:Docker = $true }
}

function Show-HelpText {
    Write-Host @"
NyxBot Deploy Script v$ScriptVersion / NyxBot 一键部署脚本

Usage / 用法:
  .\nyxbot-deploy.ps1 [options]

Modes / 模式:
  -Docker        Docker install / 容器安装 (recommended/推荐)
  -Local         Local JAR install / 本地安装

Options / 选项:
  -Text          Command-line mode / 命令行问答模式
  -Quiet         Non-interactive / 静默模式 (requires -Token)
  -Help          Show this help / 帮助

Config / 配置:
  -Port 8080     Service port / 服务端口
  -Token xxx     OneBot Token / 令牌 (required/必填)
  -Server        Server mode / 服务端模式 (default/默认)
  -Client        Client mode / 客户端模式
  -ProxyAddr URL Proxy URL / 代理地址
  -Debug         Enable debug / 调试模式

Examples / 示例:
  .\nyxbot-deploy.ps1
  .\nyxbot-deploy.ps1 -Docker -Quiet -Token abc123
  .\nyxbot-deploy.ps1 -Local -Port 9090 -Token abc123
"@
}

# ============================================================================
# Main
# ============================================================================
function Main {
    if ($Help) { Show-HelpText; return }

    Show-Banner
    Test-System

    # Load saved config from previous install if available
    Load-Config

    # Default GUI form, --text for command line, --quiet for no interaction
    if (-not $Quiet -and -not $Text) {
        $script:IsGui = $true
        Show-GuiForm
        Save-Config
    } else {
        if (-not $Quiet -and -not $Docker -and -not $Local) {
            $hasDocker = Test-DockerInstalled
            $hasJava = Test-JavaInstalled
            if ($hasDocker -and $hasJava) {
                Write-Host ""
                Write-Host "  Select install mode / 选择安装方式:" -ForegroundColor Cyan
                Write-Host "  1) Docker (recommended / 推荐)"
                Write-Host "  2) Local JAR / 本地 Jar 包安装"
                $choice = Read-Host "  Select / 选择 [1]"
                if ($choice -eq "2") { $Local = $true } else { $Docker = $true }
            } elseif ($hasDocker) {
                $Docker = $true
                Write-Step "Docker available, using Docker / 检测到 Docker"
            } else {
                $Local = $true
                Write-Step "Docker unavailable, using local / Docker 不可用, 使用本地安装"
            }
        }

        Write-Step "Mode / 安装方式: $(if ($Docker) { 'Docker' } else { 'Local' })"
        Write-Step "Directory / 安装目录: $DownloadDir"
        Write-Host ""

        Get-UserConfig
        Save-Config
    }

    if ($Docker) { Install-DockerMode } else { Install-LocalMode }
}

Main
