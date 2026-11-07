# 两后端统一前向缓冲窗口

日期：2026-11-07。用户反馈 fvp 通常只显示约 5 秒前向缓冲，要求统一两个后端，随后明确普通播放最多 2 分钟、预览 5 秒。

## 实现

- [OpenOptions](../../packages/bili_player/lib/src/player_contract.dart) 的共享默认值与允许上限改为 2 分钟。视频、PGC、直播与听视频沿用同一契约；非法值在创建原生播放器前被拒绝。此参数不持久化到设置，无须数据库迁移。
- [fvp 原生适配器](../../packages/bili_player/lib/src/fvp_native_player.dart) 原先将 `maxBufferAhead` 硬限制为 4000ms，导致默认长窗口无法生效。现在按共享上限应用实际传入值，普通播放为 120000ms，预览继续由调用方传入 5000ms；最低预缓冲门槛保持独立，不要求等满两分钟才开播。
- media_kit 继续在装载媒体前设置并回读验证 `cache-secs` 与 `demuxer-readahead-secs`，两者随共享默认值降为 120 秒。保留既有内存配额及关闭临时磁盘缓存的策略。
- 两分钟是媒体时间上限，实际预读仍受下载速度、码率和原生内存策略影响；原生 packet、解码和 I/O 边界可有少量超出。统一时间窗口不等于两个 SDK 使用相同的内存字节配额，也不改动已有 seek 取消、停帧或音画同步屏障。

MDK 的 `setBufferRange(minMs, maxMs, drop)` 使用毫秒，最大值限制未解码 packet 的缓冲时长，较大上限不要求增加开播等待；依据固定包的公开绑定及 [MDK Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setbufferrangeint64_t-minms-int64_t-maxms-bool-drop--false)。

## 验证

[常规窗口原生回归](../../integration_test/windows_buffer_ahead_test.dart) 对 media_kit／fvp 使用相同的 12 分钟低码率 DASH、HTTP Range、零音量和窗口断言，检查初始、暂停、播放推进、400 秒窗口外 seek 及短视频重新打开。

[预览原生回归](../../integration_test/windows_preview_buffer_test.dart) 也对两个后端执行同一组 5 秒窗口断言，检查随进度补充、seek 后窗口和随后普通打开的配置恢复。会话测试确认普通视频／PGC／直播默认 2 分钟，两个引擎的边界测试拒绝 2 分钟加 1 微秒，已有悬停编排断言仍为 5 秒。

检查日志位于忽略目录 `build/validation/unified-buffer-*.log`。Windows 本地 HTTP 验证不替代真实 CDN、Android／macOS 设备、长时间内存与人工音画验收；Debug 功能回归不作为性能结论。

本轮结果：

- 两后端的 2 分钟窗口原生用例均通过。media_kit 初始／暂停／推进／seek 后分别为 120.208／120.208／120.208／120.125 秒，fvp 四阶段均为 120.021 秒，均在 500ms 的分包／解码边界容差内。
- 两后端的预览原生用例均通过。media_kit 初始／推进／seek 后分别为 5.083／4.916／5.208 秒，fvp 为 5.208／5.125／5.125 秒；普通重开后两个后端都缓存至约 59.875 秒，预览窗口未污染普通播放。
- 普通视频／PGC／直播默认值三项定向会话测试通过；根脚本 PackageTests 阶段通过：API 678、播放器 212、弹幕 161、mux 5 项。未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过，不计为通过。
- 根脚本首轮格式与静态分析通过，根测试为 4563 项通过、13 项按原条件跳过、9 项失败；该轮运行期间用户将目标由 5 分钟改为 2 分钟，三个默认值测试编译缓存仍引用旧值，重新启动测试后上述三项均通过。另有同期状态栏／播放面板修改对应的六项 UI 断言失败，以当前工作区重跑相关组七项全部通过；未把首轮记为整次全量通过，也未修改这些同期 UI 文件。
- 首次 2 分钟原生构建在 Flutter assemble 阶段返回 MSB8066，尚未进入用例；保留日志，详细模式重试后两项均通过，随后两个预览用例也通过。
- `tool/test-windows-fvp.ps1` 十二项既有分轨／音频／直播／连续 seek 回归完整通过；最终对受影响播放器源码、测试和会话做定向静态分析，无问题。Windows Debug 本地 DASH 入口热重载成功，无运行时错误，随后等待 native 释放并退出。
- 普通入口 `flutter build windows --release --no-pub -t lib/main.dart` 构建通过（57.1 秒）；完整目录为 `build/windows/x64/runner/Release/`。AOT `data/app.so` SHA-256 为 `c02c5bbd43472b3d9e8f11440effba108663cea9cd23e4c9bfdc41e906ea040a`。这是当前工作区构建，包含构建当时同期的状态栏／播放面板修改；本次只提交缓冲相关文件，未发布安装包。
