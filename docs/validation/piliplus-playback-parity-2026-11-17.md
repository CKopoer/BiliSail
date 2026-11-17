# 播放底层对齐与 Windows 中途失声

日期：2026-11-17（Asia/Shanghai）。本记录补全此前[缓存与网络重试](piliplus-network-retry-2026-11-17.md)之外的底层差异，替代旧的强制倍速音频策略与 Android 默认解码队列配置。

2026-11-18 补充：不完整 TLS 记录可能在另一层原生重试中永久等待，原先的普通 HTTP 截断没有覆盖这个边界。现场、实际 PiliPlus 原生库对照与兼容修复见[持续缓冲记录](windows-tls-buffering-2026-11-18.md)。

## 现场与原因

运行中的 `build/windows/x64/runner/Release/bilisail.exe`，PID 16340，22:19:22 打开 DASH，3× 播放。活动播放器 13 在 22:19:47、22:20:05、22:20:23、22:20:41、22:21:17 记录五次警告，22:21:34 出现错误，22:22:01 在 509.92 秒处出现 `ad` / `decoderFailure`。此时视频仍播放，前向缓存约 4 MiB，但双轨最小缓存时长已为零。现场日志已另存于本地 `build/validation/windows-audio-loss-2026-11-17/`。

本项目 Windows 原生库为 `mpv v0.41.0-dev-gafd6da884` / FFmpeg `git-2026-10-12-615b071`，默认 `curl-enabled=yes`。当前安装的 PiliPlus 为 `mpv v0.41.0-725-g43b14a4c9` / FFmpeg `N-124868-gd1faab734`，没有 curl 读取器选项，使用 lavf。仅同步应用层缓存与重试条件不能覆盖这个差异。

固定 mpv 源码的 [stream_curl.c](https://github.com/CKopoer/mpv/blob/afd6da8843a07f463ba4c736a2ea636b1a92e23e/stream/stream_curl.c) 中，默认 HTTP 响应不分段，接收失败后从已收到的字节处续读，但仅完整响应成功才清零重试计数。长连接累计五次失败后，下一次失败就结束读取，即使历次重试均成功推进。音频缓存消耗到截断包时，出现音频解码错误；EDL 视频仍有包，整体播放不结束，也不一定进入 buffering。SDK 中已有音频编码与声道元数据不能证明仍有声音输出。

本地 HTTP 服务每次发送 1 MiB + 32 KiB 后关闭音频响应，保留声明的完整 Content-Length。旧 curl 路径累计五次续读后失败，在约 223 秒处出现 `Error decoding audio`，230 秒时视频继续而 `audio-pts` 不再可用；该顺序与现场相符。相同原生库切换 lavf 后，第六次中断仍继续从正确字节续读，230 秒处音频时钟正常。lavf 使用其原生 `reconnect=1`、`reconnect_delay_max=7`，见 [stream_lavf.c](https://github.com/CKopoer/mpv/blob/afd6da8843a07f463ba4c736a2ea636b1a92e23e/stream/stream_lavf.c)。

现场原始错误文本已被既有脱敏器归为 `other/unknown`，无法逐字还原每条警告；同库故障对照实验确认了可造成此现象的底层路径。不能将普通音频解码日志全部视作需要重开的故障。

## 逐项对照与实现

参考应用固定 `217fb54f51f6764176319bbdedab2a7522d75401`。核心及库插件实际锁定 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频插件锁定 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`。

| 底层路径 | 当前处理 |
| --- | --- |
| HTTP 读取 | 检查 curl capability；支持时关闭 curl，统一使用与 PiliPlus Windows 相同的 lavf 原生续读。旧库没有此选项时不写不存在的参数。写入后核对读回值，失败不静默降级 |
| DASH 分轨 | 同一 mpv EDL 时间线、`!new_stream`、`!no_chapters`；长度前缀按 UTF-8 字节计，保留签名 URL 与本地中文路径 |
| 请求头与连接 | SDK 应用 User-Agent / Referer / 其他头；原生负责 Range、重定向、TLS 与断流续读，无应用 HTTP 代理或应用层字节队列 |
| 点播缓存 | 前后各 4 MiB，默认 16 秒乘起播速度，时长回落至 2/3 后再读。倍速变化只设置 speed，不重置缓存窗口，与参考实现一致 |
| 直播缓存 | 前向 8 MiB，后向 0；普通直播使用原生默认预读时长。预览的显式小窗口为产品调用参数 |
| 离线缓存 | 本地文件关闭网络缓存。SDK 原先默认开启的磁盘缓存统一改为关闭，与参考 SDK 的原生默认相同 |
| 音视频同步 | 所有源统一 `video-sync=display-resample`；Android `autosync=30`，桌面与其他平台 `0`。不再只对有声点播切换同步策略 |
| 音频缓冲与倍速滤镜 | 删除 `audio-buffer=0.05` 和常驻 `af=scaletempo2`。恢复原生音频缓冲、动态音调校正及 SDK `setRate`，不在按下／松开倍速时暂停、seek 或重开 |
| Android 音频输出 | 使用 `opensles,aaudio,audiotrack` 的顺序回退，补全官方 SDK 单独指定 OpenSL ES 时遗漏的后备输出 |
| 精确 seek | SDK `seek absolute`，恢复 `hr-seek=default`、`hr-seek-framedrop=yes`；取消旧目标只撤销等待，不因 buffering 执行 stop/loadfile。移除生产入口额外 40 ms 延迟 |
| 视频解码队列 | 删除 Android 默认开启的自定义 8 帧／100 ms 队列，使用 mpv 默认。显式实验开关仅供既有诊断入口 |
| 硬解 | 桌面沿用 SDK `auto`；Android Release/Profile 为 `mediacodec,auto-safe`，Debug 为 `auto-safe`，与参考平台默认一致；用户显式软解仍生效 |
| Android 空闲输出 | VideoController 初始化后设置并回读 `force-window=no`，避免空闲 mpv 窗口尺寸参与新源 Surface 初始化 |
| 加载与播放控制 | `open(play:false, start:...)` 后设置倍速并按用户意图 play；继续播放直接 SDK play，不重建时间线或音轨。轨道／首帧确认只用于本项目 ready 契约，不预滚、静音蓄水或另建音频时钟 |
| 网络重开 | 明确 TCP 读取／HTTP 打开错误后延迟 3 秒；点播要求原始 buffer 整秒为 0 且仍 buffering，并节流 10 秒。重开沿用现有地址、位置、速度和音量；手动重试可刷新地址 |
| 解码、buffering 与 EOF | 普通解码日志、短缓冲与输入 EOF 只记录／更新状态，不添加半窗口、持续时钟轮询、累计欠载或备用线路探测 |
| 普通视频、PGC、直播、离线与预览 | 同一原生工厂、共享配置与会话契约；直播倍速仍固定 1×，静音预览显式选择无音轨 |

配置入口为 [native_playback_policy.dart](../../packages/bili_player/lib/src/native_playback_policy.dart)，由[原生工厂](../../packages/bili_player/lib/src/native_player_properties.dart)在媒体加载前应用，一次创建后跨源保持。没有替换个人原生资产或 SDK 事件路由。

本项目的源／账号代次、取消和释放屏障、多标签播放许可、首帧可见性、HDR 色彩映射、Windows GPU 交接及 Apple／Android 平台生命周期修复继续适配本项目。这些职责不参与独立缓存管理或音视频时钟计算。可选响度增益、软解和 Android 直出是用户设置；没有将其替换为参考应用的设置模型。音量范围内不强加音频滤镜，音视频同步默认值已统一。不是将不同版本的两套 SDK 或 GPL 应用控制器直接互换。

## 验证

- `tool/test-windows-http-audio.ps1` 原生两组测试通过：旧路径稳定复现失声；生产工厂的 lavf 路径经历六次真实 HTTP 截断后，正确续读并保持音频时钟。测试未注入 SDK 错误或播放器状态。
- 原生策略／EDL 测试通过，验证暂停加载、DASH 双轨、请求头、中文本地路径、源复用、直播／点播切换和倍速往返；音频缓冲与滤镜保持原生默认。
- 根检查各阶段通过：格式、静态分析与打包边界通过；根应用 5783 项、bili_api 1035 项、bili_player 243 项、bili_danmaku 161 项、bili_mux 15 项通过。根应用 13 项 Windows 符号链接用例跳过；播放器普通检查的 4 项原生 opt-in 用例另行执行。已配置 Windows bili_mux.dll 和 ffprobe，15 项封装测试包含实际原生执行，不将配置跳过算作通过。
- Windows 媒体脚本的普通播放、重播、后端契约、诊断、起播取消、视频就绪、仅音频、系统媒体键、停帧日志、预览、响度、静音视频、正常 DASH EOF、历史续播、缓存窗口、预读／欠载、缓存内 seek 与连续 seek 条目均完成。连续 seek 9 项通过，保留原生 playlist entry，旧目标等待取消后由原连接供数并确认最新位置。普通预览恢复断言从旧 120 秒改为现行 16 秒；欠载检查允许 lavf 在同 URL 上续读，仍要求只解析一次、不换源／CDN。
- PGC DASH、直播 HLS／FLV、音频品质与直播解码日志／明确网络错误重试回归通过。补充读取器对照：响应正常、只有媒体包长时间空缺时保持连接恢复；HTTP 完全无字节超过 5 秒读超时时，两套实际 libmpv 都在同一位置报告原生 EOF。该边界另有用例，不再将“任何长度的 socket 断供都必须保持原连接”作为 PiliPlus 行为。没有为 EOF 添加应用自动重试。
- Windows 实际 WASAPI／libmpv 输出的隔离 Debug 验证中，3× 音频时钟与位置连续推进；热重载和热重启成功，未发现运行时错误。测试入口未读取真实账号与数据库，音量为零。
- Windows x64 Release 构建通过。原现场进程后续已退出，将完整修复 bundle 替换到 `build/windows/x64/runner/Release/`；旧目录保留为 `build/windows/x64/runner/Release.before-audio-parity-20261117/`。新 `data/app.so` SHA-256 为 `14aeaca22369d4bb2eda887cb1bf18d760dcba628b0d1bbe1c325a2d997fcaa5`，libmpv 摘要仍为固定资产的 `8fa6af29a94623d7d1e16bc6db48668f321e3fc9f1eaa86a8df8d61ec57f00e3`。
- Android arm64 普通入口开发 Release 构建及身份校验通过：`dev.bilisail.bilisail.test`／`BiliSail 测试版`，1.3.0+1／13001，保留本机既有开发签名、不可调试。产物 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256 `b65d8c1b2101d1f6e0d722ce0300ba1c3a185ae37f26452defe4021c12bbf7ae`。ADB 无连接设备，未安装。
- 原生 null 输出用例验证供数、解码和时钟；Windows 验证不代表真实扬声器听感、蓝牙延迟或长期性能。Android 尚无实机结果，Apple／Linux 未构建或实机验证。

协议与行为对照独立实现；没有复制 PiliPlus GPLv3 应用源码或资源，没有修改相邻仓库、Pub 缓存及固定媒体依赖。
