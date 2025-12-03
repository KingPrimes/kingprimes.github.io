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
cover: https://origin.picgo.net/2025/11/30/c8c1d2874b419efa149f64b.webp
---

# NyxBot 一键部署脚本使用文档

**版本**: 2.0.0  
**更新日期**: 2025-12-03

---

## 简介

NyxBot 一键部署脚本是一套跨平台自动化部署工具，支持 **Linux**、**macOS** 和 **Windows** 三大操作系统。脚本能够自动完成 JDK 21 环境配置、NyxBot 最新版本下载、OneBot 协议实现引导以及程序启动等全部流程，让您无需手动配置即可快速部署 NyxBot。

### 适用对象

- 🎯 首次部署 NyxBot 的用户
- 🔄 需要更新 NyxBot 版本的用户
- 🚀 希望简化部署流程的服务器管理员
- 💻 多平台部署需求的开发者

---

## 功能特性

### 🎉 核心功能

1. **自动环境检测与安装**

   - 自动检测并安装 JDK 21（OpenJDK）
   - 支持多种包管理器（apt、yum、dnf、pacman、apk、Homebrew、winget、Chocolatey）
   - 智能识别操作系统和架构（x86_64、ARM64）

2. **智能网络优化**

   - 内置 10+ 个 GitHub 代理服务器
   - 自动测速并选择最快的代理
   - 支持手动指定代理或直连
   - 下载失败自动重试机制

3. **安全可靠**

   - SHA256 文件完整性校验
   - 下载前自动备份旧版本
   - 失败时自动恢复备份
   - JAR 文件有效性验证

4. **版本管理**

   - 自动检测本地版本
   - 仅在有新版本时下载
   - 支持强制更新模式
   - 版本信息持久化保存

5. **OneBot 协议引导**

   - 交互式安装向导
   - 支持 LLOneBot 和 NapCatQQ
   - 详细的安装步骤说明
   - 自动打开官方文档

6. **完善的日志系统**
   - 彩色终端输出
   - 详细的操作日志记录
   - 错误追踪与诊断
   - 时间戳标记

---

## 系统要求

### Linux

- **发行版**: Ubuntu 18.04+、Debian 10+、CentOS 7+、Fedora 30+、Arch Linux、Alpine Linux
- **架构**: x86_64、ARM64
- **权限**: 需要 sudo 权限（安装 JDK 时）
- **工具**: curl、bash 4.0+

### macOS

- **版本**: macOS 10.14 (Mojave) 或更高
- **架构**: Intel x86_64、Apple Silicon (M1/M2/M3)
- **工具**: curl、bash 4.0+
- **可选**: Homebrew（脚本可自动安装）

### Windows

- **版本**: Windows 10 1809+ 或 Windows 11
- **架构**: x86_64、ARM64
- **PowerShell**: 5.1 或更高
- **可选**: winget 或 Chocolatey（用于自动安装 JDK）

---

## 前置条件

### 必需条件

1. **网络连接**: 需要能够访问 GitHub API 和下载资源
2. **存储空间**: 至少 500 MB 可用空间
3. **OneBot 实现**: 需要事先安装 LLOneBot 或 NapCatQQ（脚本会引导安装）

### 可选条件

1. **JDK 21**: 如已安装可使用 `--skip-java` 跳过检测
2. **代理工具**: 如果 GitHub 访问困难，脚本会自动选择代理
3. **包管理器**: 用于自动安装 JDK（Linux: apt/yum/dnf, macOS: Homebrew, Windows: winget/choco）

---

## 快速开始

### Linux 系统

#### 1. 下载脚本

```bash
# 方法一：使用 curl
curl -O https://kingprimes.top/script/nyxbot-linux.sh

# 方法二：使用 wget
wget https://kingprimes.top/script/nyxbot-linux.sh
```

#### 2. 添加执行权限

```bash
chmod +x nyxbot-linux.sh
```

#### 3. 运行脚本

```bash
# 标准方式运行
./nyxbot-linux.sh

# 或使用 bash 运行
bash nyxbot-linux.sh
```

#### 示例输出

```
=== NyxBot启动脚本(Linux) v2.0.0 ===
[INFO] 检查JDK 21环境...
[SUCCESS] JDK 21已安装
[INFO] 检查 OneBot 协议实现...
[INFO] 开始 GitHub 代理网络测试...
[INFO] 测速: 直连 - 2 MB/s
[SUCCESS] 将使用最快的代理: https://ghfast.top
[INFO] 获取最新release信息...
[SUCCESS] 找到最新构建: NyxBot-v1.2.3.jar (版本: v1.2.3)
[INFO] 下载 NyxBot.jar...
[SUCCESS] NyxBot.jar 下载完成
[SUCCESS] SHA256校验通过
[INFO] 启动 NyxBot...
```

---

### macOS 系统

#### 1. 下载脚本

```bash
# 使用 curl 下载
curl -O https://kingprimes.top/script/nyxbot-macos.sh
```

#### 2. 添加执行权限

```bash
chmod +x nyxbot-macos.sh
```

#### 3. 运行脚本

```bash
./nyxbot-macos.sh
```

#### 首次运行注意事项

- 如果 macOS 提示"无法验证开发者"，请前往 **系统偏好设置 > 安全性与隐私 > 通用**，点击"仍要打开"
- 脚本可能会要求输入管理员密码（用于安装 Homebrew 和 JDK）
- Apple Silicon (M1/M2/M3) Mac 会自动配置 ARM64 架构的 JDK

---

### Windows 系统

#### 1. 下载脚本

**方法一：使用浏览器**

- 访问: `https://kingprimes.top/script/nyxbot-windows.ps1`
- 右键 > 另存为 `nyxbot-windows.ps1`

**方法二：使用 PowerShell**

```powershell
Invoke-WebRequest -Uri "https://kingprimes.top/script/nyxbot-windows.ps1" -OutFile "nyxbot-windows.ps1"
```

#### 2. 设置执行策略（首次运行）

以**管理员身份**打开 PowerShell，执行：

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### 3. 运行脚本

**方法一：右键运行**

- 右键点击 `nyxbot-windows.ps1`
- 选择"使用 PowerShell 运行"

**方法二：PowerShell 命令行**

```powershell
.\nyxbot-windows.ps1
```

#### Windows Defender 注意事项

如果 Windows Defender 阻止脚本运行：

1. 点击"更多信息"
2. 选择"仍要运行"
3. 或将脚本添加到排除项

---

## 命令行参数

### Linux / macOS 参数

| 参数             | 说明                              | 示例                               |
| ---------------- | --------------------------------- | ---------------------------------- |
| `--force-update` | 强制重新下载最新版本              | `./nyxbot-linux.sh --force-update` |
| `--skip-java`    | 跳过 Java 环境检查和安装          | `./nyxbot-linux.sh --skip-java`    |
| `--proxy <num>`  | 指定代理序号（0=直连，1-10=代理） | `./nyxbot-linux.sh --proxy 1`      |
| `--version`      | 显示脚本版本                      | `./nyxbot-linux.sh --version`      |
| `--help`         | 显示帮助信息                      | `./nyxbot-linux.sh --help`         |

### Windows 参数

| 参数           | 说明                              | 示例                                |
| -------------- | --------------------------------- | ----------------------------------- |
| `-ForceUpdate` | 强制重新下载最新版本              | `.\nyxbot-windows.ps1 -ForceUpdate` |
| `-SkipJava`    | 跳过 Java 环境检查和安装          | `.\nyxbot-windows.ps1 -SkipJava`    |
| `-Proxy <num>` | 指定代理序号（0=直连，1-10=代理） | `.\nyxbot-windows.ps1 -Proxy 1`     |
| `-Version`     | 显示脚本版本                      | `.\nyxbot-windows.ps1 -Version`     |
| `-Help`        | 显示帮助信息                      | `.\nyxbot-windows.ps1 -Help`        |

---

## 使用场景

### 场景 1: 首次安装（默认模式）

```bash
# Linux / macOS
./nyxbot-linux.sh

# Windows
.\nyxbot-windows.ps1
```

**执行流程**:

1. ✅ 检测并安装 JDK 21
2. ✅ 引导安装 OneBot 实现
3. ✅ 自动测速选择最快代理
4. ✅ 下载最新版 NyxBot
5. ✅ SHA256 校验
6. ✅ 启动 NyxBot

---

### 场景 2: 版本更新

```bash
# 自动更新（仅在有新版本时下载）
./nyxbot-linux.sh

# 强制更新（无论版本是否最新）
./nyxbot-linux.sh --force-update
```

**特点**:

- 自动备份旧版本
- 下载失败时恢复备份
- 保留配置文件

---

### 场景 3: 已有 Java 环境

```bash
# 跳过 Java 检测，加快启动速度
./nyxbot-linux.sh --skip-java
```

**适用情况**:

- 已手动安装 JDK 21
- 使用自定义 Java 发行版
- 多次运行脚本

---

### 场景 4: 网络受限环境

```bash
# 方法一：自动选择最快代理（推荐）
./nyxbot-linux.sh

# 方法二：使用直连（国外服务器）
./nyxbot-linux.sh --proxy 0

# 方法三：指定代理服务器
./nyxbot-linux.sh --proxy 1  # 使用第1个代理
./nyxbot-linux.sh --proxy 2  # 使用第2个代理
```

**内置代理列表**:

1. `https://ghfast.top`
2. `https://git.yylx.win/`
3. `https://gh-proxy.com`
4. `https://ghfile.geekertao.top`
5. `https://gh-proxy.net`
6. `https://j.1win.ggff.net`
7. `https://ghm.078465.xyz`
8. `https://gitproxy.127731.xyz`
9. `https://jiashu.1win.eu.org`
10. `https://github.tbedu.top`

---

### 场景 5: 服务器自动化部署

```bash
# 创建无人值守部署脚本
cat > deploy.sh << 'EOF'
#!/bin/bash
# 下载脚本
curl -sO https://kingprimes.top/script/nyxbot-linux.sh
chmod +x nyxbot-linux.sh

# 自动安装（假设已有JDK和OneBot）
./nyxbot-linux.sh --skip-java
EOF

chmod +x deploy.sh
./deploy.sh
```

---

## 详细功能说明

### JDK 21 自动安装

#### Linux 平台

脚本会自动识别以下发行版并使用相应的包管理器：

| 发行版        | 包管理器 | 安装命令                                   |
| ------------- | -------- | ------------------------------------------ |
| Ubuntu/Debian | apt      | `sudo apt install openjdk-21-jdk`          |
| CentOS/RHEL   | yum      | `sudo yum install java-21-openjdk-devel`   |
| Fedora        | dnf      | `sudo dnf install java-21-openjdk-devel`   |
| Arch Linux    | pacman   | `sudo pacman -Syu jre-openjdk jdk-openjdk` |
| Alpine Linux  | apk      | `sudo apk add openjdk21`                   |

#### macOS 平台

1. **自动安装 Homebrew**（如未安装）

   - 国内环境：使用 Gitee 镜像
   - 国外环境：使用官方源

2. **安装 OpenJDK 21**

   ```bash
   brew install openjdk@21
   ```

3. **配置环境变量**

   - Intel Mac: `/usr/local/opt/openjdk@21`
   - Apple Silicon: `/opt/homebrew/opt/openjdk@21`
   - 自动添加到 `~/.zprofile`

4. **创建系统链接**
   ```bash
   sudo ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk \
     /Library/Java/JavaVirtualMachines/openjdk-21.jdk
   ```

#### Windows 平台

脚本会按优先级尝试以下方法：

1. **winget (推荐)**

   ```powershell
   winget install --id Microsoft.OpenJDK.21 -e
   # 或
   winget install --id EclipseAdoptium.Temurin.21.JDK -e
   ```

2. **Chocolatey**

   ```powershell
   choco install -y openjdk --version=21
   ```

3. **手动安装**
   - Microsoft Build of OpenJDK: https://learn.microsoft.com/java/openjdk/download
   - Eclipse Temurin: https://adoptium.net/

---

### 网络代理与加速

#### 自动测速机制

脚本会并行测试所有可用的代理服务器：

```
[INFO] 开始 GitHub 代理网络测试...
[INFO] 测速: 直连 - 0 MB/s
[INFO] 测速: https://ghfast.top - 5 MB/s
[INFO] 测速: https://git.yylx.win/ - 3 MB/s
[INFO] 测速: https://gh-proxy.com - 4 MB/s
[SUCCESS] 将使用最快的代理: https://ghfast.top
```

#### 代理工作原理

- **直连**: `https://github.com/xxx/file.jar`
- **代理**: `https://ghfast.top/https://github.com/xxx/file.jar`

代理服务器会转发请求到 GitHub，解决国内访问慢的问题。

#### 手动指定代理

```bash
# 不使用代理（适合国外服务器）
./nyxbot-linux.sh --proxy 0

# 使用第1个代理
./nyxbot-linux.sh --proxy 1

# 使用第5个代理
./nyxbot-linux.sh --proxy 5
```

---

### SHA256 完整性校验

#### 校验流程

1. 下载 `.jar.sha256` 文件（如果存在）
2. 计算已下载文件的 SHA256 值
3. 对比期望值与实际值
4. 不匹配则删除文件并报错

#### 示例输出

```
[INFO] 获取到SHA256: a1b2c3d4e5f6...
[INFO] 下载 NyxBot.jar...
[SUCCESS] NyxBot.jar 下载完成
[INFO] 验证 NyxBot.jar 的SHA256校验和...
[SUCCESS] SHA256校验通过
```

#### 校验失败处理

```
[ERROR] SHA256校验失败！
[ERROR] 期望: a1b2c3d4e5f6...
[ERROR] 实际: z9y8x7w6v5u4...
[WARNING] 文件可能已被篡改，删除下载的文件
```

---

### 版本管理

#### 版本文件

脚本在 `nyxbot_data/.version` 文件中保存当前版本：

```
v1.2.3
```

#### 版本检查逻辑

```
本地版本: v1.2.1
最新版本: v1.2.3
结果: 需要更新

本地版本: v1.2.3
最新版本: v1.2.3
结果: 跳过下载，直接启动
```

#### 强制更新

使用 `--force-update` 参数可忽略版本检查：

```bash
./nyxbot-linux.sh --force-update
```

**适用场景**:

- 文件损坏需要重新下载
- 手动更新配置后需要重置
- 测试最新构建版本

---

### 备份与恢复机制

#### 自动备份

每次下载新版本前，会自动备份旧版本：

```
[INFO] 备份旧版本到 nyxbot_data/NyxBot.jar.bak
```

#### 自动恢复

如果下载或校验失败，会自动恢复备份：

```
[ERROR] 下载失败
[INFO] 恢复备份版本...
```

#### 清理备份

成功更新后会自动删除备份文件：

```
[SUCCESS] 版本信息已保存: v1.2.3
# 自动删除 NyxBot.jar.bak
```

---

## OneBot 协议实现

### 什么是 OneBot

OneBot 是一个聊天机器人应用接口标准，NyxBot 通过 OneBot 协议与 QQ 进行通信。

### 支持的实现

#### 1. LLOneBot（推荐 - QQ 插件方式）

**特点**:

- ✅ 作为 QQ 官方客户端的插件运行
- ✅ 无需额外的 QQ 客户端
- ✅ 使用现有 QQ 账号
- ✅ 轻量级，资源占用少

**安装步骤**:

1. **安装 QQ 客户端**

   - Windows: https://im.qq.com/pcqq
   - Linux: https://im.qq.com/linuxqq
   - macOS: https://im.qq.com/macqq

2. **下载 LLOneBot 插件**

   - 官网: https://llonebot.com/guide/getting-started
   - 选择对应平台的版本

3. **安装插件**

   - 将插件文件放入 QQ 的插件目录
   - 重启 QQ 客户端

4. **配置 OneBot**

   - 打开 QQ 设置中的 LLOneBot 配置
   - 设置 HTTP/WebSocket 服务端口（默认 3000）
   - 启用 OneBot 服务

5. **配置 NyxBot**
   - 在 NyxBot 配置文件中填写相同端口
   - 确保 IP 地址为 `127.0.0.1` 或 `localhost`

---

#### 2. NapCatQQ（推荐 - 独立客户端）

**特点**:

- ✅ 独立的 QQ 客户端
- ✅ 适合服务器部署
- ✅ 支持 Docker 容器化
- ✅ 功能完整，稳定性高

**安装步骤**:

1. **下载 NapCatQQ**

   - 官网: https://napneko.github.io/guide/boot/Shell
   - 选择适合您系统的版本

2. **安装方法**

   **Linux/macOS (Shell 脚本)**:

   ```bash
   # 下载安装脚本
   curl -o napcat.sh https://nclatest.znin.net/NapCat/NapCat-Installer/main/script/install.sh

   # 添加执行权限
   chmod +x napcat.sh

   # 运行安装
   sudo ./napcat.sh
   ```

   **Windows (安装包)**:

   - 下载 `.exe` 安装程序
   - 运行安装向导

   **Docker (推荐服务器部署)**:

   ```bash
   docker run -d \
     --name napcat \
     -p 3000:3000 \
     -v $(pwd)/napcat:/app/napcat \
     napneko/napcat:latest
   ```

3. **配置 NapCatQQ**

   - 编辑 `napcat.json` 配置文件
   - 设置 HTTP/WebSocket 端口（默认 3000）
   - 配置 QQ 账号信息（可选）

4. **启动 NapCatQQ**

   ```bash
   napcat start
   ```

5. **扫码登录**
   - 首次启动会显示二维码
   - 使用手机 QQ 扫码登录

---

### OneBot 配置示例

#### LLOneBot 配置

在 QQ 设置中配置：

```json
{
  "http": {
    "enable": true,
    "host": "127.0.0.1",
    "port": 3000
  },
  "ws": {
    "enable": true,
    "host": "127.0.0.1",
    "port": 3001
  }
}
```

#### NapCatQQ 配置

编辑 `napcat.json`:

```json
{
  "http": {
    "enable": true,
    "host": "0.0.0.0",
    "port": 3000,
    "secret": "",
    "enableHeart": true,
    "enablePost": false
  },
  "ws": {
    "enable": true,
    "host": "0.0.0.0",
    "port": 3001
  }
}
```

#### NyxBot 配置

在 NyxBot 的配置文件中（通常是 `application.yml` 或 `config.yml`）：

```yaml
onebot:
  http:
    url: http://127.0.0.1:3000
  websocket:
    url: ws://127.0.0.1:3001
```

---

## 常见问题

### Q1: 脚本提示"权限不足"

**Linux/macOS**:

```bash
# 添加执行权限
chmod +x nyxbot-linux.sh

# 如果需要 sudo 权限
sudo ./nyxbot-linux.sh
```

**Windows**:

```powershell
# 以管理员身份运行 PowerShell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

### Q2: JDK 安装失败

**手动安装 JDK 21**:

**Linux (Ubuntu/Debian)**:

```bash
sudo apt update
sudo apt install openjdk-21-jdk
```

**macOS**:

```bash
brew install openjdk@21
```

**Windows**:

- 下载: https://learn.microsoft.com/java/openjdk/download
- 或使用: `winget install Microsoft.OpenJDK.21`

**然后使用 `--skip-java` 跳过检测**:

```bash
./nyxbot-linux.sh --skip-java
```

---

### Q3: 无法访问 GitHub

**使用代理**:

```bash
# 自动选择最快代理
./nyxbot-linux.sh

# 手动指定代理
./nyxbot-linux.sh --proxy 1
```

**配置系统代理**:

```bash
# Linux/macOS
export https_proxy=http://127.0.0.1:7890

# Windows
$env:HTTPS_PROXY="http://127.0.0.1:7890"
```

---

### Q4: 下载速度很慢

1. **尝试不同的代理**:

   ```bash
   ./nyxbot-linux.sh --proxy 2
   ./nyxbot-linux.sh --proxy 3
   ```

2. **手动下载**:
   - 访问 GitHub Release 页面
   - 下载 `NyxBot.jar` 文件
   - 放到 `nyxbot_data/` 目录
   - 使用 `--skip-java` 直接启动

---

### Q5: SHA256 校验失败

**原因**:

- 下载过程中断
- 代理服务器缓存了旧版本
- 网络传输错误

**解决方法**:

```bash
# 删除缓存
rm -rf nyxbot_data/NyxBot.jar*

# 尝试直连
./nyxbot-linux.sh --proxy 0 --force-update

# 或更换代理
./nyxbot-linux.sh --proxy 2 --force-update
```

---

### Q6: OneBot 连接失败

**检查清单**:

1. ✅ OneBot 实现（LLOneBot/NapCatQQ）已启动
2. ✅ QQ 已登录
3. ✅ 端口配置正确（默认 3000）
4. ✅ 防火墙未阻止连接
5. ✅ NyxBot 配置文件正确

**测试连接**:

```bash
# 测试 HTTP 接口
curl http://127.0.0.1:3000/get_login_info

# 测试 WebSocket（使用 wscat）
wscat -c ws://127.0.0.1:3001
```

---

### Q7: NyxBot 启动失败

**查看日志**:

```bash
# 查看安装日志
cat nyxbot_data/install.log

# 查看 NyxBot 运行日志
# 日志位置通常在 logs/ 目录
```

**常见原因**:

- Java 版本不正确（需要 JDK 21）
- 配置文件错误
- 端口被占用
- OneBot 未连接

---

## 故障排除

### 诊断步骤

1. **检查 Java 环境**
   ```bash
   java -version
   # 应显示: openjdk version
   ```

"21.

````

2. **检查网络连接**
```bash
# 测试 GitHub 连接
curl -I https://api.github.com

# 测试代理（如使用）
curl -I https://ghfast.top/https://api.github.com
````

3. **检查 OneBot 状态**

   ```bash
   # 检查端口占用
   # Linux/macOS
   lsof -i :3000
   netstat -an | grep 3000

   # Windows
   netstat -ano | findstr 3000
   ```

4. **检查日志文件**

   ```bash
   # 安装日志
   cat nyxbot_data/install.log

   # NyxBot 日志
   tail -f logs/nyxbot.log
   ```

---

### 错误代码说明

| 退出码 | 含义              | 解决方法           |
| ------ | ----------------- | ------------------ |
| 0      | 正常退出          | -                  |
| 1      | 一般错误          | 查看日志文件       |
| 127    | 命令未找到        | 检查 PATH 环境变量 |
| 130    | 用户中断 (Ctrl+C) | 重新运行脚本       |

---

### 清理与重置

如果需要完全重新开始：

```bash
# 1. 删除下载目录
rm -rf nyxbot_data/

# 2. 重新运行脚本
./nyxbot-linux.sh --force-update
```

---

## 日志文件

### 日志位置

```
nyxbot_data/
├── install.log          # 脚本安装日志
├── NyxBot.jar          # 主程序
└── .version            # 版本信息
```

### 日志格式

```
[2025-12-03 15:00:00] [INFO] 检查JDK 21环境...
[2025-12-03 15:00:01] [SUCCESS] JDK 21已安装
[2025-12-03 15:00:02] [INFO] 下载 NyxBot.jar...
[2025-12-03 15:00:15] [SUCCESS] NyxBot.jar 下载完成
```

### 查看日志

```bash
# 查看完整日志
cat nyxbot_data/install.log

# 实时跟踪日志
tail -f nyxbot_data/install.log

# 搜索错误
grep ERROR nyxbot_data/install.log

# 搜索警告
grep WARNING nyxbot_data/install.log
```

---

## 高级配置

### 环境变量

可以通过环境变量自定义脚本行为：

```bash
# 设置 HTTP 代理
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890

# 设置 Java 路径
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk

# 运行脚本
./nyxbot-linux.sh
```

---

### 自定义下载目录

编辑脚本文件，修改 `DOWNLOAD_DIR` 变量：

```bash
# Linux/macOS
readonly DOWNLOAD_DIR="/opt/nyxbot"

# Windows
$DOWNLOAD_DIR = "C:\NyxBot"
```

---

### 定时任务

#### Linux (cron)

```bash
# 编辑 crontab
crontab -e

# 每天凌晨 2 点检查更新并重启
0 2 * * * /path/to/nyxbot-linux.sh --force-update
```

#### macOS (launchd)

创建 `~/Library/LaunchAgents/com.nyxbot.update.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nyxbot.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/nyxbot-macos.sh</string>
        <string>--force-update</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

加载任务：

```bash
launchctl load ~/Library/LaunchAgents/com.nyxbot.update.plist
```

#### Windows (Task Scheduler)

```powershell
# 创建计划任务
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\path\to\nyxbot-windows.ps1 -ForceUpdate"
$trigger = New-ScheduledTaskTrigger -Daily -At 2am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "NyxBot Update" -Description "自动更新 NyxBot"
```

---

### Docker 部署

创建 `Dockerfile`:

```dockerfile
FROM ubuntu:22.04

# 安装依赖
RUN apt-get update && \
    apt-get install -y openjdk-21-jdk curl && \
    rm -rf /var/lib/apt/lists/*

# 复制脚本
COPY nyxbot-linux.sh /app/
WORKDIR /app

# 下载并启动
RUN chmod +x nyxbot-linux.sh
CMD ["./nyxbot-linux.sh", "--skip-java"]
```

构建和运行：

```bash
# 构建镜像
docker build -t nyxbot:latest .

# 运行容器
docker run -d \
  --name nyxbot \
  -v $(pwd)/config:/app/config \
  -v $(pwd)/data:/app/data \
  --restart unless-stopped \
  nyxbot:latest
```

---

### Systemd 服务（Linux）

创建 `/etc/systemd/system/nyxbot.service`:

```ini
[Unit]
Description=NyxBot Service
After=network.target

[Service]
Type=simple
User=nyxbot
WorkingDirectory=/opt/nyxbot
ExecStart=/usr/bin/java -jar /opt/nyxbot/nyxbot_data/NyxBot.jar
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

启用和启动服务：

```bash
# 重载配置
sudo systemctl daemon-reload

# 启用开机自启
sudo systemctl enable nyxbot

# 启动服务
sudo systemctl start nyxbot

# 查看状态
sudo systemctl status nyxbot

# 查看日志
sudo journalctl -u nyxbot -f
```

---

## 安全建议

### 1. 文件权限

```bash
# 限制脚本执行权限
chmod 750 nyxbot-linux.sh

# 限制数据目录权限
chmod 700 nyxbot_data/
```

### 2. 用户隔离

```bash
# 创建专用用户
sudo useradd -r -s /bin/false nyxbot

# 更改所有权
sudo chown -R nyxbot:nyxbot /opt/nyxbot

# 使用专用用户运行
sudo -u nyxbot ./nyxbot-linux.sh
```

### 3. 防火墙配置

```bash
# Linux (UFW)
sudo ufw allow 3000/tcp  # OneBot HTTP
sudo ufw allow 3001/tcp  # OneBot WebSocket

# Linux (firewalld)
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=3001/tcp
sudo firewall-cmd --reload
```

### 4. 定期备份

```bash
# 备份配置和数据
tar -czf nyxbot-backup-$(date +%Y%m%d).tar.gz \
  nyxbot_data/ \
  config/ \
  data/

# 上传到远程服务器
scp nyxbot-backup-*.tar.gz user@backup-server:/backups/
```

---

## 性能优化

### JVM 参数调优

编辑启动命令，添加 JVM 参数：

```bash
# 增加堆内存
java -Xms512M -Xmx2G -jar nyxbot_data/NyxBot.jar

# 启用 G1 垃圾回收器
java -XX:+UseG1GC -jar nyxbot_data/NyxBot.jar

# 完整优化示例
java \
  -Xms512M \
  -Xmx2G \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UseStringDeduplication \
  -jar nyxbot_data/NyxBot.jar
```

---

## 贡献与反馈

### 报告问题

如果您遇到问题，请提供以下信息：

1. **操作系统**: `uname -a` 或 `systeminfo`
2. **Java 版本**: `java -version`
3. **错误日志**: `nyxbot_data/install.log`
4. **运行命令**: 您执行的完整命令
5. **错误截图**: 如果有的话

### GitHub Issues

提交问题到: https://github.com/KingPrimes/NyxBot/issues

### 社区支持

- QQ 群: [QQ群](https://jq.qq.com/?_wv=1027&k=RgqgJLij)
- Discord: [待添加]
- 文档: https://github.com/KingPrimes/NyxBot/wiki

---

## 许可证

本脚本遵循 NyxBot 项目的开源许可证。

---

## 致谢

感谢以下项目和服务：

- **OpenJDK**: 提供免费的 Java 运行环境
- **GitHub**: 代码托管和 Release 服务
- **LLOneBot**: OneBot 协议实现
- **NapCatQQ**: OneBot 协议实现
- **GitHub 代理服务**: 加速国内访问

---

## 附录

### A. 脚本文件结构

```
nyxbot-linux.sh         # Linux 启动脚本
nyxbot-macos.sh         # macOS 启动脚本
nyxbot-windows.ps1      # Windows 启动脚本

nyxbot_data/            # 数据目录
├── NyxBot.jar         # 主程序
├── .version           # 版本信息
└── install.log        # 安装日志
```

### B. 相关链接

- **NyxBot 项目**: https://github.com/KingPrimes/NyxBot
- **OneBot 标准**: https://onebot.dev/
- **LLOneBot**: https://llonebot.com/
- **NapCatQQ**: https://napneko.github.io/
- **OpenJDK**: https://openjdk.org/

### C. 常用命令速查

```bash
# 基本使用
./nyxbot-linux.sh                    # 标准安装
./nyxbot-linux.sh --force-update     # 强制更新
./nyxbot-linux.sh --skip-java        # 跳过 Java 检测
./nyxbot-linux.sh --proxy 1          # 使用代理

# 查看信息
./nyxbot-linux.sh --version          # 查看脚本版本
./nyxbot-linux.sh --help             # 查看帮助
cat nyxbot_data/.version             # 查看 NyxBot 版本
cat nyxbot_data/install.log          # 查看日志

# 诊断
java -version                        # 检查 Java 版本
curl -I https://api.github.com       # 测试网络
lsof -i :3000                        # 检查端口占用
```

---

**文档版本**: v2.0.0  
**最后更新**: 2025-12-03  
**维护者**: KingPrimes

---

**🎉 祝您使用愉快！如有问题，欢迎反馈。**
