# 弹幕发送色板与样式面板

日期：2026-10-31。

## 范围与来源

只读参考相邻 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441` 的 [发送面板](../../../PiliPlus/lib/pages/video/send_danmaku/view.dart) 与 [RGB 选择器](../../../PiliPlus/lib/pages/setting/slide_color_picker.dart)。其应用为 GPLv3；本次参考普通 RGB 预设值、自定义色值及颜色预览的交互职责，独立实现 Flutter 组件，没有复制应用源码、资源或新增依赖。参考工程锁定 `bggRGjQaUbCoE/canvas_danmaku@275046d8647a6a26cba1d0dadb9e28688cb3dbf1`，与本应用的固定 Predidit 依赖分别处理，没有修改相邻仓库或锁文件。

补齐参考面板的 14 种普通颜色，保留原有粉色 `FF6699`、金色 `FFD700`、蓝色 `00A1D6`，共 17 色。自定义支持六位十六进制输入与 R／G／B 滑块，范围为 `000000`–`FFFFFF`，只在完整合法时应用。PiliPlus 的会员渐变需要额外的 `colorful` 协议、权限与绘制适配，本轮范围为普通 RGB 发送，没有加入会员渐变入口。

## 交互与适配

- 视频与影视、普通与全屏继续共用 [样式按钮](../../lib/shared/ui/danmaku_send_style_button.dart) 和 [面板](../../lib/shared/ui/danmaku_send_style_panel.dart)，已选样式仍归 `PlaybackSession` 持有，没有新增全局偏好或数据库迁移。
- 一次打开可同时调整滚动／顶部／底部和颜色，深浅两种背景预览当前颜色；点击“完成”一次性应用。关闭、取消、遮罩或 Escape 丢弃草稿，不改变已有设置，也不发送弹幕。打开／取消不清除发送栏文字。
- 面板按当前窗口可用空间适配：宽度小于 600 时靠底，其他情况居中，内容最大宽度 440。使用现有 `showAppDialog`，保持当前 View 的弹层归属、模态快捷键隔离和焦点循环，不创建额外原生窗口。
- 色块为 44×44，提供名称提示、选中边框／勾选与读屏颜色值。发送栏最小高度调整为 44，按钮同时显示颜色圆点，深色选项仍有可辨识的按钮图形。
- 模式与色块自动换行，全部内容可滚动，遵守 SafeArea 和键盘避让；短横屏、大字号和分屏可滚动到确认按钮。自定义输入未完成时禁止应用，收起自定义编辑时回到最近合法值；键盘 Enter 可确认合法色值。重复点击入口只打开一个面板。

发送 API、账号／源隔离、确认成功后回显和未知结果不重试规则沿用 [发送链路验证](danmaku-display-area.md#发送链路复查)，色值仍为无 alpha 的 24 位 RGB。

## 验证

- [组件回归](../../test/shared/ui/danmaku_send_style_button_test.dart) 覆盖预设和旧色、确认／取消／Escape／遮罩、重复打开、禁用、完整／不完整色值、带 `#` 粘贴、滑块与重新打开。
- Android／iOS／Windows／macOS／Linux 的平台配置均覆盖 320×640、640×280、1280×800 和 2 倍文字，加入键盘 inset 后检查可达的自定义输入、确认和无溢出。这些是 Widget 配置测试，不代表各平台设备验收。
- [发送回归](../../test/features/video/video_danmaku_send_test.dart) 覆盖旧色、新增红／绿／深灰与三种模式，自定义 `000001` 经过真实控制器／Repository／API 后仍为十进制 `1`；打开面板保留草稿，确认样式不触发网络写入。
- 新增 [Widget 预览入口](../../lib/shared/ui/previews/danmaku_send_style_preview.dart)，包含手机、桌面和大字号。当前 SDK 的 CLI previewer 将目录 `bili-lite` 生成为 `bili_lite` path 依赖，与实际包名 `bilisail` 不一致而启动失败，未修改工程名或 SDK 来绕过，改用 Windows 原生合成预览检查。
- 定向 62 项测试通过，日志为 `artifacts/danmaku-style-targeted.log`。全仓 `tool/check.ps1 -SkipPub` 通过格式、静态分析、打包边界及测试：根应用 3747、API 498、播放器 105、弹幕 145、mux 5；根应用 13 项和未配置 `BILI_MUX_LIBRARY` 的 10 项 mux 原生用例跳过。计数包含同期其他任务的工作区修改，日志为 `artifacts/danmaku-style-check.log`。
- Windows Debug 原生合成预览、热重载通过，工具报告无运行时错误，实际检查普通／自定义／大字号画面，截图为 `artifacts/danmaku-style-picker-windows.png`。预览结束后，普通入口 `lib/main.dart` 的 Windows Debug 构建通过，日志为 `artifacts/danmaku-style-normal-build.log`。

本轮没有发布真实测试弹幕。Android／Apple／Linux 原生输入法、触摸手感与读屏设备验收仍待执行。
