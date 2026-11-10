# macOS 前台冷启动停滞

日期：2026-11-10。故障版本为 macOS arm64 `1.2.9+0`，系统为 macOS 26.5.1。前台冷启动后停在“正在加载”，切换应用后恢复；后台启动能正常显示首页。本次在独立分支修复，不修改 Flutter SDK、账号凭据或其他平台的启动流程。

## 证据与边界

- 用户导出的核心日志中，`startup → ready` 为 144 毫秒，启动请求在约 1.2 秒内结束、`active=0`，随后出现 38.5 秒记录空档；没有启动异常或请求超时。`ready` 表示 UI 已提交，不表示后续帧正常。
- 本机从访达直接前台启动已复现；请求全部完成后，首页仍保持加载画面。卡住时的三秒线程采样显示 AppKit 主线程和 Flutter raster 线程主要在等待事件，没有持续计算或锁等待栈。一次 ⌘Tab 后首页恢复显示。
- 现有导出没有 `lifecycleState/framesEnabled` 记录，不能把卡住时具体停在 `hidden` 写成已由日志直接观测的事实。以下缺口来自固定 SDK 与应用代码的交叉检查，修复后的正常启动仍需新构建实测。

## 修复

应用在 `applicationDidFinishLaunching` 中先启动 headless engine，再由 Dart 创建明确的主窗口。固定 [Flutter 3.47.6 的引擎](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm#L1655) 在激活时没有可见窗口会发送 `hidden`；[SchedulerBinding](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/packages/flutter/lib/src/scheduler/binding.dart#L414) 随之禁用正常帧调度。首个 warm-up／直接调度帧仍可能画出加载页，自有 `WindowInputFocus` 的同步不会修正引擎生命周期。

[原生主窗挂接](../../macos/Runner/MainFlutterWindow.swift) 验证 window handle、view ID 与 engine 身份并完成几何准备后，通过公开 `FlutterAppLifecycleDelegate` 重新读取 AppKit 遮挡状态，再按当下 `NSApp.isActive` 更新引擎活动状态。这会同时更新引擎自己的可见性／活动缓存，不直接向 Dart 伪造 `resumed`，不主动抢占前台，也不强制后台／最小化窗口持续刷新。普通启动仅在主窗挂接处同步，不引入计时轮询或每帧补救。

## 回归与发布门槛

- `startup` smoke 在创建任何 Flutter 窗口前，先通过公开原生生命周期接口向真实引擎回放无窗口激活事件。入口只接受显式 `--bilisail-release-smoke startup`，并要求没有主窗、隐式控制器或可见 AppKit 窗口；不创建引导窗口，也不调用系统激活接口。
- [Dart 入口](../../lib/main.dart) 等待引擎的真实生命周期消息，确认 `hidden` 且 `framesEnabled=false` 后，继续走同一主窗创建、依赖组装与 UI 提交流程。原生通道与生命周期等待分别限五秒，缺少禁帧前提立即阻断。[首帧检查](../../lib/app/release_smoke.dart) 不在创建窗口后调用 `activate()` 修复时序；首次 rasterize 后必须允许调度并完成另一个正常帧。后续两轮播放窗仍检查真实前台焦点，跨进程凭据检查保留。
- Dart 回归覆盖正常前台／可见后台的后续帧、`hidden/paused/detached` 即使已 rasterize 也失败，以及建窗前禁帧、原生回复后异步送达生命周期、缺少 `hidden` 时超时和原生错误传播。监督脚本只接受固定 `headless-startup`／`headless-hidden` 阶段标记，不保存额外原始数据。
- 初版提交 `617edec4` 的格式、静态分析及离线回归在 CI 通过，arm64 Release 编译和签名通过；运行 smoke 的失败及修正见下文。现行 Intel x64 构建仍跳过运行 smoke，不能当作 x64 启动已验收。

## CI 42809726088：无窗口激活前置条件失败

[arm64 job](https://github.com/CKopoer/BiliSail/actions/runs/42809726088/job/129808946983) 的 `startup.result.json` 记录 `lastStage=foreground-startup`、`errorKind=platform`、`exitCode=1`，`timedOut` 和 `supervisorTimedOut` 均为 `false`。进入该阶段后约 10.35 秒退出，尚未执行 `window-create`。结合初版原生代码的十秒 deadline，可定位到 `startup_activation_timeout` 路径；诊断白名单本身未保存具体平台错误码。

初版用 `NSApp.activate(ignoringOtherApps: true)` 等待无窗口进程真正激活，而 CI 直接启动 bundle 内的可执行文件。该请求在本次 runner 没有获得激活。Apple 的[协作激活说明](https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation)明确指出激活是系统决定是否接受的请求，不能假设一定获准。现有证据不足以进一步判定 runner 当时的前台应用或具体拒绝原因，也不表示所有无窗口应用均不能激活。

修正把生命周期缺口的回归改为受限的引擎事件回放：在无窗口阶段调用公开生命周期 delegate，要求 Dart 先实际观察到禁帧，再由生产 `attachMainWindow` 按真实 `NSApp.isActive` 和可见性恢复。回放不直接向 Dart 发送 `resumed`，也不替代生产恢复代码。首帧后的正常调度和全部后续运行门槛保留；真实访达前台冷启动仍属于设备验收。

本轮 Linux / Flutter 3.47.6、Dart 3.13.5 的两份启动定向测试共 24 项通过，`flutter analyze --no-pub` 无问题，根应用及四个包共 1107 个 Dart 文件格式检查通过。发布脚本的 25 项权限／确认、7 项打包边界、22 项真实子进程监督回归和 15 项 Python 诊断采集器测试通过；文档的 319 条本地文件链接及 `git diff --check` 通过。容器的 PID 1 不回收孤儿进程，监督回归通过进程回收包装器运行，仓库监督逻辑未改动。五份锁文件已按 `--enforce-lockfile` 解析，本机未执行 macOS 构建、GUI 或设备验证，原生执行结果须由新 macOS CI 复验。

新构建设备验收需分别覆盖从访达前台冷启动、后台冷启动后再激活、启动中切换应用，以及最小化／隐藏后恢复；前台冷启动全程不切应用，确认首页状态和图片持续刷新。
