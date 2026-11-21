# 点播与直播的原生缓存和网络重试

## 2026-11-21 Windows 直播播放列表读取中断

Windows x64 Release 在房间 23167433 播放 HLS。23:24 的两次缓存暂停分别持续 1.135 秒和 1.697 秒，同一播放器自行恢复。23:25:05，播放器 71 在两次 HTTP 503 后记录了 11 条 lavf 告警和一条错误，原生输入到达 EOF 时还剩 4.074 秒缓存。23:25:18，播放器 72 再次出现相同的 lavf 日志序列，读取已停止，剩余缓存 2.838 秒，播放意图仍为开启。第二次的脱敏日志没有 HTTP 状态码。原有 `segmentRead` 分类同时包含播放列表刷新和分片读取失败。

用该房间同一个游客 HLS/fMP4 地址同时测试两个 Windows 原生库。BiliSail 在约 72 秒时播放列表刷新遇到 HTTP 5xx，lavf 终止读取，随后 `eof-reached=yes`、`pause=yes`。本机 PiliPlus 2.1.6 的原生库有一次分片打开失败，观察到 80 秒仍在播放。两边均使用软件解码、空输出和相同请求头。进一步用相同的滚动播放列表，分别向两个原生库注入一次 HTTP 503：

| 返回 503 的请求 | BiliSail 原生库 | PiliPlus 原生库 |
| --- | --- | --- |
| 无故障 | 持续播放 | 持续播放 |
| 单个媒体分片 | 继续请求后续分片 | 继续请求后续分片 |
| 刷新播放列表 | 消耗剩余缓存后结束 | 消耗剩余缓存后结束 |

FFmpeg 的分片重试选项仅在分片打开失败时生效，播放列表刷新失败可以直接返回给上层。mpv 的 lavf 解复用器连续 11 次读包失败后终止读取。这 11 条告警并不代表 11 次 HTTP 请求。[FFmpeg HLS](https://github.com/FFmpeg/FFmpeg/blob/615b071/libavformat/hls.c#L1588-L1595)、[BiliSail 所用 mpv 基线](https://github.com/mpv-player/mpv/blob/afd6da884/demux/demux_lavf.c#L1567-L1585)、[PiliPlus 原生库对应基线](https://github.com/mpv-player/mpv/blob/43b14a4c9/demux/demux_lavf.c#L1464-L1480)。

核对 PiliPlus 2.2.1 源码，其直播播放器使用桌面 Safari UA 和 B 站主站 Referer，分别设置 mpv 的 `user-agent` 和 `referrer`。其应用收到指定 TCP／HTTPS 错误后，延迟三秒用当前地址从直播边缘重开。普通 completed 通知自身只更新完成状态。[播放器配置](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/plugin/pl_player/controller.dart#L883)、[错误订阅](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/plugin/pl_player/controller.dart#L1120-L1133)。

本次对齐直播间媒体请求头，并将当前解复用器报告的 HLS 终止读错接入同地址恢复。引擎等待缓冲播放完毕并确认本源 EOF，或收到原生终止错误后再上报。已经报告网络读错的直播若先收到 EOF，也进入终止恢复。会话三秒后重新检查账号、源代次、播放许可和用户意图。滚动 30 秒内最多安排三次终止恢复。单个分片告警和普通缓冲沿用原生处理。请求头对齐对线上 503 发生率的影响尚未测量。

mpv 将 FFmpeg 的日志回调注册到单个实例，多播放器共存时，当前直播可能只收到 EOF。应用在用户仍想播放的 HLS 直播出现这种情况时，向既有播放信息接口查询一次房间状态。仍在开播才重开同一流，下播保持结束，查询失败则提示手动重载。手动暂停、切页暂停、换源和关闭会取消待执行的恢复或状态查询。[mpv 的 FFmpeg 日志路由](https://github.com/mpv-player/mpv/blob/afd6da884/common/av_log.c#L140-L168)

Windows 原生回归使用循环更新的 fMP4 播放列表。旧连接收到四次 HTTP 503，房间状态桩返回仍在开播后，新连接使用相同的地址和媒体请求头恢复，播放位置推进到 4.163 秒。真实房间 23167433 的游客播放另观察两轮，每轮 80 秒。两轮结束时均在播放，期间的普通缓冲自行恢复，未遇到同类终止错误。

## 行为对照

| 场景 | BiliSail 原行为 | 本次采用的 PiliPlus 行为 |
| --- | --- | --- |
| 在线点播（含 PGC） | 默认预读 120 秒，前向、后向各 32 MiB。读取停滞、半个缓存窗口和反复缓冲可触发恢复 | mpv 前向、后向各 4 MiB，默认时长为 16 秒乘起播倍速，回落到时长的 2/3 后再补读。仍可指定预览窗口 |
| 直播 HLS／FLV | 64 MiB 前向、固定预读时长和起播蓄水，解码日志可触发线路切换 | 前向 8 MiB、后向 0。普通直播沿用 mpv 的默认预读时长。预览保留显式窗口 |
| 网络读错 | SDK 日志、读取状态、音视频时钟及累计欠载各自参与判断，随后可能刷新 playurl、切备用 CDN | 仅 SDK 报告 TCP 读取失败或 HTTP(S) 打开失败时安排 3 秒后的检查。点播还须仍在 buffering，且 SDK 原始缓存端点整秒为 0，点播检查节流 10 秒。直播按网络错误合并重连 |
| 恢复位置与线路 | 启动主线曾限时 6 秒，随后可能重开备用音视频并叠加重新解析 | 自动重开使用已解析的同一音视频地址／直播线路。点播带入确认位置、倍速和音量，直播从当前直播边缘打开。手动重试可重新解析过期地址 |
| 解码日志、普通缓冲、自然结束 | 多个监视器可将非终止事件升级为失败 | 日志用于诊断，buffer 和 buffering 更新进度条和提示，普通缓冲沿用原连接。本地文件关闭网络缓存。终止错误继续进入错误界面 |

PiliPlus 核对版本为 `217fb54f51f6764176319bbdedab2a7522d75401`。缓存参数见 [storage_pref.dart](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/utils/storage_pref.dart#L843-L883)，重开和错误订阅见 [controller.dart](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/plugin/pl_player/controller.dart#L960-L970) 及[错误处理](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/plugin/pl_player/controller.dart#L1120-L1156)。该版本的 overrides 和 lockfile 将核心和平台库锁定到 My-Responsitories 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频插件锁定到 bggRGjQaUbCoE 的 `85f0a69ea66b100882b27a3375c72e5155375343`。本项目按行为独立实现，沿用自己的固定媒体 fork。

## 本项目保留的边界

- 文件级 mpv 参数随卸载释放，播放器复用和阻塞 seek 的替换 loadfile 都使用对应文件的配置。准备完成时读取 SDK 已有缓存端点，避免起播期间已经填满的缓存要等下次补读才显示。
- 原生打开阶段同时收到明确网络错误和对应条目的终止事件时，会话可延迟 3 秒再试一次。重开本身失败则交给手动重试。清晰度／色彩兼容回退有独立原因和期限。
- 重试前核对源代次、账号、播放意图和播放许可。暂停、跳转、切源、关闭和收回播放许可都会取消待执行的重试。控制条保留错误提示。在网络播放期间也可从「更多播放选项 → 重新加载」手动刷新地址。
- 旧版曾记录播放还有约 40.7 秒缓存时重开，现场日志缺少触发原因。此次移除了可导致此类重开的路径。具体现场记录见 [Android 排查](android-rebuffer-reload-2026-11-15.md)。

## 验证

- 在独立工作树运行根检查脚本，根应用 5746 项通过、13 项跳过。bili_api 1021 项、bili_player 258 项、bili_danmaku 161 项、bili_mux 15 项通过，播放器包另有 3 项跳过。配置了本机 Windows x64 的 bili_mux.dll 和 ffprobe，实际执行了封装原生测试。
- 增加手动重新加载入口后，根应用静态分析与播放面板的 498 项测试通过。其中一项验证了缓冲时从「更多播放选项」重新加载，点播从已确认的位置恢复。Windows x64 Release 构建通过。
- Windows x64 实际播放器读取到点播缓存参数为前后各 4194304 字节、16 秒、补读阈值约 10.667 秒。在受控 HTTP DASH 上连续注入网络读错和解码日志，音视频继续播放，源代次保持不变。双轨分别两次断供、随后恢复时仍只解析一次，主线两条连接继续供数，备用线路请求数为零。
- Windows FLV 实测在长时间断供后沿用原连接。破坏视频帧引发解码日志时保持原直播连接，随后通过 SDK 的错误流连续注入两条相同 TCP 读错，3 秒后只重连一次，沿用同一地址。该用例验证 SDK 到会话的重试路径。
- Windows 的 UGC／PGC DASH、直播 HLS／FLV、缓存内 seek、不同轨道长度的正常 EOF 及单会话原生播放回归通过。原生回归使用本地媒体和受控 HTTP 服务，未采集线上偶发问题的发生率。
- Android arm64 开发 Release 在 Gradle 配置阶段被工具链阻止。当前 [Android 配置](../../android/settings.gradle.kts) 固定 AGP 9.1.0，本机 Flutter 3.50.0 要求至少 9.1.1。ADB 无连接设备。Android、Apple 和 Linux 没有本轮实机结果。
