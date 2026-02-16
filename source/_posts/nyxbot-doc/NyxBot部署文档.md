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
summary: NyxBot的部署文档,NyxBot是用于查询Warframe信息的QQ机器人。
# 封面
cover: /img/d99b802/d99b802_featured.webp
---

## OneBot客户端

| 项目名称     | 项目地址                                                                                                                                                  | 项目文档                                                         |
|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------|
| Gensokyo | [Hoshinonyaruko/Gensokyo: 基于qq官方api开发的符合onebot标准的golang实现，轻量、原生跨平台.](https://github.com/Hoshinonyaruko/Gensokyo)                                      |                                                              |
| OneBots  | [lc-cn/onebots: 基于icqq的多例oneBot管理应用](https://github.com/lc-cn/onebots?tab=readme-ov-file)                                                             | [OneBots - OneBots](https://docs.onebots.org/)               |
| LLOneBot | [LLOneBot/LLOneBot: 使你的 NTQQ 支持 OneBot 11 和 Satori 协议进行机器人开发](https://github.com/LLOneBot/LLOneBot)                                                   | [快速开始](https://llob.napneko.com/zh-CN/guide/getting-started) |
| NapCat   | [NapNeko/NapCatQQ: 现代化的基于 NTQQ 的 Bot 协议端实现](https://github.com/NapNeko/NapCatQQ)                                                                      | [快速开始](https://napneko.github.io/guide/start-install)        |
| Lagrange | [LagrangeDev/Lagrange.Core: An Implementation of NTQQ Protocol, with Pure C#, Derived from Konata.Core](https://github.com/LagrangeDev/Lagrange.Core) | [使用手册](https://lagrangedev.github.io/Lagrange.Doc/)          |

## NyxBot Windows 部署方式

1. 从 [OneBot客户端](#OneBot客户端) 中任选其一，根据其文档进行部署
    1. 此处以 [LLOneBot](https://github.com/LLOneBot/LLOneBot) 为例
    2. 打开设置
    3. 选择LLOneBot
    4. 配置链接方式为 **反向WebSocket模式**
    5. 填写链接地址
    6. 默认链接地址：**ws://localhost:8080/ws/shiro**
    7. 若您的NyxBot与OneBot客户端不在同一台机器上部署则根据您的IP地址自行更改链接地址
    8. 例如：ws://ip地址:端口号/ws/shiro
2. 安装完成之后下载安装 [Oracle Java21](https://www.oracle.com/java/technologies/downloads/#java21)
   或 [Open jdk 21](https://www.openlogic.com/openjdk-downloads) 按照提示进行安装
3. 此处以 [Oracle Java21](https://www.oracle.com/java/technologies/downloads/#java21) 为例
    1. 进入下载页面，选择**Windows**，下载 **X64 Installer**安装包进行 Java的安装
4. Java安装完成之后下载 [NyxBot](https://github.com/KingPrimes/NyxBot/releases) 程序
    1. 在下载界面选择带有 **latest** 绿色标签的版本
    2. 在这个标签中找到 **NyxBot.jar** 点击下载
5. 所有准备工作做完之后进行程序的启动与初始化
    1. 将下载好的 NyxBot.jar **移动到一个空白的文件夹下**
    2. 进入这个文件夹
    3. 在此文件夹中新建文件名为 run.bat文件
        1. **注意，此操作需要打开显示 文件扩展名**
    4. 编辑run.bat文件
    5. 内容为：**java -jar NyxBot.jar**
    6. 如果您要使用代理请添加以下启动参数例如：
        ``` bash http代理
        java -Dhttp.proxy=http://127.0.0.1:7890 -jar NyxBot.jar
       ```
       ``` bash Socks代理
        java -Dsocks.proxy=socks://127.0.0.1:7890 -jar NyxBot.jar
       ```
       ``` bash Socks5代理
        java -Dsocks.proxy=socks5://127.0.0.1:7890 -jar NyxBot.jar
       ```

## NyxBot Linux 部署方式

1. **此处系统为 Ubuntu 20.04**
2. 从 [OneBot客户端](#OneBot客户端) 中任选其一，根据其文档进行部署
    1. 此处以 [NapCat](https://github.com/NapNeko/NapCatQQ) 为例
    2. 进入 [NapCat的文档](https://napneko.github.io/guide/boot/Shell#napcat-installer-linux%E4%B8%80%E9%94%AE%E4%BD%BF%E7%94%A8%E8%84%9A%E6%9C%AC-%E6%94%AF%E6%8C%81ubuntu-20-debian-10-centos9) 可以看到有一键使用脚本
         
    3. ```bash
         curl -o napcat.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh && sudo bash napcat.sh
        ```
    4. 命令选项(高级用法)
        1. --tui: 使用tui可视化交互安装
        2. --docker [y/n]: --docker y为使用docker安装反之为shell安装
        3.
       具体的命令选项可以去查看 [NapCat的文档](https://napneko.github.io/guide/boot/Shell#napcat-installer-linux%E4%B8%80%E9%94%AE%E4%BD%BF%E7%94%A8%E8%84%9A%E6%9C%AC-%E6%94%AF%E6%8C%81ubuntu-20-debian-10-centos9)
    5. 安装完成之后 进入 **/opt/QQ/resources/app/app_launcher/napcat/config** 目录下
    6. 更改 **webui.json**
    7. ```json
         {
          "host": "0.0.0.0",
          "port": 6099,
          "prefix": "",
          "token": "napcat",
          "loginRate": 3
         }
         ```
    8. 更改其**token**值 用于登录web控制页面
    9. 运行 **napcat start qq号** 命令
    10. 等待启动之后访问web控制页面
    11. 地址为：**http://ip:6099/webui** 点击**QR**获取二维码**扫描登录**qq账号
    12. 输入您设置的Token登录到后台
    13. 点击网络设置，添加网络配置为 **WebSocket客户端**
    14. **启用，并配置URL**
    15. 默认链接地址：**ws://localhost:8080/ws/shiro**
    16. 若您的NyxBot与OneBot客户端不在同一台机器上部署则根据您的IP地址自行更改链接地址
    17. 例如：**ws://ip地址:端口号/ws/shiro**
    18. 完整示例
    19. ![NapcatWebConfig.webp](/img/d99b802/NapcatWebConfig.webp)
3. 安装Java
    1. 执行 **sudo apt update** 命令 更新包管理器
    2. 执行 **sudo apt install openjdk-21-jdk 命令**
    3. 若执行第二个命令时出错则 执行 Java 命令安装命令提示进行Java的安装，Java版本不得小于21
    4. 验证安装 执行 **java -version** 你应该看到类似于以下的输出
    5. ```bash
       openjdk version "21.0.x" 2024-xx-xx
       OpenJDK Runtime Environment (build 21.0.x+xx)
       OpenJDK 64-Bit Server VM (build 21.0.x+xx, mixed mode, sharing)
         ````
    6. 若输出不是 **2024** 以上请手动下载安装
4. 创建一个文件夹并下载 NyxBot.jar
    1. ```bash
       mkdir nyxbot
       cd ./nyxbot
       wget https://github.com/KingPrimes/NyxBot/releases/download/v0.3.0/NyxBot.jar -O NyxBot.jar
       ```
    2. v0.3.0为版本号，最新版本请到 [Github](https://github.com/KingPrimes/NyxBot/releases) 查看
    3. 后台启动NyxBot
       ```bash
       nohup java -jar NyxBot.jar > /dev/null 2>&1 &
       ```
    4. 如果您要使用代理请添加以下启动参数例如：
         ``` bash
        nohup java -Dhttp.proxy=http://127.0.0.1:7890 -jar NyxBot.jar > /dev/null 2>&1 &
       ```
    5. 查看程序是否在后台运行
       ```bash
       ps -ef | grep NyxBot
       ```

## NyxBot 安卓部署方式

1. 下载并安装 [ZeroTermux App](https://github.com/hanxinhao000/ZeroTermux)
2. 输入命令，更新包管理库 **pkg update && pkg upgrade**
3. 安装 proot-distro : **pgk install proot-distro**
    1. 查看可安装的Linux系统输入命令：**proot-distro list**
    2. 安装Ubuntu系统：**proot-distro install ubuntu**
    3. 进入Ubuntu系统：**proot-distro login ubuntu**
    4. 退出Ubuntu系统：**exit**
4. 安装 screen 会话 **pgk install screen**
    1. 使用screen进入Ubuntu系统 ： **screen -S proot-distro login ubuntu**
    2. 查看会话列表：**screen -ls**
    3. 进入会话：**screen -r 12654**
5. 进入Ubuntu系统之后部署方式与 **Linux 部署方式** 相同

## NyxBot Docker部署方式

1. 在 docker hub 中搜索 [kingprimes/nyxbot](https://hub.docker.com/r/kingprimes/nyxbot)
2. 下载镜像文件
   ``` bash
    docker pull kingprimes/nyxbot
   ```
3. 运行镜像文件
    ``` bash
   docker run --name Nyxbot -d -p 8080:8080 kingprimes/nyxbot
    ```
4. 如果需要配置代理则添加环境变量
   ``` bash
   docker run --name Nyxbot -d -p 8080:8080 -e HTTP_PROXY=http://127.0.0.1:7890 kingprimes/nyxbot
   ```
     ``` bash
   docker run --name Nyxbot -d -p 8080:8080 -e ALL_PROXY=socks://127.0.0.1:7890 kingprimes/nyxbot
   ```
5. 访问 NyxBot 后台 IP:8080
    1. 这里的地址是[本地地址](http://localhost:8080)，如果你部署到服务器上请使用 IP:端口 / 域名:端口 进行访问 NyxBot 的后台

## NyxBot 自己打包jar

1. 需要你有一个[Github账号](https://github.com/)
2. 跳转到[NyxBot仓库](https://github.com/KingPrimes/NyxBot)
3. 在你登录GitHub账号的情况下点击界面中的 Fork按钮 根据提示复刻到你自己的账号下
4. 等待复刻完成之后如下图操作
   ![d99b802_1.webp](/img/d99b802/d99b802_1.webp)
   ![d99b802_2.webp](/img/d99b802/d99b802_2.webp)
   ![d99b802_3.webp](/img/d99b802/d99b802_3.webp)
   ![d99b802_4.webp](/img/d99b802/d99b802_4.webp)
   ![d99b802_5.webp](/img/d99b802/d99b802_5.webp)

## 注意事项

1. 如果出现端口冲突请添加 -Dserver.port=[端口] | --server.port=[端口] 启动参数 选一个即可 注意：***端口号是数字*** 不需要添加引号
```bash 修改端口示例
      java -Dserver.port=端口 -jar NyxBot.jar
```

```bash 修改端口示例
      java -jar NyxBot.jar --server.port=端口
```
   - 端口被占用时会出现以下错误
   - ![port_error.webp](/img/d99b802/port_error.webp)