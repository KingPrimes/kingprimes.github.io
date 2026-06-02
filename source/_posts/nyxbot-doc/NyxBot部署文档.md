---
# 标题
title: NyxBot部署文档
# 描述
description: NyxBot的部署文档
# 发布日期
date: 2024-12-08T22:41:08+08:00
# 永久链接
permalink: posts/d99b802
# 是否为草稿
draft: false
# 文章关键字
keywords:
  - NyxBot部署文档
  - Warframe机器人
  - Warframe Bot
# 是否开启评论
comment: true
# 文章置顶(数值越大置顶优先级越大)
sticky: 0
# 文章标签
tags:
  - qqbot
  - NyxBot
  - WarframeBot
# 文章分类
categories:
  - Bots
# 文章摘要
summary: NyxBot的部署文档,从零开始手把手教你部署 Warframe QQ 机器人。
# 封面
cover: /img/d99b802/d99b802_featured.webp
---

## 🚀 新手请看这里

**如果你不想折腾，只想快速搞定**：直接用一键部署脚本，输入一行命令，脚本帮你自动完成下载、安装、启动。

👉 [NyxBot 一键部署教程](https://kingprimes.top/posts/0b74998)

```bash
# Linux / macOS — 复制这行命令到终端，回车即可
curl -fsSL https://kingprimes.top/script/nyxbot-deploy.sh | bash
```

> 一键脚本支持 Docker 容器部署（推荐）、本地部署、TUI 可视化表单。**本文是手动部署教程**，适合想了解每一步细节的用户。

---

## 在开始之前

NyxBot 是一个 QQ 机器人，它不能直接登录 QQ。你需要两样东西配合工作：

```
你的 QQ 号 → [OneBot 客户端] → (WebSocket) → [NyxBot]
                      ↑                            ↑
               帮你连 QQ 的服务               Warframe 查询机器人
```

| 你需要准备的 | 是什么 | 在哪里下载 |
|-------------|--------|-----------|
| **OneBot 客户端** | 一个软件，负责让你的 QQ 号能接收机器人命令 | 下面有表格 |
| **Java 21** | NyxBot 运行需要的环境（就像玩 Java 版 MC 需要装 Java） | [Oracle Java21](https://www.oracle.com/java/technologies/downloads/#java21) |
| **NyxBot.jar** | 机器人主程序 | [GitHub Releases](https://github.com/KingPrimes/NyxBot/releases) |

---

## OneBot客户端

选择一个安装即可。**推荐 NapCat 或 LLOneBot**（用的人最多，教程最全）。

| 项目名称 | 一句话介绍 | 教程链接 |
|----------|-----------|----------|
| LLOneBot | 装在 NTQQ 里的插件，Windows 新手首选 | [快速开始](https://llob.napneko.com/zh-CN/guide/getting-started) |
| NapCat | 功能最强，Windows/Linux 都能用 | [快速开始](https://napneko.github.io/guide/start-install) |
| Lagrange | 纯 C# 实现，轻量 | [使用手册](https://lagrangedev.github.io/Lagrange.Doc/) |
| Gensokyo | Go 语言实现 | [GitHub](https://github.com/Hoshinonyaruko/Gensokyo) |
| OneBots | 多账号管理 | [文档](https://docs.onebots.org/) |

**必须记住的关键信息**：不管选哪个 OneBot 客户端，最后都要配置一个地址让它连接 NyxBot：

```
ws://localhost:8080/ws/shiro   ← 同一台电脑用这个
ws://你的IP:8080/ws/shiro      ← 不同电脑用这个（换成实际 IP）
```

---

## 💻 Windows 手动部署（手把手）

### 第一步：安装 OneBot 客户端

这里以 **LLOneBot** 为例（最简单，适合新手）：

1. 打开你的 QQ（Windows 版 NTQQ）
2. 在 QQ 主界面搜索"LLOneBot"，按照它的[安装教程](https://llob.napneko.com/zh-CN/guide/getting-started)装好
3. 装好后，打开 QQ 设置 → 找到 LLOneBot → 按下面配置：

   | 配置项 | 值 |
   |--------|-----|
   | 连接方式 | **反向WebSocket** |
   | 监听地址 | `ws://localhost:8080/ws/shiro` |

4. 如果你把 NyxBot 装在了另一台电脑上，把 `localhost` 换成那台电脑的 IP 地址，例如 `ws://192.168.1.5:8080/ws/shiro`

### 第二步：安装 Java 21

> 为什么要装 Java？NyxBot 是用 Java 写的，没有 Java 环境它跑不起来。就像你要玩 Minecraft 也得先装 Java。

1. 打开 Oracle Java 下载页：https://www.oracle.com/java/technologies/downloads/#java21
2. 选择 **Windows** 标签
3. 点击 **x64 Installer**（后缀是 `.exe`）下载
4. 双击下载好的 `.exe` 文件，一路点"下一步"完成安装
5. 验证安装成功：按 `Win + R`，输入 `cmd` 回车，在弹出的黑色窗口输入：

   ```
   java -version
   ```

   如果看到 `openjdk version "21"` 开头的字，说明装好了。如果提示"java 不是内部命令"，说明没装上，重新装一次。

### 第三步：下载 NyxBot

1. 打开 https://github.com/KingPrimes/NyxBot/releases
2. 找到带有绿色 **Latest** 标签的版本（最新的）
3. 在"Assets"里找到 `NyxBot.jar`，点击下载
4. 下载完成后，**新建一个空的文件夹**（比如在桌面建一个叫 `NyxBot` 的文件夹）
5. 把 `NyxBot.jar` 移动到刚建的空文件夹里

### 第四步：启动 NyxBot

1. 进入 `NyxBot.jar` 所在的文件夹
2. 在文件夹空白处 **右键 → 新建 → 文本文档**
3. 把新建的文件重命名为 `run.bat`
   > ⚠️ **新手常见错误**：文件名变成了 `run.bat.txt` ？因为你没开"显示文件扩展名"。
   > 打开任意文件夹 → 顶部菜单栏"查看" → 勾选"文件扩展名" → 然后再重命名。
4. 右键 `run.bat` → 编辑，粘贴下面这行：

   ```
   java -jar NyxBot.jar
   ```

5. 如果你需要挂代理（翻墙软件），改成：

   ```
   java -Dhttp.proxy=http://127.0.0.1:7890 -jar NyxBot.jar
   ```

   > `127.0.0.1:7890` 是你代理软件（Clash/V2Ray 等）的地址，根据你实际情况改。

6. 保存文件，双击 `run.bat` 运行
7. 看到黑色窗口出现日志输出，说明启动成功了！别关这个窗口，关了机器人就停了
8. 打开浏览器输入 http://localhost:8080 ，看到 NyxBot 管理页面就是成功了

### 第五步：检查 OneBot 连接

回到 QQ 的 LLOneBot 设置，查看状态是否为"已连接"。如果显示"连接中"或"断开"：

- 确认 NyxBot 是否在运行（黑色窗口没关）
- 确认地址是否写对了（`ws://localhost:8080/ws/shiro`）
- 查看黑色窗口里有没有报错

---

## 🐧 Linux 手动部署（以 Ubuntu 24.04 为例）

> 如果你用的不是 Ubuntu，也没关系。主要区别在于"安装 Java"那一步用的命令不同。CentOS/Fedora 用 `dnf`，Alpine 用 `apk`。不会的话在 QQ 群里问。

### 第一步：安装 OneBot 客户端（NapCat）

1. 打开终端（SSH 连上你的服务器，或直接在桌面右键打开终端）
2. 运行 NapCat 一键安装命令：

   ```bash
   curl -o napcat.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh && sudo bash napcat.sh
   ```

3. 它会问你要不要用 Docker、要不要装 TUI。**第一次用不需要改任何选项，一直回车选默认就行**
4. 安装完成后，进入 NapCat 的配置目录：

   ```bash
   cd /opt/QQ/resources/app/app_launcher/napcat/config
   ```

5. 修改配置文件 `webui.json`：

   ```bash
   nano webui.json
   ```

   > `nano` 是一个简单的文本编辑器。进入后按方向键移动光标，改完后按 `Ctrl+X` 退出，按 `Y` 保存，回车确认。

6. 把内容改成这样（重点是改 `token`，不能让它空着）：

   ```json
   {
     "host": "0.0.0.0",
     "port": 6099,
     "prefix": "",
     "token": "你自己设一个密码比如nyxbot123",
     "loginRate": 3
   }
   ```

7. 启动 NapCat（把 `你的QQ号` 换成实际的）：

   ```bash
   napcat start 你的QQ号
   ```

8. 访问 NapCat 网页管理面板：`http://你的服务器IP:6099/webui`
9. 输入刚设的 `token` 登录
10. 点"QR"获取二维码 → 用手机 QQ 扫码登录
11. 登录后，点"网络设置" → 添加一个新的网络配置：

    | 配置项 | 值 |
    |--------|-----|
    | 类型 | **WebSocket 客户端** |
    | URL | `ws://localhost:8080/ws/shiro` |
    | 启用 | ✅ 打勾 |

    ![NapcatWebConfig.webp](/img/d99b802/NapcatWebConfig.webp)

### 第二步：安装 Java 21

在终端里输入：

```bash
sudo apt update
sudo apt install openjdk-21-jre-headless -y
```

> 这行命令做了两件事：
> 1. `sudo apt update` — 更新软件包列表
> 2. `sudo apt install openjdk-21-jre-headless -y` — 安装 Java 21 运行环境

验证安装：

```bash
java -version
```

你应该看到类似输出：
```
openjdk version "21.0.x" 2024-xx-xx
```

如果提示找不到 `java` 命令，说明没装上。换一条命令试试：

```bash
sudo apt install openjdk-21-jre -y
```

### 第三步：下载并启动 NyxBot

逐条复制运行以下命令（一条一条来，等每条执行完再执行下一条）：

```bash
# 1. 创建一个文件夹放机器人
mkdir ~/nyxbot
cd ~/nyxbot

# 2. 下载最新版 NyxBot（去 https://github.com/KingPrimes/NyxBot/releases 看最新版本号，替换下面命令里的版本号）
wget https://github.com/KingPrimes/NyxBot/releases/download/v2.1.5/NyxBot.jar -O NyxBot.jar

# 3. 后台启动（关闭终端也不会停）
nohup java -jar NyxBot.jar > nyxbot.log 2>&1 &

# 4. 检查是否启动成功
tail -f nyxbot.log
```

> `nohup` 的意思是"no hang up"——即使你关了终端窗口程序也不会停。
> 第 4 条里的 `tail -f` 会实时显示日志，看到管理页面地址输出就说明成功了。按 `Ctrl+C` 可以退出日志查看（不会停止程序）。

打开浏览器访问 `http://你的服务器IP:8080`，看到 NyxBot 管理页面即成功。

### 第四步：检查 OneBot 连接

回到 NapCat 网页管理 → 网络设置，看刚配的 WebSocket 客户端状态是否为"已连接"。如果显示"断开"：

- 确认 NyxBot 是否在运行：`ps -ef | grep NyxBot`，如果只显示一条 `grep` 的结果，说明没运行
- 确认地址格式：`ws://localhost:8080/ws/shiro`（不要漏了 `ws://`、`/ws/shiro` 末尾没有斜杠）

---

## 🐳 NyxBot Docker 部署（最简单）

Docker 部署的好处：不需要装 Java、不需要手动下载文件、一键启动。

> **推荐**：用 [一键部署脚本](https://kingprimes.top/posts/0b74998) `nyxbot-deploy.sh --docker`，会自动帮你输入下面这些命令。

### 如果你装了 Docker

先确认 Docker 已安装（运行 `docker --version` 确认），然后选以下任一种方式：

**方式一：一行命令启动（傻瓜式）**

```bash
docker run --name nyxbot -d --restart unless-stopped \
  -p 8080:8080 \
  -e SHIRO_TOKEN=你的Token \
  -v ./nyxbot_data:/app/data \
  kingprimes/nyxbot:latest
```

> 把 `你的Token` 换成 OneBot 客户端里配的 Token。没配 Token 可以不写这一行。

启动后访问 `http://你的服务器IP:8080`

**方式二：docker compose（推荐，方便改配置）**

```bash
# 下载 compose 文件
wget https://raw.githubusercontent.com/KingPrimes/NyxBot/main/docker-compose.yml

# 创建 .env 文件（把所有配置写在这里）
echo 'SHIRO_TOKEN=你的Token' > .env
echo 'SERVER_PORT=8080' >> .env

# 启动
docker compose up -d
```

### 如果你在中国大陆，Docker Hub 可能连不上

试试国内镜像（不用改任何 Docker 配置，直接用）：

```bash
# 方法 1：直接从镜像源拉取
docker pull docker.1panel.live/kingprimes/nyxbot:latest

# 方法 2：换个镜像源
docker pull docker.m.daocloud.io/kingprimes/nyxbot:latest

# 如果都拉不下来，去 QQ 群问
```

> 💡 镜像同时支持 **Intel/AMD** 和 **Apple Silicon (M 系列芯片)**。可以锁定版本如 `v2.1` 或 `v2.1.5`。

### 如果你连 Docker 都不会装

**Ubuntu**（一步到位）：

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# 退出重新登录，Docker 就好了
```

**Windows/Mac**：直接去 https://www.docker.com/products/docker-desktop 下载安装包，双击安装。

---

## 📱 NyxBot 安卓部署方式

> 安卓部署需要在手机上装一个叫 Termux 的终端模拟器 App。

1. 下载并安装 [ZeroTermux App](https://github.com/hanxinhao000/ZeroTermux)
2. 打开 ZeroTermux，逐条输入（一条一条来）：

   ```bash
   pkg update && pkg upgrade
   pkg install proot-distro
   proot-distro install ubuntu
   pkg install screen
   screen -S nyxbot proot-distro login ubuntu
   ```

3. 进入 Ubuntu 环境后，回到上面 [Linux 部署方式](#🐧-linux-手动部署以为-ubuntu-2404-为例)，从 Java 安装那一步开始做

> 安卓部署比较折腾，如果搞不定建议直接用 Docker 或者在电脑上跑。

---

## 📦 NyxBot 自己打包 JAR（Fork 用户）

> 这一节给想自己改代码、自己打包的开发者看的。普通用户**不需要**看。

1. 登录 GitHub → 打开 [NyxBot 仓库](https://github.com/KingPrimes/NyxBot)
2. 点击右上角 **Fork 按钮**
3. 等待 Fork 完成后，到你自己的仓库里
4. 点击 **Actions** 标签页 → 选择 **Build For Release**
5. 点击 **Run workflow** → 输入要构建的分支名（默认 `main`）→ 点击 Run
6. 等待约 10 分钟构建完成
7. 构建成功后在你的仓库 Release 页面下载 `NyxBot.jar`

   ![Fork 教程](/img/d99b802/d99b802_1.webp)
   ![Fork 教程](/img/d99b802/d99b802_2.webp)
   ![Fork 教程](/img/d99b802/d99b802_3.webp)
   ![Fork 教程](/img/d99b802/d99b802_4.webp)
   ![Fork 教程](/img/d99b802/d99b802_5.webp)

---

## ⚠️ 常见问题 & 排查

### 端口被占用

如果启动时报错 `Port 8080 was already in use`，说明 8080 端口被其他程序占了。

改一个端口启动即可：

```bash
# 改成 9090 端口
java -jar NyxBot.jar -serverPort=9090
```

然后管理页面地址也相应变成 `http://localhost:9090`

![端口占用错误](/img/d99b802/port_error.webp)

### OneBot 连不上

| 现象 | 可能原因 | 解决方法 |
|------|----------|----------|
| OneBot 显示"连接中"不通 | NyxBot 没启动 | 确认 NyxBot 是否在运行 |
| OneBot 显示"连接中"不通 | 地址填错 | 检查是不是 `ws://localhost:8080/ws/shiro` |
| OneBot 连上后立刻断开 | NyxBot 认不到消息格式 | 检查 OneBot 客户端是不是"反向 WebSocket"模式 |

### 国内下载太慢

用一键部署脚本——它会自动测速找最快的代理下载。

---

## 💬 获取帮助

- **QQ 群**：[点击加群](https://jq.qq.com/?_wv=1027&k=RgqgJLij)
- **GitHub Issues**：https://github.com/KingPrimes/NyxBot/issues
- **提交 Issue 时请附上**：操作系统、Java 版本、错误日志截图
