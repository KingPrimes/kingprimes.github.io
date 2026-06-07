(function () {
  var currentModel = 0;
  var costumeIndex = 0;

  function getGreeting() {
    var now = new Date();
    var m = now.getMonth() + 1;
    var d = now.getDate();
    if (m === 1 && d === 1) return '🎉 元旦快乐！新的一年万事如意！';
    if (m === 2 && d === 14) return '💕 情人节快乐！';
    if (m === 3 && d === 8) return '🌸 妇女节快乐！';
    if (m === 4 && d === 1) return '😄 愚人节快乐！';
    if (m === 5 && d === 1) return '🎊 劳动节快乐！';
    if (m === 6 && d === 1) return '🎈 儿童节快乐！';
    if (m === 9 && d === 10) return '🎉 教师节快乐！';
    if (m === 10 && d === 1) return '🇨🇳 国庆节快乐！';
    if (m === 12 && d === 24) return '🎄 平安夜快乐！';
    if (m === 12 && d === 25) return '🎄 圣诞节快乐！';
    if (m === 12 && d === 31) return '🎆 跨年夜快乐！';
    if (m === 1 && d >= 28 && d <= 31) return '🧨 新年快乐！';
    if (m === 2 && d >= 1 && d <= 15) return '🧨 新年快乐！';
    if (m === 2 && d === 12) return '🏮 元宵节快乐！';
    var hour = now.getHours();
    if (hour >= 5 && hour < 9) return '早上好！开始元气满满的一天吧！';
    if (hour >= 9 && hour < 12) return '上午好！今天有什么计划吗？';
    if (hour >= 12 && hour < 14) return '中午好！记得吃午饭哦~';
    if (hour >= 14 && hour < 18) return '下午好！要不要休息一下？';
    if (hour >= 18 && hour < 22) return '晚上好！今天辛苦了！';
    return '夜深了，注意休息哦~';
  }

  function playRandomActivity(w) {
    if (!w || !w.l2d) return;
    var r = Math.random();
    if (r < 0.5) {
      // 随机播放身体动作
      if (w.l2d.playMotion) w.l2d.playMotion('tap_body');
    } else {
      // 随机播放面部表情
      if (w.l2d.setExpression) {
        var facial = ['M_shengqi','M_KUQI','M_lianhei','M_lianhong','M_LIUHAN','M_mimiyan','M_quanquanyan','M_xingxingyan','aixinyan'];
        w.l2d.setExpression(facial[Math.floor(Math.random() * facial.length)]);
      }
    }
  }

  var widget = L2D_WIDGET.createWidget({
    model: [
      {
        path: '/live2d-widget-model-koharu/moon_rabbit/psd_b.model3.json',
        scale: 1.7,
        offset: [0, -0.7],
        tips: {
          welcomeMessage: [getGreeting()],
          messages: [],
          typing: {
            speed: 150,
            param: 'ParamMouthOpenY',
            minValue: 0.5,
            maxValue: 1,
          },
        },
      },
      {
        path: '/live2d-widget-model-koharu/maolili_vts/mailili.model3.json',
        scale: 1.7,
        offset: [0, -0.7],
        tips: {
          welcomeMessage: [getGreeting()],
          messages: [],
          typing: {
            speed: 150,
            param: 'ParamMouthOpenY',
            minValue: 0.5,
            maxValue: 1,
          },
        },
      },
    ],
    position: 'bottom-left',
    size: { width: 300, height: 350 },
    primaryColor: '#49B1F5',
    transitionDuration: 1000,
    menus: {
      style: {
        gap: '8px',
        padding: '6px',
      },
      items: [
        {
          icon: 'mdi:bed',
          label: '休眠',
          onClick: function (w) { w.sleep(); },
        },
        {
          icon: 'mdi:swap-horizontal',
          label: '换装',
          onClick: function (w) {
            currentModel = (currentModel + 1) % 2;
            costumeIndex = 0;
            w.switchModel(currentModel);
          },
        },
        {
          icon: 'mdi:tshirt-crew',
          label: '装扮',
          onClick: function (w) {
            if (currentModel !== 0) return;
            costumeIndex = (costumeIndex + 1) % 3;
            var names = ['costume_default', 'costume_hood', 'costume_scarf'];
            w.l2d.setExpression(names[costumeIndex]);
          },
        },
        {
          icon: 'mdi:information-outline',
          label: '关于',
          onClick: function () {
            var urls = [
              'https://www.bilibili.com/video/BV1cR4y1Y7vw',
              'https://www.bilibili.com/video/BV1sd6gY2EY9',
            ];
            window.open(urls[currentModel] || urls[0]);
          },
        },
      ],
    },
  });

  // 开屏播放 hello 动作
  setTimeout(function () {
    if (widget && widget.l2d && widget.l2d.playMotion) {
      widget.l2d.playMotion('tap_body', 0);
    }
  }, 1500);

  // 每 25~40 秒随机播放表情或动作
  setInterval(function () { playRandomActivity(widget); }, 30000);
})();
