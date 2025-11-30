---
title: 赞助
type: 'reward'
comments: false
aside: true
date: 2025-11-22 20:12:53
updated: 2025-11-22 20:12:53
description: 本页面记录了自「老王的冒险之旅」博客创建以来，所有的打赏记录。感谢大家的支持！
keywords:
  - 打赏记录
  - 老王的冒险之旅
  - KingPrimes
top_img: https://origin.picgo.net/2025/11/30/tag_imgad81a708114fc9f5.webp
aplayer: false
---

<link rel="stylesheet" href="/css/reward-custom.css">

{% note orange 'fas fa-mug-hot' flat %}

给老王上一杯卡布奇诺～
本页面记录了自「老王的冒险之旅」博客以及项目中，所有的打赏记录。感谢大家的支持！❤️
{% endnote %}

<!-- 二维码展示 -->
<div class="reward-qr-display">
    <div class="reward-item">
        <a href="/img/wechatpay.png" target="_blank">
            <img class="post-qr-code-img" src="/img/wechatpay.png" alt="微信">
        </a>
        <div class="post-qr-code-desc">微信</div>
    </div>
    <div class="reward-item">
        <a href="/img/alipay.png" target="_blank">
            <img class="post-qr-code-img" src="/img/alipay.png" alt="支付宝">
        </a>
        <div class="post-qr-code-desc">支付宝</div>
    </div>
</div>

<!-- 统计信息卡片 -->
{% reward_stats %}

<!-- 赞助列表 -->
{% tabs coffee %}

<!-- tab 微信@fab fa-weixin -->

<div class="reward-table-wrapper">

{% reward_table 微信 %}

</div>

<!-- endtab -->

<!-- tab 支付宝@fab fa-alipay -->

<div class="reward-table-wrapper">

{% reward_table 支付宝 %}

</div>

<!-- endtab -->

{% endtabs %}