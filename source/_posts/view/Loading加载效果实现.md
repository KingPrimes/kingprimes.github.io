---
# 标题
title: Loading加载效果实现
# 发布日期
date: 2025-04-10T22:55:56+08:00
# 文章url别名
permalink: posts/c8c1d28
# 文章描述
description: 使用Css实现的Loading加载动画效果实现
# 文章关键字
keywords: 加载动画
# 是否开启评论
comment: true
# 文章置顶(数值越大置顶优先级越大)
sticky: 0
# 文章标签
tags:
  - View
  - Style
# 文章分类
categories:
  - View
# 文章摘要
summary: 前端小球3D加载动画效果实现
# 文章头图片
cover: /img/38f55ae/38f55ae.webp
---

# Loading 圆形小球加载效果实现

## CSS样式

```css
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    background: #0dcaf0;
}

.loading {
    width: 150px;
    height: 150px;
    margin: 50px auto;
    position: relative;
    border-radius: 50%;
}

.loading .dot {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 10px;
    height: 10px;
    margin-left: 5px;
    margin-top: 5px;
    perspective: 70px;
    transform-style: preserve-3d;
}

.loading .dot::before,
.loading .dot::after {
    content: "";
    position: absolute;
    width: 100%;
    height: 100%;
    border-radius: 50%;
}

.loading .dot::before {
    background: #b6b6b2;
    top: -100%;
    animation: moveBlack 2s infinite alternate;
}

.loading .dot::after {
    background: #ffffff;
    top: 100%;
    animation: moveWhite 2s infinite alternate;
}

@keyframes moveBlack {
    0% {
        animation-timing-function: ease-in;
    }
    25% {
        transform: translate3d(0, 100%, 10px);
        animation-timing-function: ease-out;
    }
    50% {
        transform: translate3d(0, 200%, 0);
        animation-timing-function: ease-in;
    }
    75% {
        transform: translate3d(0, 100%, -10px);
        animation-timing-function: ease-out;
    }
}

@keyframes moveWhite {
    0% {
        animation-timing-function: ease-in;
    }
    25% {
        transform: translate3d(0, -100%, -10px);
        animation-timing-function: ease-out;
    }
    50% {
        transform: translate3d(0, -200%, 0);
        animation-timing-function: ease-in;
    }
    75% {
        transform: translate3d(0, -100%, 10px);
        animation-timing-function: ease-out;
    }
}

.dot:nth-child(1) {
    transform: rotate(15deg) translateY(-75px);
}

.dot:nth-child(1)::before,
.dot:nth-child(1)::after {
    animation-delay: -0.5s;
}

.dot:nth-child(2) {
    transform: rotate(30deg) translateY(-75px);
}

.dot:nth-child(2)::before,
.dot:nth-child(2)::after {
    animation-delay: -1s;
}

.dot:nth-child(3) {
    transform: rotate(45deg) translateY(-75px);
}

.dot:nth-child(3)::before,
.dot:nth-child(3)::after {
    animation-delay: -1.5s;
}

.dot:nth-child(4) {
    transform: rotate(60deg) translateY(-75px);
}

.dot:nth-child(4)::before,
.dot:nth-child(4)::after {
    animation-delay: -2s;
}

.dot:nth-child(5) {
    transform: rotate(75deg) translateY(-75px);
}

.dot:nth-child(5)::before,
.dot:nth-child(5)::after {
    animation-delay: -2.5s;
}

.dot:nth-child(6) {
    transform: rotate(90deg) translateY(-75px);
}

.dot:nth-child(6)::before,
.dot:nth-child(6)::after {
    animation-delay: -3s;
}

.dot:nth-child(7) {
    transform: rotate(105deg) translateY(-75px);
}

.dot:nth-child(7)::before,
.dot:nth-child(7)::after {
    animation-delay: -3.5s;
}

.dot:nth-child(8) {
    transform: rotate(120deg) translateY(-75px);
}

.dot:nth-child(8)::before,
.dot:nth-child(8)::after {
    animation-delay: -4s;
}

.dot:nth-child(9) {
    transform: rotate(135deg) translateY(-75px);
}

.dot:nth-child(9)::before,
.dot:nth-child(9)::after {
    animation-delay: -4.5s;
}

.dot:nth-child(10) {
    transform: rotate(150deg) translateY(-75px);
}

.dot:nth-child(10)::before,
.dot:nth-child(10)::after {
    animation-delay: -5s;
}

.dot:nth-child(11) {
    transform: rotate(165deg) translateY(-75px);
}

.dot:nth-child(11)::before,
.dot:nth-child(11)::after {
    animation-delay: -5.5s;
}

.dot:nth-child(12) {
    transform: rotate(180deg) translateY(-75px);
}

.dot:nth-child(12)::before,
.dot:nth-child(12)::after {
    animation-delay: -6s;
}

.dot:nth-child(13) {
    transform: rotate(195deg) translateY(-75px);
}

.dot:nth-child(13)::before,
.dot:nth-child(13)::after {
    animation-delay: -6.5s;
}

.dot:nth-child(14) {
    transform: rotate(210deg) translateY(-75px);
}

.dot:nth-child(14)::before,
.dot:nth-child(14)::after {
    animation-delay: -7s;
}

.dot:nth-child(15) {
    transform: rotate(225deg) translateY(-75px);
}

.dot:nth-child(15)::before,
.dot:nth-child(15)::after {
    animation-delay: -7.5s;
}

.dot:nth-child(16) {
    transform: rotate(240deg) translateY(-75px);
}

.dot:nth-child(16)::before,
.dot:nth-child(16)::after {
    animation-delay: -8s;
}

.dot:nth-child(17) {
    transform: rotate(255deg) translateY(-75px);
}

.dot:nth-child(17)::before,
.dot:nth-child(17)::after {
    animation-delay: -8.5s;
}

.dot:nth-child(18) {
    transform: rotate(270deg) translateY(-75px);
}

.dot:nth-child(18)::before,
.dot:nth-child(18)::after {
    animation-delay: -9s;
}

.dot:nth-child(19) {
    transform: rotate(285deg) translateY(-75px);
}

.dot:nth-child(19)::before,
.dot:nth-child(19)::after {
    animation-delay: -9.5s;
}

.dot:nth-child(20) {
    transform: rotate(300deg) translateY(-75px);
}

.dot:nth-child(20)::before,
.dot:nth-child(20)::after {
    animation-delay: -10s;
}

.dot:nth-child(21) {
    transform: rotate(315deg) translateY(-75px);
}

.dot:nth-child(21)::before,
.dot:nth-child(21)::after {
    animation-delay: -10.5s;
}

.dot:nth-child(22) {
    transform: rotate(330deg) translateY(-75px);
}

.dot:nth-child(22)::before,
.dot:nth-child(22)::after {
    animation-delay: -11s;
}

.dot:nth-child(23) {
    transform: rotate(345deg) translateY(-75px);
}

.dot:nth-child(23)::before,
.dot:nth-child(23)::after {
    animation-delay: -11.5s;
}

.dot:nth-child(24) {
    transform: rotate(360deg) translateY(-75px);
}

.dot:nth-child(24)::before,
.dot:nth-child(24)::after {
    animation-delay: -12s;
}
```

## HTML代码

```html

<div class="loading">
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
    <div class="dot"></div>
</div>
```

## 展示效果

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}
.loading {
  width: 150px;
  height: 150px;
  margin: 50px auto;
  position: relative;
  border-radius: 50%;
}
.loading .dot {
  position: absolute;
  left: 50%;
  top: 50%;
  width: 10px;
  height: 10px;
  margin-left: 5px;
  margin-top: 5px;
  perspective: 70px;
  transform-style: preserve-3d;
}
.loading .dot::before,
.loading .dot::after {
  content: '';
  position: absolute;
  width: 100%;
  height: 100%;
  border-radius: 50%;
}
.loading .dot::before {
  background: #b6b6b2;
  top: -100%;
  animation: moveBlack 2s infinite alternate;
}
.loading .dot::after {
  background: #ffffff;
  top: 100%;
  animation: moveWhite 2s infinite alternate;
}
@keyframes moveBlack {
  0% {
    animation-timing-function: ease-in;
  }
  25% {
    transform: translate3d(0, 100%, 10px);
    animation-timing-function: ease-out;
  }
  50% {
    transform: translate3d(0, 200%, 0);
    animation-timing-function: ease-in;
  }
  75% {
    transform: translate3d(0, 100%, -10px);
    animation-timing-function: ease-out;
  }
}
@keyframes moveWhite {
  0% {
    animation-timing-function: ease-in;
  }
  25% {
    transform: translate3d(0, -100%, -10px);
    animation-timing-function: ease-out;
  }
  50% {
    transform: translate3d(0, -200%, 0);
    animation-timing-function: ease-in;
  }
  75% {
    transform: translate3d(0, -100%, 10px);
    animation-timing-function: ease-out;
  }
}
.dot:nth-child(1) {
  transform: rotate(15deg) translateY(-75px);
}
.dot:nth-child(1)::before,
.dot:nth-child(1)::after {
  animation-delay: -0.5s;
}
.dot:nth-child(2) {
  transform: rotate(30deg) translateY(-75px);
}
.dot:nth-child(2)::before,
.dot:nth-child(2)::after {
  animation-delay: -1s;
}
.dot:nth-child(3) {
  transform: rotate(45deg) translateY(-75px);
}
.dot:nth-child(3)::before,
.dot:nth-child(3)::after {
  animation-delay: -1.5s;
}
.dot:nth-child(4) {
  transform: rotate(60deg) translateY(-75px);
}
.dot:nth-child(4)::before,
.dot:nth-child(4)::after {
  animation-delay: -2s;
}
.dot:nth-child(5) {
  transform: rotate(75deg) translateY(-75px);
}
.dot:nth-child(5)::before,
.dot:nth-child(5)::after {
  animation-delay: -2.5s;
}
.dot:nth-child(6) {
  transform: rotate(90deg) translateY(-75px);
}
.dot:nth-child(6)::before,
.dot:nth-child(6)::after {
  animation-delay: -3s;
}
.dot:nth-child(7) {
  transform: rotate(105deg) translateY(-75px);
}
.dot:nth-child(7)::before,
.dot:nth-child(7)::after {
  animation-delay: -3.5s;
}
.dot:nth-child(8) {
  transform: rotate(120deg) translateY(-75px);
}
.dot:nth-child(8)::before,
.dot:nth-child(8)::after {
  animation-delay: -4s;
}
.dot:nth-child(9) {
  transform: rotate(135deg) translateY(-75px);
}
.dot:nth-child(9)::before,
.dot:nth-child(9)::after {
  animation-delay: -4.5s;
}
.dot:nth-child(10) {
  transform: rotate(150deg) translateY(-75px);
}
.dot:nth-child(10)::before,
.dot:nth-child(10)::after {
  animation-delay: -5s;
}
.dot:nth-child(11) {
  transform: rotate(165deg) translateY(-75px);
}
.dot:nth-child(11)::before,
.dot:nth-child(11)::after {
  animation-delay: -5.5s;
}
.dot:nth-child(12) {
  transform: rotate(180deg) translateY(-75px);
}
.dot:nth-child(12)::before,
.dot:nth-child(12)::after {
  animation-delay: -6s;
}
.dot:nth-child(13) {
  transform: rotate(195deg) translateY(-75px);
}
.dot:nth-child(13)::before,
.dot:nth-child(13)::after {
  animation-delay: -6.5s;
}
.dot:nth-child(14) {
  transform: rotate(210deg) translateY(-75px);
}
.dot:nth-child(14)::before,
.dot:nth-child(14)::after {
  animation-delay: -7s;
}
.dot:nth-child(15) {
  transform: rotate(225deg) translateY(-75px);
}
.dot:nth-child(15)::before,
.dot:nth-child(15)::after {
  animation-delay: -7.5s;
}
.dot:nth-child(16) {
  transform: rotate(240deg) translateY(-75px);
}
.dot:nth-child(16)::before,
.dot:nth-child(16)::after {
  animation-delay: -8s;
}
.dot:nth-child(17) {
  transform: rotate(255deg) translateY(-75px);
}
.dot:nth-child(17)::before,
.dot:nth-child(17)::after {
  animation-delay: -8.5s;
}
.dot:nth-child(18) {
  transform: rotate(270deg) translateY(-75px);
}
.dot:nth-child(18)::before,
.dot:nth-child(18)::after {
  animation-delay: -9s;
}
.dot:nth-child(19) {
  transform: rotate(285deg) translateY(-75px);
}
.dot:nth-child(19)::before,
.dot:nth-child(19)::after {
  animation-delay: -9.5s;
}
.dot:nth-child(20) {
  transform: rotate(300deg) translateY(-75px);
}
.dot:nth-child(20)::before,
.dot:nth-child(20)::after {
  animation-delay: -10s;
}
.dot:nth-child(21) {
  transform: rotate(315deg) translateY(-75px);
}
.dot:nth-child(21)::before,
.dot:nth-child(21)::after {
  animation-delay: -10.5s;
}
.dot:nth-child(22) {
  transform: rotate(330deg) translateY(-75px);
}
.dot:nth-child(22)::before,
.dot:nth-child(22)::after {
  animation-delay: -11s;
}
.dot:nth-child(23) {
  transform: rotate(345deg) translateY(-75px);
}
.dot:nth-child(23)::before,
.dot:nth-child(23)::after {
  animation-delay: -11.5s;
}
.dot:nth-child(24) {
  transform: rotate(360deg) translateY(-75px);
}
.dot:nth-child(24)::before,
.dot:nth-child(24)::after {
  animation-delay: -12s;
}
</style>

<div class="loading">
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
          <div class="dot"></div>
  </div>

<!--more-->
