# 触摸长按临时倍速

日期：2026-10-07。

## 行为与设置

- 普通视频、影视与离线点播共用播放面板：触摸长按视频画面达到设置中的「长按触发延迟」后，使用「长按临时倍速」播放；松开或收到手势取消事件后恢复按下前的倍速。默认延迟 400 毫秒、临时 3x，复用现有设置，不新增持久化字段。
- 普通画面和全屏均支持，控制栏显示或隐藏时行为一致。加速期间显示当前倍速提示；长按不切换控制栏、不跳转进度，也不主动改变播放／暂停意图。
- 页面隐藏、切换播放源、打开弹窗、修改长按设置、应用失活／进入后台和页面销毁都会取消等待或恢复临时速度。旧手势尚未达到触发延迟时发生上述变化，继续按住也不会对新页面／新播放源加速；需要重新按下。
- 短按仍切换控制栏，双击仍切换全屏；触发前拖动超过手势容差不会加速。播放器按钮与滑块保留自己的交互。仅触摸设备识别此手势，鼠标点击保留原行为；直播不开放倍速。
- 快捷键总开关仅影响键盘／侧键，触摸长按仍可使用现有延迟与倍速设置。设置中的倍速项增加触摸操作说明。

## 状态归属

[PlaybackShortcutController](../../lib/features/playback/application/playback_shortcut_controller.dart) 由播放面板持有，普通／全屏视图共用。触摸按下先登记输入来源及播放源代次，再由手势识别器通知开始加速，让既有输入取消和路由／焦点隔离也能取消尚未触发的触摸。键盘与触摸交替时只保留最近一次长按，旧输入的松开不会结束新输入的长按。

[PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart) 使用 Flutter 的 [LongPressGestureRecognizer](https://api.flutter.dev/flutter/gestures/LongPressGestureRecognizer/LongPressGestureRecognizer.html)，指定触摸设备与设置中的延迟，复用原单击／双击识别器；延迟修改后重建识别器。开始／恢复都调用现有 `PlaybackSession.beginTemporaryRate`／`endTemporaryRate`，沿用源代次隔离和串行媒体命令，不直接调用原生后端。

临时速度不会进入工作区播放快照或应用内手动倍速记忆；原有会话恢复和迟到调速防护见 [应用会话内继承倍速](session-playback-rate.md)。没有新增依赖、数据库迁移或播放器包契约。

## 验证

- 播放面板与会话共 168 项定向回归通过，日志：[播放回归](../../build/touch-hold-playback-tests.log)；随后增加的 2 项键盘／触摸交替长按回归也通过，日志：[交替输入回归](../../build/touch-hold-input-handoff.log)。新增共 26 项用例覆盖设置的延迟／倍速、普通／全屏和控制栏显隐、保持播放／暂停意图、松开恢复、原生调速未完成时松开、触发前／后的七类取消、设置修改后下一次手势、短按、拖动、鼠标、按钮、直播和交替输入边界。既有鼠标／触摸双击、键盘长按和临时速度不写入快照／继承记录的回归继续通过。
- `tool/check.ps1 -SkipPub` 完整通过：根应用 1264、`bili_api` 319、`bili_player` 32、`bili_danmaku` 52，共 1667 项测试；根应用与三个包的格式、静态分析均通过，日志：[完整检查](../../build/touch-hold-check.log)。上述后加的 2 项交替输入回归单独验证。
- Windows 原生播放器定向回归通过：真实 `MediaKitEngine` 与本地音视频分轨，在普通／全屏画面注入触摸长按，验证实际 1.5x → 3x → 1.5x，正常松开及取消均恢复、暂停／位置／控制栏／播放源保持，并继续通过六轮全屏和既有弹幕验证。日志：[Windows 原生回归](../../build/touch-hold-windows-native-final.log)。这项测试包含 Windows Debug 构建；触摸由测试框架注入，不能替代移动设备人工操作。

按用户要求，通过测试后直接提交，不再额外构建。当前仅连接 Windows 与 Edge，没有 Android 实机；本轮未构建 Android／发布产物，Android 真实触摸手感、原生音画倍速及 macOS 运行仍未验证。测试不使用真实账号或 Bilibili 在线请求，不作性能结论。
