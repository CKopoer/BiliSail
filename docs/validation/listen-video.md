# 听视频与音频播放控件

日期：2026-10-30。

## 行为与来源

- 视频、影视及本地分轨播放共用 `PlaybackSession.audioOnly`。完整控制栏及精简小窗直接提供耳机按钮，窄屏全屏的“更多播放选项”也提供“听视频”。小窗同时按轨道能力提供字幕菜单，见[小窗入口](responsive-player.md#小窗字幕与听视频入口2026-10-30)。
- 仅在已解析的 DASH 内容含独立音轨时提供入口。进入后关闭原媒体，在同一个 engine 中以 `ProgressiveSource(audio)` 打开音频地址；不向播放器传入视频地址，也不采用只隐藏 surface／禁用视频解码的方式。
- 进度、手动暂停意图、倍速、音量、音量均衡和播放互斥规则保持；重试及备用 CDN 只打开音频。换分 P／剧集继承当前模式，页面和导航检查点恢复自己的模式；停止／账号清理不把该选择写入设置或持久化 URL。
- 听视频期间移除视频 surface、弹幕叠加层及弹幕请求。恢复视频重新打开 DASH 分轨，沿用确认进度及用户意图。快速返回、切源、关闭仍使用既有 generation、取消和账号代次隔离。
- 下一项若没有独立音轨，显示错误并保留“返回视频”，不悄悄下载混合视频流。渐进 MP4、本地合并文件及直播 HLS／FLV 当前不提供入口；直播 `only_audio` 需要另外核对并接入真正的音频源。
- 本功能沿用既有后台、锁屏、媒体键及 PiP 平台策略，不将“听视频”视为这些能力的设备验收。

只读参考本地 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441`：

- `lib/plugin/pl_player/controller.dart` 的独立音轨打开职责；
- `lib/pages/video/widgets/header_control.dart` 的入口能力判断；
- `lib/http/live.dart`、`lib/pages/live_room/controller.dart` 的直播 `only_audio` 参数差异。

参考仓库当时的 media-kit overrides 实际使用 `My-Responsitories/media-kit` 的 `native` ref，锁文件解析为 `73771ec38176be2d984a3049c28177bce23b54a0`；本项目保持自己的固定 Predidit 依赖。PiliPlus 应用为 GPLv3，本轮仅参考行为，独立编写会话逻辑和 Flutter 控件，没有复制应用源码、资源或修改相邻仓库。

## 布局

2026-10-30 增加[歌词字幕与拖动／点击跳转](listening-subtitle-lyrics-2026-10-30.md)，包含响应式布局、字幕偏好和生命周期验证。

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

## 关闭超时复验（2026-10-30）

用户要求处理剩余四个关闭超时并重跑完整检查。当前工作区起点为 `d65f5c2`，已包含 `aa81d10` 的关闭流程调整；本次复查时四项已不再复现，没有新增关闭实现改动。四个用例仍保留原有的 `manager.close().timeout(2s)` 检查，覆盖 Android 应用内、Windows 应用内／独立窗口、macOS 独立窗口。

- 四项单独复跑全部通过，日志 `build/validation/playback-close-before.log`。
- 在当前主工作区执行完整 `tool/check.ps1 -SkipPub`，退出码 0。格式、根静态分析、Linux 适配器分析和全部打包边界脚本通过；本次没有依赖修改，沿用已解析依赖。
- 根应用 **3504**、bili_api **496**、bili_player **96**、bili_danmaku **118**、bili_mux **5** 项通过，总计 **4219 项通过、0 失败**，包括原先四个关闭用例。
- 根应用 13 项按既有条件跳过；另有 10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生验证通过。
- 完整日志：`build/validation/playback-close-full-check.log`。本次为自动检查复验，没有新增平台构建、设备操作或性能测量。
