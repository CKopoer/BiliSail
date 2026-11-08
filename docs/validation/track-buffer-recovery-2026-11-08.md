# 分轨缓冲续读与共同缓冲进度

日期：2026-11-08（Asia/Shanghai）。

**历史记录：已由[播放控制流程简化](player-control-simplification-2026-11-08.md)替代。** 当前源码已移除本文的代理、字节缓存与 MP4 索引，改用原生缓存；下列结果仅对应当时实现，历史源码链接固定到移除前提交。

后续修正：本文保留首次实现的历史结果；“缓存淘汰／未知索引导致缓冲条停在当前位置”及 fvp 片尾快速 seek 的状态，以[缓冲显示与连续跳转修复](buffer-display-rapid-seek-2026-11-08.md)为准。

## 现有保护与本轮目标

现有 `NativePlaybackHealth` 并非只在播放越过缓存终点时触发：它同时检测单轨时钟／解码活动停滞和总进度冻结。不过，这些检测针对播放受损，最终会暂停整组并交给会话重开，不能提前修复尚未耗尽的网络缓存。

本轮将 HTTP(S) DASH 分轨的网络读取交给两个后端共用的 [DashTrackBuffer](https://github.com/CKopoer/BiliSail/blob/b328741134a3582cb723bd6679d5e9e1d5c73826/packages/bili_player/lib/src/dash_track_buffer.dart)。网络卡住时只续读该轨，保留原播放器、已解码数据、源代次、播放位置和用户意图。正常缓冲满后停止读取是背压，不是故障；播放中的网络读恢复不发布 opening、seek 或通用错误提示。

## 实现与边界

- `SharedPlayerEngine` 在源校验后为真实 media_kit／fvp 后端创建当前源独占的 loopback HTTP 入口。原始 CDN URL 与已有允许的媒体请求头仅保存在内存；原生播放器读取随机能力路径，不能向入口指定任意上游地址。仅绑定 IPv4 loopback，最多 8 个活动读取，关闭／替换源同时关闭服务和上游请求，资源释放等待同一完成屏障。播放器状态仍只有共享引擎一个所有者。
- 每个在途分块独立读取，2 秒没有上游数据时从下一缺失字节发起 Range 请求，单次故障最多续读 3 次，并有 10 秒恢复预算。下载与原生 socket 的背压分离：原生暂时不读时，已发出的有限分块仍可完成续读；不会将本地输出等待当成上游超时。请求块按名义码率选择 256 KiB–4 MiB，仅用码率选择 I/O 大小，不据此计算缓冲时间。SDK 仍控制 2 分钟前向窗口。
- 校验 206、Content-Range 的起止与总长、实体长度、可用的 ETag／Last-Modified；恢复携带 If-Range，忽略 Range 的 200 响应、实体改变、认证失败和错误区间不能拼接成成功数据。只对有限的读超时、连接异常和暂时 HTTP 错误重试，不执行账户写操作。保留系统 TLS 校验，最多 5 次重定向，不允许 HTTPS 降为 HTTP。错误日志不转发签名地址或响应头。
- 源拥有的视频字节缓存最多 32 MiB，音频按标称码率与窗口选择 8–32 MiB 的上限，按需占用、不写磁盘，避免高码率音轨过早淘汰普通 8 MiB 配额外的数据。每轨最多保留 2 MiB 索引前缀，MP4 表项有数量上限，索引解析在临时 isolate 中完成。支持直接 `sidx` v0／v1，以及单轨 MP4 的 `stco`／`co64`、`stsc`、`stsz`、`stts` 与单项非空 edit；完整连续的分段／chunk 才能扩展可用时域，不能跨过缺失字节或 seek 产生的空洞。
- 缓冲条使用 `min(音频连续缓存终点, 视频连续缓存终点, 原生缓冲终点)`，且不回退到当前播放位置之前。原生终点继续作为包缓存与原有窗口的上界。两轨字节缓存是可立即供给播放器的内存数据，不等于两轨都已解码；内存淘汰后不假定 SDK 仍保留被淘汰数据，因此这是可核实的共同范围，可能低估 SDK 自有缓存。索引缺失、过大、多轨或复杂 edit／分层索引不估算时间，缓冲条保守停在当前位置，实际播放及续读仍继续。缓冲端点的更新不改播放位置；原有视频越界健康检查仍使用原生视频端点，不能误用更短的音频显示端点。
- fvp 保留既有临时音频解码探针与缓冲配置，探针读取的字节可由当前源缓存复用。自定义测试端口保持原有注入行为。
- 这是 HTTP DASH 的加载恢复。直播／单一容器／纯音频／本地媒体沿用原生路径；不凭下载停滞推断解码器挂死。缓存已耗尽、实体失效、SDK／输出管线失效或续读预算耗尽时，仍须按既有规则等待数据或暂停并恢复整组，不能保证任何故障都完全无感。

架构依据：mpv 的 `demuxer-cache-state` 在多 demuxer 时仅描述主 demuxer，不能当成外部音轨缓存；MDK 当前绑定的 `buffered()`／外部轨挂载同样没有提供完整的每轨无扰恢复契约。见 [mpv 官方手册](https://mpv.io/manual/stable/#command-interface-demuxer-cache-state)与 [MDK Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。本轮未修改 SDK、依赖版本、Pub 缓存、设置或数据库。

## 验证

- [传输测试](https://github.com/CKopoer/BiliSail/blob/b328741134a3582cb723bd6679d5e9e1d5c73826/packages/bili_player/test/dash_track_buffer_test.dart)：双向单轨停滞、逐字节续读、另一轨不重连、公共最短端点、原生上界、内存淘汰、重复读命中、有限重试、错误 Range／实体变更及关闭期间的资源屏障。
- [MP4 索引测试](https://github.com/CKopoer/BiliSail/blob/b328741134a3582cb723bd6679d5e9e1d5c73826/packages/bili_player/test/mp4_buffer_index_test.dart)：两种 sidx、普通 MP4、截断／畸形索引、完整分段及连续范围。
- [共享引擎测试](../../packages/bili_player/test/shared_player_engine_test.dart)：事件和定时采样均采用共同缓冲，不改变当前进度或重复准备播放器；保留原起播、seek、暂停、释放和故障测试。
- [Windows 原生专项](https://github.com/CKopoer/BiliSail/blob/b328741134a3582cb723bd6679d5e9e1d5c73826/integration_test/windows_track_buffer_recovery_test.dart)：两个后端分别在已打开后阻塞音频／视频 HTTP 响应，要求准确续读、进度单调、同一 generation、无 opening／额外 seek／失败，并确认缓冲继续增长。fvp 音频先显式跳至未缓存的 400 秒，按索引只阻塞该新位置的实际请求，排除临时探针的旧读取。`tool/test-windows-buffer.ps1` 生成素材并运行原有窗口和新增恢复用例，也由完整媒体回归调用；已生成素材时可设置 `BILI_TEST_BUFFER_DIR` 指向 `build/validation/player-buffer-fixtures/` 单独运行。

原生播放器的缓存读取速度现在测量本地入口吞吐，不能当作 CDN 下载速度；原有“缓存速度不是总网速”的 UI 说明继续适用。原始 HTTP 失败的数字状态码通过脱敏回调保留，避免本地网关状态覆盖真实的 403 等诊断，原始地址和响应头不进入事件。

本机结果：

- 根应用测试 4726 项通过，13 项沿用符号链接权限条件跳过；四包分别为 API 719、播放器最终 341、弹幕 161、mux 5 项通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。最终格式、静态分析、PowerShell 解析、420 个文档相对链接及 `git diff --check` 通过。
- 根脚本首轮完成打包边界与格式，静态分析发现两处新增测试 lint，修复后定向分析通过。第二轮在现有 macOS 冒烟监督夹具清理处出现 PowerShell 空引用，随后独立复跑 22 项监督检查通过；根测试与四包检查分别通过脚本相应阶段完成，不将前两轮记为单次全量成功。
- Windows 的普通／多窗播放 8、重播 6、共享后端契约 4、脱敏 HTTP 诊断 1、起播 9、首帧 6、听视频 7、系统媒体 1、中途停滞 9、media_kit seek 9、预览 2、音量均衡 2、明确无音轨 2、fvp 中途双轨中断 4、fvp 后端 3、fvp seek 同步 9 项通过。在线／交互环境限定用例未启用。原先连续 seek 夹具只处理 Range 起点，已补齐结束字节；最初的 HTTP 403 诊断缺失也已修复并原生复验通过。
- 两后端前向窗口 2 项与分轨续读 4 项最终通过。窗口用原生统计单独验证 119–120.5 秒范围，同时断言界面共同缓存为正、未超过原生窗口；例如 fvp 初始共同缓存约 85 秒，而主视频窗口为 120.021 秒，后续播放和 400 秒 seek 仍保持窗口上限。窗口测试发现并修复“缺口刚好邻接已缓存尾部”时的空块循环，新增 HTTP 回归验证区间在准确的结束字节终止。原生释放／渲染队列／尺寸 C++ 回归 9 项通过。
- 临时双后端 Debug HTTP 入口经 DTD 热重载成功，无运行时错误；完成两个播放器与 HTTP 服务释放后以 0 退出。入口位于忽略目录 `.dart_tool/dash_track_hot_reload_20261108.dart`，没有替换普通入口或操作账号。
- fvp 片尾快速 seek 的自动播放用例仍失败，暂停用例通过。恢复原有音频探针窗口后仍能复现；使用当前 HEAD `b92157b37d790a8869ea88e85b3352b4128a1f01` 的原 `SharedPlayerEngine`／`FvpEngine` 在忽略目录隔离对照，同一用例亦失败（回到 2 秒的误差为 583ms），当前实现则报 `PlayerFailure`。两次表现不同，尚未证明同根因，也不能将该项记为通过；没有为此扩大修改 seek 状态机。对照材料与日志保存在 `integration_test/.dart_tool/dash_buffer_baseline/` 和 `build/validation/dash-buffer-eof-*.log`。

Android 普通入口开发 Release 已按 `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 构建，复用未改动的 arm64 mux 组件。身份为 `dev.bilisail.bilisail.test`／“BiliSail 测试版”，版本 `1.2.8+5`、不可调试、沿用原开发证书；APK、摘要与身份元信息位于 `build/development/android-arm64/`。最终 APK SHA-256 为 `7e24d547e236571698439c04400b59984d836e1dcfcd51d49d5b5923a2500257`。没有安装、复制账号或改动设备设置。

本轮不包含真实 CDN、人工扬声器／耳机音画同步、性能或长时间内存测试；Android 的实际播放及前后台／隔离进程链路、macOS／iOS／Linux 设备均未验证。原始日志位于忽略目录 `build/validation/dash-buffer-*.log`。
