# Android 系统手势条背景修复

日期：2026-10-30。

## 原因与处理

- 当前固定的 Flutter 3.47.6 中，`MaterialApp._themeBuilder` 使用 `SystemUiOverlayStyle.light/dark`；这两个预设都将系统导航栏设为黑色，导航图标设为浅色。此前应用没有自己的系统栏样式，因此浅色页面底部可能仍保留黑底。
- [应用入口](../../lib/main.dart)显式启用 edge-to-edge，使 Android 10–14 也使用贯穿系统栏的安全区布局；Android 15/16 沿用系统强制的 edge-to-edge，不退出该模式。
- [AndroidSystemUi](../../lib/core/presentation/android_system_ui.dart)在 [MaterialApp builder](../../lib/app/bili_app.dart) 内以 `AnnotatedRegion<SystemUiOverlayStyle>` 提供随当前应用主题变化的样式。兼容系统使用主题 `surface` 底色，浅色主题使用深色图标、深色主题使用浅色图标；关闭导航栏对比度遮罩并清除分隔线。Android 15+ 手势区由系统透明合成，实际背景由 Flutter 绘制。
- [工作区](../../lib/app/shell.dart)在既有窄屏底色修复之上，让 Android 的 Scaffold 统一使用主题 `surface`，底栏／侧栏布局的手势区都能与界面衔接；`SafeArea` 继续保留，按钮和内容不进入手势条区域。其他平台保持原背景与系统栏策略。
- [Android 全屏适配](../../android/app/src/main/kotlin/dev/bilisail/bilisail/MobileWindowHandler.kt)在 API 26–29 改变系统栏可见性时保留深浅图标标志，避免退出全屏后出现浅底浅图标。全屏显隐与方向策略仍由既有窗口服务管理。
- [共享全屏播放路由](../../lib/features/playback/presentation/playback_panel.dart)显式使用黑底、浅色系统栏图标，确保浅色应用主题下临时唤出系统栏仍可见；路由关闭后恢复当前页面主题，不改变播放器或会话所有权。

官方依据：[Flutter 系统栏样式与 AnnotatedRegion](https://api.flutter.dev/flutter/services/SystemChrome/setSystemUIOverlayStyle.html)、[edge-to-edge 迁移与 Android 16 限制](https://docs.flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge)。本次没有引入依赖或复制上游源码。

## 验证

- [系统栏回归](../../test/core/presentation/android_system_ui_test.dart)的 6 项用例覆盖实际平台通道样式、浅色→深色→浅色切换、含 AppBar／黑底全屏的路由进出、390×844／900×600 两种布局的浅深色底部实际像素与安全区几何，以及 iOS 不应用 Android 策略。
- 为隔离同期功能修改，验证使用 `8396b88` 基线、已提交的窄屏背景修复 `2ee2ef5` 和本次改动组成的独立检出。五份锁文件的 `--enforce-lockfile` 解析通过；`tool/check.ps1 -SkipPub -Stage Lint` 的格式、全工程静态分析及打包边界检查通过。最后补充的全屏样式与测试也通过定向静态分析。
- 根应用全量运行得到 3401 项通过、9 项下载仓储超时、13 项符号链接权限跳过；9 项失败均在未修改的 `sqlite_download_repository_test.dart`。随后以 `--concurrency=1` 复查本次系统栏／外壳／窗口服务及该下载文件：125 项通过、1 项权限跳过，其中界面与窗口 92 项、下载 33 项通过，原 9 项超时未复现。保留首次失败记录，不将它改写为单次全量通过。
- 四包测试通过：bili_api 496、bili_player 96、bili_danmaku 118、bili_mux 5，共 715 项。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不代表原生封装验收。
- Android arm64 mux 准备通过；最终执行 `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 通过，复用未修改的 mux 资产。实际 APK 校验为 `dev.bilisail.bilisail.test`／`BiliSail 测试版`、`1.2.5+0`（versionCode 12500），Release/AOT 且不可调试，沿用现有开发证书。没有安装到设备。保留既有 CupertinoIcons 字体资源和第三方 Java 弃用警告。
- 隔离检出首次下载 SQLite／media-kit 原生资产时发生 TLS 握手失败；复用本机缓存后，原构建钩子继续检查归档及库的哈希，未改动 Pub 缓存、TLS 验证或依赖来源。
- 完整日志、最终 APK 及校验元信息保留在 `build/validation/android-system-navigation-2026-10-30/`；文档本地链接和 `git diff --check` 通过。
- 本轮 `adb devices -l` 没有连接设备，未做真实系统手势条、三键导航、输入法收起及全屏往返验收。DTD 未发现调试应用，热重载调用未能执行。组件/构建验证不能代替这些设备检查；未构建或操作 Windows/macOS，也未作性能测量。
