# fvp 缓冲条小幅回缩

日期：2026-11-09（Asia/Shanghai）。针对点播中 fvp 缓冲条偶尔向后缩一点的问题。

## 原因与复现

[MDK 的 buffered() 契约](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#int64_t-bufferedint64_t-bytes--nullptr-const)返回未解码的数据包时长，并非从呈现位置起算的精确缓存终点。解码线程会成批取包，呈现时钟随后推进；直接计算 `position + buffered()`，会在没有丢失媒体数据时出现短暂回退。

旧实现还先对音视频的剩余时长取最小值，再加视频位置。两条管线的呈现位置不完全相同，因此必须先各自换算绝对端点再取交集。

[Windows 原生回归](../../integration_test/windows_fvp_buffer_timeline_test.dart)用 720 秒的本地合成分轨素材和回环 HTTP：先提供至少 30 秒缓存，再暂停网络供给，继续播放 8 秒。旧实现的首次成功复现使用 20 秒起始缓存，32 次采样中出现 15 次回缩，幅度为 41–208ms。单纯从磁盘快速读取、持续补满两分钟缓存的对照没有复现，说明需要在测试中保留网络供给间歇。

`bufferedTimeRanges()` 要求额外启用 MDK demuxer 历史包缓存；本次没有为缓冲显示改变原生缓存策略、容量或下载行为。

## 修复边界

- [原生适配器](../../packages/bili_player/lib/src/fvp_native_player.dart)按 `min(videoPosition + videoBuffered, audioPosition + audioBuffered)` 求共同端点，再换算为主播放位置之后的时长。无外部音频仍采用单管线值；无效／空值按非负边界处理。Android worker 沿用同一生产端口和已有 IPC 字段，无新增消息或轮询。
- [fvp 显示修正](../../packages/bili_player/lib/src/fvp_buffer.dart)仅在位置未回退、未进入原生 buffering、剩余缓存大于 250ms 时，保留相差不超过 250ms 的前一显示端点。容差按媒体时间限定，连续小降幅与前一显示值比较，不能累积为无界历史最大值。更大的下降、接近耗尽及 buffering 立即显示；直播不应用此修正。
- 显示状态随 backend/source 生命周期创建，seek 开始及 interrupt 清空，暂停／继续不重用旧 seek 的证据。
- [BackendHealth](../../packages/bili_player/lib/src/playback_backend.dart)将 `displayBuffered` 与原始 `buffered` 分开。[共享层](../../packages/bili_player/lib/src/shared_player_engine.dart)只在绘制时间线时使用显示值，原有健康检测仍读取原始端点。信息面板和缓存内 seek 使用原生值，最多可能与缓冲条相差上述 250ms，不以显示值证明双轨已解码或跳转已就绪。

本次细化了[控制流程简化](player-control-simplification-2026-11-08.md)中“不保留历史最大值”的规则：仍接受原生真实缩短，仅对 fvp 的小幅队列／时钟采样差异做有界显示修正。没有更改 media_kit、原生 SDK／依赖、普通两分钟与预览五秒窗口、缓冲／恢复预算或用户播放意图。

## 验证

- 新增纯逻辑测试覆盖双轨不同起点、单轨和空队列、显示抖动、更大或累计回退、原生 buffering、接近耗尽、位置回退及重置；fvp engine 回归验证显示修正不改变原始健康样本，并在向前 seek 后清空旧端点。
- 首轮 Windows 修复后相同断流条件的 32 次采样没有回缩，8 秒播放正常推进。
- 最终 [Windows 缓冲脚本](../../tool/test-windows-buffer.ps1)以 0 退出，共 12 项原生用例通过：新增 1／2 倍速断流回归各 32 次采样均无回缩，分轨音频跳转 2 项、两后端两分钟滚动窗口 2 项、缓存内跳转 2 项、两后端播放／暂停连续跳转 4 项。使用当前生产适配器与 Windows x64 Debug 构建实际运行，没有替换 SDK 或变更依赖。
- `tool/check.ps1 -SkipPub` 首轮在根格式检查被同期动态模块 `lib/domain/dynamic_post.dart`、`lib/shared/data/dynamic_post_mapper.dart` 拦截；随后整体 `flutter analyze --no-pub` 也在同期新增 `lib/shared/ui/dynamic_content_card.dart:159` 报 `curly_braces_in_flow_control_structures`。保留这些非本任务修改，没有将整体检查记为通过。
- 独立执行根脚本 `RootTests` 和最终 `PackageTests` 均以 0 退出：根应用 4819、API 748、播放器 367、弹幕 161、mux 5 项，共 6100 项通过。根应用 13 项沿用符号链接权限条件跳过；未配置 `BILI_MUX_LIBRARY`，mux 的 10 项原生用例跳过，不计原生通过。新增 engine widget 用例首轮未在测试体结束前清理采样 Timer，已改用既有 `tester.runAsync(engine.dispose)` 释放方式，并在最终全包测试通过。
- 本次播放器与集成测试格式检查、Dart MCP 定向静态分析通过；三个文档的 361 个相对链接、缓冲脚本 PowerShell 解析及 `git diff --check` 通过。五份锁文件无变化。
- 独立 Windows Debug 本地分轨入口正常准备，经 DTD 热重载成功且无运行时错误；随后主动释放播放器并退出。该入口位于忽略目录，不作为普通应用交付入口。

日志保存在忽略目录 `build/validation/fvp-buffer-*.log`。真实 CDN、人工音画验收和长时间播放不属于受控本地媒体测试的结论；Android、macOS、iOS、Linux 尚无本轮构建／实机验证。
