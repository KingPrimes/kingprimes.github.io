---
title: NyxBot一键部署
comments: true
sticky: 0
aside: true
date: 2025-12-03 23:02:17
updated: 2026-06-02 21:00:00
tags:
  - NyxBot
  - qqbot
  - WarframeBot
categories:
  - Bots
keywords:
  - NyxBot部署文档
  - Warframe机器人
  - Warframe Bot
description: NyxBot的一键部署文档
permalink: posts/0b74998
cover: /img/0b74998/0b74998.webp
---

# NyxBot 一键部署脚本使用文档

**版本**: 4.1.0  
**更新日期**: 2026-06-02

> 💡 **只需要一分钟，会复制粘贴就能装好。不需要懂编程。**

---

## 🚀 新版统一部署脚本（推荐）

**v4.1 全新升级！** Windows 图形化窗口、无需管理员权限、自动版本检测与更新提醒、SHA256 完整性校验。

在开始之前，请先装好 **OneBot 客户端**（NapCat 或 LLOneBot），它是让机器人连上 QQ 的软件。
> 不会装？看这里 → [NyxBot 手把手部署教程](https://kingprimes.top/posts/d99b802)

---

### 💻 Windows（最多人用的系统）

**第一步：下载脚本**

打开 **PowerShell**（在开始菜单搜索就行，普通运行即可，不需要管理员），输入：

```powershell
Invoke-WebRequest -Uri "https://kingprimes.top/script/nyxbot-deploy.ps1" -OutFile "nyxbot-deploy.ps1"
```

> 如果提示"无法加载文件"或"禁止执行脚本"，先输入这行再试：
> `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

**第二步：运行脚本**

```powershell
.\nyxbot-deploy.ps1
```

会弹出一个**图形化窗口**，填好配置就能一键安装：

```
┌─────────────────────────────────┐
│ NyxBot One-Click Deploy      X │
├─────────────────────────────────┤
│ Port / 端口    [8080    ]      │  ← 端口号，不改就用 8080
│ Token *        [        ]      │  ← OneBot Token，必填！
│ Mode / 模式   ○Server ○Client  │  ← 选 Server（默认就行）
│ Proxy / 代理   [        ]      │  ← 没有代理就空着
│ Install / 安装 ○Docker ○Local  │  ← 推荐 Docker，没有就 Local
├─────────────────────────────────┤
│ NyxBot: Running / 运行中        │  ← 安装后会显示运行状态
│ Task:    Active / 已注册        │  ← 开机自启状态
│ [停止] [移除计划任务]           │  ← 管理按钮
├─────────────────────────────────┤
│         [取消] [开始安装]        │
└─────────────────────────────────┘
```

- **Token** 是唯一必须填的（在 NapCat / LLOneBot 里能看到）
- **其他选项**保持默认就行，什么都不用改
- 填好 Token，点 **Deploy / 开始安装**，等着就行

脚本会自动：测速选最快线路 → 下载 → 校验文件完整性 → 创建计划任务 → 启动 NyxBot。

安装完成后打开浏览器访问 `http://localhost:8080`，看到 NyxBot 管理页面就是成功了。

> 💡 **不需要管理员权限！** 脚本会尝试创建计划任务（开机自启），如果没有管理员权限会自动降级为用户级任务，一样能开机自启。即使计划任务创建失败，也会直接启动 NyxBot，不影响使用。

---

#### 📌 已经装过了？再跑一次就行

再次运行脚本，窗口会自动检测：

- **版本已是最新** → 跳过下载，直接启动（几秒钟就好）
- **发现新版本** → 弹出更新提示，选"是"更新，选"否"继续用旧版
- 上次填的 Token、端口等配置会自动预填，不用重新输入

窗口下方有实用的管理按钮：

| 按钮 | 作用 |
|------|------|
| **Stop / 停止** | 停止正在运行的 NyxBot，同时移除计划任务防止自动重启 |
| **Remove Task / 移除计划任务** | 仅移除开机自启，不影响当前运行 |

---

#### 📌 命令行模式（没有图形界面时用）

```powershell
.\nyxbot-deploy.ps1 -Text     # 命令行问答模式
```

如果环境不支持图形窗口（如远程 SSH），加 `-Text` 参数就会用传统的命令行问答方式来安装。

**其他参数**：

```powershell
.\nyxbot-deploy.ps1 -Docker -Quiet -Token 你的Token      # 静默 Docker（不弹窗不提问）
.\nyxbot-deploy.ps1 -Local -Port 9090 -Token 你的Token    # 本地安装 + 自定义端口
.\nyxbot-deploy.ps1 -Help                                 # 查看所有参数说明
```

---

### 🐧 Linux / macOS

**一步到位（复制粘贴就完事）**：

```bash
curl -fsSL https://kingprimes.top/script/nyxbot-deploy.sh | bash
```

脚本会自动检测你的系统、安装 Java（没有的话）、测速选最快下载路线、下载 NyxBot、弹出配置表单。

**不喜欢管道？手动下载**：

```bash
curl -O https://kingprimes.top/script/nyxbot-deploy.sh
chmod +x nyxbot-deploy.sh
./nyxbot-deploy.sh
```

**常用玩法**：

```bash
./nyxbot-deploy.sh                          # 交互式部署
./nyxbot-deploy.sh --docker                 # 强制 Docker 容器部署
./nyxbot-deploy.sh --local                  # 强制本地 JAR 部署
./nyxbot-deploy.sh --tui                    # TUI 可视化表单（SSH 友好）
./nyxbot-deploy.sh --quiet --token=xxx      # 静默部署（不提问）
```

---

### 新版特性

| 特性 | 说明 |
|------|------|
| 🖥️ **Windows 图形化窗口** | 可视化表单填写配置，不需要记命令，一看就会 |
| 🔍 **自动版本检测** | 已安装时自动跳过下载，发现新版本弹窗提醒 |
| 🔐 **SHA256 完整性校验** | 下载后自动验证文件哈希值，确保文件没损坏 |
| 🛑 **一键停止** | 图形窗口内直接停止 NyxBot、管理计划任务 |
| 📝 **配置自动保存** | Token、端口等配置自动记忆，再跑脚本不用重新填 |
| 🐳 **Docker 部署** | 自动检测 Docker，优先容器安装，国内镜像源自动切换 |
| 📊 **TUI 可视化** | 基于 dialog 的表单交互（SSH 终端友好） |
| 📶 **网络测速** | 9 个 GitHub 代理 + 直连实时并行测速，自动选最快 |
| 🤖 **静默模式** | `--quiet --token=xxx` 一行部署，适合 CI/CD |
| 💻 **Linux/macOS 合一** | 一个脚本覆盖两大系统，自动识别 |
| 🔒 **智能降级** | Docker 不可用自动切换到本地安装，管理员权限缺失自动降级 |

### 安装后输出示例

**Windows**：

```
========================================
  NyxBot Deploy v1.0.0
  NyxBot 一键部署脚本
========================================

[+] System / 系统: Windows Windows 10 专业版 (x64)
[+] Java 21 : installed / 已安装
[>] Network speed test / 网络测速 (parallel / 并行)...
  Testing 9 proxies / 正在测试 9 个代理......
[+] Best / 最快: https://gh-proxy.com (48.8 KB/s)
[>] Get latest version / 获取最新版本...
[+] Version / 版本: v2.1.5
[>] Downloading NyxBot v2.1.5 / 正在下载...
  File size / 文件大小: 165.2 MB
  Testing Range support with chunk 0 / 使用首个分块测试 Range 支持...
[+]   Range supported, downloading remaining chunks...
  Chunk 1/3 / 分块 1/3... Done / 完成
  Chunk 2/3 / 分块 2/3... Done / 完成
  Chunk 3/3 / 分块 3/3... Done / 完成
  Assembling & verifying / 正在合并并校验... Done / 完成
[+] Download complete / 下载完成 (165.2 MB)
  Verifying SHA256 / 正在校验完整性... OK / 通过
[>] Creating scheduled task / 创建计划任务...
[+]   Task level: User (auto-start on logon) / 用户级(登录自启)
[+] NyxBot started / 已启动 (task: NyxBot)

+------------------------------------------+
|  NyxBot Installed / NyxBot 安装完成!      |
+------------------------------------------+
  Dashboard / 管理页面: http://localhost:8080
  Data / 数据目录: <当前目录>\NyxBot
  Status / 状态: Get-ScheduledTask 'NyxBot'
```

**Linux / macOS**：

```
[✔] 系统: Ubuntu 22.04 x86_64
[✔] Java 21: 已安装
[✔] Docker: 已安装 (v26.1.0)
[>] 安装方式: Docker 容器模式
[>] 数据目录: /home/nyxbot/NyxBot (映射至容器 /app/data)

┌──────────────────────────────────────────┐
│        NyxBot 安装完成！                   │
├──────────────────────────────────────────┤
│  管理页面: http://localhost:8080           │
│  查看日志: docker logs -f nyxbot          │
│  重启:     docker restart nyxbot          │
└──────────────────────────────────────────┘
```

---

## 安装后如何管理

### Windows

**推荐方式：重新运行部署脚本**，图形窗口会显示 NyxBot 运行状态，可以一键停止或管理计划任务。

**手动方式：**

```powershell
# 查看计划任务状态
Get-ScheduledTask -TaskName "NyxBot"

# 手动启动
Start-ScheduledTask -TaskName "NyxBot"

# 手动停止（停掉 java 进程）
Get-Process -Name "java" | Where-Object { $_.CommandLine -like "*NyxBot.jar*" } | Stop-Process

# 移除计划任务（不再开机自启）
Unregister-ScheduledTask -TaskName "NyxBot" -Confirm:$false
```

### Linux / macOS

```bash
# Docker 模式
docker logs -f nyxbot          # 看日志
docker restart nyxbot          # 重启

# 本地 systemd (Linux)
systemctl status nyxbot        # 看状态
systemctl restart nyxbot       # 重启

# 本地 nohup (macOS / 无 systemd 的 Linux)
tail -f ./NyxBot/nyxbot.log
```

---

## 常见问题

### Q1: PowerShell 报错"禁止执行脚本"

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

输入这行，然后重新运行脚本。

### Q2: 脚本说找不到 Java 怎么办

脚本会自动帮你装 Java 21。如果自动安装失败了：

- **Ubuntu/Debian**：`sudo apt install openjdk-21-jre-headless -y`
- **CentOS/Fedora**：`sudo dnf install java-21-openjdk-headless -y`
- **macOS**：`brew install openjdk@21`
- **Windows**：去 [Oracle](https://www.oracle.com/java/technologies/downloads/#java21) 下载安装包双击安装

装完再跑一次脚本。

### Q3: 国内网络下载太慢

脚本内置了 8 个 GitHub 加速源（ghfast.top、gh-proxy.com 等），会自动测速选最快的。如果你发现还是慢：

1. 手动去 [GitHub Releases](https://github.com/KingPrimes/NyxBot/releases) 下载 `NyxBot.jar`
2. 放到脚本同级目录下的 `NyxBot/` 文件夹里
3. 运行脚本时选本地安装模式

### Q4: Docker Hub 拉不下镜像

脚本内置了 3 个国内 Docker 镜像源，会自动切换。你也可以手动拉：

```bash
docker pull docker.1panel.live/kingprimes/nyxbot:latest
docker tag docker.1panel.live/kingprimes/nyxbot:latest kingprimes/nyxbot:latest
```

### Q5: 怎么改端口？

**Windows**：再跑一次 `.\nyxbot-deploy.ps1`，窗口里的 Port 改成你想要的端口号，点开始安装就行。脚本会自动更新计划任务。

**Linux / macOS**：

```bash
# 启动时指定
./nyxbot-deploy.sh --port=9090

# 已经装了？Docker 模式重跑容器：
docker rm -f nyxbot
docker run --name nyxbot -d -p 9090:8080 kingprimes/nyxbot:latest
```

## 第三方脚本支持

- 除了官方提供的部署脚本外，我们还支持由社区维护的第三方部署脚本。

### nyxbot-linux-D_R.run

**来源**: [FreeStar007/NyxGo](https://github.com/FreeStar007/NyxGo)

基于 Python 的可视化部署脚本，提供更友好的交互界面。

- ✅ 基于 Python 实现，提供更友好的交互界面
- ✅ 自动检测系统环境并安装依赖
- ✅ 支持多种 OneBot 实现的自动安装
- ✅ 内置 Python 虚拟环境，不影响系统 Python
- ✅ 包含可视化的部署进度和状态显示
- ✅ Linux 系统 (Debian/Ubuntu, RHEL/CentOS, Arch 等)

<details open>
  <summary>教程视频</summary>
  <div style="position:relative; padding-bottom:75%; width:100%; height:0">
      <iframe src="//player.bilibili.com/player.html?bvid=BV1Z527BfEB5&page=1&autoplay=0" scrolling="no" border="0" frameborder="no" framespacing="0" allowfullscreen="true" style="position:absolute; height: 100%; width: 100%;"></iframe>
  </div>
</details>

> 第三方脚本的问题请直接向原作者反馈：[GitHub Issues](https://github.com/FreeStar007/NyxGo/issues)

---

## 贡献与反馈

如果您遇到问题，请提供以下信息：

1. **操作系统**: `uname -a`（Linux/macOS）或在 Windows 设置中查看
2. **Java 版本**: `java -version`
3. **NyxBot 版本**：在你下载时看到的版本号
4. **错误截图**: 如果有的话

- GitHub Issues: https://github.com/KingPrimes/NyxBot/issues
- QQ 群: [点击加群](https://jq.qq.com/?_wv=1027&k=RgqgJLij)

---

## 附录

### 脚本文件

```
nyxbot-deploy.sh        # Linux / macOS 统一脚本（推荐）
nyxbot-deploy.ps1       # Windows PowerShell 脚本（推荐）
```

> 旧版 `nyxbot-linux.sh` / `nyxbot-macos.sh` / `nyxbot-windows.ps1` 在服务器保留可用，但推荐使用新版。

### 常用命令

```bash
# 交互式部署
./nyxbot-deploy.sh

# Docker 容器
./nyxbot-deploy.sh --docker

# 本地 JAR
./nyxbot-deploy.sh --local

# 静默（不提问）
./nyxbot-deploy.sh --quiet --token=xxx --port=9090

# 管理
systemctl status nyxbot               # Linux 服务状态
docker logs -f nyxbot                 # Docker 日志
tail -f ./NyxBot/nyxbot.log     # 本地日志
```

### 相关链接

- **NyxBot 项目**: https://github.com/KingPrimes/NyxBot
- **Docker 镜像**: https://hub.docker.com/r/kingprimes/nyxbot
- **手动部署教程**: https://kingprimes.top/posts/d99b802

---

**文档版本**: v4.1.0  
**最后更新**: 2026-06-02
**维护者**: KingPrimes
