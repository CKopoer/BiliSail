# macOS 长时间运行后灰窗与退出兜底

日期：2026-11-06。对应 [#78](https://github.com/CKopoer/BiliSail/issues/78)：1.2.6+6 在 MacBook Air / macOS 27.0.1 长时间运行并经历休眠后出现纯灰窗口，菜单退出和 ⌘Q 无效。当前没有完整 sample、发生前后的日志或稳定复现条件，用户确认无法取得这些材料。本次修复源码中确认存在的退出无限等待，不将其写成灰屏触发原因已经确定或长期稳定性已经通过。

## 定位与可能路径

1. **确定的退出缺陷**：[ApplicationTerminationCoordinator](../../macos/Runner/AppDelegate.swift) 首次退出后设置 pending，必须等 Dart 回复才可能清除；无回复时，后续每次退出都返回 `terminateCancel`。[MacOSApplication.requestExit](../../macos/Runner/MainFlutterWindow.swift) 又把除 `response=exit` 之外的所有结果解释为取消，包括引擎不可用、通道未实现、FlutterError 和格式异常。因此 UI/isolate/通道失效会进一步变成无法退出。
2. **不能仅靠线程名称确认 isolate 消失**：固定 [FlutterEngine.mm](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm) 默认合并 platform/UI 线程，Dart UI 可以运行在 AppKit 主线程；DartWorker 不是 UI isolate 的专属线程。原报告还保留 raster/io 线程，不能直接认定整个 FlutterEngine 已销毁。mpv 线程消失也可能是会话已经关闭，缺少时序无法判定先后关系。
3. **休眠后的渲染停滞是候选**：上游 [flutter/flutter#188493](https://github.com/flutter/flutter/issues/188493) 报告显示设备变化后 raster 停滞，但其 Dart 仍可回应，且有外接显示器断开的具体条件。#78 没有相应 raster 栈，不能套用其根因或据此切换渲染器。
4. **isolate 或清理流程中断也是候选**：灰窗、播放器线程消失与清理已部分执行相容，也与独立的 Dart/原生故障相容。当前没有事件证明应用曾进入退出清理；没有修改播放会话所有权、Flutter SDK、媒体依赖或全局异常处理来猜测性规避。

## 修复行为

- 正常退出仍等待 Dart 既有的下载、播放、数据库和窗口清理，且离开平台消息回复栈后才调用 AppKit terminate，保留之前修复的关闭重入边界。
- 原生主队列在首次退出时启动 **30 秒**清理 deadline。Dart 始终无回复时，记录 `BILISAIL_TERMINATION:timeout` 并排队进入原生退出，不再无限取消。计时器不依赖 Dart，也不定期监视或自动结束正常运行、后台或休眠中的应用。
- 只有明确的 `response=cancel` 才保留应用；空回复、未实现、FlutterError、未知格式均为 unavailable，记录 `BILISAIL_TERMINATION:unavailable` 并排队进入原生退出。
- 每次请求持有独立 attempt；成功或取消后取消 deadline。旧 timeout、迟到回复和重复回复不能影响新请求、撤销已排队的退出或重复执行 terminate。等待与排队期间的重复 ⌘Q 仍合并。
- 原生固定日志记录引擎启动、应用终止、engine shutdown 开始/完成，以及 NSWorkspace 休眠/唤醒通知。观察者在宿主释放时从对应通知中心移除。日志不包含窗口标题、参数、通道回复、异常正文、路径或账号内容。

此兜底依赖 AppKit 主线程仍能调度，符合 #78 提供的主线程空闲描述；它不能恢复已经损坏的渲染表面，也不解决主线程本身卡死或 native shutdown 内部死锁。清理超时后未完成的 Dart flush 不保证完成；正常路径仍完整等待清理。没有强杀进程、清空数据或自动重建 engine。

## 验证

- [Swift XCTest](../../macos/RunnerTests/RunnerTests.swift) 更新原有 4 项退出测试，增加 5 项：无回复超时与迟到/重复回复、成功取消 deadline、取消后重试隔离旧 timeout/回复、不可用回复延后退出，以及通道结果分类。
- 当前 Windows 主机没有 Swift/Xcode，**尚未编译 Swift、运行 XCTest 或构建 macOS 应用**。通用 Dart/Flutter 检查不能替代这些原生验收。
- `tool/check.ps1 -SkipPub` 完整通过，日志 `build/issue-78-check-2026-11-06.log`：格式、统一静态分析、脚本/打包边界及 **5503** 项 Dart/Flutter 离线测试（根应用 4502、bili_api 672、bili_player 163、bili_danmaku 161、bili_mux 5），另有 15 项 Python 诊断测试和 22 项真实子进程监督场景通过。13 项 Windows 符号链接用例因权限跳过，10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，均不计为原生通过。计数包含工作区同期播放器/Android 修改，本任务保留这些修改。
- 本文与文档索引共 203 条本地 Markdown 路径及 `git diff --check` 通过。本次仅修改 Swift、XCTest 与文档，无 Dart 热重载内容；原生宿主必须重新编译。

Mac 上执行原生测试：

```sh
xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Debug -destination 'platform=macOS' -only-testing:RunnerTests
```

设备验收需覆盖正常播放后 ⌘Q、重复退出、主窗口关闭、播放窗口单独关闭，以及长时间挂起/合盖唤醒。故障注入应在测试构建让 exit 请求不回复或返回不可用，确认 30 秒兜底、脱离回复栈终止、进程结束与系统音频断言释放；不能用正常退出冒充异常路径验证。

若再次发生，可在 macOS「控制台」按 `BILISAIL_LIFECYCLE:` / `BILISAIL_TERMINATION:` 检索，或执行：

```sh
log show --last 1d --style compact \
  --predicate 'process == "BiliSail" AND (eventMessage BEGINSWITH "BILISAIL_LIFECYCLE:" OR eventMessage BEGINSWITH "BILISAIL_TERMINATION:")'
```

这些标记位于 macOS unified log，不包含在现有仅导出核心/播放器文件的日志 ZIP 中。需要结合故障当时的完整 sample（特别是 main/raster 栈）与应用日志，才能继续区分渲染阻塞、Dart 无响应和退出清理中断；本次没有这些证据，灰屏最初触发点仍待验证。
