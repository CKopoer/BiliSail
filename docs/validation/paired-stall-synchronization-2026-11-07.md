# 单轨中断后的两秒同步与恢复

日期：2026-11-07。

## 问题与行为

首次 fvp 断音修复虽然接上了自动重试，8 秒无音频帧阈值仍会让画面单独前进太久。media_kit 原有独立音频时钟和视频缓存边界能较快发现部分分轨提前结束，但低速播放、原生 buffering 标志与实际轨道活动不一致时，仍缺统一的墙钟截止时间。

现行约定：需要的音频或视频不再推进而另一轨仍推进时，在最多约 2 秒内暂停同一实例的音视频，进入现有会话恢复。这个阈值按单调墙钟计算，不随 0.25／4／8 倍速拉长。明确的提前结束可立即触发。正常原生 buffering 已同步暂停双轨时继续等待补充缓存，连续 30 秒无进展才重载，不因本次缩短而频繁重开网络源。

## 实现边界

- [NativeTrackHealth](../../packages/bili_player/lib/src/native_track_health.dart) 统一判断两条必需轨道的活动，使用 250ms 样本，预留两次采样／调度间隔。内部无进展窗口为 1.5 秒，使原生缓存样本和下一轮调度仍能落在约 2 秒上限内。缓存存在不等于画面推进；buffering 标志也不能掩盖另一轨仍在播放。双轨已停住时才保留正常 refill 等待。
- [NativePlaybackHealth](../../packages/bili_player/lib/src/native_playback_health.dart) 包装轨道检测并保留总时钟、media_kit 外部音频时钟、视频缓存边界和 30 秒 buffering 预算。非 buffering 总时钟静默冻结的阈值也由 8 秒改为 2 秒。
- media_kit 使用当前 source generation 的异步音频时钟缓存与播放进度，原有音频落后和视频越过缓存边界的快速检测继续保留。fvp 使用实际原生解码音频帧计数与主视频进度。采样和故障分类共享，平台采集留在各自适配器。
- fvp 主视频在完整时长之前报告 `ended` 时，必须判为提前中断。此时 MDK 主状态可能已停止而外部音频尚存，仅调用普通 `pause` 会被旧结束状态过滤；现在通过 `interrupt` 清空媒体并停止整个 native 实例，再交给恢复重开。正常片尾及其重播保持原语义。
- 两后端均发出原有 `PlayerFailure`，由 [PlaybackSession](../../lib/features/playback/application/playback_session.dart) 统一处理备用线路／重解析。既有最多 3 次 native open、最多 2 次解析、35 秒原生准备预算和后续 1 秒退避继续生效。没有新增一层重试；暂停、seek、换源、关闭和账号变化仍撤销旧恢复，离线文件不自动网络重试。
- 单音轨／无音频预览只检查所需轨道，静音及解码出的静默 PCM 仍算活动；源代次、seek、用户暂停和正常片尾清理旧判断。

## 验证

验证日志位于独立工作区忽略目录 `build/validation/paired-*.log`。

- [共享状态测试](../../packages/bili_player/test/native_track_health_test.dart)覆盖双向中断、错误 buffering 标志、正常同步 buffering／恢复、低速／高速／时钟抖动、静音、单轨媒体、暂停／seek／换源与正常片尾。
- [Windows fvp 受控回归](../../integration_test/windows_fvp_audio_recovery_test.dart)构造带完整 30 秒时长元数据的截断音频／截断视频，各自验证故障后两轨实际停止，以及真实 PlaybackSession 重解析、断点重开、恢复实际音频帧。视频提前结束在约 5.5 秒立即中断，音频先断通过共享截止时间中断。
- [Windows media_kit 回归](../../integration_test/windows_video_stall_test.dart)验证双向提前结束、异常帧尺寸、缓存充足的静默冻结与自动恢复、短时视频缺数据后同步继续。同步 buffering 等待仍可超过 2 秒，单边播放不会借用 30 秒 refill 预算。
- 根检查按阶段完成：格式、静态分析和打包边界通过，根应用 4635、API 696、播放器 275、弹幕 161、mux 5，共 **5772 项通过**。首次播放器全量测试发现原生错误监视器的旧 8 秒测试在新的 2 秒截止后重新报错而留下计时器；更新该测试以验证 2 秒内重复错误不会延长期限后，`tool/check.ps1 -SkipPub -Stage PackageTests` 全部通过。13 项符号链接测试因本机权限跳过，10 项 mux 原生测试因未设置 `BILI_MUX_LIBRARY` 跳过，不计为通过。
- `tool/test-windows-fvp.ps1` 的 **16 项**通过（双向提前结束及自动恢复 4、后端／分轨／直播 3、seek 同步和暂停意图 9）。最终音频先断在无音频帧 1500／1749ms 时触发，视频先断在约 5500ms 立即触发。故障后原生计数停止、自动分支重解析恢复实际出帧均有断言。
- media_kit 的 `windows_video_stall_test.dart` **9 项**通过；缓存充足静默冻结在约 2014／2015ms 检出，正常视频短时缺数据后同步继续。`tool/test-windows-video-dispose.ps1` **9 项**通过。
- 普通入口 Windows Release 构建通过，独立 fvp Debug fixture 热重载成功且无运行时错误，随后等待 engine 释放并退出；没有替换已安装的旧应用。不同工作区的同期测试数量不累计。
- 文档相对链接检查和 `git diff --check` 通过。验证在基于 `d081154` 的独立工作区加本补丁和同期后端源码快照执行，不将主工作区其他未提交变更视为已通过本轮全量检查。
- 合入主工作区后，`tool/check.ps1 -SkipPub -Stage Lint` 和播放器 **278 项**测试再次通过，329 条文档相对链接有效；保留同期后端提交及其他任务改动。本轮同步修复按用户后续要求不提交，仍保留为工作区修改。

## 验证限制

Windows 原生测试使用本地脱敏媒体、零音量和受控截断，不代替真实 CDN 长播放或扬声器可听验收。音频帧存在不能证明系统混音器或输出设备实际发声。设备性能及 Android／Apple 双向故障验收仍须实测，不由公开接口存在推断跨平台通过。
