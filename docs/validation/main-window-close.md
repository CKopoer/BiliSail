# 主窗口关闭与三端退出清理

日期：2026-10-25。

## Windows Release 关闭时的插件访问冲突（2026-11-23）

Windows x64 的 `1.3.0+7` Release 停留在首页时，向主窗口发送 `WM_CLOSE` 后，三次进程退出分别耗时 1868、1804、1832 毫秒，退出码均为 `0xc0000005`。本机 Windows 应用程序事件中，用户此前的退出和这三次复现均指向 `flutter_windows.dll+0x15cdf`。匹配的 Flutter 符号将地址定位到 `FlutterDesktopMessengerSetCallback`，转储中的调用方是 `media_kit_video_plugin.dll`。

Flutter 3.50.1 的 Windows 引擎析构先执行 `messenger_->SetEngine(nullptr)`，随后销毁注册的插件。视频插件在析构时注销方法处理器，触发了对已断开引擎的访问。修复让注册器管理处理器的剩余生命周期。用原 Release 的可执行文件、AOT 和资源做对照，仅替换重新编译的视频插件后，三次主窗口销毁耗时 23–40 毫秒，进程退出耗时 122–135 毫秒，退出码均为 0。受控 C++ 回归同时覆盖 messenger 已断开、管理和渲染任务在途、平台回调等待处理的情况。[插件修复及回归](https://github.com/CKopoer/media-kit/commit/8e16eba1b01be05927b4fa098323ed496fea380d)

使用新锁定依赖和本地 DASH 双轨运行 Release 退出探针。独立播放窗口处于普通、最小化、全屏状态时，各从主窗口关闭三次，进程退出分别耗时 310–324、136–153、154–167 毫秒。九次均确认播放 view 和原生播放窗口已关闭。重新构建普通入口 `lib/main.dart` 后，首页关闭三次，进程退出分别耗时 126、114、129 毫秒。以上十二次退出码均为 0。[退出探针脚本](../../tool/test-windows-exit-latency.ps1)

## 问题与修复

- Windows 双标签的播放窗和主浏览窗共用 engine。固定 Flutter 3.47.6 的 `WindowsLifecycleManager.HandleCloseMessage` 仅在进程最后一个顶层窗口关闭时请求 Dart 退出；播放窗尚在时，主窗会直接进入 `WM_DESTROY` 并销毁 engine，绕过应用的播放／下载／数据库清理。
- [WindowService](../../lib/core/platform/window_service.dart) 通过 `bilisail/application_exit` 注册关闭处理，由 [FlutterWindow](../../windows/runner/flutter_window.cpp) 在主 HWND 自己的消息处理函数中拦截 `WM_CLOSE`，把原生关闭、标题栏关闭和 Alt+F4 送入 `ServicesBinding.exitApplication(cancelable)`。不使用 `window_manager.setPreventClose`：该插件的全局窗口消息监听也接收 SDK 播放窗事件，会混淆两个窗口的关闭职责。全部清理结束后解除主窗拦截，播放窗仍走自己的 SDK delegate。
- [AppDependencies.close](../../lib/app/dependencies.dart) 返回同一个清理 Future。主窗关闭、系统退出和重复请求都等待该 Future，避免第二次调用因布尔标记提前返回。沿用下载任务收尾、悬停预览释放、播放会话／原生 engine 释放、账号及数据库关闭的既有顺序；播放进度收尾仍发生在账号 epoch 失效之前。
- Android 双标签是应用内的两个页面槽。[外壳](../../lib/app/shell.dart)此前确认退出后直接 `SystemNavigator.pop()`，不会触发桌面的可取消退出通知。现在通过 [router](../../lib/app/router.dart) 与 [BiliApp](../../lib/app/bili_app.dart) 注入共享清理回调，先等待清理，再结束 Activity；取消确认不开始清理，清理期间的重复返回不再打开第二个退出确认。
- macOS 主窗关闭原本已走 Flutter 退出回调。进一步核对固定 SDK 的 `FlutterEngineTerminationHandler`：收到退出请求时立即将 `shouldTerminate` 设为真，Dart 清理尚未完成时再次 Cmd+Q 会让默认 AppDelegate 放行退出。[AppDelegate](../../macos/Runner/AppDelegate.swift)现在明确区分等待与获准状态，合并系统退出请求，通过 [原生宿主](../../macos/Runner/MainFlutterWindow.swift)以 SDK 同样的 JSON `flutter/platform` 通道调用 `System.requestAppExit`，收到 `exit` 后才允许 Cocoa 终止；取消可再次请求。保持 SDK 窗口 delegate 和 headless engine 初始化方式。

本轮不改变关闭单独播放窗、媒体返回历史和隐藏播放页的规则，不增加持久化设置。系统强制杀进程、断电和 Android 任务管理器强制停止没有可等待的退出握手，不能由此保证异步清理完成。

## macOS 全屏原生标签关闭（同日）

先全屏再播放时，用户点击主浏览窗的原生标签关闭按钮会退出并收到系统崩溃提醒。主窗关闭请求现先通过 Dart 事件队列离开 SDK 的 isolate-local FFI 关闭回调；清理获准后，原生退出协调器也先离开 Flutter 通道回复栈，再在主线程队列调用 `NSApp.terminate`。获准至队列执行期间继续合并重复退出，取消仍允许重试。主标签的关闭按钮保留，语义仍是等待共享清理后退出应用。源码风险、4 项 XCTest 和尚待 Mac 构建／全屏设备复测的边界见[双标签崩溃专项](macos-dual-playback-crash.md#全屏原生标签关闭2026-10-25)；本轮没有取得该次设备崩溃栈，不将时序修正等同于已经确认根因或完成设备验收。

## Release 退出延迟修正（同日）

用户随后报告仅打开、关闭 Windows Release 也要等待很久。实测启动后 3 秒／12 秒发送主窗 `WM_CLOSE`，进程退出分别耗时 6895／9026 毫秒；临时逐阶段计时显示 Dart 的下载、预览、播放、账号、数据库和图片清理总共只用 2／1 毫秒。计时代码在定位后移除。

`System.exitApplication` 通过 `WM_QUIT` 结束消息循环，不一定先收到 `WM_DESTROY`。原先 `FlutterWindow` 的空析构函数让成员直接开始析构，没有先运行已有的 `OnDestroy`，窗口消息还可能在成员销毁期间重入。现在只在派生窗口析构时调用现有 `Destroy()`，先按 `OnDestroy` 的顺序清理通道和 Flutter controller，再释放窗口。正常窗口关闭已经清理过的成员仍可安全重复经过该入口；播放会话／下载／数据库的等待顺序保持。

[Release 退出耗时回归](../../tool/test-windows-exit-latency.ps1)启动独立的 Release 进程，按 PID 定位其主 HWND，发送原生关闭并等待进程正常结束，检查退出码为 0、耗时不超过 2 秒。该门槛只用于测试。修正后的首轮两次实测为 104／77 毫秒，日志 `build/validation/exit-latency/destroy-results.json`。移除临时计时代码后重新构建 Release（`build/exit-latency-release-final.log`），启动后 3 秒关闭的三次耗时为 71／71／70 毫秒（`build/validation/exit-latency/final-results.json`），启动后 1 秒关闭的三次为 101／99／125 毫秒（`build/validation/exit-latency/immediate-results.json`），六次退出码均为 0。产物仍为 `build/windows/x64/runner/Release/bilisail.exe`，需保留整个 Release 目录；这些数据针对本机仅启动后退出场景。

本轮 `tool/check.ps1 -SkipPub` 通过：根应用 2599、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 3231 项测试通过；10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志 `build/exit-latency-check.log`。原生主窗关闭回归两项通过（`build/exit-latency-main-close.log`），视频资源释放回归 9 项通过（`build/exit-latency-native-dispose.log`）。

## 双标签播放中关闭主窗的退出延迟（2026-10-27）

使用空凭据、内存数据库和本地 DASH 音视频，在独立 Windows Release 进程中复现：主窗收到 `WM_CLOSE` 后，Dart 依赖清理仅用 3–5 毫秒，进程却在 3658／3457／3389 毫秒后以 `0xc0000409` 退出；Windows 事件记录指向 `ucrtbase.dll`。此前只启动再退出的回归没有创建第二个 view，集成测试也会取消最终进程退出，因此没有覆盖这个阶段。

退出清理遗漏了仍然挂载的 SDK 播放 view 和原生播放窗口。通过保持其他清理不变、在 engine 退出前显式卸载并销毁播放窗，三次退出恢复为 247／248／201 毫秒且退出码均为 0，确认问题位于这一生命周期边界；本轮未采集原生调用栈，不推断 `ucrtbase.dll` 内部的具体终止原因。

- [播放窗口适配器](../../lib/core/platform/detached_playback_window.dart)新增进程级关闭控制器，由 [AppDependencies](../../lib/app/dependencies.dart)持有，[BiliApp](../../lib/app/bili_app.dart)注入。共享依赖清理先完成原有播放释放，再等待播放 view 从 Widget 树卸载、几何保存及原生窗口销毁，最后返回退出许可。账号 epoch 失效与数据库关闭仍发生在播放进度收尾之后。
- 同一个关闭 Future 合并重复请求；关闭开始后不再创建播放窗。清理同时等待已卸载但仍在退休的窗口，以及快速关闭／重开遗留的所有创建任务，防止迟到的 prepare 在退出握手结束后留下新 view。原生窗口销毁继续离开 Flutter 帧栈和 FFI 回调栈。
- [窗口组件回归](../../test/core/platform/detached_playback_window_test.dart)覆盖卸载先于原生销毁、几何等待、重复退出、取消排队创建、多个迟到 prepare、已经卸载的宿主，以及清理后不再挂载媒体。 [主窗集成回归](../../integration_test/windows_main_close_test.dart)改为在延迟数据库关闭时确认播放窗已销毁且只剩主 view，保留清理期间重复关闭和独立播放窗关闭的检查。
- [退出耗时脚本](../../tool/test-windows-exit-latency.ps1)新增 `-WithPlayback`，构建 [AOT 本地探针](../../tool/validation/windows_exit_probe.dart)，分别验证普通、最小化、全屏播放窗。按 PID 向真实主 HWND 发 `WM_CLOSE`，等待进程退出，检查退出码为 0、view 清理完成及总耗时不超过 2 秒；该阈值是测试门槛。探针使用空凭据和内存数据库，脚本结束时恢复普通 `lib/main.dart` Release 产物，并恢复环境变量。

最终执行 `tool/test-windows-exit-latency.ps1 -WithPlayback -StartupSeconds 0 -Samples 3 -Output build/validation/exit-latency/playback-final.json`，在确认两个 view 和播放进度推进后立即关闭主窗：普通播放窗 270／252／169 毫秒，最小化播放窗 73／73／91 毫秒，全屏播放窗 82／88／79 毫秒，九次退出码均为 0。日志为 `build/playback-exit-release-latency.log`；这些数值只代表本机受控本地分轨场景。

`tool/check.ps1 -SkipPub` 通过：根应用 3008、bili_api 478、bili_player 83、bili_danmaku 93、bili_mux 5，共 3667 项测试通过，格式、静态分析和打包边界检查通过（`build/playback-exit-check.log`）。根应用有 13 项既有条件用例跳过，mux 另有 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。真实主窗关闭集成回归两项通过（`build/playback-exit-main-close.log`），原生视频生命周期／渲染队列／尺寸回归九项通过（`build/playback-exit-native-dispose.log`）。Windows x64 mux 组件构建通过（`build/exit-playback-mux.log`）。

脚本最终恢复普通 `lib/main.dart` 的 Windows Release 构建成功，产物为 `build/windows/x64/runner/Release/bilisail.exe`，分发须保留整个 Release 目录。随后普通应用启动 3 秒再关闭，三次为 61／57／59 毫秒，退出码均为 0（`build/validation/exit-latency/idle-final.json`），用于检查没有独立播放窗时的退出。构建仍保留第三方 CMake 的 CMP0175 提示。

Android／macOS、本机 Windows 以外的设备、真实账号最后一次云进度和运行中的下载任务尚未实测。DTD 未发现可连接的调试应用，热重载请求返回无活动连接；本轮原生回归使用重新构建的测试宿主，耗时测量使用 Release/AOT。

## 初次主窗修复的验证边界

以下为 `99f63c0` 初次修复时的验证快照；退出延迟修正后的验证见上节。

- [窗口通道测试](../../test/core/platform/window_service_test.dart)：主窗口关闭拦截、播放 view 隔离、等待退出回调、重复关闭、取消重试及清理后的拦截解除。
- [Android 返回测试](../../test/app/predictive_back_test.dart)：双／多标签确认前取消、清理未完成时不得调用 `SystemNavigator.pop`、重复返回合并、清理后结束一次，以及既有页内／模态／媒体返回优先级。
- [macOS 原生单元测试](../../macos/RunnerTests/RunnerTests.swift)：等待清理期间重复 Cmd+Q、获准后的原生终止，以及取消后重试。需在 Mac 以 `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -only-testing:RunnerTests` 执行。
- [Windows 原生回归](../../integration_test/windows_main_close_test.dart)通过 `tool/test-windows-main-close.ps1` 运行：分别覆盖只有主窗、播放窗仍打开两个场景，使用内存数据库、空凭据和本地合成 DASH 音视频。先向播放 HWND 发原生关闭，确认仅调用其关闭 delegate、不发起应用退出，再重开播放窗。真实主 HWND 收到 `WM_CLOSE` 后延迟数据库关闭，检查 native engine 已释放、清理等待期间窗口未被销毁、重复关闭复用同一 Future、插件全局关闭拦截始终关闭。生命周期观察者最终取消进程终止，以便测试宿主回收并输出结果。

- 最终定向回归 250 项通过，覆盖 Windows/macOS 窗口与工作区、Android 确认退出／隐藏播放页及预测返回、播放会话释放。日志：`build/main-window-close-targeted-final.log`。
- 本任务 9 个 Dart 文件的静态分析通过，日志 `build/main-window-close-analysis-targeted.log`；最终全仓库分析被同期未提交的 `integration_test/android_dpi_adaptation_test.dart:58` 一处 `curly_braces_in_flow_control_structures` 提示阻塞，日志 `build/main-window-close-analysis-final.log`。69 个相关文档本地链接及任务暂存差异空白检查通过。
- 最终 Windows 原生回归两项通过，包含播放窗单独关闭与重开、主窗关闭、清理等待和重复请求；使用当前生产主窗口适配与真实 libmpv。日志：`build/main-window-close-native-final.log`。`tool/test-windows-video-dispose.ps1` 的 9 项 native 生命周期／渲染队列／尺寸测试也通过，日志：`build/main-window-close-native-dispose.log`。
- `tool/check.ps1 -SkipPub` 首轮通过，四个独立包分别通过 456／81／93／2 项测试。最终重跑时根应用 2392 项通过，65 项失败均来自同期尚未提交的 `test/shared/ui/dpi_adaptation_test.dart`，报错为目标控件查找 `Bad state: No element`；未修改该专项测试或将其纳入提交，不能声称最终工作区全量通过。日志：`build/main-window-close-check.log`、`build/main-window-close-check-final.log`。10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为 native 通过。
- Windows 和 Android 的 mux 目标组件构建通过。Android arm64 Profile APK 构建通过，产物 `build/app/outputs/flutter-apk/app-profile.apk`（约 118.5 MB）；使用调试签名，保留已有 CupertinoIcons 字体资源提示。日志：`build/main-window-close-android-profile.log`。
- 当前生产入口的 Windows Release 构建通过，产物 `build/windows/x64/runner/Release/bilisail.exe`，分发须保留整个 Release 目录。日志：`build/main-window-close-windows-release-final.log`。构建保留第三方 CMake 的 CMP0175 提示，未修改依赖或绕过原生补丁校验。
- 当前 Windows 主机没有 Mac/Xcode，未执行 macOS 编译、两项 XCTest 或真实 Cmd+Q／主窗关闭验收；`adb devices` 无连接设备，未做 Android 实机退出验收。Windows 本地合成音视频回归不替代真实账号／下载任务、跨屏全屏、长期播放和性能验收。DTD 没有可连接的调试应用，热重载请求未能执行；Windows 集成回归使用重新构建的测试宿主。
