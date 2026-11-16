# 点播与直播的原生缓存和网络重试

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
