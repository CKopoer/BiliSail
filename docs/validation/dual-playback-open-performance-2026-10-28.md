# Windows 双标签播放窗打开性能

日期：2026-10-28。用户反馈 Windows 双标签模式每次点击视频、重新弹出播放窗都有延迟。

## 定位与修改

热点在窗口首帧前，视频详情和媒体下载不参与以下测量。固定 Flutter 3.47.6 的 Windows `FlutterWindowsView::OnWindowSizeChanged` 对已有渲染 surface 的尺寸变化同步等待新帧，最多 100 ms。原来使用固定尺寸 `RegularWindowController`，新 view 尚未挂载 Flutter 内容时，SDK 创建窗口、应用配置自绘标题栏分别触发这段等待。连续重开采样中，创建约 103–105 ms，准备约 101–103 ms，占首显耗时绝大部分。

- [窗口适配](../../lib/core/platform/detached_playback_window.dart)在 Windows 使用 SDK 自带 `RegularWindowController.sizedToContent(resizable: true)`。准备阶段不等待尚不存在的首帧；首帧后 SDK 自动停止内容定尺寸，恢复用户自由缩放。macOS 继续使用原构造方式。没有修改 Flutter SDK、Pub 缓存或播放器依赖。
- 初始内容以恢复后的原生客户区尺寸布局。SDK 按系统标题栏计算外框，而应用使用自绘标题栏；直接切换构造方式会每次重开多加一段标题栏高度。[原生几何适配](../../windows/runner/playback_window_geometry_win32.h)在首显前保留准备好的外框尺寸，首次显示后移除约束。尺寸按值存入窗口 subclass，取消、旧 owner 替换与销毁均清理；保留原有首次可见即最大化的处理。
- 新页面等待其播放 view 准备完成后直接挂载，省去主窗口内隐藏页面的一次创建、布局和跨 view 迁移。只有从单／多标签切换过来的已有页面暂时保留在隐藏区域，沿用原页面、Provider scope 和播放会话。准备期间取消打开的新页面不启动页面工作。
- 视频、PGC、直播和离线播放共用窗口宿主。未增加窗口池、提前初始化播放器或延长已关闭会话的生命周期。

## Profile 测量

[窗口探针](../../tool/validation/windows_playback_open_probe.dart)使用真实 `DesktopPlaybackWindow`、`WorkspacePlaybackWindow` 和视频详情加载态，记录请求、宿主 build、原生创建、prepare、view 首帧和 Win32 `IsWindowVisible`。无账号、网络、媒体解码或观看记录写入。首显以 Dart 发起打开请求至观察到原生窗口可见为准；这不是鼠标硬件事件到画面的完整延迟，也不是视频首个解码帧耗时。

同机 Windows Profile/AOT，普通窗口每组 8 次，第 1 次为该进程首次打开，后 7 次关闭后重开；最大化组预先最大化并关闭一次，再连续重开 8 次。

| 测量 | 修改前 | 优化后首轮 | 最终源码复测 |
| --- | ---: | ---: | ---: |
| 普通窗口重复打开中位数 | 225.53 ms | 19.33 ms | 37.94 ms |
| 普通窗口重复打开范围 | 222.44–227.14 ms | 16.23–21.31 ms | 27.54–50.29 ms |
| 该进程首次打开 | 334.43 ms | 25.17 ms | 48.81 ms |
| 最大化重开范围 | 本轮未采集 | 16.47–20.21 ms | 27.84–63.04 ms |

首轮普通窗口重复打开中位数减少约 91%。最终源码复测同时观察到另一任务的弹幕 GPU 探针进程，未控制其负载，因此同时保留两轮结果，不将该比例视为稳定承诺。最终复测的创建阶段为 2.83–4.28 ms，准备阶段为 0.69–1.04 ms，原来的两段约 100 ms 同步等待已消除；其余首显耗时仍受帧调度和机器负载影响。这是本机受控窗口加载态样本，不推导为所有设备或公网视频的统一加速比例。

两轮普通窗口准备、首次可见和稳定后客户区均为 1120×791 物理像素，连续 8 次未累加高度；最大化首次观察和稳定后均为 1920×1032，准备时保留普通尺寸供用户还原。

可复测入口：

```powershell
./tool/test-windows-playback-open.ps1 -Output build/validation/window-open/normal.json
./tool/test-windows-playback-open.ps1 -Maximized -Output build/validation/window-open/maximized.json
```

输出路径必须未存在；脚本正常结束或失败后恢复普通 Profile 入口。`-SkipBuild` 仅用于已构建该探针的受控对照，不会替换产物。不同任务不要共享同一个 Flutter 构建目录。

本轮因同期弹幕任务使用主工作区 Profile 目录，将当前源码复制到忽略目录 `artifacts/window-open-workspace` 构建。首次共享目录产物被另一个入口覆盖，已弃用该次结果；上述数据全部来自独立副本。副本复用已校验原生下载缓存，保留 TLS 和 CMake/hash 校验。原始记录位于副本的 `build/validation/window-open/baseline.json`、`final-normal.json`、`final-maximized.json`、`final-normal-verified.json` 和 `final-maximized-verified.json`。

## 验证与边界

- 新增组件回归验证新页面只在准备好的 view 创建、准备期间取消不启动页面；现有回归继续覆盖延迟 prepare、合并最新媒体／标题、关闭、退出排空和导航模式迁移。
- `tool/test-window-geometry.ps1` 通过；新增原生回归模拟 SDK 重复添加系统标题栏高度，并验证首显前尺寸稳定、首显后用户缩放和取消后解除约束。既有最大化首显、还原、最小化、全屏、重入取消、旧 owner 隔离和标题栏测试通过。
- 独立副本执行 `tool/check.ps1` 通过：根应用 3187、`bili_api` 495、`bili_player` 83、`bili_danmaku` 95、`bili_mux` 5，共 3865 项通过；根应用 13 项按既有条件跳过，mux 原生 10 项因未设置 `BILI_MUX_LIBRARY` 跳过。五处格式、静态分析和打包边界检查通过，日志为副本的 `build/window-open-full-check.log`。该结果对应捕获的工作区快照，不包含其他任务随后继续修改的代码。
- `windows_playback_test.dart` 原入口在 Debug 运行：6 项通过、2 项失败。失败分别为折叠进度条查找不到，以及 Flutter `LiveTestWidgetsFlutterBinding.handlePointerEvent` 对已关闭 view 执行 `firstWhere` 抛出异常。双窗口用例已走完单会话、跨模式迁移、暂停／进度／倍速保留、用户调整大小、最大化、侧键返回、关闭返回浏览页及最大化连续重开两次的行为断言，但因最后检查到测试绑定异常而失败，不能计作整套通过。日志为 `build/window-open-native-debug.log`。
- `tool/test-windows-main-close.ps1`：无播放时通过，有播放时完成关闭流程后被 `tester.takeException()` 捕获的 `StateError: No element` 阻塞，结果 1 通过、1 失败，日志为 `build/window-open-main-close.log`。在独立副本中临时撤回本次生产改动并恢复原集成测试，重复上述两项测试，分别得到相同的 6 通过／2 失败、1 通过／1 失败及相同失败点；对照日志 `build/window-open-baseline-native-debug.log`、`build/window-open-baseline-main-close.log`。随后恢复优化源码并逐文件核对一致。这些既有失败未扩大到本次性能修复范围。
- 额外的临时 Profile 合并集成入口也未通过，包含 Debug 按键映射不可用、上述控件查找／多 view 事件异常，以及旧 `detached_playback_window_smoke_test.dart` 沿用系统标题栏高度的断言（实际自绘标题栏外框差 16 px，旧断言要求至少 24 px）。该试验日志 `build/window-open-native-playback.log` 保留，不修改无关旧断言。性能结论仅来自独立 Profile 探针，不使用 Debug 帧率。
- 最终源码完成 Windows Profile 构建和普通／最大化各 8 次探针复测，随后重新以 `lib/main.dart` 构建成功，日志为副本的 `build/window-open-ordinary-build.log`。可试用产物在 `artifacts/window-open-workspace/build/windows/x64/runner/Profile/bilisail.exe`，需保留整个 Profile 目录；它是普通应用入口，未遗留测试夹具。未构建 Release 安装包。
- 未验证其他 Windows 机器、Windows 10、跨显示器 DPI、Android/macOS 实机或公网视频加载时间。没有可连接的 Dart 调试应用，无法热重载；原生变更通过重新构建验证。

## 最大化重开时顶部栏闪变（2026-10-31）

用户确认仅在最大化播放窗中出现“先低后高”的顶部栏。标题栏组件一直固定为 44 逻辑像素，没有高度动画；问题在首帧布局与首次可见状态不一致：隐藏 HWND 保留普通尺寸，SDK 先渲染普通尺寸的场景，首帧回调才触发原生最大化，随后 Flutter 再渲染最大化尺寸。旧探针连续 8 次记录到首帧标题栏宽度 1120、客户区 1120×791，而首次可见及稳定客户区已是 1920×1032；首次最大化期间会短暂使用旧尺寸的场景。

- 原生恢复几何时，若存在待执行的首次最大化，则返回所在显示器工作区的物理尺寸。Windows 自绘标题栏下，该尺寸等于最大化后的客户区。普通窗口继续沿用准备好的实际客户区。
- Dart 窗口适配器将该尺寸换算为逻辑像素，供初始宽松约束下的场景布局使用。原生窗口仍保持隐藏，首帧回调继续负责首次可见即最大化；普通位置记忆、用户还原、首显后的自由缩放与全屏沿用原处理。
- Profile 探针增加首帧场景、标题栏尺寸和 DPR 记录，并检查首帧场景与稳定客户区一致、标题栏为 44。Windows Profile 最大化重开 8 次，首帧均为 1920×1032、标题栏 1920×44；普通窗口 8 次均为 1120×791、标题栏 1120×44。最终带断言的探针复测两组各 8 次通过，记录在 `build/validation/caption/final-maximized.json` 与 `final-normal.json`，旧实现对照为 `baseline-maximized.json`。这是本机受控窗口加载态验证，不代表公网视频或跨显示器验收。
- `tool/test-window-geometry.ps1` 通过，覆盖首次可见尺寸与自绘客户区一致、普通窗口不使用最大化尺寸、取消后清理，以及既有最大化／还原／缩放／全屏／旧 owner 隔离。窗口服务、独立窗口生命周期、顶部栏和工作区播放窗口的 54 项定向测试通过，日志为 `build/caption-targeted-tests.log`。
- `tool/check.ps1 -SkipPub` 通过：根应用 3681、API 497、播放器 101、弹幕 136、封装包 5，共 4420 项通过。根应用 13 项按既有条件跳过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过；格式、静态分析和打包边界检查通过，日志为 `build/caption-full-check.log`。最终改动文件另行静态分析通过。
- Windows mux 资产重新构建成功；探针执行后已重新构建普通 `lib/main.dart` 的 Windows Profile 和 Release，未遗留探针入口。日志为 `build/caption-ordinary-profile-build.log` 和 `build/caption-ordinary-release-build.log`；可试用入口为 `build/windows/x64/runner/Release/bilisail.exe`，需保留整个 Release 目录。没有可连接的 DTD／调试应用，本轮通过重新构建验证；未测试跨显示器 DPI、Windows 10、真实账号或公网视频，Android/macOS 未构建或实机验证。
