# 听视频与音频播放控件

日期：2026-10-30。

## 行为与来源

- 视频、影视及本地分轨播放共用 `PlaybackSession.audioOnly`。普通、全屏和精简小窗在画面右上角提供耳机按钮，“更多播放选项”也保留“听视频”。小窗底栏同时按轨道能力提供字幕菜单，见[播放器布局](responsive-player.md#配置入口上移与小窗播放进度2026-10-31)。
- 仅在已解析的 DASH 内容含独立音轨时提供入口。进入后关闭原媒体，在同一个 engine 中以 `ProgressiveSource(audio)` 打开音频地址；不向播放器传入视频地址，也不采用只隐藏 surface／禁用视频解码的方式。
- 进度、手动暂停意图、倍速、音量、音量均衡和播放互斥规则保持；重试及备用 CDN 只打开音频。换分 P／剧集继承当前模式，页面和导航检查点恢复自己的模式；停止／账号清理不把该选择写入设置或持久化 URL。
- 听视频期间移除视频 surface、弹幕叠加层及弹幕请求。恢复视频重新打开 DASH 分轨，沿用确认进度及用户意图。快速返回、切源、关闭仍使用既有 generation、取消和账号代次隔离。
- 下一项若没有独立音轨，显示错误并保留“返回视频”，不悄悄下载混合视频流。渐进 MP4、本地合并文件及直播 HLS／FLV 当前不提供入口；直播 `only_audio` 需要另外核对并接入真正的音频源。
- 手动听视频与系统后台策略分别处理，不将“听视频”视为后台、锁屏、媒体键或 PiP 的设备验收。

## 移动端后台保留播放源（2026-10-31）

- Android 和 iOS 进入系统后台时不自动切换听视频，也不重新解析或打开媒体；沿用当前播放器、媒体源以及播放／暂停意图。原本已手动选择听视频时仍保持手动模式；普通视频、影视、直播及渐进媒体均保留当前源。回到前台也不主动重新打开或恢复用户手动暂停的播放。
- 普通视频继续使用原音视频源，后台仍可能下载或解码视频，不保证节省视频流量。切换不再主动触发重新加载，但实际画面恢复仍受系统、网络、解码和设备状态影响，不能保证零缓冲。后台继续播放和 iOS 能力均需实机验证，系统可能中断或限制进程；工程未显式配置 iOS 音频会话类别，原生后端与系统的实际行为仍待确认。
- 只读参考 PiliPlus 提交 [`936072449e82e3d90c28c728c0087bf5136fa441`](https://github.com/bggRGjQaUbCoE/PiliPlus/commit/936072449e82e3d90c28c728c0087bf5136fa441) 的 `lib/plugin/pl_player/view/view.dart` 和 `lib/pages/video/view.dart`：允许后台播放时保留播放器并停止弹幕显示；不允许时暂停。仅参考行为，未复制 GPLv3 应用源码。
- `tool/check.ps1 -SkipPub` 通过：根应用 3680 项、bili_api 497 项、bili_player 101 项、bili_danmaku 136 项、bili_mux 5 项；根应用 13 项按条件跳过，另 10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。格式、静态分析和打包边界检查通过，日志 `build/background-retain-check-final.log`。
- Windows 本地分轨原生测试通过，验证后台无 Flutter 帧时播放位置前进，播放器及源代次保持不变；该结果不能代替 Android 或 iOS 设备测试。Android arm64 开发 Release 构建通过，APK 为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，版本 `1.2.5+2`，SHA-256 `bebee961b5a6ca35a810c287f056088a0f49582c7ffdb6cdeab569c069b97aea`；未安装或连接设备。

只读参考本地 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441`：

- `lib/plugin/pl_player/controller.dart` 的独立音轨打开职责；
- `lib/pages/video/widgets/header_control.dart` 的入口能力判断；
- `lib/http/live.dart`、`lib/pages/live_room/controller.dart` 的直播 `only_audio` 参数差异。

参考仓库当时的 media-kit overrides 实际使用 `My-Responsitories/media-kit` 的 `native` ref，锁文件解析为 `73771ec38176be2d984a3049c28177bce23b54a0`；本项目保持自己的固定 Predidit 依赖。PiliPlus 应用为 GPLv3，本轮仅参考行为，独立编写会话逻辑和 Flutter 控件，没有复制应用源码、资源或修改相邻仓库。

## 布局

2026-10-30 增加[歌词字幕与点击跳转](listening-subtitle-lyrics-2026-10-30.md)；2026-10-31 按用户要求改为拖动／滚动只浏览、点击才跳转，小窗口听视频播放器占页面可用高度约 50%。包含响应式布局、字幕偏好和生命周期验证。

- 控件常驻，沿用应用浅／深主题。顶部保留工作区返回／主页和“返回视频”；窄窗或大字体时后者使用带提示的图标。
- 手机内联区域以小封面和标题横排；竖向全屏用居中封面与标题；桌面／平板较大区域采用大封面和标题横排。无封面时显示静态耳机后备图形，不增加持续动画。
- 底部保留进度、前后 10 秒、播放／暂停、倍速、音量、下一集和全屏。窄屏把下一集和音量放进选项菜单，大字体时倍速使用图标入口。
- 播放位置只重建进度局部；拖动预览保留到 seek 确认，旧 seek 完成不能清除新的拖动。
- 布局依据播放器实际宽高，不按操作系统或设备型号分叉。键盘沿用同一个播放 owner，控件支持触摸、鼠标和语义提示。

## 验证

- `test/features/playback/audio_playback_test.dart`：UGC／PGC／离线分轨的音频源、暂停／进度／倍速／音量、音频 CDN 备用、迟到请求、换集／检查点、不支持的内容，以及 320×180、390×220、900×506、390×760 的普通／2 倍文字布局和交互。
- `integration_test/audio_only_playback_test.dart`：Windows 原生 engine，通过本机 HTTP 服务检查切换后仅请求音频、请求头、音频解码且无视频输出，以及恢复 DASH 和暂停位置。已纳入 `tool/test-windows-media.ps1`。

2026-10-30 本轮执行：

| 检查 | 结果 |
| --- | --- |
| 新增音频行为／布局测试 | 20 项通过；覆盖普通／全屏往返、倍速、音量、seek 确认及完整工具栏入口 |
| 精简小窗兼容回归 | 视频／影视／直播／离线 × 点击／动态模式共 8 项通过，保持三个工作按钮 |
| 播放会话／控件定向回归 | 537 项通过，包含当时的 19 项音频用例；随后新增的 seek／菜单用例另跑通过 |
| 首次 `tool/check.ps1 -SkipPub` | 打包边界脚本、格式、静态分析通过；当时根测试 3494 通过、13 跳过、4 失败，后续复验见下节 |
| 首次根测试失败复查 | 当时 `workspace_router_test.dart` 四个平台／窗口组合在 `manager.close().timeout(2s)` 处超时；单文件复跑为 77 通过、4 失败，后续复验已通过 |
| `tool/check.ps1 -SkipPub -Stage PackageTests` | bili_api 496、bili_player 96、bili_danmaku 118、bili_mux 5 项通过；未配置 `BILI_MUX_LIBRARY` 的 10 个原生 mux 用例跳过 |
| Windows 原生音频集成 | 独立工作区 Debug 构建与 1 项受控测试通过；音频期间所有媒体 HTTP 请求均为音轨，音频解码成功、无视频输出，恢复后 DASH 两轨、暂停和位置通过 |
| Windows mux 构建准备 | `tool/build-download-mux.ps1 -Target windows-x64` 成功；该构建结果不作为 mux 原生用例通过 |
| Windows 控件运行检查 | 独立本地音频预览启动、热重载成功，运行时错误查询为空 |

原生验证使用独立工作区（起点 `2ee2ef5`，覆盖本任务播放源码）以避开共享构建目录的链接占用；使用本机已有 NuGet 工具和固定原生资产。只访问受控本地媒体 HTTP 服务，没有执行真实账号或公开 CDN 操作。日志和组件截图位于忽略目录 `build/validation/audio-listening-*`。

Android、macOS、iOS、Linux 原生构建／设备验收、真实在线内容及长期听视频未在本轮执行；未据此声明后台播放或性能收益。

## 返回视频的重复加载修复（2026-10-31）

- 三端共用的 `MediaKitEngine.open` 原先从零位置加载并确认视频输出，随后再 seek 到听视频进度，可能出现两次缓冲。现将进度作为 `Media.start` 随打开请求提交，原生加载阶段直接定位；继续等待确认位置、视频解码／输出和独立音轨，不再在画面就绪后无条件 seek。
- Android 的“返回视频”动作可能先于前台恢复回调到达。前台模式偏好改变而实际仍需后台音频时，更新偏好并保留当前音频源；恢复前台时才打开视频，避免先重复打开音频。
- 只读对照 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/plugin/pl_player/controller.dart::_createVideoController`：将续播位置作为 `Media.start` 传入。依赖及许可范围同上，本次独立实现，没有复制应用源码或修改参考仓库／Pub 缓存。
- 回归断言媒体实际打开次数、返回过程无额外 seek，以及播放／暂停、进度、倍速、音量和迟到请求隔离。原生测试使用本机合成 DASH 分轨及 HTTP 服务，不访问真实账号或在线 CDN。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析和打包边界脚本通过，根应用 3679、bili_api 497、bili_player 101、bili_danmaku 136、bili_mux 5 项，共 **4418 项通过、0 失败**。根应用按既有条件跳过 13 项，另 10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过；日志：`build/validation/listening-return-full-check.log`。计数包含本轮共享工作区的同期功能。
- 定向听视频测试 **35 项通过**。Windows 原生对照中，旧实现因返回过程出现额外 seek 而失败；修复版验证暂停／播放往返、重复点击和前后台回调交错时只打开一次视频，独立音轨、实际视频解码、进度、倍速和音量保持。另覆盖 DASH／渐进视频／纯音频的暂停定位、回退 seek，以及续播位置到达／超过片尾。日志：`build/validation/listening-return-native-before.log`、`build/validation/listening-return-endpoint-before.log`、`build/validation/listening-return-endpoint-after.log`、`build/validation/listening-return-targeted-final.log`。
- 在独立工作区覆盖本任务的播放源码后，完整 `tool/test-windows-media.ps1` **32 项原生测试通过、0 失败**，包括重播、准备／取消、视频输出、听视频、媒体键、中断恢复、预览、音量均衡及长视频缓冲窗口；日志：`build/validation/listening-return-windows-media.log`。复用已缓存的原生资产，构建钩子继续校验哈希，没有修改来源／TLS／校验规则。
- 独立的本地合成分轨调试入口热重载成功，运行时错误查询为空；验证后已退出，没有打开用户数据库或真实账号。
- 本次未执行 Android、macOS、iOS、Linux 原生构建／设备验收，也未进行真实在线内容、长期播放或 Profile／Release 性能测量。

## 关闭超时复验（2026-10-30）

用户要求处理剩余四个关闭超时并重跑完整检查。当前工作区起点为 `d65f5c2`，已包含 `aa81d10` 的关闭流程调整；本次复查时四项已不再复现，没有新增关闭实现改动。四个用例仍保留原有的 `manager.close().timeout(2s)` 检查，覆盖 Android 应用内、Windows 应用内／独立窗口、macOS 独立窗口。

- 四项单独复跑全部通过，日志 `build/validation/playback-close-before.log`。
- 在当前主工作区执行完整 `tool/check.ps1 -SkipPub`，退出码 0。格式、根静态分析、Linux 适配器分析和全部打包边界脚本通过；本次没有依赖修改，沿用已解析依赖。
- 根应用 **3504**、bili_api **496**、bili_player **96**、bili_danmaku **118**、bili_mux **5** 项通过，总计 **4219 项通过、0 失败**，包括原先四个关闭用例。
- 根应用 13 项按既有条件跳过；另有 10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生验证通过。
- 完整日志：`build/validation/playback-close-full-check.log`。本次为自动检查复验，没有新增平台构建、设备操作或性能测量。
