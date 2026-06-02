---
title: NyxBot一键部署
comments: true
sticky: 0
aside: true
date: 2025-12-03 23:02:17
updated: 2025-12-03 23:02:17
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

**版本**: 4.0.0  
**更新日期**: 2025-06-02

> 💡 **只需要一分钟，会复制粘贴就能装好。不需要懂编程。**

---

## 🚀 新版统一部署脚本（推荐）

**v4.0 全新升级！** 新增 Docker 容器部署、TUI 可视化表单、静默安装模式、国内镜像源自动切换。

在开始之前，请先装好 **OneBot 客户端**（NapCat 或 LLOneBot），它是让机器人连上 QQ 的软件。
> 不会装？看这里 → [NyxBot 手把手部署教程](https://kingprimes.top/posts/d99b802)

---

### 💻 Windows（最多人用的系统）

**第一步：下载脚本**

在开始菜单搜索 **PowerShell**，右键 → 以管理员身份运行。然后输入：

```powershell
Invoke-WebRequest -Uri "https://kingprimes.top/script/nyxbot-deploy.ps1" -OutFile "nyxbot-deploy.ps1"
```

> 如果提示"无法加载文件"或"禁止执行脚本"，先输入这行再试：
> `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

**第二步：运行脚本**

```powershell
.\nyxbot-deploy.ps1
```

脚本会一步步问你：端口（直接回车用默认 8080）、Token（必填）、通讯模式（选 1 服务端）。填完自动下载并启动。

安装后打开浏览器访问 `http://localhost:8080`，看到 NyxBot 管理页面就是成功了。

**其他玩法**：

```powershell
.\nyxbot-deploy.ps1 -Docker -Quiet -Token 你的Token      # 静默 Docker
.\nyxbot-deploy.ps1 -Local -Port 9090 -Token 你的Token    # 本地安装
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
| 🐳 **Docker 部署** | 自动检测 Docker，优先容器安装，国内镜像源自动切换 |
| 📊 **TUI 可视化** | 基于 dialog 的表单交互（SSH 终端友好） |
| 📶 **网络测速** | 8 个 GitHub 代理 + 直连实时测速，自动选最快 |
| 📦 **curl -# 进度条** | 下载进度实时显示（速度 + 剩余时间） |
| 🤖 **静默模式** | `--quiet --token=xxx` 一行部署，适合 CI/CD |
| 💻 **Linux/macOS 合一** | 一个脚本覆盖两大系统，自动识别 |
| 🔒 **智能降级** | Docker 不可用自动切换到本地安装 |

### 安装后输出示例

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

**文档版本**: v4.0.0  
**最后更新**: 2025-06-02  
**维护者**: KingPrimes
