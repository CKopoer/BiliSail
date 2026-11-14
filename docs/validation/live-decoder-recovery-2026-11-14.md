# 直播解码错误恢复与脱敏诊断

日期：2026-11-14（Asia/Shanghai）。用户在 Windows Release 观看主播 UID `8739477`（直播间 `545068`）时反复缓冲，重新打开后恢复。本次修复恢复入口与提示归因，不把当时异常流的具体来源视为已经查明。

## 原因与修复

现场约 17:25–17:26 有 127 条 `ffmpeg/video` error、11 条音频解码 warning。固定 media-kit `302d60eedc55ca677e911e529569b1e14d8c2e7e` 只把部分前缀转入 error stream，不包含 `ffmpeg/video`；应用此前依赖 error stream 启动停滞检查，因此这些视频错误没有启动自动重试。原有检查还会在进度重新推进后清除等待，无法单独覆盖反复短时卡顿。

共享适配器现在将视频解码 error/fatal 同时送入已有停滞检查。正常进展可以消除单次错误的等待；持续无进展沿用非 buffering 2 秒、buffering 30 秒的原有截止时间，避免遇到可恢复坏帧就换源。

此外增加有界的重复缓冲判断：30 秒内至少 3 次伴随视频错误的 buffering，扣除确认媒体进度后累计停滞至少 6 秒，报告反复解码缓冲。单次停滞至少 1 秒才计入，最多保存 8 个片段。连续正常播放 10 秒、暂停、seek、源代次改变时清除证据。无视频错误的网络等待、仅 buffering 标志跳动但媒体进度正常推进的情况，不会触发该判断。

两种检测都只报告到现有 `PlayerFailure` / `PlaybackSession` 链，由会话重新解析地址并按既有规则使用备用线路；保留最多 3 次原生打开总额度、音量和最新播放许可。直播重新打开直播边缘，不沿用点播 seek。没有另开播放器、额外重试层或无限重试。

共享提示改为“播放缓冲中…”，保留 300ms 显示门槛；准备和恢复提示保持独立。固定依赖会把 [mpv `core-idle`](https://mpv.io/manual/stable/#properties-core-idle) 与 `paused-for-cache` 都映射成 buffering，前者不能当作网络故障诊断。

## 脱敏日志

沿用设置页导出的本地滚动日志，不新增遥测、上传或数据库字段。

- 每个引擎分配仅本次进程有效的 `playerId`，与 generation 一起标识实例。记录通用源类别（DASH、预览、直播 manifest/progressive），不记录业务 ID 或媒体地址。
- 增加固定错误子类：NAL/码流、缺少参考帧、损坏包、时间戳、分片读取、提前读取结束、音画不同步、硬解建议、解码失败。未知仍为 unknown；含有 `hwdec` 的建议不再直接当作硬解失败。
- 缓冲超过 300ms 记录开始、结束、时长。就绪、错误突发和持续缓冲的有限时点记录：播放核心空闲、实际缓存暂停、缓存读取/EOF、前向缓存字节、读速率、估计缓存时长、原生 `time-pos`、音频 PTS、A/V 差、丢帧和实际硬解/编码。
- 使用实际存在的 `time-pos`，不把它说成独立的视频输出帧时间；锁定 mpv [属性表](https://github.com/CKopoer/mpv/blob/afd6da8843a07f463ba4c736a2ea636b1a92e23e/player/command.c#L4346)没有旧式 `video-pts`。原生时间和缓存值只能结合错误与暂停原因解释。
- 没有常驻逐帧采样。错误采样至少间隔 2 秒，一次固定读取 13 个属性，每项最多等待 400ms，共享单个在途批次；原生读取超过 Dart 截止时间后，仍阻止新批次积压。换源、暂停/seek 状态改变或释放后的迟到结果被丢弃。
- 文本只转为固定枚举或允许的 codec/硬解名称；结构化属性仅提取固定数值/布尔字段，缺失保持未知。没有原始错误文本、URL/query、header、Cookie、Token、账号或聊天内容。沿用文件轮转、写队列和丢弃计数上限。

缓存终点与时长是估计，不能单凭“仍有几秒缓存”认定每条轨道都有完整、可解码的数据。

## 回归入口与验证

- `native_video_buffer_monitor_test.dart`、`shared_player_engine_test.dart`：错误信号与失败链、正常推进、重复短停顿、纯网络等待、窗口/次数边界以及暂停/seek/代次隔离。
- `native_buffering_diagnostics_test.dart`、`player_diagnostic_event_test.dart` 与根日志测试：固定允许字段、敏感文本排除、读取截止、在途批次上限、迟到结果及缓冲脉冲。
- 新增 `integration_test/native_live_decoder_recovery_test.dart` 并接入 `tool/test-windows-content.ps1`：本地 FLV 前段正常，后段破坏 AVC NAL 长度，保留 AAC/FLV tag 边界，并保持坏连接不结束。真实 SDK 必须产生 `ffmpeg/video` error，会话自行重新解析健康地址、恢复音视频；验证失败次数、解析次数和 HTTP 请求数有界。无真实账号；测试 query 中的合成敏感值必须从日志排除。
- `native_live_buffer_test.dart` 新增实际缓存暂停和日志边界断言，确保正常网络长停顿与短补数仍等待原连接。

本轮首次 Windows 原生坏流回归通过：384 条视频错误，1 次失败、2 次总解析，坏流/健康流各 1 次 HTTP 请求，自动重开后音视频推进，耗时约 36.8 秒。该素材实际进入缓存暂停，因此沿用 30 秒等待边界后恢复；这不是自动重开的固定耗时承诺。

最终验证：

- `tool/check.ps1 -SkipPub` 通过打包边界、格式、根应用/四个包分析及 **6867** 项离线测试：根应用 5468、bili_api 935、bili_player 298、bili_danmaku 161、bili_mux 5。13 项符号链接权限用例、3 项未配置原生媒体环境的播放器用例、10 项未配置 `BILI_MUX_LIBRARY` 的 mux 用例跳过，不计为原生通过。日志 `build/validation/live-buffering-2026-11-14/full-check.log`。
- 最终代码的 Windows 原生坏流用例再次通过：384 条错误，1 次失败，2 次解析，坏/好流各 1 次 HTTP 请求，约 37.0 秒内自动重开后恢复推进。日志 `final-native_live_decoder_recovery_test.log`，脱敏播放日志位于同目录的 `native-recovery/`。
- 正常直播弱网回归通过：4229ms 等待 9 秒保持不变，短补数不恢复，补齐后推进至 6063ms，只有 1 次 HTTP 请求、0 次失败。共享 UGC/PGC/HLS/FLV 播放 2 项和原生 HTTP 403 脱敏诊断 1 项通过。日志为 `native-buffer.log`、`final-windows_content_playback_test.log`、`final-windows_playback_diagnostics_test.log`。
- 基于本任务隔离源码快照的 Windows 普通入口 Release 构建通过，入口为 `build/validation/live-buffering-2026-11-14/release-source/build/windows/x64/runner/Release/bilisail.exe`，使用时保留完整 Release 目录。8 个本任务应用/播放器源码与当前文件逐项哈希一致，产物与源码核对写入 `release-manifest.json`。构建首次缺少 NuGet 路径，复用现有 `.dart_tool/native-tools/nuget.exe` 后通过；保留现有第三方插件 CMake/C++ 警告，没有改插件缓存。该快照未纳入后续其他任务的评论编辑变更。
- 新文档相对链接与 `git diff --check` 通过；未改依赖或锁文件。
- 使用无账号/无网络请求的加载提示预览启动 Windows Debug，DTD 热重载成功，运行时错误查询为空；预览不替代原生播放回归。

Windows 验证使用本机受控媒体，没有将 545068 当时相同的异常 CDN 分片留存重放，因此不能宣称查明或修复了直播源自身的缺陷。Android、Apple、Linux 未构建或实机验收；本次没有性能结论。
