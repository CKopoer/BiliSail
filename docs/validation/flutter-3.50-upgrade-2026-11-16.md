# Flutter 3.50 适配

日期：2026-11-16。

## SDK 与构建入口

项目固定到 Flutter **3.50.0 stable / Dart 3.14.0**。同步 `.flutter-version`、根应用和 Flutter 包的最低约束、检查／发布脚本、共享 CI 安装 Action 与发布说明。纯 Dart `bili_api` 不因应用升级而提高其独立最低约束；五份锁文件均在新 SDK 下校验。

Windows SDK 固定提交 `ab2912035e160d9cad6306df307576da6128ebdb`，归档 SHA-256 为 `35fb843409c80a1c69b64bbae1756bba437222f909622d83540e266e1759aab8`，来自[官方 Windows 发布清单](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json)。现有缓存键仍包含 SDK 版本与提交，不复用旧版本引擎。

## 直接迁移多窗口与设计库

- 播放窗口直接使用 `WindowController`、`WindowController.shrinkWrap`、`WindowControllerDelegate` 和 `Window`。保留 Windows 隐式主视图、macOS headless 主窗口、既有 `ViewAnchor`、单 engine 和会话释放顺序。
- 继续由应用显式管理窗口和窗口内 `DialogRoute`，没有采用自动注册新窗口的 `WindowManager`。新 SDK 不再由 `WidgetsApp` 自动提供该注册表；图片查看器回归改为验证实际视图数量、所属 Navigator、图片请求和返回行为。
- 应用、测试、集成测试、诊断入口和包内工具直接导入独立 `material_ui`；设计本地化使用该包公开的 `GlobalMaterialLocalizations.delegates`。不保留旧 UI 类型转换或兼容桥。
- 直接固定 `material_ui 1.11.0`；Markdown 本地移植直接固定 `cupertino_ui 1.1.6`。播放器包只在测试／诊断入口需要 Material，放入其 dev dependencies；媒体 fork 的固定提交未改变。
- `smooth_scroll_multiplatform` 本地版本变为 `1.0.8+bilisail.2`，只迁移 SDK／Material 导入，保持插值实现和许可。

Markdown 上游 `1.0.12` 及核对时的主分支仍使用旧设计库，其公开 `ThemeData` 和 `SelectableText` 无法完成直接迁移。仓库内保留该固定版本的六个库文件，直接迁移两种 UI 导入，并移除 Dart 3.14 不再接受的形参 `final` 修饰符。解析、排版、选择、链接、图片与表格逻辑保持原实现；来源、完整 Pub 摘要及 BSD-3-Clause 许可见 [UPSTREAM](../../third_party/flutter_markdown_plus/UPSTREAM.md)。不修改 Pub 缓存或相邻仓库。

## 减少动态效果与滚动

共享 `shouldReduceMotion` 同时观察 `MediaQuery.disableAnimationsOf` 与 `MediaQuery.reduceMotionOf`；任一标记开启时使用各组件既有的减少动画分支。覆盖滚轮、标签与指示器、卡片预览、列表反馈、返回过渡、歌词滚动等既有显式设置。没有新增产品设置或数据库迁移。

保留弹簧默认、Chromium／多平台模式、阻尼、距离与时长倍率、输入仲裁、嵌套边界、触控板、PageStorage 和隐藏标签取消。多平台模式原有基础距离倍率仍为 2。开启动效减弱时停止当前滚轮活动并保留位置和设置；关闭后恢复原模式，不重放旧动量。未引入 `ScrollPhysics.shouldUpdate` 或替换控制器。

SDK 测试查找器对 `excludeFromSemantics` 的 Tooltip 仍检查旧 Material 类型。相关弹幕样式测试直接查找独立 Material Tooltip，保留组件原有无障碍标签；不通过修改产品语义配合测试。导航设置测试将同名选项限定在对应设置组。

## 验证

`tool/check.ps1 -EnforceLockfile` 完整通过：五份锁文件严格解析后再执行普通 Pub，锁文件未漂移；根应用／四个包与本地第三方库格式、全仓静态分析、打包边界脚本通过。最终测试结果：

| 范围 | 通过 | 跳过 |
| --- | ---: | ---: |
| 根应用 | 5,692 | 13 |
| bili_api | 1,021 | 0 |
| bili_player | 373 | 3 |
| bili_danmaku | 161 | 0 |
| bili_mux | 5 | 10 |
| 合计 | 7,252 | 26 |

`BILI_MUX_LIBRARY` 未配置，10 项 mux 原生用例跳过；播放器的 3 项原生媒体用例也未执行，不能用普通检查或窗口烟测代替原生媒体完整验收。

Windows 额外完成：

- 从既有固定源码重新准备 `windows-x64` mux 组件。
- 普通 `lib/main.dart` Windows x64 Release 构建通过，输出 `build/windows/x64/runner/Release/bilisail.exe`；未安装或启动此普通入口产物。
- 现有离线窗口烟测通过：保留主视图、窗口缩放与最大化恢复、标题栏返回、全屏、IME 关联开关和关闭后视图释放。全屏原生窗口、客户区、Flutter 视图与屏幕均为 1920×1080。边框断言按自绘标题栏的实际语义验证；注销视图时显式等待有上限的原生异步消息，不假定 `pumpAndSettle` 已排空平台事件。
- 通过 MCP 连接上述 Debug 烟测进程并执行热重载，返回成功；测试进程已退出。现有安装版进程未改动。

烟测使用 `flutter run` 自检并输出 `All tests passed` 与 `NATIVE_WINDOW` 标记；其未检测到 `integration_test` 原生结果收集插件的提示不影响这些自检断言，也不作为 Android／XCTest instrumentation 报告。IME 仅验证关联调用，不代表真实输入法候选、组合和中文提交验收。

主要命令：

```powershell
.\tool\check.ps1 -EnforceLockfile
flutter --print-dtd run -d windows -t integration_test/detached_playback_window_smoke_test.dart
flutter build windows --release -t lib/main.dart
```

最终日志：`build/flutter-350-check-final.log`、`build/flutter-350-native-smoke-final.log`、`build/flutter-350-windows-release.log`。另有 162 项动效／窗口／Markdown 定向测试、522 项播放面板／弹幕样式回归，以及其余受影响组件定向验证；这些范围互有重叠，不累加进全量统计。

本机未执行 Android／macOS 构建与实机验收，也未执行安装升级、真实视频播放全回归或性能测量；没有从引擎更新推导帧率、视频解码或 GPU 性能结论。

## 2026-11-23 Windows 图片上传期间的原生闪退

系统安装的 x64 MSIX `1.3.0.7` 在 22:15 和 22:24 两次出现 `nvwgf2umx.dll+0x19632f` 读取地址 `0x230` 的异常。匹配的 Flutter PDB 显示，IO 线程经 Skia 和 ANGLE 提交单帧图片，上传尺寸分别为 48×48 和 60×30。两次光栅线程均停在 `GL_WaitSync` 入口获取 ANGLE 全局互斥锁处。转储没有记录先前两条命令是否曾并发访问同一个 D3D11 immediate context，也没有将异常地址关联到具体纹理。

Flutter 3.50 的 Windows 引擎中，窗口呈现和 IO 图片上传共用 ANGLE 的 D3D11 immediate context。部分 EGL 调用与 GL 调用使用不同的锁，两条线程可能同时访问该 context。开启 Impeller 的报告和显式关闭 Impeller 的报告被 Flutter 归入同一问题。引擎维护者采用的缓解措施是在引擎取得的 D3D11 immediate context 上启用多线程保护。该安装包所用的 media_kit 在自己的 ANGLE 设备上启用保护，无法由此推断 Flutter 引擎设备也受到保护。[Flutter #196618](https://github.com/flutter/flutter/issues/196618) · [Skia 报告 #196587](https://github.com/flutter/flutter/issues/196587) · [Flutter 修复 #196897](https://github.com/flutter/flutter/pull/196897)

11 月 23 日发生闪退的安装包使用 Flutter 3.50.1，该版本缺少这项保护，3.50 稳定分支回移仍在审查。已在 SDK 提交 `ae9b586f34` 上用 `git apply --check` 核对回移差异可以应用。当前结论来自源码和转储，修复后的 Windows 构建及本机播放稳定性仍待验证。[稳定分支回移 #196991](https://github.com/flutter/flutter/pull/196991)

同日，项目切换到 Flutter 3.51.0-1.0.pre-292（main），自带 Dart 3.15.0-174.0.dev。对应的 Flutter 提交为 `a7c861f6b2e720aed2d93a7d5fbea844a3322636`。Git 祖先关系确认其中包含 `6ace1aedf0`。官方构建记录将此提交对应到引擎内容哈希 `7287464421953ee518d1f84ee8effd98fa9e76b5`。Windows x64 和 ARM64 的 Release 引擎归档均已发布。偶发闪退是否消失仍需使用新引擎重复实测。[Flutter 源码](https://github.com/flutter/flutter/commit/a7c861f6b2e720aed2d93a7d5fbea844a3322636) · [官方引擎构建记录](https://storage.googleapis.com/flutter_infra_release/flutter/7287464421953ee518d1f84ee8effd98fa9e76b5/engine_stamp.json)
