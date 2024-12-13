---
# 标题
title: {{ replace .TranslationBaseName "-" " " | title }}
# 副标题
subtitle:
# 发布日期
date: {{ .Date }}
# 文章url别名
slug: {{ substr .File.UniqueID 0 7 }}
# 是否为草稿
draft: true
# 作者信息
author:
  # 作者名称
  name: KingPriems
  # 作者链接
  link: https://github.com/KingPrimes
  # 作者邮箱
  email: Sakitama_q@163.com
  # 作者头像
  avatar: https://avatars.githubusercontent.com/u/50130875
# 文章描述
description:
# 文章关键字
keywords:
# 文章许可证
license:
# 是否开启评论
comment: true
# 文章权重
weight: 0
# 文章标签
tags:
  - draft
# 文章分类
categories:
  - draft
# 是否从主页隐藏 false不隐藏
hiddenFromHomePage: false
# 是否从搜索中隐藏 false不隐藏
hiddenFromSearch: false
# 是否从相关文章中隐藏文章 false不隐藏
hiddenFromRelated: false
# 是否从RSS/Atom订阅源中隐藏文章 false不隐藏
hiddenFromFeed: false
# 文章摘要
summary:
# 文章头图片
featuredImage:
featuredImagePreview: 
# 是否显示目录
toc: true
# 是否启用数学公式渲染
math: false
# 是否启用图片画廊功能
lightgallery: false
# 文章的密码
password:
# 文章的密码提示信息
message:
# 文章是否转载
repost:
  enable: false
  # 原文链接
  url:
# 关闭末尾赞赏按钮
reward: false
# See details front matter: https://fixit.lruihao.cn/documentation/content-management/introduction/#front-matter
---

<!--more-->
