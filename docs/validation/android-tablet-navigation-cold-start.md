# Android 平板冷启动导航布局

日期：2026-10-31。

## 问题与定位

- 用户反馈 Samsung Tab S9 普通全屏横屏运行时，推荐流已经显示四列，但导航仍为底栏，手动选择侧栏也无效。旧版本在保持应用打开的情况下转为竖屏后恢复侧栏，再转横屏保持正常；这属于修复前的用户复现，不是本次修复后的实机验收。
- [MainActivity](../../android/app/src/main/kotlin/dev/bilisail/bilisail/MainActivity.kt) 继承 `AudioServiceActivity`。固定的 [`audio_service` 0.18.19](https://github.com/ryanheise/audio_service/blob/audio_service-v0.18.19/audio_service/android/src/main/java/com/ryanheise/audioservice/AudioServicePlugin.java) 使用 Application Context 创建缓存引擎。
- 当前 Flutter 引擎 `692136cb6582dbfc5af3fb33c2515a069f2f66d0` 的 [完整屏幕指标初始化](https://github.com/flutter/flutter/blob/692136cb6582dbfc5af3fb33c2515a069f2f66d0/engine/src/flutter/shell/platform/android/io/flutter/util/ViewUtils.java) 需要从 Context 找到 Activity，因此上述创建路径会跳过初始上报。FlutterView 挂载时仍正常上报窗口指标；实际旋转触发配置变化后才补报完整屏幕指标。已同时核对固定源码和本机 SDK 的 `flutter.jar` 字节码。
- 原生显示宽、高和密度的初始值均为 `-1`。原先先除法再判断尺寸时，`Size(-1, -1) / -1` 得到有限且非空的 `Size(1, 1)`，随后命中移动端短边小于 600 的强制底栏分支。推荐网格使用实际布局宽度，所以能够同时出现四列内容和紧凑导航。尚未直接采集该设备的原始指标，未把此初始值记为实机测量值。

## 修复

- MainActivity 在配置缓存引擎、恢复前台和配置变化时，使用当前 Activity 重新计算并上报完整显示屏指标。继续复用原 audio_service 引擎，不创建第二个引擎，不修改插件缓存或 Flutter SDK。
- [WindowSizePolicy](../../lib/core/platform/window_size_policy.dart) 在除法前校验原始尺寸和密度：拒绝非正尺寸、非正密度、NaN、无穷值和溢出的结果。完整屏幕指标不可用时，临时采用独立上报且合法的窗口尺寸／密度；两者都不可用时返回零尺寸，由现有方向宿主跳过更新。
- 合法完整屏幕指标始终优先，因此已展开平板的窄分屏仍能保持大屏方向策略；导航继续根据实际窗口宽度强制底栏。手机短边小于 600、手机横屏和小于 600 的可用窗口仍受原有底栏限制，手动侧栏不会绕过这些约束。
- 不迁移、不重写导航设置；保留页面、搜索草稿、PageStorage 和播放会话。

## 验证

- [尺寸策略回归](../../test/core/platform/window_size_policy_test.dart) 使用独立的 display／view 测试对象，覆盖原生 `-1` 初始值、零／负尺寸、NaN／无穷密度、除法溢出、合法完整屏幕优先、手机横屏回退和两种指标都无效。避免 Flutter 测试框架自动绑定 display／view 密度而掩盖真实差异。
- [外壳布局回归](../../test/app/shell_layout_test.dart)覆盖平板在首次屏幕上报前的自动侧栏、底栏／侧栏设置切换、首次旋转后的横竖屏一致性、窄分屏强制底栏及草稿／组件身份保留。
- 新增场景中的 11 项在旧实现上复现失败；修复后尺寸、布局、导航模式、方向宿主和预测返回共 172 项通过。日志：`build/validation/tablet-display-fix-before.log`、`build/validation/tablet-display-fix-targeted.log`。
- 首次主工作区构建和 `tool/check.ps1 -SkipPub` 被同期图标设置修改中缺失的 `defaultTargetPlatform` 导入阻塞（当时位于 `app_icon_settings.dart:58`），未修改该任务代码。随后从已提交源码 `a1356f3a8cc36942d26f2a01226885e7f6923680` 加本任务七个文件导出独立快照，隔离其他未提交修改。失败日志：`build/validation/tablet-display-fix-android-release.log`、`build/validation/tablet-display-fix-check.log`。
- Android arm64 mux 从固定来源构建成功。独立快照通过 `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild`，复用该组件，原有 Native Assets 钩子继续完成来源／哈希校验。开发 Release APK 已复制到规定的 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，身份为 `dev.bilisail.bilisail.test`／「BiliSail 测试版」、`1.2.5+3`／12503、arm64 AOT、不可调试、本机原有开发签名；SHA-256 为 `901433d0e04e81378084d9ca061e672cfa405d8f91c44ce86c521e3851a59d0c`。日志：`build/validation/tablet-display-fix-snapshot-android-release.log`；保留既有 CupertinoIcons 字体资源和 Java 编译兼容性提示，未安装。
- 独立快照的 `tool/check.ps1 -EnforceLockfile` 全部通过：五份锁文件可复现解析、格式、静态分析、打包边界，以及根应用 3716、`bili_api` 498、`bili_player` 105、`bili_danmaku` 145、`bili_mux` 5，共 4469 项测试通过。13 项 Windows 符号链接用例因权限不足跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。日志：`build/validation/tablet-display-fix-snapshot-check.log`。提交前确认实现和测试文件与该快照一致，三个任务文档的 172 个本地链接及 `git diff --check` 通过。
- 没有连接 Android 设备或可连接的 DTD 调试进程，热重载请求未能执行。仍需使用本次 APK 验收 Tab S9 冷启动横屏、无需先旋转即可切换侧栏、横竖屏往返、分屏／前台恢复及手机强制底栏。组件回归和 APK 构建不代表这些实机行为已经通过；未构建 Windows／macOS／iOS，未测性能。
