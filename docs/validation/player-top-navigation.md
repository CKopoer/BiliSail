# 播放器顶部导航与正在观看人数

日期：2026-10-25；2026-11-03 更新 iOS 多标签与全屏导航。

## 交互与边界

- 视频、影视、直播及离线播放共用的顶部控件移除视频标题、分 P 标记和空降片段查询／状态文字。保留空降助手设置、片段时间轴和当前片段的跳过按钮。按用户后续要求，返回／主页的位置统一如下：

| 平台与模式 | 播放页顶部导航行 | 播放控件内 |
| --- | --- | --- |
| Android 单／双标签 | 隐藏 | 普通小窗／完整布局及全屏均显示返回、回到主页 |
| iOS 单／双标签 | 显示返回、回到主页 | 普通布局隐藏；全屏显示返回（退出全屏） |
| iOS 多标签 | 隐藏这两个按钮 | 普通与全屏均显示返回、回到主页 |
| 其他平台单／双标签 | 显示返回、回到主页 | 隐藏这两个按钮 |
| 其他平台多标签 | 隐藏这两个按钮 | 隐藏这两个按钮 |

- 返回沿用工作区的页内详情、访问历史和双标签媒体历史；Android／iOS 全屏控件中的返回先退出全屏。其他平台全屏不补充这两个控件按钮，退出全屏沿用既有播放控件。回到主页先退出全屏，再执行对应导航模式的动作。
- Android 小窗保留左上角返回、回到主页，不随右侧工具精简而隐藏，也不移入“更多播放选项”；按钮仍随播放控件整体显隐。iOS 单／双标签普通播放沿用常驻顶部导航行，不在播放器内重复添加；多标签通过点按画面唤出左上角导航。iOS 全屏视频和听视频均保留左上角返回，顶部控件按安全区避让刘海／横屏缺口。
- 单标签关闭所有播放页及对应会话，恢复进入这段播放浏览链之前的页面、位置和返回历史。进入播放的页面受到缓存淘汰保护；返回记录仍受工作区已有 16 页／64 条历史上限约束。普通一级导航开启新的浏览链。
- 双标签保留媒体源、播放意图和独立播放窗口，选中原浏览页并聚焦主窗口；应用内双标签选择原浏览页。iOS 多标签返回沿访问历史回退，主页选中既有首页，不关闭其他播放标签；其他平台多标签不提供返回／主页按钮。
- Windows 独立播放窗在既有 Flutter 标题栏中加入主页；macOS 在既有原生标题栏附件中加入主页。两者复用同一个工作区动作和窗口级输入隔离，弹窗期间不触发原生导航，窗口释放后撤销对应回调。平台／模式切换通过共享导航作用域更新普通／全屏按钮，不创建第二个播放会话。
- UGC 视频右上显示服务端 `total` 文案加“人正在看”，普通／全屏共用读取能力。按 bvid、cid 和账号 epoch 隔离结果；每次完成后等待 30 秒再刷新，单次读取不重叠。控件自动隐藏仍保留同一订阅；页面隐藏、关闭或应用进入后台时取消请求与刷新，恢复后重新读取。失败／无数据／服务端禁用展示时隐藏，后续定时读取可恢复，不伪造零人数。
- 本次人数不扩展到影视、直播或离线媒体；直播已有独立在看／看过人数协议与展示，保持原有实现。

## 协议与参考来源

Web profile，`api.bilibili.com` GET `/x/player/online/total`，参数为 `bvid/cid`（原始字符串，只编码一次），Web Cookie 可选，无 WBI／CSRF；JSON 响应使用 `data.total` 与 `data.show_switch.total`，无分页。遵循共享总 deadline、会话取消与至多 3 次读请求尝试，不额外叠加 Provider 自动重试。

只读核对 biliuwp-lite 提交 `baf7e7591e8dc2fe012cf1e7ba54a056dec7f3b0` 的 [PlayerAPI.GetPlayerOnline](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/PlayerAPI.cs) 和 [PlayerVM.GetOnline](../../../biliuwp-lite/src/BiliLite.UWP/Modules/Player/PlayerVM.cs)，采用端点、内容身份和 `total` 展示语义。仅参考协议，自行实现 Dart／Flutter；没有复制参考应用源码、图片、图标或其他资源，也没有改变其许可范围或增加运行时依赖。按钮布局参考用户提供的 B 站移动端截图。

游客只读在线验证：`BV1xx411c7mD / cid=62131` 返回 `code=0`，包含字符串 `total/count` 和布尔展示开关；随后通过本项目 `PlaybackMetadataClient` 实际读取成功。人数会变化，不把一次快照当成固定结果。日志：`build/player-topbar-online.log`。

## 验证

### iOS 播放返回入口补齐（2026-11-03）

- 核对现行工作区和共享播放面板后，iOS 单／双标签普通播放已有左上角常驻返回／主页；多标签和遮住工作区标题栏的全屏缺少独立左上角返回入口。现在多标签接入既有 `PlaybackNavigation`，全屏视频／听视频的返回只退出全屏。其他平台沿用原导航显示规则。
- 普通视频、影视、直播及离线播放共用这份入口策略；没有固定跳首页、额外播放会话或绕过模态／页内详情的返回分支。默认点击模式仍隐藏播放器控件，点按画面后可触达；iOS 单／双标签普通播放的常驻标题栏不受该显隐设置影响。
- [工作区回归](../../test/app/workspace_shell_test.dart)新增 12 项 iOS 平台行为测试，覆盖四类媒体与单／双／多标签：页内详情先返回，随后回退媒体历史，主页沿现有模式返回原浏览页或首页；双／多标签保留页面。
- [播放面板回归](../../test/features/playback/playback_panel_test.dart)新增 4 项 iOS 平台行为测试，覆盖真实视频页面与三种模式、默认隐藏与点按唤出、普通／全屏不重复导航、竖屏顶部／横屏左右安全区、模态阻挡，以及视频／听视频全屏返回。视频仍为同一源及单个 surface，保留 45 秒位置和手动暂停。
- 两个完整测试文件复测 538 项通过；首轮新增听视频测试的 tooltip 定位错误已修正并包含在复测中。本任务四个 Dart 文件静态分析无问题，格式、文档链接及 `git diff --check` 通过。四包共 855 项通过（API 547、播放器 142、弹幕 161、mux 5），10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。日志：`build/ios-playback-navigation-targeted.log`、`build/ios-playback-navigation-package-tests.log`；计数包含检查时的同期改动。
- `tool/check.ps1 -SkipPub` 完成打包边界与格式检查后，被同期 macOS 关闭修改的 5 条 lint 阻塞（`window_service.dart` 和 `macos_fullscreen_close_test.dart`）。继续执行 `-Stage RootTests` 还遇到同期 macOS 全屏关闭、卡片菜单用例失败，运行在关闭用例失败后长时间未收尾，已结束自己启动的该次检查；未修改或终止其他任务。完整根检查未通过，13 项环境相关根测试跳过。记录见 `build/ios-playback-navigation-check.log`、`build/ios-playback-navigation-root-tests.log`，不将本任务定向通过写成全仓库通过。
- 本机为 Windows；上述 `TargetPlatformVariant.iOS` 回归验证 Flutter 行为，不代表 Xcode 编译、签名安装或 iPhone／iPad 真机验收。未改 Apple 原生代码，也未测原生播放、刘海设备实际手感或性能。DTD 调试连接被自动审批拒绝（`approval policy is never`），未执行热重载。

### Android 小窗导航修复（2026-11-01）

- 移除共享顶部控件按小窗布局隐藏导航按钮的条件；显示权限仍由工作区作用域决定。Android 单／双标签小窗保留返回、回到主页，iOS 继续在顶部导航行显示，多标签规则不变。
- 回归覆盖 320px 小窗、双倍字号、控件显隐及两个按钮的点击；全屏返回只退出全屏，主页先退出全屏再导航，媒体打开次数及单一 surface 保持。视频／影视／直播／离线的小窗控件回归同步更新。
- `tool/check.ps1 -SkipPub` 通过：根应用 3908、API 538、播放器 115、弹幕 153、封装包 5，共 4719 项通过；格式、静态分析及打包边界检查通过。根应用 13 项环境相关用例跳过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过；日志 `build/android-small-player-navigation-check.log`。计数包含检查时已有的同期改动。
- 文档相对链接及 `git diff --check` 通过。本轮未构建安装包或执行 Android／iOS 实机验收；未发现可连接的 DTD／调试应用，热重载未完成。

### 按平台与模式调整按钮位置

- 314 项定向回归通过，日志 `build/player-navigation-placement-targeted.log`。覆盖 Android/iOS/Windows/macOS/Linux/Fuchsia 与三种导航模式、顶部行和播放控件显隐、普通／全屏状态即时更新而不重新打开媒体、主页按钮回到原浏览窗口且保持播放、标题栏按钮／拖动／关闭，以及原生消息的 view ID／绑定 owner／窗口可用性和模态隔离。
- macOS 新增标题栏 Home 的显示宽度、可用状态及 Back/Home 分别派发的 XCTest。当前主机为 Windows，未执行该测试或编译 Swift；须在 Mac 运行 `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=macOS' -only-testing:RunnerTests`，并实机核对原生按钮、全屏和窗口切换。
- `tool/check.ps1 -SkipPub` 全量通过：根应用 2716、API 460、播放器 81、弹幕 93、封装包 2，共 3352 项自动测试；格式、静态分析与打包边界脚本通过。10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，日志 `build/player-navigation-placement-check.log`。
- Windows Debug 重新构建并启动成功，DTD 热重载通过，未发现 Flutter 运行时错误；日志 `build/player-navigation-placement-debug.log`。212 条本地文档链接及 `git diff --check` 通过。未进行 Android/iOS/macOS 实机操作，也未重建 Release；macOS 原生改动不能通过 Dart Widget 测试代替编译／设备验收。
- 检查计数对应日志完成时的工作区；交付前随后出现的 `.metadata`、`pubspec.lock`、`ios/`、`linux/`、`test/widget_test.dart` 同期改动已保留，未纳入上述检查结果。

### 首轮人数与导航接入

- `tool/check.ps1 -SkipPub` 全量通过：根应用 2709、API 460、播放器 81、弹幕 93、封装包 2，共 3345 项自动测试通过；根应用及四包格式、静态分析和打包边界脚本通过。10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不算原生集成通过。日志：`build/player-topbar-check.log`。
- 最终人数靠右调整后，共 198 项播放面板回归通过；播放出错时保留导航按钮的专项也通过。人数控制器、工作区和协议回归覆盖三种导航模式、单标签多视频／空间往返及缓存上限、桌面双窗口保留、全屏按钮、320px 双倍字号、人数轮询／取消／账号与分 P 隔离，以及协议字段校验。日志：`build/player-topbar-panel-final.log`、`build/player-topbar-error.log`、`build/player-topbar-followup.log`、`build/player-topbar-api-targeted.log`。最终格式与分析复核日志：`build/player-topbar-final-lint.log`。
- Windows Debug 构建成功，实际启动后通过 DTD 热重载成功，未发现 Flutter 运行时错误；日志：`build/player-topbar-debug.log`。只读截图确认真实播放窗口与画面，截图时控件处于隐藏状态，未完成真实窗口按钮逐项手动验收。
- 212 条本地文档链接和 `git diff --check` 通过。本轮没有构建 Release，也没有运行 Android/macOS 构建或实机验收；未修改原生播放后端，不把 Debug 启动、自动测试或接口快照当成长期播放／性能验证。
