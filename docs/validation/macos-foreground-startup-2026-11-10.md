# macOS 前台冷启动停滞

日期：2026-11-10。故障版本为 macOS arm64 `1.2.9+0`，系统为 macOS 26.5.1。前台冷启动后停在“正在加载”，切换应用后恢复；后台启动能正常显示首页。本次在独立分支修复，不修改 Flutter SDK、账号凭据或其他平台的启动流程。

## 证据与边界

- 用户导出的核心日志中，`startup → ready` 为 144 毫秒，启动请求在约 1.2 秒内结束、`active=0`，随后出现 38.5 秒记录空档；没有启动异常或请求超时。`ready` 表示 UI 已提交，不表示后续帧正常。
- 本机从访达直接前台启动已复现；请求全部完成后，首页仍保持加载画面。卡住时的三秒线程采样显示 AppKit 主线程和 Flutter raster 线程主要在等待事件，没有持续计算或锁等待栈。一次 ⌘Tab 后首页恢复显示。
- 现有导出没有 `lifecycleState/framesEnabled` 记录，不能把卡住时具体停在 `hidden` 写成已由日志直接观测的事实。以下缺口来自固定 SDK 与应用代码的交叉检查，修复后的正常启动仍需新构建实测。

## 修复

应用在 `applicationDidFinishLaunching` 中先启动 headless engine，再由 Dart 创建明确的主窗口。固定 [Flutter 3.47.6 的引擎](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterEngine.mm#L1655) 在激活时没有可见窗口会发送 `hidden`；[SchedulerBinding](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/packages/flutter/lib/src/scheduler/binding.dart#L414) 随之禁用正常帧调度。首个 warm-up／直接调度帧仍可能画出加载页，自有 `WindowInputFocus` 的同步不会修正引擎生命周期。

[原生主窗挂接](../../macos/Runner/MainFlutterWindow.swift) 验证 window handle、view ID 与 engine 身份并完成几何准备后，通过公开 `FlutterAppLifecycleDelegate` 重新读取 AppKit 遮挡状态，再按当下 `NSApp.isActive` 更新引擎活动状态。这会同时更新引擎自己的可见性／活动缓存，不直接向 Dart 伪造 `resumed`，不主动抢占前台，也不强制后台／最小化窗口持续刷新。同步只在主窗挂接处执行，不引入计时轮询或每帧补救。

## 回归与发布门槛

- `startup` smoke 在创建任何 Flutter 窗口前先激活应用，并等待真实 `didBecomeActive`（原生最多 10 秒、Dart 通道最多 15 秒）。只有显式 `--bilisail-release-smoke startup` 路径可使用这个探测入口，普通启动不主动激活。
- [Dart 入口](../../lib/main.dart) 在前台条件建立后，继续走同一主窗创建、依赖组装与 UI 提交流程。[首帧检查](../../lib/app/release_smoke.dart) 不再在创建窗口后调用 `activate()` 修复时序；首次 rasterize 后必须允许调度并完成另一个正常帧。后续两轮播放窗和跨进程凭据检查保留。
- Dart 回归覆盖正常前台／可见后台的后续帧、`hidden/paused/detached` 即使已 rasterize 也失败，以及启动探测先于主窗挂接、激活失败传播。监督脚本只增加固定 `foreground-startup` 阶段白名单，不保存额外原始数据。
- 本机无 Flutter/Dart SDK，未运行 `tool/check.ps1`、Flutter 测试或应用构建。按本次要求推送分支，格式、分析、离线回归及 macOS 编译／运行 smoke 由 remote CI 执行。现行 Intel x64 构建仍跳过运行 smoke，不能当作 x64 启动已验收。

新构建设备验收需分别覆盖从访达前台冷启动、后台冷启动后再激活、启动中切换应用，以及最小化／隐藏后恢复；前台冷启动全程不切应用，确认首页状态和图片持续刷新。
