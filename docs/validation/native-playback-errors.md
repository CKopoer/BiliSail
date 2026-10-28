# 播放错误与控制栏排查

日期：2026-10-05。用户反馈播放期间出现 `Native playback error`，画面和声音仍然继续，但控件无法弹出。

## 已确认原因

- 固定依赖 `media_kit 1.2.6` 的 `lib/src/player/native/player/real.dart` 将 `MPV_EVENT_LOG_MESSAGE` 中部分 `file`、`ffmpeg/tcp`、`vd`、`ad`、`cplayer`、`stream` error 日志也转发至 `Player.stream.error`。这些事件不是“播放已终止”的充分证据。[上游源码](https://github.com/media-kit/media-kit/blob/main/media_kit/lib/src/player/native/player/real.dart)用于定位，判断依据为本机实际锁定版本。
- 原适配器将每条 error 立即转为 `PlaybackPhase.failed` 和固定字符串 `Native playback error.`，会话保留错误文字，即使后续原生位置继续前进也不会清除。
- 原播放页底部控制栏仅在 `session.error == null` 时构建，因此出错后 hover/点击不能让控件重新出现。
- 排查时应用数据目录仅有 SQLite 和安全存储文件，仓库 `artifacts` / `.buildlog` 是已有构建、测试记录。原实现没有将 native error/log 写盘，这次原始消息无法追溯，不能据此断言是 CDN、硬解或某个具体 codec 的故障。

## 本轮修正

- 原生日志与失败分开：在运行期间收到 error 时开始有界观察，正常确认进度前进即解除；持续 8 秒不前进且仍有播放意图，才报告可重试的停滞。日志洪泛不会延长截止时间，暂停与 seek 暂停计时；代次变化、结束、停止与销毁取消观察。准备阶段保留原有轨道/音频就绪检查。
- 8 秒是恢复观察预算，不是证明底层错误不可恢复的判据。用户仍可重载/切清晰度；没有新增自动重放或无限重试，也不把单条位置事件当作音视频完整性验证。
- 错误展示改为顶部提示条，底部播放配置、清晰度、音量、全屏等入口保持可用；错误时播放按钮/空格执行重新加载，沿用原会话保存的位置与播放意图。
- `MediaKitEngine.onDiagnostic` 输出结构化白名单字段，经应用组合根写至 Windows `%APPDATA%\dev.bililite\bili_lite\logs\playback-*.log`。文件名区分运行/进程；字段含 UTC 时间、generation、phase、positionMs、bufferedMs、播放意图、原生模块、错误类别和可识别的 HTTP 状态。未知原文只记 `unknown`，不保存 URL、query、Cookie、token、账号、标题或原始日志。
- 每份文件 256 KiB、每次运行两份轮转；创建/轮转时最多六份，写入队列最多 64 条，洪泛丢弃计数。文件写入失败停用该日志，不影响正常播放；无自动上传。
- 本机原生 DLL 将 HTTP 403 的 FFmpeg 消息记在 warning 级别，因此订阅 warn/error/fatal 并保留白名单严重性。该版 mpv 的 FFmpeg 日志桥接使用进程级上下文：本机在连续创建/销毁 Player 后，403 有时只留下 `stream/openFailed`，独立新进程才取得 `ffmpeg/httpStatus=403`。诊断测试因此使用独立原生测试进程，不能承诺每条网络错误都能取得 HTTP 状态；未知模块/文本仍保持脱敏，不猜测状态码。[对应 mpv 源码](https://github.com/mpv-player/mpv/blob/652a1dd/common/av_log.c)

## 验证范围

回归覆盖继续播放的非终止性日志、真实停滞与错误洪泛、暂停/seek、旧代次/结束/销毁、错误态控件和全屏，以及日志脱敏/轮转/队列容量/不可写目录。

- 根应用播放面板/会话/日志共 **47** 项测试通过；`bili_player` 分析无问题、**16** 项测试通过。
- `tool/test-windows-media.ps1` 通过。首个原生进程报告 5 项，其中公网分支未启用，实际执行 4 项本地验证（DASH headers/重定向/Range、解码、seek/倍速/全屏、标签保留及安全存储探针）；第二个独立进程执行 1 项 HTTP 403 错误落盘验证，确认状态码存在且测试 URL/token 不落盘。
- Windows release 构建成功。为避免覆盖运行中的旧版本，使用独立源码快照构建并导出至 `artifacts/bili-lite-native-error-fix-windows-x64`。构建快照保存在忽略目录 `build/native-error-fix-source`，不是额外 Git 工作树；导出的整个目录一起使用。EXE SHA-256：`CC3FFCD1C8EB7987F3C196279DAB80A7A5C960D03AC6FB68E03ADC62DD262C2B`；`data/app.so` SHA-256：`1417FA571A47A8007BA37951081AC98DA0F3F9DEC9C6ABFC0B3F51E90A94A658`。
- 本轮早期 `tool/check.ps1 -SkipPub` 全通过；最终复跑时，工作区同时新增其他功能，检查停在 `lib/app/router.dart`、`shell.dart`、`workspace_tabs.dart` 的格式。单独全工程 analyze 另报告 `api_profile_repository.dart` 两处初始化风格及 `tool/profile_smoke.dart` 两处 print lint。本次没有改写这些并行改动，不将最终工作区全量检查标为通过。
- 详细记录：`artifacts/native-error-final-playback-tests.log`、`native-error-player-analysis.log`、`native-error-player-tests.log`、`native-error-windows-media.log`、`native-error-windows-build.log`；完整检查受阻记录为 `native-error-check.log`、`native-error-final-analysis.log`。真实 HTTP 403 脱敏事件位于 `artifacts/native-playback-diagnostics/playback-*.log`，它们是受控测试证据，不是用户此前故障的日志。

未取得本次用户故障的原始 native 文本；新日志只能记录新版启动后的事件。Android/macOS 原生运行、长时间网络恢复与性能仍需逐平台实测。

## 播放完成后加载提示不消失（2026-10-07）

用户反馈视频已经播放到末尾、时间显示完成，但仍显示“正在准备音视频…”。本机锁定的 `media_kit 1.2.6` 在 EOF 时先发送 `completed=true`，随后发送 `buffering=false`。适配器为防止后续通知覆盖完播状态，在 `ended` 后忽略状态切换；此前完播只修改 phase 和播放意图，保留了 `isBuffering=true`，后续清除事件又被忽略。播放面板直接读取该标记，导致加载提示一直存在。

修复在进入 `PlaybackPhase.ended` 时同时清除缓冲、seek 标记，继续保留完播状态直到显式 seek/play 或换源。共享播放面板也排除已结束源的缓冲提示；解析新源和正常播放缓冲仍显示原有加载提示。

修复前，窗口/全屏两项回归均复现提示残留，Windows 原生队列测试确认完播后 `isBuffering` 实际为 true。修复后两项界面回归及 `integration_test/windows_watch_later_queue_test.dart` 通过，覆盖结束时/延后一秒/末尾重播均无残留提示、分 P 与下条自动推进，以及重播沿用原 source generation。使用本地分轨夹具，未启用在线 smoke；Android/macOS 原生运行尚未验证。

原生修复前后日志分别为 `build/playback-completion-native-before.log` 与 `build/playback-completion-native-after.log`。

## 打开视频黑屏、重新打开恢复（2026-10-24）

系统安装版 1.1.1.0 用户反馈打开视频时画面黑屏、声音正常，重新打开同一视频恢复。排查发现并通过组件测试复现了控制器替换时保留旧画面状态的路径；故障现场已消失，现有日志没有控制器身份、Texture 挂载及逐帧时序，尚不能将该路径定为本次实机事件的唯一原因。

固定 media-kit fork `24f5c7cb6b78f68fa7c23c73ffe7294f0bd962ab` 的 `VideoState` 只在初始化时订阅播放器宽高，`didUpdateWidget` 不会在 controller 变化后重新订阅。共享输出原先未给 `Video` 设置控制器身份 key：若旧源未取得尺寸，清空和重新绑定控制器发生在同一 Flutter 帧内，ValueListenableBuilder 可以跳过中间空值，保留旧 `_visible=false` 与旧播放器监听。新播放器和纹理已就绪，界面仍不创建 Texture；重新进入页面则会重建状态并恢复。

[共享输出](../../packages/bili_player/lib/src/media_kit_video_output.dart)现使用 `ObjectKey(controller)`，更换控制器时同步重建画面状态及监听；同一控制器的普通重建保留状态。修复覆盖使用该输出的视频、PGC、直播、离线及悬停预览，不改变 engine 所有权、播放命令或原生解码配置。

当前 Windows 的“首帧完成”由原生 Resize 的正尺寸通知触发，`hasVideoOutput` 也只检查纹理 ID 和尺寸，不能证明 Flutter 已实际显示画面。日志中 10:27:57 有一次 TLS 打开失败后切换备用地址、随后音视频及输出就绪的过程，但没有准确的视频身份和故障时间关联，不能据此断言 TLS 直接造成了本次黑屏。

[正式回归](../../packages/bili_player/test/media_kit_video_output_test.dart)直接使用生产输出构建的组件及固定依赖的真实 `Video`，注入 fake 播放器和纹理元数据，覆盖新尺寸在替换前／后就绪、旧播放器迟到尺寸不能隐藏新画面，以及同一控制器重建保留状态。修改前两项替换用例失败，修改后三项通过；日志为 `build/black-screen-regression-before.log` 和 `build/black-screen-regression-after.log`。这些用例验证组件生命周期和 Texture 挂载，不等同于原生 GPU 实机画面或可听音频验证。

`tool/check.ps1 -SkipPub` 最终通过格式、静态分析、打包边界与根应用／四包测试，共 2,604 项（2,002／426／81／93／2）；另有 10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。日志为 `build/black-screen-fix-check-final.log`。首轮静态分析发现新测试直接读取受保护的 controller 字段，改为 fake 子类的只读 getter 后完整重跑通过。文档相对链接和 `git diff --check` 通过。

本轮没有构建或替换系统安装包；Windows 原生 GPU 实机播放及 Android/macOS 运行尚未验证。没有活动 DTD／debug 应用，热重载尝试返回无应用连接，不能将组件测试或全量离线检查当作已安装程序的修复验收。

## 播放中视频断流但音频继续（2026-10-28）

本机普通入口 Windows Release 出现画面停止且不能自行恢复。保留的 `playback-1793197674339106-35292.log` 中，23:03:48（北京时间）播放位置为 1,028.920 秒，视频缓冲端点为 1,029.000 秒；23:04:10 播放位置已经推进至 1,090.692 秒，缓冲端点仍为 1,029.000 秒，并出现 `vd/hardwareDecoder` warning。这些记录支持视频数据停止补充后音频继续的路径；日志没有逐帧时间戳和原始错误，不能仅凭 warning 断言显卡、驱动或某个 CDN 是最初断流的原因。

使用现有 12 秒 H.264/AAC 分轨素材，本地 HTTP 服务声明完整视频长度，只交付前三分之一后断开连接，并拒绝后续视频 Range；音频完整可用。[原生回归](../../integration_test/windows_video_stall_test.dart)修改前复现：视频缓冲停在 **3.791 秒**，播放位置继续至 **10.031 秒**，状态始终 `playing`，失败事件为 0。首帧和解码尺寸均正常，因此不是启动时的视频未就绪。复现日志为 `build/validation/video-stall-20261028/before.log`，现场日志副本也保存在该忽略目录。

共享播放器使用视频作为主源、`audio-files` 作为外部音轨。mpv 可以把提前耗尽的视频当作视频轨 EOF，继续播放外部音轨；这时主文件不一定产生错误 `END_FILE`，也不一定保持网络 buffering。mpv 的[缓存暂停实现](https://github.com/mpv-player/mpv/blob/88eb9f2e73/player/playloop.c)依据 demuxer idle/underrun 和输出 underrun 判断缓冲，普通等待补数据不能覆盖所有提前 EOF。原有 `NativeErrorMonitor` 只在错误流触发后等待播放位置恢复；音频位置推进也会满足该条件，不能用它证明视频恢复。

本轮修复：

- [DashVideoContinuity](../../packages/bili_player/lib/src/dash_video_continuity.dart)仅对带外部音轨的 DASH 监控主视频缓冲。播放位置超过视频缓冲 500ms、缓冲端点持续不变至少 1 秒、且距离正常结尾超过 2 秒时，报告 `videoInterrupted`。暂停、seek、正常 buffering、源替换、未知缓冲和正常 EOF 不触发；不增加逐帧 Provider 更新、FFI 查询或定时轮询。
- [MediaKitEngine](../../packages/bili_player/lib/src/media_kit_engine.dart)先保留视频缓冲边界并冻结待处理的位置事件，再实际暂停 native player，随后报告专用失败。仅把 phase 标成 failed 不会停止外部音频。暂停超时/失败时释放旧 player；旧 generation 的异步操作不能改变新源。失败后的迟到位置事件也不能覆盖恢复位置。
- [PlaybackSession](../../lib/features/playback/application/playback_session.dart)在当前账号与源仍有效、用户仍要播放且播放许可有效时，重新解析并重载一次，从视频缓冲边界继续，保留清晰度、倍速、音量、内容与配音选择。重载沿用已有打开/备用地址预算，重载后的再次视频中断明确报错；手动重试或新的视频可以重新获得一次恢复机会。暂停、切页互斥、stop、close、换源及账号 scope/epoch 变化取消排队的恢复，恢复期间的用户暂停继续生效。
- 脱敏诊断新增 `videoInterrupted` 事件和失败分类，记录触发时的位置、视频缓冲和状态，不记录媒体 URL、凭据或原生正文。没有调整硬解偏好、缓存容量、media-kit fork 或 Windows 原生补丁。

自动验证：

- 13 项缓冲连续性单元回归通过，覆盖持续音频推进、正常缓冲、暂停/seek/结束、补充数据、换源和重置。
- 12 项会话行为回归通过，覆盖自动恢复一次、再次中断、手动重试、新视频、设置保留、暂停/许可与账号/源生命周期隔离。
- Windows 原生回归 2 项通过：底层在 3.791 秒边界失败并实际暂停，静置后 native 位置不再前进，正常资源重开恢复；使用完整 `PlaybackSession` 时同一 URL 的后续请求恢复正常，自动重载后继续至 6.041 秒、缓冲推进至 11.875 秒，视频仍有解码和输出。日志 `build/validation/video-stall-20261028/after-native.log`；已纳入 `tool/test-windows-media.ps1`。
- 既有 `native_video_readiness_test.dart` 的 5 项 Windows 原生回归通过，覆盖无法解码视频、换正常源、暂停续播、seek 的确认位置、progressive 与纯音频。日志 `build/validation/video-stall-20261028/readiness.log`；完整播放会话单测 210 项通过（`session-all.log`）。
- 最终 `tool/check.ps1 -SkipPub` 通过格式、静态分析、打包边界及根应用与四包测试：3343 / 492 / 96 / 116 / 5，共 **4052 项通过**。13 项 Windows 符号链接用例因权限跳过，10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，均不计为通过。日志 `build/validation/video-stall-20261028/check-final.log`。
- 复用已准备的固定来源 Windows mux 资产，`flutter build windows --release --no-pub -t lib/main.dart` 通过（88.5 秒），正常入口 `build/windows/x64/runner/Release/bilisail.exe`，须保留整个 Release 目录；日志 `build/validation/video-stall-20261028/release.log`。本轮没有制作或替换系统安装包；构建和全量检查针对对应执行时的工作区，提交仅包含本任务文件。

本修复覆盖“视频数据提前耗尽而外部音频继续”的已复现路径。缓冲充足时纯 GPU 呈现停顿、无新帧但缓冲仍前进的解码故障，以及真实故障 CDN 的最初诱因仍不由这些数据证明；未增加未经验证的全局软解或网络重试参数。Android/macOS 原生执行、真实账号长时间播放和人工可听音画同步需分别验收。
