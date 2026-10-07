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
