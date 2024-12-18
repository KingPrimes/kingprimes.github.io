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
                message: ['Live2D模型来自B站 @星临之海'],
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
        // 菜单选项
        menus: {
            // 禁用菜单
            disable: true
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
            }
        ]
    });

})
(() => {
    // It will be executed when the DOM tree is built.
    document.addEventListener('DOMContentLoaded', () => {
        //初始化
        PLUGINS_LIVE2D.initPluginsLive2d();
    });
});