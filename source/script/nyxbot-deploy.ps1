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

$ScriptVersion = "3.0.0"
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
$JavaExe = ""

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

function Mask-Secret([string]$Value) {
    if (-not $Value) { return "Not set / 未设置" }
    if ($Value.Length -le 8) { return "****" }
    return "$($Value.Substring(0, 4))****$($Value.Substring($Value.Length - 4))"
}

function Protect-ConfigFile([string]$Path) {
    try {
        $file = Get-Item -LiteralPath $Path
        $acl = $file.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $acl.SetAccessRuleProtection($true, $false)
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user, 'FullControl', 'Allow')
        $acl.SetAccessRule($rule)
        $file.SetAccessControl($acl)
    } catch {
        Write-Warn "Config ACL hardening skipped / 已跳过配置文件权限加固: $($_.Exception.Message)"
    }
}

function Quote-TaskArg([string]$Value) {
    return '"' + ($Value -replace '"', '\"') + '"'
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
    function Test-JavaExecutable([string]$JavaExe) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $JavaExe
        $psi.Arguments = '-version'
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $v = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        if ($v -match 'version "(\d+)\.') {
            $major = [int]$Matches[1]
            if ($major -ge 21) {
                $javaDir = Split-Path $JavaExe -Parent
                if ($javaDir -and ($env:Path -notlike "*$javaDir*")) { $env:Path = "$javaDir;$env:Path" }
                $script:JavaExe = $JavaExe
                Write-Success "Java $major : installed ($JavaExe) / 已安装"
                return $true
            }
            return $false
        }
        return $false
    }

    $candidates = @()
    if ($script:JavaExe) { $candidates += $script:JavaExe }
    $cmd = Get-Command java -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }

    $javaHomes = @(
        $env:JAVA_HOME,
        [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine'),
        [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
    ) | Where-Object { $_ }
    foreach ($javaHome in $javaHomes) {
        $candidates += (Join-Path $javaHome "bin\java.exe")
    }

    $programFiles = @(${env:ProgramFiles}, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($root in $programFiles) {
        $candidates += @(Get-ChildItem -LiteralPath (Join-Path $root "Microsoft") -Directory -Filter "jdk-21*" -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName "bin\java.exe" })
        $candidates += @(Get-ChildItem -LiteralPath (Join-Path $root "Java") -Directory -Filter "jdk-21*" -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName "bin\java.exe" })
    }

    foreach ($candidate in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if ((Test-Path -LiteralPath $candidate)) {
            try { if (Test-JavaExecutable $candidate) { return $true } } catch { }
        }
    }

    Write-Warn "Java 21: not installed or not found / Java 21 未安装或未找到"
    return $false
}

function Install-Java21 {
    function Refresh-JavaPath {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = "$machinePath;$userPath"
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Step "Installing JDK 21 with winget / 正在通过 winget 安装 JDK 21..."
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        winget install --id Microsoft.OpenJDK.21 -e --source winget `
            --accept-package-agreements --accept-source-agreements --silent
        $exit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        if ($exit -eq 0) {
            Refresh-JavaPath
            if (Test-JavaInstalled) { return $true }
        } else {
            Write-Warn "winget install failed (exit code: $exit) / winget 安装失败 (退出码: $exit)"
        }
    } else {
        Write-Warn "winget not found, falling back to MSI installer / 未找到 winget，改用 MSI 安装包"
    }

    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ($arch) {
        'ARM64|AARCH64' { $msiUrl = 'https://aka.ms/download-jdk/microsoft-jdk-21-windows-aarch64.msi' }
        'AMD64|X64'     { $msiUrl = 'https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.msi' }
        default {
            Write-Warn "Unsupported Windows architecture for automatic JDK install: $arch / 当前架构不支持自动安装 JDK: $arch"
            return $false
        }
    }

    if (-not (Test-Path -LiteralPath $DownloadDir)) {
        New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    }

    $msiPath = Join-Path $DownloadDir "microsoft-jdk-21.msi"
    Write-Step "Downloading Microsoft OpenJDK 21 MSI..." "下载 Microsoft OpenJDK 21 MSI..."
    try {
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing -TimeoutSec 600
        $ProgressPreference = $oldProgress
    } catch {
        $ProgressPreference = $oldProgress
        Write-Warn "Failed to download JDK MSI / 下载 JDK MSI 失败: $($_.Exception.Message)"
        return $false
    }

    if (-not (Test-Path -LiteralPath $msiPath) -or ((Get-Item -LiteralPath $msiPath).Length -le 0)) {
        Write-Warn "Downloaded JDK MSI is empty / 下载的 JDK MSI 为空"
        return $false
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Step "Installing Microsoft OpenJDK 21 MSI silently..." "静默安装 Microsoft OpenJDK 21 MSI..."
        $msiArgs = @("/i", $msiPath, "/qn", "/norestart")
    } else {
        Write-Step "Opening Microsoft OpenJDK 21 MSI installer..." "打开 Microsoft OpenJDK 21 MSI 安装向导..."
        Write-Host "  Please finish the installer wizard, then this script will continue. / 请完成安装向导，脚本会继续。"
        $msiArgs = @("/i", $msiPath, "/norestart")
    }

    $proc = Start-Process -FilePath "msiexec.exe" `
        -ArgumentList $msiArgs `
        -Wait -PassThru

    if ($proc.ExitCode -notin @(0, 3010)) {
        Write-Warn "MSI install failed (exit code: $($proc.ExitCode)) / MSI 安装失败 (退出码: $($proc.ExitCode))"
        Write-Step "Extracting portable JDK from MSI..." "从 MSI 解包免安装 JDK..."
        $portableDir = Join-Path $DownloadDir "jdk-21"
        Remove-Item -LiteralPath $portableDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $portableDir -Force | Out-Null
        $extract = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList @("/a", $msiPath, "/qn", "TARGETDIR=$portableDir") `
            -Wait -PassThru
        if ($extract.ExitCode -ne 0) {
            Write-Warn "Portable JDK extraction failed (exit code: $($extract.ExitCode)) / 免安装 JDK 解包失败 (退出码: $($extract.ExitCode))"
            return $false
        }

        $java = Get-ChildItem -LiteralPath $portableDir -Recurse -Filter "java.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\bin\\java\.exe$" } |
            Select-Object -First 1
        if (-not $java) {
            Write-Warn "Portable JDK extraction did not contain java.exe / 解包后的 JDK 中未找到 java.exe"
            return $false
        }

        $script:JavaExe = $java.FullName
        Save-Config
        return (Test-JavaInstalled)
    }

    Refresh-JavaPath
    return (Test-JavaInstalled)
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

function Test-WindowsServer {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        return ($os.ProductType -ne 1)
    } catch {
        return $false
    }
}

function Start-InstallConsole {
    if (-not $PSCommandPath) {
        Write-Fail "Cannot open install console because script path is unknown / 无法打开安装控制台，脚本路径未知"
    }

    $hostPath = (Get-Process -Id $PID).Path
    if (-not $hostPath) { $hostPath = "powershell.exe" }

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-NoExit",
        "-File", $PSCommandPath,
        "-Text",
        "-Quiet"
    )

    Write-Step "Opening install console / 正在打开安装控制台..."
    Start-Process -FilePath $hostPath -ArgumentList $args -WorkingDirectory (Split-Path $PSCommandPath -Parent)
}

function Start-InstallGui {
    if (-not $PSCommandPath) {
        Write-Fail "Cannot open install window because script path is unknown / 无法打开安装窗口，脚本路径未知"
    }

    if (-not (Test-Path -LiteralPath $DownloadDir)) {
        New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $logFile = Join-Path $DownloadDir "install.log"
    $errFile = Join-Path $DownloadDir "install.err.log"
    Remove-Item -LiteralPath $logFile, $errFile -Force -ErrorAction SilentlyContinue

    $hostPath = (Get-Process -Id $PID).Path
    if (-not $hostPath) { $hostPath = "powershell.exe" }

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        "-Text",
        "-Quiet"
    )

    $proc = Start-Process -FilePath $hostPath `
        -ArgumentList $args `
        -WorkingDirectory (Split-Path $PSCommandPath -Parent) `
        -RedirectStandardOutput $logFile `
        -RedirectStandardError $errFile `
        -WindowStyle Hidden `
        -PassThru

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NyxBot Installing" Width="760" Height="520"
        WindowStartupLocation="CenterScreen" Background="#F7F9FB">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="NyxBot 安装中" FontSize="22" FontWeight="Bold" Foreground="#1F2937"/>
        <TextBlock Grid.Row="1" Name="TxtStatus" Text="正在准备安装..." Margin="0,8,0,12" FontSize="13" Foreground="#4B5563"/>
        <TextBox Grid.Row="2" Name="TxtLog" FontFamily="Consolas" FontSize="12" IsReadOnly="True"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                 TextWrapping="NoWrap" Background="#0B1020" Foreground="#D1D5DB"
                 BorderThickness="0" Padding="12"/>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
            <Button Name="BtnCancel" Content="Cancel / 取消" Width="110" Height="34" Margin="0,0,10,0"/>
            <Button Name="BtnClose" Content="Close / 关闭" Width="110" Height="34" IsEnabled="False"/>
        </StackPanel>
    </Grid>
</Window>
'@

    $reader = New-Object System.IO.StringReader($xaml)
    $xmlReader = [System.Xml.XmlReader]::Create($reader)
    $window = [Windows.Markup.XamlReader]::Load($xmlReader)
    $xmlReader.Close(); $reader.Close()

    $txtStatus = $window.FindName("TxtStatus")
    $txtLog = $window.FindName("TxtLog")
    $btnCancel = $window.FindName("BtnCancel")
    $btnClose = $window.FindName("BtnClose")
    $state = @{ LastText = ""; Completed = $false }

    $btnCancel.Add_Click({
        if (-not $proc.HasExited) {
            $proc.Kill()
            $txtStatus.Text = "安装已取消 / Installation cancelled"
        }
        $btnCancel.IsEnabled = $false
        $btnClose.IsEnabled = $true
    })
    $btnClose.Add_Click({ $window.Close() })

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Add_Tick({
        $text = ""
        if (Test-Path -LiteralPath $logFile) { $text += Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $errFile) {
            $err = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
            if ($err) { $text += "`r`n--- Error / 错误 ---`r`n$err" }
        }

        if ($text -ne $state.LastText) {
            $txtLog.Text = $text
            $txtLog.ScrollToEnd()
            $state.LastText = $text
        }

        if ($proc.HasExited -and -not $state.Completed) {
            $state.Completed = $true
            $timer.Stop()
            $btnCancel.IsEnabled = $false
            $btnClose.IsEnabled = $true
            if ($proc.ExitCode -eq 0) {
                $txtStatus.Text = "安装完成 / Installation complete"
            } else {
                $txtStatus.Text = "安装失败，退出码: $($proc.ExitCode) / Installation failed"
            }
        } elseif (-not $proc.HasExited) {
            $txtStatus.Text = "正在安装，请稍候... / Installing, please wait..."
        }
    })
    $timer.Start()
    $window.ShowDialog() | Out-Null
    if ($proc.HasExited -and $proc.ExitCode -eq 0) {
        Show-InstalledGui
    }
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

function Wait-NyxBotStarted {
    param([int]$TimeoutSec = 90)
    Write-Step "Waiting for NyxBot to become ready / 等待 NyxBot 启动完成..."
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-NyxBotRunning) {
            Write-Host ""
            Write-Success "NyxBot is running / NyxBot 已运行"
            return $true
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
    }
    Write-Host ""
    Write-Warn "NyxBot did not become ready within ${TimeoutSec}s / NyxBot 在 ${TimeoutSec}s 内未就绪"
    return $false
}

function Stop-NyxBot {
    $stopped = $false
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*NyxBot.jar*" }
        foreach ($p in $procs) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
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

function Get-ConfigFilePath {
    return (Join-Path $DownloadDir ".nyxbot_config.json")
}

function Test-InstalledConfig {
    return (Test-Path -LiteralPath (Get-ConfigFilePath))
}

function Test-InstallationComplete {
    if (-not (Test-InstalledConfig)) { return $false }

    Load-Config
    if ($script:Docker) {
        try {
            docker inspect nyxbot 2>$null | Out-Null
            return ($LASTEXITCODE -eq 0)
        } catch {
            return $false
        }
    }

    $jarFile = Join-Path $DownloadDir "NyxBot.jar"
    if (-not (Test-Path -LiteralPath $jarFile)) { return $false }
    if ((Get-Item -LiteralPath $jarFile).Length -le 0) { return $false }

    $startCmd = Join-Path $DownloadDir "start-nyxbot.cmd"
    if (Test-ScheduledTaskExists) { return $true }
    if (Test-Path -LiteralPath $startCmd) { return $true }
    return $false
}

function Stop-InstalledNyxBot {
    if ($script:Docker) {
        try { docker stop nyxbot 2>$null | Out-Null } catch { }
        return
    }
    Stop-NyxBot | Out-Null
}

function Uninstall-InstalledNyxBot {
    if ($script:Docker) {
        try { docker stop nyxbot 2>$null | Out-Null } catch { }
        try { docker rm nyxbot 2>$null | Out-Null } catch { }
        return
    }
    Stop-NyxBot | Out-Null
    Remove-NyxBotTask | Out-Null
}

function Restart-InstalledNyxBot {
    Load-Config
    if ($script:Docker) {
        docker stop nyxbot 2>$null | Out-Null
        docker rm nyxbot 2>$null | Out-Null

        $ea = @("-e", "SERVER_PORT=$script:Port", "-e", "SHIRO_TOKEN=$script:Token", "-e", "TZ=Asia/Shanghai")
        if ($script:Debug) { $ea += "-e"; $ea += "DEBUG=true" }
        if ($script:Client) {
            $ea += "-e"; $ea += "SHIRO_WS_SERVER_ENABLE=false"
            $ea += "-e"; $ea += "SHIRO_WS_CLIENT_ENABLE=true"
        }
        if ($script:ProxyAddr) { $ea += "-e"; $ea += "HTTP_PROXY=$script:ProxyAddr" }
        if ($script:ProxyUser) { $ea += "-e"; $ea += "PROXY_USER=$script:ProxyUser" }
        if ($script:ProxyPass) { $ea += "-e"; $ea += "PROXY_PASSWORD=$script:ProxyPass" }

        docker run -d --name nyxbot --restart unless-stopped `
            -p "${script:Port}:8080" `
            -v "${DownloadDir}\data:/app/data" `
            -v "${DownloadDir}\logs:/app/logs" `
            $ea `
            "${ImageName}:latest"
        if ($LASTEXITCODE -ne 0) { throw "Docker container restart failed / Docker 容器重启失败" }
        if (-not (Wait-NyxBotStarted)) { throw "NyxBot did not become ready / NyxBot 未就绪" }
        return
    }

    $jarFile = Join-Path $DownloadDir "NyxBot.jar"
    if (-not (Test-Path -LiteralPath $jarFile)) { throw "NyxBot.jar not found / 未找到 NyxBot.jar" }

    Stop-NyxBot | Out-Null
    $ja = @("-jar", $jarFile, "-serverPort=$script:Port")
    if ($script:Debug) { $ja += "-debug" }
    if ($script:Server) { $ja += "-wsServerEnable" }
    if ($script:Client) { $ja += "-wsClientEnable" }
    $ja += "-shiroToken=$script:Token"
    if ($script:ProxyAddr) { $ja += "-httpProxy=$script:ProxyAddr" }
    if ($script:ProxyUser) { $ja += "-proxyUser=$script:ProxyUser" }
    if ($script:ProxyPass) { $ja += "-proxyPassword=$script:ProxyPass" }

    $startCmd = Join-Path $DownloadDir "start-nyxbot.cmd"
    $logFile = Join-Path $DownloadDir "nyxbot.log"
    $javaBin = if ($script:JavaExe) { Quote-TaskArg $script:JavaExe } else { "java" }
    $javaCommand = "$javaBin $($ja | ForEach-Object { Quote-TaskArg $_ })"
    Set-Content -Path $startCmd -Encoding ASCII -Force -Value @(
        "@echo off",
        "cd /d $(Quote-TaskArg $DownloadDir)",
        "$javaCommand >> $(Quote-TaskArg $logFile) 2>&1"
    )

    $tr = Quote-TaskArg $startCmd
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    schtasks /delete /tn $TaskName /f 2>&1 | Out-Null
    if ($isAdmin) {
        schtasks /create /tn $TaskName /tr $tr /sc onstart /ru SYSTEM /f 2>&1 | Out-Null
    } else {
        schtasks /create /tn $TaskName /tr $tr /sc onlogon /f 2>&1 | Out-Null
    }
    $taskOk = ($LASTEXITCODE -eq 0) -and (Test-ScheduledTaskExists)
    if ($taskOk) { schtasks /run /tn $TaskName 2>&1 | Out-Null } else { Start-Process -FilePath $startCmd -WorkingDirectory $DownloadDir -WindowStyle Hidden | Out-Null }
    $ErrorActionPreference = $prevEAP

    if (-not (Wait-NyxBotStarted)) { throw "NyxBot did not become ready / NyxBot 未就绪" }
}

function Show-LogWindow {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $logFile = Join-Path $DownloadDir "nyxbot.log"
    $tempLog = $null
    $logProc = $null

    if ($script:Docker) {
        $tempLog = Join-Path $DownloadDir "docker-live.log"
        $tempErr = Join-Path $DownloadDir "docker-live.err.log"
        Remove-Item -LiteralPath $tempLog -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempErr -Force -ErrorAction SilentlyContinue
        try {
            $logProc = Start-Process -FilePath "docker" -ArgumentList @("logs", "-f", "--tail", "100", "nyxbot") `
                -RedirectStandardOutput $tempLog -RedirectStandardError $tempErr -WindowStyle Hidden -PassThru
            $logFile = $tempLog
        } catch {
            Set-Content -LiteralPath $tempLog -Value "Failed to start docker logs: $($_.Exception.Message)" -Force
            $logFile = $tempLog
        }
    }

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NyxBot Logs" Width="820" Height="560" WindowStartupLocation="CenterScreen" Background="#111827">
    <Grid Margin="14">
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="NyxBot 实时日志" FontSize="18" FontWeight="Bold" Foreground="#F9FAFB" Margin="0,0,0,10"/>
        <TextBox Grid.Row="1" Name="TxtLog" FontFamily="Consolas" FontSize="12" IsReadOnly="True" TextWrapping="NoWrap"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="#030712" Foreground="#D1D5DB" BorderThickness="0" Padding="10"/>
        <Button Grid.Row="2" Name="BtnClose" Content="Close / 关闭" Width="110" Height="34" HorizontalAlignment="Right" Margin="0,12,0,0"/>
    </Grid>
</Window>
'@
    $reader = New-Object System.IO.StringReader($xaml)
    $xmlReader = [System.Xml.XmlReader]::Create($reader)
    $window = [Windows.Markup.XamlReader]::Load($xmlReader)
    $xmlReader.Close(); $reader.Close()
    $txtLog = $window.FindName("TxtLog")
    $btnClose = $window.FindName("BtnClose")
    $state = @{ LastText = "" }
    $btnClose.Add_Click({ $window.Close() })

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(700)
    $timer.Add_Tick({
        $text = ""
        if (Test-Path -LiteralPath $logFile) {
            $text = Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue
        } else {
            $text = "Log file not found / 日志文件不存在: $logFile"
        }
        if ($tempErr -and (Test-Path -LiteralPath $tempErr)) {
            $errText = Get-Content -LiteralPath $tempErr -Raw -ErrorAction SilentlyContinue
            if ($errText) { $text += "`r`n--- Error / 错误 ---`r`n$errText" }
        }
        if ($text -ne $state.LastText) {
            $txtLog.Text = $text
            $txtLog.ScrollToEnd()
            $state.LastText = $text
        }
    })
    $timer.Start()
    $window.ShowDialog() | Out-Null
    $timer.Stop()
    if ($logProc -and -not $logProc.HasExited) { $logProc.Kill() }
}

function Confirm-UpdateInstall {
    Load-Config
    if ($script:Docker) {
        $result = [System.Windows.MessageBox]::Show(
            "Docker mode updates are applied by pulling and restarting the latest image.`nDocker 模式会通过拉取最新镜像并重启来更新。`n`nUpdate now? / 是否现在更新？",
            "NyxBot Update / 检查更新",
            "YesNo",
            "Question"
        )
        return ($result -eq "Yes")
    }

    try {
        Get-Release
        $jarFile = Join-Path $DownloadDir "NyxBot.jar"
        if (-not (Test-Path -LiteralPath $jarFile)) {
            $result = [System.Windows.MessageBox]::Show(
                "NyxBot.jar is missing. Download version $ReleaseTag now?`n未找到 NyxBot.jar，是否现在下载 $ReleaseTag？",
                "NyxBot Update / 检查更新",
                "YesNo",
                "Question"
            )
            return ($result -eq "Yes")
        }

        if (-not $ExpectedDigest) {
            $result = [System.Windows.MessageBox]::Show(
                "Latest version is $ReleaseTag, but release digest is unavailable. Update now?`n最新版本为 $ReleaseTag，但 Release 未提供校验值。是否现在更新？",
                "NyxBot Update / 检查更新",
                "YesNo",
                "Question"
            )
            return ($result -eq "Yes")
        }

        $localHash = (Get-FileHash -Algorithm SHA256 $jarFile).Hash.ToLower()
        if ($localHash -eq $ExpectedDigest) {
            [System.Windows.MessageBox]::Show("NyxBot is already up to date ($ReleaseTag).`nNyxBot 已是最新版本 ($ReleaseTag)。", "NyxBot Update / 检查更新", "OK", "Information") | Out-Null
            return $false
        }

        $result = [System.Windows.MessageBox]::Show(
            "New version available: $ReleaseTag`n发现新版本：$ReleaseTag`n`nUpdate now? / 是否现在更新？",
            "NyxBot Update / 检查更新",
            "YesNo",
            "Question"
        )
        return ($result -eq "Yes")
    } catch {
        [System.Windows.MessageBox]::Show("Failed to check update:`n$($_.Exception.Message)`n检查更新失败。", "NyxBot Update / 检查更新", "OK", "Error") | Out-Null
        return $false
    }
}

function Show-InstalledGui {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    Load-Config
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NyxBot" Width="760" Height="540" WindowStartupLocation="CenterScreen" Background="#F7F9FB">
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Text="NyxBot 已安装" FontSize="24" FontWeight="Bold" Foreground="#1F2937"/>
        <TextBlock Grid.Row="1" Name="TxtStatus" Text="正在读取状态..." Margin="0,8,0,16" FontSize="14" Foreground="#4B5563"/>
        <Border Grid.Row="2" Background="White" BorderBrush="#E5E7EB" BorderThickness="1" CornerRadius="8" Padding="14" Margin="0,0,0,14">
            <StackPanel>
                <TextBlock Name="TxtMode" FontSize="13" Foreground="#111827" Margin="0,0,0,6"/>
                <TextBlock Name="TxtPort" FontSize="13" Foreground="#111827" Margin="0,0,0,6"/>
                <TextBlock Name="TxtToken" FontSize="13" Foreground="#111827" Margin="0,0,0,6"/>
                <TextBlock Name="TxtProxy" FontSize="13" Foreground="#111827" Margin="0,0,0,6"/>
                <TextBlock Name="TxtDir" FontSize="13" Foreground="#111827"/>
            </StackPanel>
        </Border>
        <TextBlock Grid.Row="3" Text="可在这里查看实时日志、刷新运行状态、停止运行或卸载服务/容器。卸载不会删除数据目录。" TextWrapping="Wrap" Foreground="#6B7280"/>
        <WrapPanel Grid.Row="4" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button Name="BtnUpdate" Content="Check Update / 检查更新" Width="160" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnConfig" Content="Config / 修改配置" Width="140" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnLogs" Content="Logs / 实时日志" Width="120" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnRefresh" Content="Refresh / 刷新" Width="110" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnStop" Content="Stop / 结束运行" Width="130" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnUninstall" Content="Uninstall / 卸载服务" Width="140" Height="34" Margin="0,0,8,8"/>
            <Button Name="BtnClose" Content="Close / 关闭" Width="110" Height="34" Margin="0,0,0,8"/>
        </WrapPanel>
    </Grid>
</Window>
'@
    $reader = New-Object System.IO.StringReader($xaml)
    $xmlReader = [System.Xml.XmlReader]::Create($reader)
    $window = [Windows.Markup.XamlReader]::Load($xmlReader)
    $xmlReader.Close(); $reader.Close()

    $txtStatus = $window.FindName("TxtStatus")
    $window.FindName("TxtMode").Text = "Install / 安装方式: $(if ($script:Docker) { 'Docker' } else { 'Local JAR' })"
    $window.FindName("TxtPort").Text = "Port / 端口: $script:Port"
    $window.FindName("TxtToken").Text = "Token: $(Mask-Secret $script:Token)"
    $proxyText = if ($script:ProxyAddr) { $script:ProxyAddr } else { "None / 无" }
    $window.FindName("TxtProxy").Text = "Proxy / 代理: $proxyText"
    $window.FindName("TxtDir").Text = "Data / 数据目录: $DownloadDir"

    function Update-InstalledStatus {
        if ($script:Docker) {
            try {
                $running = (docker inspect -f "{{.State.Running}}" nyxbot 2>$null) -eq "true"
                $txtStatus.Text = if ($running) { "Status / 状态: Running / 运行中" } else { "Status / 状态: Stopped / 未运行" }
            } catch { $txtStatus.Text = "Status / 状态: Unknown / 未知" }
        } else {
            $running = Test-NyxBotRunning
            $task = Test-ScheduledTaskExists
            $txtStatus.Text = "Status / 状态: $(if ($running) { 'Running / 运行中' } else { 'Stopped / 未运行' })    Task / 计划任务: $(if ($task) { 'Registered / 已注册' } else { 'None / 无' })"
        }
    }

    $window.FindName("BtnUpdate").Add_Click({
        if (Confirm-UpdateInstall) {
            $window.Close()
            Start-InstallGui
        }
    })
    $window.FindName("BtnConfig").Add_Click({
        $window.Close()
        Show-GuiForm
        Save-Config
        $apply = [System.Windows.MessageBox]::Show("Config saved. Apply and restart now?`n配置已保存，是否立即应用并重启？", "NyxBot", "YesNo", "Question")
        if ($apply -eq "Yes") {
            try {
                Restart-InstalledNyxBot
                [System.Windows.MessageBox]::Show("Config applied and NyxBot restarted successfully.`n配置已应用，NyxBot 已重启。", "NyxBot", "OK", "Information") | Out-Null
            } catch {
                [System.Windows.MessageBox]::Show("Failed to apply config or restart NyxBot:`n$($_.Exception.Message)`n配置应用或重启失败。", "NyxBot", "OK", "Error") | Out-Null
            }
            Show-InstalledGui
        } else {
            Show-InstalledGui
        }
    })
    $window.FindName("BtnLogs").Add_Click({ Show-LogWindow })
    $window.FindName("BtnRefresh").Add_Click({ Update-InstalledStatus })
    $window.FindName("BtnStop").Add_Click({ Stop-InstalledNyxBot; Update-InstalledStatus })
    $window.FindName("BtnUninstall").Add_Click({
        $result = [System.Windows.MessageBox]::Show("Remove service/container only. Data directory will be kept.`n仅卸载服务/容器，保留数据目录。", "NyxBot", "OKCancel", "Warning")
        if ($result -eq "OK") { Uninstall-InstalledNyxBot; Update-InstalledStatus }
    })
    $window.FindName("BtnClose").Add_Click({ $window.Close() })
    Update-InstalledStatus
    $window.ShowDialog() | Out-Null
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
    $deadline = (Get-Date).AddSeconds(20)
    while (($jobs | Where-Object { $_.State -eq 'Running' }) -and (Get-Date) -lt $deadline) {
        Write-Host "." -NoNewline
        Start-Sleep -Milliseconds 500
    }
    Write-Host ""
    $jobs | Where-Object { $_.State -eq 'Running' } | ForEach-Object {
        Stop-Job $_ -ErrorAction SilentlyContinue
    }
    $bestSpeed = 0
    $bestProxyName = ""

    foreach ($job in $jobs) {
        $result = $job | Receive-Job
        if (-not $result) {
            $result = @{ Name = $job.Name; Speed = 0; Success = $false }
        }
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

function Download-FileSingle {
    param(
        [string]$Url,
        [string]$Destination,
        [long]$ExpectedSize = 0,
        [int]$TimeoutSec = 3600
    )

    $tmp = "$Destination.tmp"
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Write-Step "Single-thread download / 单线程下载..."

    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = "GET"
    $req.UserAgent = "Mozilla/5.0"
    $req.Timeout = 30000
    $req.ReadWriteTimeout = 30000

    $resp = $null
    $stream = $null
    $fs = $null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastReport = [DateTime]::UtcNow
    $downloaded = 0L

    try {
        $resp = $req.GetResponse()
        if ($ExpectedSize -le 0 -and $resp.ContentLength -gt 0) { $ExpectedSize = $resp.ContentLength }
        $stream = $resp.GetResponseStream()
        if ($stream.CanTimeout) { $stream.ReadTimeout = 30000 }
        $fs = [System.IO.File]::Create($tmp)
        $buf = New-Object byte[] 262144

        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $fs.Write($buf, 0, $n)
            $downloaded += $n

            if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
                throw "Download timed out after ${TimeoutSec}s"
            }

            if (([DateTime]::UtcNow - $lastReport).TotalSeconds -ge 3) {
                $speed = if ($sw.Elapsed.TotalSeconds -gt 0) { $downloaded / $sw.Elapsed.TotalSeconds } else { 0 }
                if ($ExpectedSize -gt 0) {
                    $pct = [math]::Round(($downloaded * 100.0) / $ExpectedSize, 1)
                    Write-Host "  Downloaded / 已下载: $([math]::Round($downloaded/1MB, 1)) MB / $([math]::Round($ExpectedSize/1MB, 1)) MB (${pct}%, $(Format-Speed $speed))"
                } else {
                    Write-Host "  Downloaded / 已下载: $([math]::Round($downloaded/1MB, 1)) MB ($(Format-Speed $speed))"
                }
                $lastReport = [DateTime]::UtcNow
            }
        }
    } finally {
        if ($fs) { $fs.Close() }
        if ($stream) { $stream.Close() }
        if ($resp) { $resp.Close() }
    }

    if (-not (Test-Path -LiteralPath $tmp) -or ((Get-Item -LiteralPath $tmp).Length -le 0)) {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "Downloaded file is empty"
    }

    if ($ExpectedSize -gt 0 -and ((Get-Item -LiteralPath $tmp).Length -ne $ExpectedSize)) {
        $actual = (Get-Item -LiteralPath $tmp).Length
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "Size mismatch: expected $ExpectedSize, got $actual"
    }

    Move-Item -LiteralPath $tmp -Destination $Destination -Force
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
    $requestTimeoutMs = 30000
    $readTimeoutMs = 30000
    $singleDownloadTimeoutSec = 900
    try {
        $headReq = [System.Net.HttpWebRequest]::Create($url)
        $headReq.Method = "HEAD"
        $headReq.UserAgent = "Mozilla/5.0"
        $headReq.Timeout = $requestTimeoutMs
        $headReq.ReadWriteTimeout = $readTimeoutMs
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

        # Keep the probe small; downloading a full chunk here looks like a hang on slow proxies.
        Write-Host "  Testing Range support / 测试 Range 支持..." -NoNewline
        $start0 = 0
        $end0 = [math]::Min(1048575, $totalSize - 1)
        $expected0 = $end0 - $start0 + 1
        $probeFile = Join-Path $chunkDir "range_probe"
        $chunk0Ok = $false
        $resp = $null
        $stream = $null
        $fs = $null
        try {
            $req = [System.Net.HttpWebRequest]::Create($url)
            $req.Method = "GET"
            $req.UserAgent = "Mozilla/5.0"
            $req.Timeout = $requestTimeoutMs
            $req.ReadWriteTimeout = $readTimeoutMs
            $req.AddRange($start0, $end0)
            $resp = $req.GetResponse()
            if ([int]$resp.StatusCode -eq 206 -and $resp.ContentLength -eq $expected0) {
                $stream = $resp.GetResponseStream()
                if ($stream.CanTimeout) { $stream.ReadTimeout = $readTimeoutMs }
                $fs = [System.IO.File]::Create($probeFile)
                $buf = New-Object byte[] 262144
                $totalRead = 0
                while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                    $fs.Write($buf, 0, $n)
                    $totalRead += $n
                }
                $fs.Close(); $fs = $null
                if ($totalRead -eq $expected0) {
                    $chunk0Ok = $true
                    Write-Host " OK / 支持"
                    Write-Success "  Range supported, downloading chunks / Range 支持，开始下载分块"
                }
            }
        } catch {
            Write-Host " Failed / 失败"
        } finally {
            if ($fs) { $fs.Close() }
            if ($stream) { $stream.Close() }
            if ($resp) { $resp.Close() }
            Remove-Item $probeFile -Force -ErrorAction SilentlyContinue
        }

        if (-not $chunk0Ok) {
            Write-Warn "  Range not supported or chunk 0 failed, falling back to single-thread / Range 不支持，回退单线程"
            Remove-Item $chunkDir -Recurse -Force -ErrorAction SilentlyContinue
            $useChunked = $false
        } else {
            # Download chunks sequentially (avoids proxy concurrency limits)
            $allOk = $true
            for ($i = 0; $i -lt $numChunks; $i++) {
                $start = $i * $chunkSize
                $end = [math]::Min(($i + 1) * $chunkSize - 1, $totalSize - 1)
                if ($start -ge $totalSize) { break }
                $expectedSize = $end - $start + 1
                $chunkFile = Join-Path $chunkDir "chunk_$i"

                Write-Host "  Chunk $($i + 1)/${numChunks} / 分块 $($i + 1)/${numChunks}..." -NoNewline
                $resp = $null
                $stream = $null
                $fs = $null
                try {
                    $req = [System.Net.HttpWebRequest]::Create($url)
                    $req.Method = "GET"
                    $req.UserAgent = "Mozilla/5.0"
                    $req.Timeout = $requestTimeoutMs
                    $req.ReadWriteTimeout = $readTimeoutMs
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
                    if ($stream.CanTimeout) { $stream.ReadTimeout = $readTimeoutMs }
                    $fs = [System.IO.File]::Create($chunkFile)
                    $buf = New-Object byte[] 262144
                    $totalRead = 0
                    while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                        $fs.Write($buf, 0, $n)
                        $totalRead += $n
                    }
                    $fs.Close(); $fs = $null
                    $stream.Close(); $stream = $null
                    $resp.Close(); $resp = $null
                    if ($totalRead -ne $expectedSize) {
                        Write-Host " Failed (incomplete) / 失败(不完整)"
                        $allOk = $false
                        break
                    }
                    Write-Host " Done / 完成"
                } catch {
                    Write-Host " Failed / 失败"
                    Write-Warn "  Chunk $($i + 1) error: $($_.Exception.Message)"
                    $allOk = $false
                    break
                } finally {
                    if ($fs) { $fs.Close() }
                    if ($stream) { $stream.Close() }
                    if ($resp) { $resp.Close() }
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
        $downloaded = $false
        $lastError = $null
        try {
            Write-Warn "Using single-thread download. This can take a long time on slow proxies. / 正在使用单线程下载，代理较慢时可能需要较长时间。"
            Download-FileSingle -Url $url -Destination $dest -ExpectedSize $totalSize -TimeoutSec 3600
            $downloaded = $true
        } catch {
            $lastError = $_
            Write-Warn "Download failed with selected route, trying fallbacks... / 当前线路下载失败，尝试备用线路..."
        }

        if (-not $downloaded) {
            $fallbackUrls = @($DownloadUrl)
            foreach ($p in $Proxies) {
                if ($p.Url) { $fallbackUrls += "$($p.Url)/$($DownloadUrl -replace '^https://', '')" }
            }
            $fallbackUrls = $fallbackUrls | Where-Object { $_ -and $_ -ne $url } | Select-Object -Unique

            foreach ($fallbackUrl in $fallbackUrls) {
                try {
                    Write-Step "Trying fallback route / 尝试备用线路: $fallbackUrl"
                    Download-FileSingle -Url $fallbackUrl -Destination $dest -ExpectedSize $totalSize -TimeoutSec 3600
                    $downloaded = $true
                    break
                } catch {
                    $lastError = $_
                    Write-Warn "Fallback failed / 备用线路失败: $($_.Exception.Message)"
                }
            }
        }

        if (-not $downloaded) {
            Write-Fail "Download failed / 下载失败: $lastError"
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
    if (-not (Test-Path -LiteralPath $DownloadDir)) {
        New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
    }
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
        JavaExe   = $script:JavaExe
    } | ConvertTo-Json
    Set-Content -Path $configFile -Value $config -Force
    Protect-ConfigFile $configFile
}

function Load-Config {
    $configFile = Join-Path $DownloadDir ".nyxbot_config.json"
    if (Test-Path $configFile) {
        try {
            $saved = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($saved) {
                if ($saved.Port -and $script:Port -eq "8080")      { $script:Port = $saved.Port }
                if ($saved.Token -and -not $script:Token)           { $script:Token = $saved.Token }
                if (-not $script:Server -and -not $script:Client) {
                    if ($saved.Server)                              { $script:Server = $true; $script:Client = $false }
                    if ($saved.Client)                              { $script:Client = $true; $script:Server = $false }
                }
                if (-not $script:Docker -and -not $script:Local) {
                    if ($saved.Docker)                              { $script:Docker = $true; $script:Local = $false }
                    if ($saved.Local)                               { $script:Local = $true; $script:Docker = $false }
                }
                if ($saved.ProxyAddr -and -not $script:ProxyAddr)   { $script:ProxyAddr = $saved.ProxyAddr }
                if ($saved.ProxyUser -and -not $script:ProxyUser)   { $script:ProxyUser = $saved.ProxyUser }
                if ($saved.ProxyPass -and -not $script:ProxyPass)   { $script:ProxyPass = $saved.ProxyPass }
                if ($saved.Debug -and -not $script:Debug)           { $script:Debug = $saved.Debug }
                if ($saved.JavaExe -and -not $script:JavaExe)       { $script:JavaExe = $saved.JavaExe }
            }
        } catch { }
    }
}

# ============================================================================
# Interactive config
# ============================================================================
function Get-UserConfig {
    if ($Quiet) {
        if (-not $script:Token) { Write-Fail "--quiet requires --token=xxx" }
        return
    }

    Write-Host ""
    Write-Host "--- Basic Config / 基础配置 ---"
    $input = Read-Host "  Port / 端口 [$script:Port]"
    if ($input) { $script:Port = $input }

    while (-not $script:Token) {
        $secureToken = Read-Host "  Token (required / 必填)" -AsSecureString
        $script:Token = [System.Net.NetworkCredential]::new('', $secureToken).Password
        if (-not $script:Token) { Write-Warn "Token cannot be empty / 不能为空" }
    }

    if (-not $script:Server -and -not $script:Client) {
        Write-Host "  Mode / 模式: 1) Server/服务端  2) Client/客户端"
        $mode = Read-Host "  Select / 选择 [1]"
        if ($mode -eq "2") { $script:Client = $true; $script:Server = $false } else { $script:Server = $true; $script:Client = $false }
    }

    Write-Host ""
    Write-Host "--- Proxy / 代理 (Enter=skip/回车跳过) ---"
    if (-not $script:ProxyAddr) { $script:ProxyAddr = Read-Host "  Proxy URL / 代理地址" }
    if ($script:ProxyAddr) {
        $script:ProxyUser = Read-Host "  Username / 用户名"
        $secureProxyPass = Read-Host "  Password / 密码" -AsSecureString
        $script:ProxyPass = [System.Net.NetworkCredential]::new('', $secureProxyPass).Password
    }

    Write-Host ""
    Write-Host "--- Confirm / 确认 ---"
    Write-Host "  Port/端口: $script:Port | Mode/模式: $(if ($script:Client) { 'Client/客户端' } else { 'Server/服务端' }) | Token: $(Mask-Secret $script:Token)"
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
        $script:Docker = $false
        $script:Local = $true
        Save-Config
        Install-LocalMode
        return
    }
    docker stop nyxbot 2>$null; docker rm nyxbot 2>$null

    $ea = @("-e", "SERVER_PORT=$script:Port", "-e", "SHIRO_TOKEN=$script:Token", "-e", "TZ=Asia/Shanghai")
    if ($script:Debug) { $ea += "-e"; $ea += "DEBUG=true" }
    if ($script:Client) {
        $ea += "-e"; $ea += "SHIRO_WS_SERVER_ENABLE=false"
        $ea += "-e"; $ea += "SHIRO_WS_CLIENT_ENABLE=true"
    }
    if ($script:ProxyAddr) { $ea += "-e"; $ea += "HTTP_PROXY=$script:ProxyAddr" }
    if ($script:ProxyUser) { $ea += "-e"; $ea += "PROXY_USER=$script:ProxyUser" }
    if ($script:ProxyPass) { $ea += "-e"; $ea += "PROXY_PASSWORD=$script:ProxyPass" }

    Invoke-DockerPull "${ImageName}:latest"

    Write-Step "Starting container / 启动容器..."
    docker run -d --name nyxbot --restart unless-stopped `
        -p "${script:Port}:8080" `
        -v "${DownloadDir}\data:/app/data" `
        -v "${DownloadDir}\logs:/app/logs" `
        $ea `
        "${ImageName}:latest"

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Container start failed / 容器启动失败"
    }

    if (-not (Wait-NyxBotStarted)) {
        try { docker logs --tail 80 nyxbot } catch { }
        Write-Fail "NyxBot failed to become ready / NyxBot 启动后未就绪"
    }

    Write-Success "NyxBot started / 已启动 (container: nyxbot)"
    Show-PostInstall -Docker
}

# ============================================================================
# Local install
# ============================================================================
function Install-LocalMode {
    if (-not (Test-JavaInstalled)) {
        if (-not (Install-Java21)) {
            Write-Step "Please install JDK 21 manually / 请手动安装 JDK 21:"
            Write-Step "  https://www.oracle.com/java/technologies/downloads/#jdk21-windows"
            $r = Read-Host "  Press Enter when done / 装完后按回车, q=quit"
            if ($r -eq "q") { exit 0 }
            if (-not (Test-JavaInstalled)) { Write-Fail "Java 21 not found / 未找到 Java 21" }
        }
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

    $ja = @("-jar", $dest, "-serverPort=$script:Port")
    if ($script:Debug) { $ja += "-debug" }
    if ($script:Server) { $ja += "-wsServerEnable" }
    if ($script:Client) { $ja += "-wsClientEnable" }
    $ja += "-shiroToken=$script:Token"
    if ($script:ProxyAddr) { $ja += "-httpProxy=$script:ProxyAddr" }
    if ($script:ProxyUser) { $ja += "-proxyUser=$script:ProxyUser" }
    if ($script:ProxyPass) { $ja += "-proxyPassword=$script:ProxyPass" }
    $startCmd = Join-Path $DownloadDir "start-nyxbot.cmd"
    $logFile = Join-Path $DownloadDir "nyxbot.log"
    $javaBin = if ($script:JavaExe) { Quote-TaskArg $script:JavaExe } else { "java" }
    $javaCommand = "$javaBin $($ja | ForEach-Object { Quote-TaskArg $_ })"
    Set-Content -Path $startCmd -Encoding ASCII -Force -Value @(
        "@echo off",
        "cd /d $(Quote-TaskArg $DownloadDir)",
        "$javaCommand >> $(Quote-TaskArg $logFile) 2>&1"
    )
    $tr = Quote-TaskArg $startCmd

    # Create scheduled task via schtasks (works without admin for user-level tasks)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    Write-Step "Creating scheduled task / 创建计划任务..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Remove existing task first
    schtasks /delete /tn $TaskName /f 2>&1 | Out-Null

    if ($isAdmin) {
        Write-Host "  Executing: schtasks /create /tn $TaskName /tr <java command> /sc onstart /ru SYSTEM /f"
        schtasks /create /tn $TaskName /tr $tr /sc onstart /ru SYSTEM /f
        $taskOk = ($LASTEXITCODE -eq 0) -and (Test-ScheduledTaskExists)
    } else {
        Write-Host "  Executing: schtasks /create /tn $TaskName /tr <java command> /sc onlogon /f"
        schtasks /create /tn $TaskName /tr $tr /sc onlogon /f
        $taskOk = ($LASTEXITCODE -eq 0) -and (Test-ScheduledTaskExists)
    }

    if (-not $taskOk) {
        Write-Warn "  Failed to create scheduled task, starting directly / 计划任务创建失败，直接启动..."
        $proc = Start-Process -FilePath $startCmd -WorkingDirectory $DownloadDir -PassThru -WindowStyle Hidden
        if (-not (Wait-NyxBotStarted)) {
            Write-Fail "NyxBot failed to become ready / NyxBot 启动后未就绪"
        }
        Write-Success "NyxBot started / 已启动 (PID: $($proc.Id))"
    } else {
        if ($isAdmin) {
            Write-Success "  Task level: System (auto-start on boot) / 系统级(开机自启)"
        } else {
            Write-Success "  Task level: User (auto-start on logon) / 用户级(登录自启)"
        }
        schtasks /run /tn $TaskName 2>&1 | Out-Null
        if (-not (Wait-NyxBotStarted)) {
            Write-Fail "NyxBot failed to become ready / NyxBot 启动后未就绪"
        }
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
            <PasswordBox Name="TxtToken" Padding="8,6" FontSize="13" BorderBrush="#CCCCCC" BorderThickness="1" Background="White"/>
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
                <RadioButton Name="RadDocker" Content="Docker"/>
                <RadioButton Name="RadLocal" Content="Local / 本地" IsChecked="True"/>
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
    $window.FindName("TxtToken").Password = $Token
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
        if (-not $txtToken.Password.Trim()) {
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
    $script:Token = $txtToken.Password.Trim()
    if ($radClient.IsChecked) { $script:Client = $true; $script:Server = $false } else { $script:Server = $true }
    if ($txtProxy.Text.Trim()) { $script:ProxyAddr = $txtProxy.Text.Trim() }
    if ($radLocal.IsChecked) { $script:Local = $true; $script:Docker = $false } else { $script:Docker = $true; $script:Local = $false }
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

    if ((Test-WindowsServer) -and -not $script:Quiet -and -not $script:Text) {
        Write-Step "Windows Server detected, using console mode / 检测到 Windows Server，使用控制台模式"
        $script:Text = $true
    }

    # Load saved config from previous install if available
    Load-Config

    if (-not $script:Quiet -and -not $script:Text -and (Test-InstallationComplete)) {
        Show-InstalledGui
        return
    }

    # Default GUI form, --text for command line, --quiet for no interaction
    if (-not $script:Quiet -and -not $script:Text) {
        $script:IsGui = $true
        Show-GuiForm
        Save-Config
        Start-InstallGui
        return
    } else {
        if (-not $script:Quiet -and -not $script:Docker -and -not $script:Local) {
            $script:Local = $true; $script:Docker = $false
            Write-Step "Using local install by default / 默认使用本地安装"
        }

        Write-Step "Mode / 安装方式: $(if ($script:Docker) { 'Docker' } else { 'Local' })"
        Write-Step "Directory / 安装目录: $DownloadDir"
        Write-Host ""

        Get-UserConfig
        Save-Config
    }

    if ($script:Docker) { Install-DockerMode } else { Install-LocalMode }
}

Main
