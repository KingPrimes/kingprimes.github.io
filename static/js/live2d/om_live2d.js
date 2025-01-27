let oml2d;
const PLUGINS_LIVE2D = new (function () {
    oml2d = OML2D.loadOml2d({
        // 插件所在的位置
        dockedPosition: 'right',
        // 提示词
        tips: {
            // 复制时
            copyTips: {
                message: ['复制了啥?'],
            },
            idleTips: {
                wordTheDay(wd) {
                    return `${wd.hitokoto}  by.${wd.from}`
                },
            },
            welcomeTips: {
                message: {
                    'default': ['欢迎光临~']
                },
            }
        },
        // 模型列表
        models: [
            {
                // 模型名称
                name: 'moon_rabbit',
                path: '/data/live2d/moon_rabbit/psd_b.model3.json',
                position: [0, 60],
                scale: 0.08,
                stageStyle: {
                    height: 450
                }
            },
            {
                name: 'maolili_vts',
                path: '/data/live2d/maolili_vts/mailili.model3.json',
                position: [0, 60],
                scale: 0.08,
                stageStyle: {
                    height: 450
                }
            }
        ],
        // 菜单选项
        menus: {
            // 禁用菜单
            disable: false,
            items: [
                {
                    id: "Rest",
                    icon: "icon-rest",
                    title: "休息",
                    onClick(i) {
                        let t;
                        i.statusBarOpen((t = i.options.statusBar) == null ? void 0 : t.restMessage)
                        i.clearTips()
                        i.setStatusBarClickEvent(() => {
                                i.statusBarClose()
                                i.stageSlideIn()
                                i.statusBarClearEvents()
                            }
                        )
                        i.stageSlideOut()
                    }
                }, {
                    id: "SwitchModel",
                    icon: "icon-switch",
                    title: "切换模型",
                    onClick(i) {
                        i.loadNextModel()
                    }
                }, {
                    id: "About",
                    icon: "icon-about",
                    title: "关于模型",
                    onClick(i) {
                        switch (i.models.currentModelIndex){
                            case 0:
                                window.open('https://www.bilibili.com/video/BV1cR4y1Y7vw')
                                break;
                            case 1:
                                window.open('https://www.bilibili.com/video/BV1sd6gY2EY9')
                                break;
                        }
                    }
                }
            ]
        },

    });
    this.initPluginsLive2d = function () {
        // 初始化
        oml2d.init();
    }
})
(() => {
    // It will be executed when the DOM tree is built.
    document.addEventListener('DOMContentLoaded', () => {
        //初始化
        PLUGINS_LIVE2D.initPluginsLive2d();
    });
});