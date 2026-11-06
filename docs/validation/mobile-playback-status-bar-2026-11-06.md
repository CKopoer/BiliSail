# 移动端播放页黑色状态栏

日期：2026-11-06。

## 修改

- Android／iOS 的视频、影视、直播和离线播放页共用工作区的[状态栏适配](../../lib/core/presentation/mobile_playback_status_bar.dart)。在既有顶部安全区绘制纯黑背景，并提供白色状态栏图标；Android edge-to-edge 下由 Flutter 实际绘制底色。
- [工作区外壳](../../lib/app/shell.dart)按当前页面身份启用；进入 UP 空间或返回浏览页时恢复原页面背景和图标策略。保留既有 SafeArea、底部导航栏策略和播放会话所有权，桌面平台保持原行为。
- 全屏显隐与方向仍由既有窗口服务管理，本次没有修改原生工程或播放器。

## 验证

- `flutter test --no-pub test/core/presentation/mobile_playback_status_bar_test.dart test/core/presentation/android_system_ui_test.dart`：11 项通过。
- 新增[组件回归](../../test/core/presentation/mobile_playback_status_bar_test.dart)覆盖 Android／iOS、浅／深主题、四类播放路由、390×844 与 900×600 布局，读取实际顶部绘制像素与平台通道图标参数，并验证保留的播放页不影响 UP 空间和首页。既有 Android 系统栏测试同时通过。
- 三个改动 Dart 文件定向 `flutter analyze --no-pub` 通过。
- 按用户要求不构建、不安装、不进行实机或性能测试；Android／iOS 系统实际合成、刘海／挖孔屏和全屏往返由用户后续验收。未发现运行中的 DTD／调试应用，无法热重载。
