# macOS 全屏独立播放窗关闭时序

日期：2026-11-03。用户报告应用全屏、双窗口模式、播放器全屏时，关闭窗口快捷键使整个应用崩溃。本轮在 Windows 核对固定 SDK 和当前源码，修复确认存在的生命周期竞态；没有本次 Mac 崩溃报告，也没有在 Mac 复现，不能将源码修正视为已经确认该设备的崩溃模块或完成原生验收。

## 当前关闭链与缺口

- 浏览窗和播放窗仍由同一个 headless engine/isolate 持有，各有自己的 FlutterView。[播放窗口外壳](../../lib/app/workspace_playback_window.dart)提供局部 MaterialApp/Navigator/AppInputHost；[PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart)通过最近的 Navigator 展示全屏路由，普通和全屏共用同一个 PlaybackSession，不把路由推到浏览窗。
- Flutter 收到的 Cmd+W 由播放窗自己的输入宿主按现有 closeTab 规则处理，先关闭页内详情或消费媒体历史，历史为空才关闭播放槽。AppKit 原生关闭则经 SDK delegate 的 windowShouldClose 进入 Dart；两条入口最终都移除播放子树。主窗的关闭和 Cmd+Q 仍走既有进程级退出握手。
- 固定 Flutter 3.47.6 的 `FlutterWindowController.mm` 中，`InternalFlutter_Window_SetFullScreen` 只调用 `NSWindow.toggleFullScreen`，没有等待 AppKit 动画完成。原 Dart 适配将同步 FFI 返回包装为已完成 Future，PlaybackPanel 的退出清理因此不是原生退出全屏的完成屏障。
- 同一 SDK 的 `destroyWindow` 先 dispose FlutterViewController，再移除 NSWindow delegate 并关闭窗口。原[窗口退休流程](../../lib/core/platform/detached_playback_window.dart)只等待 Flutter 帧和几何保存；页面的 ProviderScope 释放通过 PlaybackManager 异步关闭会话，也没有接入该窗口退休 Future。因此原生全屏转换、媒体/纹理释放、视图销毁可能交错。
- 历史 `Timer.run` 修正仅覆盖主浏览窗退出与进程终止重入，不覆盖本次播放窗的原生全屏完成和媒体释放屏障。

## 修复

1. [macOS 原生宿主](../../macos/Runner/MainFlutterWindow.swift)按 viewId 和 NSWindow handle 双重匹配接收全屏请求。每个窗口独立的 `WindowFullScreenCoordinator` 观察 AppKit 的 will/did enter/exit 通知，将切换和通道回复排到下一轮主线程；不替换 SDK 的窗口 delegate。
2. 普通全屏切换等到 didEnter/didExit 才完成；关闭开始后丢弃未启动的进入请求，等待已开始的转换，最后退出全屏。重复关闭共用同一完成条件，迟到的全屏请求不能重新启动退休窗口。原生等待限 10 秒，Dart 通道限 12 秒；失败明确报错，不能继续执行 SDK destroy。
3. [WindowService](../../lib/core/platform/window_service.dart)通过注入的窗口能力接收完成信号，关闭 Future 单飞并禁止迟到呈现变更。[组合根](../../lib/app/bili_app.dart)将 [PlaybackManager.drainReleases](../../lib/features/playback/application/playback_manager.dart)接入独立窗口退休：子树卸载后等待已关闭页面的 engine 释放，再等待原生退出全屏，离开帧/通道回调栈后才销毁窗口。保留的其他会话不参与释放。
4. 原生播放窗关闭请求先离开 SDK isolate-local FFI 回调，再执行工作区导航和焦点切换；快速重开等待上一个窗口退休完成，避免两个播放器的创建/释放重叠。

保留“主浏览窗＋独立播放窗”、现有媒体历史和单会话所有权；无依赖、设置、持久化格式或 Flutter/插件缓存修改。原生关闭失败会保留未安全退出全屏的 native view 并报告错误，避免强行销毁；实际 AppKit 失败恢复体验仍需 Mac 验收。

## 回归与平台边界

- [完整会话 widget 回归](../../test/features/playback/macos_fullscreen_close_test.dart)使用真实 PlaybackManager/PlaybackSession 和 fake engine/secondary view，验证全屏 Navigator 属于播放 view、浏览 Navigator 不入栈、普通/全屏最多一个 surface、Cmd+W 与重复关闭请求、延迟媒体释放和原生退出完成、保留其他会话及释放完成后的再次打开。
- [窗口组件回归](../../test/core/platform/detached_playback_window_test.dart)验证关闭回调离开原生调用栈、失败屏障不销毁窗口、快速重开必须等待旧 engine/全屏窗口退休；[窗口能力回归](../../test/core/platform/window_service_test.dart)验证关闭单飞、等待注入的原生完成、几何读取期间的关闭与迟到全屏取消。
- [Swift XCTest](../../macos/RunnerTests/RunnerTests.swift)新增四项调度回归，覆盖进入动画期间重复关闭、未开始的进入取消、系统退出全屏、外部关闭失败和通知栈外回复。Windows 没有 Xcode，未编译/执行这些 XCTest。Mac 命令：`xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -only-testing:RunnerTests`。
- Windows 原生 `tool/test-windows-video-dispose.ps1` 的 9 项生命周期、渲染队列和尺寸测试通过；它验证 Windows 释放边界，不验证 AppKit。
- 最终窗口、窗口能力、全屏关闭、WorkspacePlaybackWindow 与侧键五组定向测试 **63 项通过**；日志为 `build/macos-fullscreen-close-targeted-final.log`。
- Windows `tool/test-windows-main-close.ps1` 编译 Debug 宿主并通过 2 项真实集成回归，包含本地 DASH 音视频、独立播放窗关闭/重开、主窗等待 engine/secondary view 释放、重复退出和延迟数据库关闭。日志为 `build/macos-fullscreen-windows-main-close.log`；仍有第三方 CMake CMP0175 提示，不据 Debug 构建作性能结论。
- `tool/check.ps1 -SkipPub` 在任务隔离验证副本完整通过：脚本/打包边界、格式、统一静态分析和 **4966** 项 Dart/Flutter 离线测试（根应用 4111、API 547、播放器 142、弹幕 161、封装 5），另有 15 项 Python 采集器测试与 22 项真实子进程监督场景通过。13 项 Windows 符号链接用例因权限跳过，10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，均不计为原生通过。并行验证曾占用共享 native-assets DLL，因此副本使用独立 build 目录；本任务九份代码/测试文件的 SHA-256 与副本一致。完整日志为 `build/macos-close-validation/build/macos-fullscreen-close-check-final.log`。
- 本文 11 条本地文档/源码路径与 `git diff --check` 通过。DTD 未发现可连接的调试应用，热重载请求未完成；Swift 修改仍需重新编译 macOS 宿主。

Mac 实机仍需：主窗先进入系统全屏后打开视频；播放窗再次进入/退出播放器全屏；Cmd+W、菜单关闭及红色关闭按钮；按住/重复关闭；进入/退出动画中关闭；原生分组标签中的播放标签关闭；普通播放窗关闭并立即重开；主窗仍可浏览、无遗留音频和回调；主窗关闭/Cmd+Q 正常等待共享清理。需分别记录 macOS arm64/x64 的构建、XCTest 和设备音画结果。本轮没有 Mac 构建、真实账号或性能测量。
