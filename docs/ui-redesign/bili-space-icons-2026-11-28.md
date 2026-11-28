# Bili-Space 图标来源与 BiliSail 互动图标

核对本机 Bili-Space 提交 `4a4db371093b9c0069a6875009f66ff5ba7e4500`。Bili-Space 在 WebView 中加载 B 站页面，并注入自己的外壳、精选界面和播放器增强。按钮使用独立素材、源码内联图形和网页原有资源。动效取决于具体入口。 [Windows 注入入口](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/src/main.cpp#L442-L489)

| 按钮或动效 | 来源与获取方式 |
| --- | --- |
| 设置、消息、星光 | 仓库已有独立 SVG，启动时读取并注入。`message-square-more.svg` 和 `sparkles.svg` 对应 Lucide 的同名图标，图标页标为 ISC。`settings.svg` 与 SVG Repo 的 529867 文件去除空白后完全一致，路径也与 480 Design 的 Solar Broken `Settings.svg` 一致。SVG Repo 单页标为 CC0，此处记录站点标注。 [本地素材入口](https://github.com/GuqiGG/Bili-Space/tree/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets) · [SVG Repo 设置](https://www.svgrepo.com/svg/529867/settings) · [Solar 原始路径](https://github.com/480-Design/Solar-Icon-Set/blob/main/icons/SVG/Broken/Settings%2C%20Fine%20Tuning/Settings.svg) · [Lucide 消息](https://lucide.dev/icons/message-square-more) · [Lucide 星光](https://lucide.dev/icons/sparkles) · [Lucide 许可](https://lucide.dev/license) |
| 首页小电视、标题栏、搜索、稍后再看、换一换、画中画 | 多数路径直接写在 `enhance.js` 的 SVG 字符串或模板里。小电视另有 `assets/tv.svg`。补帧有独立 `frame-interpolation.svg` 并注入 `ICON_FRAMES`，当前播放器的补帧按钮实际显示“补帧”文字。 [小电视](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L2) · [标题栏模板](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L3117) · [补帧按钮](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L3286-L3292) · [画中画](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L3897) |
| 精选点赞、投币、收藏、分享、评论 | `SWIPE_ACTIONS` 已内联 SVG 路径。源码注释注明前四个来自 B 站视频页工具栏，评论气泡是项目配套绘制的。精选图标的常态颜色与选中填充由 CSS 控制。 [图标路径](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L2308-L2314) · [状态样式](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L2710-L2723) |
| 精选点赞、投币、收藏庆祝动画 | 从当前视频 iframe 读取官网的 `window.SVGA`，沿视频工具栏的 Vue 组件取 `likeBase`、`coinBase`、`favBase`。点赞心形、拇指和三连烟花另有源码列出的三个 B 站 CDN `.svga` 地址。`SVGA.Parser` 加载资源，播放器在图标上方叠加播放一次。依赖官网页面组件和素材可用性。 [播放与 CDN 地址](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L2315-L2332) |
| 精选弹跳、三连蓄力、稍后再看转针、换一换旋转、窗口按钮 | 项目通过 CSS 或 Web Animations API 直接驱动 SVG。精选点击缩放，三连长按使用描边进度环和抖动，稍后再看的时针与分针按实际时间更新并响应悬停，窗口按钮使用旋转、弹簧或路径插值。主要动效遵守系统减少动态效果设置。 [窗口按钮](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L495-L528) · [换一换](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L1028-L1038) · [稍后再看](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L1104-L1133) · [精选反馈](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/enhance.js#L2334-L2343) |
| 官网内容区与常规播放控件 | WebView 直接使用 B 站网页和播放器的 DOM 与样式。`assets/web-copy` 另存公开页面响应与 CDN 快照，例如空间页的 `freshspace` CSS 和 WOFF2 图标字体。清单登记原始 URL、类型与 SHA-256，采集脚本使用独立游客会话。 [快照说明](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/web-copy/README.md) · [资源清单](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/assets/web-copy/manifest.json#L617-L683) |
| 启动、安装包与托盘 | 品牌源文件登记为 Simple Icons 的 Bilibili SVG，另有 IconArchive 参考 PNG。本地生成的 `bili-space.png` 和 `.ico` 用于应用品牌资源，Windows 托盘读取内嵌的 ICO。上游项目记录图稿为 CC0，Bilibili 商标归权利人。 [来源和哈希](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/vendor/bilibili-icon-source.json) · [托盘入口](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/src/main.cpp#L77-L83) · [Simple Icons 声明](https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md) |

独立 SVG 的上游可查发布者的图标页与许可。网页资源可通过对应按钮的 DOM、样式以及 Network 中的 Font、XHR 和其他资源请求追溯。基础 SVGA 需追到视频页组件数据，项目源码里的三个 CDN 地址只覆盖额外庆祝效果。此次来源核对基于源码与资源清单，CDN 当前可用性未验证。Bili-Space 根许可为 PolyForm Noncommercial 1.0.0，第三方作品的许可分别取自各自的上游。 [Bili-Space 许可](https://github.com/GuqiGG/Bili-Space/blob/4a4db371093b9c0069a6875009f66ff5ba7e4500/LICENSE)

## BiliSail 的实现

BiliSail 原先在同一操作栏混用了 Material 图标、UWP 来源的 `BiliIcons` 字体和自绘投币填充图标。首批收敛视频详情、精选、动态卡片里的互动图标。 [原有资源记录](../../assets/README.md#uwp-业务图标) · [视频和精选操作栏](../../lib/features/video/presentation/video_actions_bar.dart) · [动态卡片](../../lib/shared/ui/dynamic_post_card.dart)

新图形由 Flutter Canvas 独立绘制。统一 24 单位画布、1.7 单位圆角描边，按入口沿用现有 18／22／24 逻辑像素尺寸。点赞、投币和收藏提供轮廓和实心选中态，选中时使用各入口原有的强调色。选中状态从空心切到实心后，图形在 240 毫秒内轻微缩小、放大再归位。首次挂载和视频互动状态初次加载直接显示目标状态。隐藏页面和系统减少动画时直接显示静态图形。按钮仍由原有控件处理点击、焦点、提示和语义。 [共享图标组件](../../lib/shared/ui/interaction_icon.dart) · [动效测试](../../test/shared/ui/interaction_icon_test.dart)

这套图形与动效均来自 BiliSail 自身代码，离线渲染。参考采用范围为圆角线条、明确的选中轮廓和图标内短反馈。

## 验证

已渲染浅色和深色图标样张。33 项定向测试覆盖选中反馈、减少动画、隐藏页、宽窄屏按钮布局和精选评论入口。格式、静态分析和打包边界检查通过。四个包共 1,526 项测试通过，9 项播放器和 14 项封装原生测试因所需配置缺失跳过。

根应用 6,157 项通过、14 项跳过、5 项失败。失败集中在 `video_card_measurement_cache_test.dart` 和 `video_card_variants_test.dart` 的视频卡排版断言。两组测试只加载 HarmonyOS Sans，却使用同期提交 `bba3221a` 切换后的抖音美好体默认主题。复跑能重现 5 项失败，临时对照将主题显式指定为测试已加载的 HarmonyOS Sans 后，两组用例均通过。未进行实机视觉验收。
