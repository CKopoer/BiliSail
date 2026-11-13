# 多标签并发播放

日期：2026-10-06；默认值更新于 2026-10-24。当前“允许多个标签页同时播放”默认关闭，已保存的有效选择继续保留；以下 2026-10-06 记录中的默认开启为历史行为。

## 鼠标关闭顶部标签页（2026-11-13）

- 在“设置 → 外观”选择多标签页后，可在“关闭标签页（可多选）”中独立启用鼠标中键、右键和双击。点击顶部对应的临时标签页关闭该页，固定根标签不受影响。触摸双击保留原有行为。
- 三项默认关闭，沿用既有关闭按钮与快捷键；保存后立即应用，切换到单／双标签暂停这些鼠标关闭方式，返回多标签保留选择。保存失败按共享设置控制器回退并提示，恢复默认会清除三项选择。
- `preferences.v1` 快照版本增至 47；缺失和非法值回退关闭，有效布尔值分别保留。数据库表结构和版本不变。关闭动作复用工作区原有生命周期，关闭非当前标签保留当前页面，关闭当前标签按访问历史回退。
- Flutter 3.47.6／Dart 3.13.5 下，`tool/check.ps1` 的 Lint、RootTests、PackageTests 三阶段通过，格式、静态分析、锁文件复现和打包边界检查通过。根应用 5313、bili_api 917、bili_player 238、bili_danmaku 161、bili_mux 5 项测试通过，合计 6634 项；另行运行的 18 项定向回归通过，覆盖独立开关、多选、立即生效、保存回退、默认恢复、固定标签和页面释放。日志位于 `build/validation/tab-close/`。
- 本次在 Linux 云环境验证；根应用 6 项 Windows 专属用例、播放器 3 项原生用例、封装包 10 项原生用例按环境条件跳过。未进行平台构建或实机鼠标验收。容器的 PowerShell 检查通过临时子进程回收包装运行，仓库检查脚本保持原样。

## Windows 播放窗每次打开延迟（2026-10-28）

定位到首帧前原生尺寸调整的两次约 100 ms 等待。Windows 改用 SDK 的首帧内容定尺寸模式并保留原生外框恢复，新页面直接在播放 view 创建；已有页面跨模式迁移继续保留状态。本机 Profile 窗口加载态探针的重复打开中位数从 225.53 ms 降至首轮 19.33 ms，最终源码在同期弹幕 GPU 探针运行时复测为 37.94 ms；创建／准备阶段均不再出现约 100 ms 等待。测量口径、源码边界、复测方法和验收见[专项记录](dual-playback-open-performance-2026-10-28.md)。

## Windows 播放窗首次可见即最大化（2026-10-27）

- 后续反馈确认延迟感来自窗口先按普通尺寸出现，再展开到最大化。固定 SDK 首帧仍调用 `SW_SHOWNORMAL`；此前 `InitialShowMaximizer` 在 `WM_WINDOWPOSCHANGED` 中恢复最大化，此时普通窗口已经可见。新增首显观察回归在旧代码上失败，日志为 `build/first-maximize-before.log`，不能将此前只检查最终最大化状态的通过记录当作“首次可见即最大化”。
- 当前改为在第一次 `WM_WINDOWPOSCHANGING` 中清除 `SWP_SHOWWINDOW`，让 SDK 完成普通矩形恢复时保持隐藏；本次位置变更结束后直接以 `SW_MAXIMIZE` 显示。这个消息中修改 `WINDOWPOS.flags` 的契约见 [Microsoft 文档](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-windowposchanging)。处理仍在首帧回调的同一原生消息栈内完成，无新增定时等待；用户以后主动还原、最小化和最大化继续沿用系统行为。
- 转发原生消息可能同步触发 Flutter 监听；恢复期间继续保护几何租约，并在转发后再次确认未取消或被新 owner 接管。取消中的窗口保持隐藏，不能在消息回栈后重新显示。原生回归同时检查普通尺寸从未可见、真正的最大化状态、还原矩形、最小化、首帧前关闭、回调中取消、旧 owner 隔离和全屏。
- `tool/test-window-geometry.ps1` 原生回归通过（`build/first-maximize-native.log`）；真实 Flutter 本地分轨工作区回归通过，新增连续两次关闭后以最大化重开，同时覆盖普通／最大化全屏和关闭回收（`build/first-maximize-media-final.log`）。集成夹具复用同一会话，重开允许保留暂停意图；Dart view 挂载与首帧后的原生显示分别等待，首次可见尺寸由上述原生消息观察回归验证。
- `tool/check.ps1 -SkipPub` 全量通过：根应用 3004、API 478、播放器 83、弹幕 93、封装 5，共 3663 项；根应用 13 项按原有条件跳过，另有 10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，格式、静态分析和打包边界通过（`build/first-maximize-check.log`）。本轮原生首显修正不改变播放器释放实现。
- Windows Release 主入口重建成功：`build/windows/x64/runner/Release/bilisail.exe`（`build/first-maximize-release.log`），须保留整个 Release 目录；未替换或关闭用户正在运行的已安装应用。最终静态分析再次通过（`build/first-maximize-analysis-final.log`）。窗口首显状态与媒体加载耗时分别看待；本轮未测点击到首显的端到端耗时、跨屏 DPI、Windows 10 或 Android／macOS，不推导固定毫秒收益。

## Windows 播放窗顶部边框与开关等待（2026-10-27）

- 本轮反馈指向最小化／最大化／关闭按钮上方的原生空白带。普通播放窗的 Flutter 客户区改为覆盖到窗口顶边，44 逻辑像素的标题栏直接绘制到顶；简介／评论／更多工具行保留原位置。最大化时仍扣除屏幕工作区外的 resize inset，避免按钮被裁剪；普通窗口补上顶边和两个顶角的原生缩放命中测试。窗口样式、侧边／底边缩放和全屏沿用现有实现。自定义客户区与命中测试依据 [Microsoft 文档](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe)。
- 创建／激活窗口直接排到当前 Flutter 调用栈之后的事件，不再额外等待一帧；继续合并同轮请求并检查关闭／重开代次。原生创建、标题和激活仍不在构建或绘制栈内执行。
- Windows 关闭改为一次原生调用按 view／owner 保存尺寸、隐藏窗口并退休几何租约，随后再拆除标题栏适配。Flutter 内容卸载及原生 view 销毁仍按原有安全顺序等待；等待期间窗口已隐藏，避免按钮上方的系统边框在关闭时重新闪现。旧窗口的迟到保存不能隐藏或退休新窗口。
- 本轮定向窗口组件回归 56 项通过（`build/dual-window-targeted-final.log`），覆盖事件在下一帧前启动、退出构建栈、关闭／快速重开和 view 转移。`tool/test-window-geometry.ps1` 通过真实 HWND 顶部原点、顶边／顶角缩放、最大化／全屏、隐藏后尺寸保留和旧 owner 隔离；`tool/test-windows-video-dispose.ps1` 的 9 项原生回归通过。原生分轨工作区用例通过，覆盖窗口转移、普通／最大化全屏、单会话和关闭返回（`build/dual-window-native-final.log`）。
- `tool/check.ps1 -SkipPub` 的打包边界、五处格式和静态分析通过；根测试已有 3000 项通过、13 项跳过，但 `profile_folder_performance_test.dart` 的分页卡片断言和 `video_card_content_reuse_test.dart` 的滚动边界断言失败，最后的同期新增 `retained_card_pages_test.dart` 多分钟无进展，本次主动结束该测试进程，未修改这些测试／列表代码（`build/dual-window-check.log`）。四个包另行完成脚本检查，478／83／93／5 项通过，mux 原生 10 项因未设置 `BILI_MUX_LIBRARY` 跳过（`build/dual-window-packages.log`）；不把这轮根检查记为全量通过。
- 本机真实 Flutter 验证窗口已检查普通／最大化下标题栏贴顶、按钮完整和关闭回收，并执行成功的热重载。Windows Release 主入口重建成功：`build/windows/x64/runner/Release/bilisail.exe`（`build/dual-window-release.log`），须保留整个 Release 目录。Android／macOS、Windows 10、跨屏 DPI 与真实视频开关耗时未测；不以 Debug 窗口观感或减少等帧次数推导毫秒级性能收益。

## Windows 播放窗深色顶部边框（2026-10-26）

- 双标签播放窗由 Flutter SDK 创建，未经过主窗口 `Win32Window::UpdateTheme`。此前仅 Flutter 内容和 44 逻辑像素自绘标题栏切换深色，保留用于窗口缩放的原生顶部边框仍按浅色绘制，形成白条。
- `WindowService.configurePlaybackTitleBar` 现在按 view 传递亮度与标题栏背景色，播放窗挂载和主题变化时同步。原生适配使用 `DWMWA_USE_IMMERSIVE_DARK_MODE` 和 `DWMWA_CAPTION_COLOR` 更新窗口装饰，保留窗口样式、缩放、最大化及全屏几何；旧版 Windows 不支持自定义标题颜色时仍尝试深色模式属性。属性定义见 [Microsoft DWM 文档](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute)。
- 定向回归 53 项通过，覆盖应用深色与系统浅色不一致、深浅主题切换、重复重建、view 关闭后的调用保护，以及侧键和评论详情返回；日志 `build/playback-frame-targeted-final.log`。`tool/test-window-geometry.ps1` 在隔离桌面通过真实 HWND 的亮度属性、失焦、窗口样式、普通／最大化／全屏几何与释放回归。标题栏颜色属性仅支持设置，原生测试未使用不支持的颜色读回断言。
- `tool/check.ps1 -SkipPub` 通过：根应用 2792、bili_api 460、bili_player 81、bili_danmaku 93、bili_mux 5，共 3431 项通过；格式、静态分析和打包边界检查通过，10 项 mux 原生测试因未设置 `BILI_MUX_LIBRARY` 跳过，日志 `build/playback-frame-check-final.log`。Windows mux 资产和 Windows Release 重建成功，入口为 `build/windows/x64/runner/Release/bilisail.exe`，日志 `build/playback-frame-mux-build.log`、`build/playback-frame-windows-release.log`；已核对分发 AOT、mux 资产和固定 libmpv 哈希。
- 本轮未操作用户运行中的客户端，未执行实际视频播放、跨屏 DPI、Windows 10、Android 或 macOS 实机验收；没有可连接的 Dart 调试进程，不能热重载原生改动，需使用重新构建的程序。

## 单标签恢复与 Android 默认值（2026-10-25）

用户后续要求恢复单标签，并将其设为 Android 缺省模式，取代下文“各平台默认双标签”的默认值决定。其他平台仍默认双标签；已保存的单／双／多标签配置全部保留。单标签按实际访问顺序返回播放及普通页面，出栈释放不再被历史引用的会话；双标签的独立播放槽和多标签并发策略保持。行为与本轮验证见[单标签记录](single-page-navigation.md#恢复单标签2026-10-25)。

## 主窗口关闭与应用退出（2026-10-25）

Windows 播放窗尚开着时，主窗关闭也必须经过应用清理；Android 确认退出先等待清理再结束 Activity；macOS 重复 Cmd+Q 等待清理获准。三个入口共享同一个依赖关闭 Future。2026-10-27 补上退出前的独立播放 view 卸载和原生窗口销毁等待，覆盖普通／最小化／全屏播放中的完整 Release 进程退出。原因、回归命令和平台验收边界见[主窗口关闭专项](main-window-close.md)。

## macOS 双标签原生崩溃修复（2026-10-25）

macOS 已有 implicit 原生主控制器时，Flutter 3.47.6 的第二窗口入口触发 multiview 断言。第一次修复使用应用内回退，随后按用户要求保留双窗口：改为从 headless engine 创建明确的主浏览窗，再创建共享 engine 的播放窗；主窗口服务按 view 注入并保留 SDK delegate。原因、预检、打包时双窗口 smoke 和待实机项见[专项记录](macos-dual-playback-crash.md)。

## 各平台默认双标签（2026-10-25）

- 各平台导航默认值统一为双标签，平台适配入口、`AppSettings` 两个构造器及 `SqliteSettingsRepository` 的缺省值一致；设置页说明同步更新。
- 首次启动和缺失／非法导航值采用双标签；已保存的有效双／多标签选择保留，旧单标签迁移行为不变。设置快照及数据库版本不变。
- `tool/check.ps1 -SkipPub` 通过（`build/default-dual-tabs-check-final.log`）：根应用 2243、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2865 项测试通过，五处格式、静态分析及打包边界检查通过。覆盖各平台默认值、窗口缩放、设置持久化与旧值回退；多标签专用回归显式选择多标签。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。
- 本轮未执行平台构建、实机或性能测试；未发现可连接的调试应用，热重载未完成。改动文档的 147 个本地链接与 `git diff --check` 通过。

## Windows 播放窗标题栏与 Android 单页显示（2026-10-25）

- Windows 双标签独立播放窗改用 44 逻辑像素的共享标题栏，返回、最小化、最大化／还原及关闭同排，标题区域支持拖动和双击最大化。视频、影视、直播和离线共用窗口外壳；全屏路由覆盖标题栏。
- 原生适配只移除播放窗口的系统标题区域，保留原生缩放边框、窗口样式和系统命令；按该播放 view 定位 HWND，不通过仅管理主窗口的 `window_manager` 操作播放窗。最大化保留屏幕工作区顶边，全屏沿用 SDK 去除装饰的逻辑。实现参考 [Microsoft 自定义窗口边框说明](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe)，未引入 Windows App SDK 或修改 Flutter SDK。
- Android 双标签表示保留浏览与播放两个页面槽，同一时间只显示当前页面；不创建第二个系统窗口，也不左右分屏。隐藏页保留状态并停止媒体 surface、绘制和焦点参与。从浏览页可用“返回播放”回到已有播放页；返回先处理页内详情，再回退媒体历史，历史为空则关闭播放并回浏览。设置说明同步明确“同一时间只显示一个”。
- 定向组件测试覆盖标题栏高度、按钮和拖动目标、最大化状态图标、返回的模态隔离，以及 Android 390×844、844×390、1080×844 下单页可见和状态保留。`tool/test-window-geometry.ps1` 通过，在隔离桌面验证移除系统标题区域、普通尺寸、最大化顶边、全屏边框与释放恢复，未操作用户正在运行的应用。
- 最终定向组件回归 90 项通过，日志 `build/dual-caption-targeted-final.log`。根脚本的格式、静态分析和打包边界检查通过；根应用 2216 项通过、2 项同期新增的桌面评论详情模态回归失败，断言在 `comment_detail_navigation_test.dart` 的“模态打开后仍能找到评论详情”，未为此改动同期评论实现，日志 `build/dual-caption-check-complete.log`。四个包另行按根脚本的命令完成格式、分析和测试：API 446、播放器 81、弹幕 93、封装包 2 项通过；mux 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，日志 `build/dual-caption-packages.log`。
- Windows mux 资产构建和 Windows Release 构建通过，最终入口仍为 `build/windows/x64/runner/Release/bilisail.exe`，日志 `build/dual-caption-windows-release-final.log`。首次链接被正在运行的程序占用，用户关闭后在原目录重建；曾尝试的 `build/dual-caption-release` 临时目录已清理，CMake 输出配置恢复原值。
- 未发现可连接的调试应用，热重载请求未执行成功。Android/macOS 本轮未构建或实机验证，Windows 标题栏实际拖动／跨屏 DPI 和最大化按钮悬停贴靠体验留待用户确认。

## 双标签独立播放窗全屏留白（2026-10-25）

- `RegularWindow` 的播放 view 仍挂在浏览窗口的 Widget 树下。原 `PlaybackPanel` 使用 `Navigator.of(context, rootNavigator: true)`，越过播放窗的独立 Navigator，将全屏路由推到浏览窗口；内容随浏览窗口的客户区布局，不能覆盖已进入全屏的播放窗口。
- [共享播放面板](../../lib/features/playback/presentation/playback_panel.dart) 改为使用当前窗口最近的 Navigator；视频、影视、直播和离线播放沿用同一实现。全屏继续使用原会话和单个视频 surface，退出时恢复原页面。
- 新增双 view 回归：浏览窗口和播放窗口尺寸不同，连续两次进出全屏，检查路由所属 view、播放器覆盖完整视口、浏览路由不被 push，以及源和 surface 数量不变。旧代码会将路由挂到主 view 0，修复后保留在播放 view 100。
- `tool/check.ps1 -SkipPub` 通过：根应用 2210、API 446、播放器 81、弹幕 93、封装包 2，共 2832 项测试；格式、静态分析及打包边界检查通过。mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/fullscreen-check.log`。
- Windows Debug 构建与本地分轨工作区原生回归通过，覆盖普通／最大化播放窗进出全屏、完整视口、源 generation 保留、单个 surface、还原尺寸及最终关闭回收；日志为 `build/fullscreen-native-playback.log`。独立窗口 smoke 测得屏幕、窗口外框、客户区和 Flutter view 均为 1920×1080，日志为 `build/fullscreen-window-probe.log`。两处旧测试的等待条件同步覆盖新 view 内容挂载及关闭后异步回收。
- 本轮未重建或替换正在运行的 Release，未测试 Android/macOS、跨显示器或性能；未连接到可热重载的调试应用，热重载请求未执行成功。

## 行为与实现

- 原因是所有播放页共用一个 `PlaybackSession` 和 native engine，打开新视频会调用 stop 并替换旧媒体源，因此旧流中止而非保持暂停。
- `PlaybackManager` 按标签管理独立会话，app 注入原有 Repository、安全日志、账号／epoch 和进度端口的会话工厂；页面作用域按需创建并在关闭时释放。视频、影视、直播共用这个机制，每个标签内换源仍只有一个播放器。
- 多标签模式且允许并发时，多个已打开的播放标签可同时播放。隐藏页卸载 surface、绘制和快捷键，媒体继续推进；返回沿用同一源，不重算磁盘续播或重新请求 URL。
- 单标签模式或关闭并发开关时，进入其他播放页先完成旧会话的原生暂停，再允许目标播放。播放许可同步更新并约束解析完成、用户命令和播放命令队列，快速导航不会放行过时目标。切到普通页面保留最近播放会话；导航暂停保留用户意图，返回或恢复允许并发时继续，手动暂停保持暂停。
- 各页的刷新和视频／影视弹幕发送读取本页会话，避免使用另一标签的源／播放位置。全屏仍转交同一会话的 surface。关闭标签只释放自己的播放器；账号变化取消全部播放和旧请求，退出等待所有会话及已开始的释放。
- 不改变平台默认模式、16 页容量上限、凭据边界、插件／SDK 版本或数据库 schema；不增加系统后台服务或性能支持结论。

## 验证

- 会话回归新增多标签并发与独立进度／倍速、关闭单页、单标签导航互斥、手动暂停保留、迟到解析、延迟原生暂停、快速选择隔离、账号停止与全资源释放。
- 页面回归直接运行真实工作区 router、ProviderScope 和 PlaybackPanel，覆盖单／多标签初始模式、模式来回切换、隐藏 surface、返回原源和关闭标签。
- Windows 原生用两个独立 MediaKitEngine 打开本地 DASH 音视频分轨，确认两路均解码视频／音频并同时推进；切单标签后旧进度冻结，返回恢复原 generation，手动暂停与关闭一个会话不影响另一路。未使用真实账号或账户写操作。
- `tool/check.ps1 -SkipPub` 最终通过：根应用 707、`bili_api` 227、`bili_player` 16、`bili_danmaku` 21 项，共 **971 项**；四处格式检查和静态分析均通过。日志：`artifacts/multi-tab-playback-check-final.log`。
- 完整检查期间修正近期功能变更留下的测试夹具：合集页面显式注入游客控制器，播放快捷键测试安装已有 AppNoticeHost，工作区测试保留输入框的新标签屏蔽并覆盖 Ctrl+W 关闭行为。未改变对应生产逻辑。
- `tool/test-windows-media.ps1` 通过：执行 7 项本地原生验证，包含新增两路 DASH 并发、分轨 headers／重定向／Range、云端／本地进度、响应式／全屏、保留页面与 HTTP 403 脱敏诊断；未开启公网媒体分支。主文件日志中的 `+7` 包含一个未执行的公网分支，诊断文件另有 `+1`，不把这个提前返回计为实测。日志：`artifacts/multi-tab-playback-native.log`。
- `flutter build windows --release --no-pub -t lib/main.dart` 通过，入口为 `build/windows/x64/runner/Release/bilisail.exe`；日志：`artifacts/multi-tab-playback-windows-release.log`。正在运行的已安装 MSIX 应用未替换，新构建可从该目录运行。

本轮未构建 Android/macOS，二者没有设备实测；Windows 并发实测使用本地分轨 fixture，没有进行真实账号、公网多视频／PGC／直播并发或 CPU/GPU／内存测量。不将 Windows 并发结果推导为其他平台的播放、系统后台或性能验收。

## 并发播放开关（2026-10-06）

- 设置 → 播放新增“允许多个标签页同时播放”，默认开启。单标签页模式禁用开关但保留已保存值，切回多标签页后沿用选择。
- 实际并发许可为多标签页模式与 `allowConcurrentPlayback` 的合取，由 app 组合根传给既有 `PlaybackManager`。关闭开关立即暂停当前／最近选择的播放标签以外的会话；重新开启恢复被策略暂停的会话，手动暂停保持暂停。切换开关不重建播放器、刷新 URL 或丢失进度。
- `preferences.v1` JSON 快照版本由 12 升至 13；旧快照缺失／非法字段回退为开启，保留导航、主题等已有设置，SQLite schema 仍为 2。
- 回归覆盖单／多标签模式和开关开／关的四种组合、真实设置页切换开关、暂停意图与媒体源保留、控件禁用、保存重载和旧配置迁移。
- 定向设置／播放页面测试通过 123 项，日志 `artifacts/concurrent-playback-setting-targeted.log`。`tool/check.ps1 -SkipPub` 通过：根应用 723、`bili_api` 227、`bili_player` 16、`bili_danmaku` 23 项，共 **989 项**；四处格式与静态分析均通过。此计数包含工作区当时已有的其他并行修改，日志 `artifacts/concurrent-playback-setting-check.log`。
- 五份本轮更新文档的本地链接和 `git diff --check` 通过。
- `tool/test-windows-media.ps1` 通过，复测两路 DASH 解码与互斥暂停、返回恢复和原生错误诊断；仍不启用公网分支。日志 `artifacts/concurrent-playback-setting-native.log`。
- Windows Release 构建通过。原发布目录中的程序正在运行，常规打包受阻，因此将当前源码与锁文件复制至忽略目录 `artifacts/playback-settings-build`，执行 `flutter pub get --enforce-lockfile` 和 `flutter build windows --release --no-pub -t lib/main.dart`；副本的 CMake 安装目录显式指向自身 `build/windows/x64/runner/Release`。独立构建下载原生依赖失败后，复用现有 MPV／ANGLE／SQLite 缓存并校验依赖声明的 MD5／SHA256，未修改依赖或 SDK。新程序为 `artifacts/playback-settings-build/build/windows/x64/runner/Release/bilisail.exe`；日志 `artifacts/concurrent-playback-setting-windows-snapshot-release.log`。
- 本轮开关使用真实 router／设置页的组件测试验证；未进行新 Release 界面的手动操作验收，Android/macOS 未构建或实测。
