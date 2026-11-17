# PiliPlus 缓冲、同步与底层播放链路复核

日期：2026-11-18（Asia/Shanghai）。在 [TLS 持续缓冲修复](windows-tls-buffering-2026-11-18.md)后，重新核对应用控制器、实际锁定的 SDK 和原生库，不把参数相同等同于二进制行为相同。

## 参考与结论

- `git ls-remote https://github.com/bggRGjQaUbCoE/PiliPlus.git HEAD` 返回 `217fb54f51f6764176319bbdedab2a7522d75401`，与相邻只读检出的提交相同。
- 参考 overrides／lockfile：核心和平台库为 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频插件为 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`。本项目仍固定个人 fork 的 `302d60eedc55ca677e911e529569b1e14d8c2e7e`，没有替换 SDK／原生资产或修改 Pub 缓存。
- 正常缓冲与同步控制路径已按参考行为实现，新复现的 Windows TLS 不完整记录无限等待由 `7989af55` 修复。本轮未发现另一套需要引入的缓存管理或音视频时钟算法。
- SDK、平台和产品契约存在差别，不能称所有源码、设置项和原生实现完全一致。下面分别列明已对齐行为与保留差异。

## 逐项复核

| 路径 | PiliPlus 依据 | 本项目结果 |
| --- | --- | --- |
| 原生同步 | `_initPlayer`、`Pref.videoSync`／`autosync` | `display-resample`；Android autosync 30，其他平台 0。音频缓冲保持原生 0.2 秒，无常驻 scaletempo2 或独立应用音频时钟 |
| DASH 分轨 | `_createVideoController` 的 EDL | 同一 mpv 时间线，`!new_stream`、`!no_chapters`，验证完整双轨。长度按 UTF-8 字节计算，兼容中文路径和签名 URL |
| HTTP 请求 | `setMediaHeader`、原生读取 | SDK 应用 UA／Referer／允许的请求头，原生负责 Range、重定向与续读，无应用代理或字节队列 |
| 点播缓存 | `initBuffer` | 前后各 4 MiB，默认 16 秒乘起播倍速，补读阈值为窗口的 2/3。变速本身只设置 speed，不清缓存 |
| 直播缓存 | `initLiveBuffer` | 前向 8 MiB，后向 0；普通直播不额外固定时长，显式预览窗口属于调用参数 |
| 离线／听视频 | FileSource 的 cache=no、仅音频选择 | 本地关闭网络缓存；听视频直接打开音轨，共用控制及恢复契约 |
| 加载与历史位置 | 暂停 open 中传 start，再 `_initializePlayer` | 同样暂停加载并在 open 中传位置，再设倍速并按意图 play；不先播放后 seek，不静音预滚 |
| play／pause／重播 | SDK `play`／`pause`，repeat 时 seek 0 | 直接 SDK 控制；普通继续不重开、不重建音轨，重播才回到 0 |
| 倍速与音调 | `setPlaybackSpeed` → SDK `setRate` | 直接 speed、原生动态音调校正，无额外暂停／seek／音频滤镜；直播保持 1× |
| 精确／连续 seek | SDK `seek absolute`、默认 hr-seek | 同样使用 absolute、hr-seek=default、hr-seek-framedrop=yes；取消旧目标只撤销等待，保留连接／缓存／playlist entry，确认最新目标 |
| 缓冲事件 | SDK core-idle／paused-for-cache／demuxer-cache-time | 同源事件更新缓冲提示与端点；UI 端点下限为当前位置，重试仍读未钳制的 SDK buffer |
| 网络重开 | 错误订阅、3 秒检查、点播 10 秒节流 | 同样识别 TCP 读取／HTTP 打开错误；点播要求仍 buffering 且 SDK buffer 整秒为 0。沿用原地址／位置／倍速／音量，不自动刷新地址或切 CDN |
| 错误路由 | SDK LOG_MESSAGE 分发 | 当前 SDK 已转发 stream 错误；实际 404 在点播／直播均归为 networkOpen。排除最初对缺少转发的怀疑，没有叠加重复日志监听 |
| 解码日志／EOF | 错误订阅无额外自动换线 | 普通解码日志只诊断，不把输入 EOF、短缓冲、满缓存 idle 升级为自动重开；提前播放结束按本项目终止失败契约显示错误 |
| HLS 分片 | SDK demuxer-lavf-o | 当前 SDK 同样包含 seg_max_retry=5、strict=experimental、allowed_extensions=ALL 和协议白名单，无需重复覆盖 |
| 原生 TCP／TLS | SDK network-timeout=5，实际原生库不同 | 保留 lavf 续读，rw_timeout=5000000 补齐当前 Windows SChannel 的外层 EAGAIN 超时；兼容项并非参考 Dart 控制器原样参数 |
| Android 解码／音频 | HwDecType.kHwdec、AudioOutput.defaultValue | Release/Profile mediacodec,auto-safe，Debug auto-safe；opensles,aaudio,audiotrack，空闲 force-window=no，不默认开启额外解码帧队列 |
| 桌面解码／输出 | 固定视频插件 NativeVideoController.create | hwdec=auto、vo=libmpv；用户显式软解保留，个人 fork 的 GPU 交接／释放屏障继续生效 |

参考：[应用控制器](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/plugin/pl_player/controller.dart)、[设置默认值](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/utils/storage_pref.dart)、[核心 SDK](https://github.com/My-Responsitories/media-kit/blob/73771ec38176be2d984a3049c28177bce23b54a0/media_kit/lib/src/player/native/player/real.dart)、[桌面视频插件](https://github.com/bggRGjQaUbCoE/media-kit/blob/85f0a69ea66b100882b27a3375c72e5155375343/media_kit_video/lib/src/video_controller/native_video_controller/real.dart)、[Android 视频插件](https://github.com/bggRGjQaUbCoE/media-kit/blob/85f0a69ea66b100882b27a3375c72e5155375343/media_kit_video/lib/src/video_controller/android_video_controller/real.dart)。

本项目入口：[原生策略](../../packages/bili_player/lib/src/native_playback_policy.dart)、[后端适配](../../packages/bili_player/lib/src/media_kit_backend.dart)、[共享状态](../../packages/bili_player/lib/src/shared_player_engine.dart)、[缓存与 EDL](../../packages/bili_player/lib/src/native_media_options.dart)、[会话重试](../../lib/features/playback/application/playback_session.dart)。

## 保留的适配差异

- PiliPlus 单例控制器与本项目多标签会话不能互换。保留每页唯一 engine、播放许可、账号／源代次、取消与释放屏障、终止错误界面及有界打开恢复，不复制全局控制器和未取消的 Timer。
- 保留暂停目标的双轨／首帧确认、普通／全屏同 owner、HDR 色调映射、Android Surface、Windows GPU 交接和 Apple 释放修复。这些确认不修改原生同步时钟，也不额外蓄水或预滚。
- 参考缓冲参数在单例控制器中首次惰性初始化；本项目按每次 open 参数计算窗口，后续变速不改变当前源窗口。保留显式预览和 OpenOptions 契约，避免继承上一个源的配置。
- 可选超分、放大音量限幅、系统音频焦点／PiP 与交互设置属于独立平台／产品能力；本轮没有将其作为缓冲／同步修复移植，不宣称平台功能完全同构。
- 按协议、配置和行为独立实现，未复制 PiliPlus GPLv3 应用源码；MIT 媒体 SDK 固定来源和个人 fork 边界保持原状。

## 验证

记录目录：`build/validation/piliplus-audit-2026-11-18/`。

- 两套实际 Windows libmpv 在统一初始化／点播缓存参数下，对同步、音调、丢帧、cache-pause、预读及解封装探测的可读取默认值独立对照，采样值相同。该实验只证明这些属性，不证明二进制所有内部实现相同。
- 增加真实 HTTP 404 用例，覆盖点播和直播的 networkOpen 分类；扩展生产工厂复用回归，读取 SDK 初始化及切源后的实际网络超时、cache-pause 默认值和 HLS 分片重试配置。3 项原生回归通过。
- HTTP／TLS 真实断流、Windows 普通播放及热重载结果见 [TLS 专项](windows-tls-buffering-2026-11-18.md)，对应生产源码本轮没有再次改变。

- `tool/check.ps1 -SkipPub` 完整通过：格式、静态分析、打包边界，根应用 5793 项、bili_api 1035 项、bili_player 243 项、bili_danmaku 161 项、bili_mux 15 项通过。根应用 13 项 Windows 环境用例、播放器普通检查 10 项原生 opt-in 跳过；受影响用例另行执行。配置实际 Windows mux DLL 与 ffprobe，15 项封装测试包含原生执行。
- 扩展后的 `tool/test-windows-http-audio.ps1` 完整通过：8 项实际 HTTP／TLS 故障及网络打开错误回归；生产工厂切源／倍速复用回归另行通过。
- `tool/test-windows-buffer.ps1` 完整通过，7 个入口共 12 项实际 Windows 回归：自然 DASH EOF、历史续播、缓存窗口、预读断供、反复欠载、缓存内 seek 与连续跳转。缓存内及连续 seek 保留原生播放源／缓存，不以重开替代跳转。
- `tool/test-windows-content.ps1` 完整通过，4 个入口共 6 项实际 Windows 回归：PGC DASH、HLS／FLV、音频品质、直播缓存和明确网络错误后的同地址恢复。测试使用本地／受控 HTTP 素材，无真实账号、未启用 Online。
- 隔离普通 Debug 双轨夹具再次热重载成功，无运行时错误，随后经原生释放完成退出；未读取用户账号和数据库。构建曾等待上一个测试进程释放 DLL，自动重试后成功，没有终止用户进程。
- 已交付的普通入口 Windows Release 与 TLS 修复的生产源码一致，本轮只补测试／脚本／复核文档，不再重建相同二进制；`data/app.so` SHA-256 仍为 `74c3f0ac088f57aa7a6e5e7d1c364064c292bde5d545134ec0ac22b71f8916e7`。
- `tool/test-windows-content.ps1` 完整通过，4 个入口共 6 项：PGC DASH、直播 HLS／FLV、音质、直播供数及明确网络错误重开。没有使用真实账号或线上写操作。
- 隔离双轨夹具再次热重载成功，无运行时错误，随后确认原生释放并关闭测试进程；普通入口 Release 的生产源码和 data/app.so 摘要仍与 TLS 修复构建相同，无需因仅增加测试／文档而替换应用。
- Android、Apple、Linux 本轮没有构建／实机结果；源码默认值对照不能替代这些平台的设备验收，Windows 受控故障回归也不代表线上长期播放或性能验收。
