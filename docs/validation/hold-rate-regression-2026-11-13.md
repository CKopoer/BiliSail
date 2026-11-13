# 长按与松开倍速回归修复

日期：2026-11-13（Asia/Shanghai）。基线：最新 `origin/master` 的 `9d4a450d`。

## 原因

仓库没有 `v1.2.9+0` 标签；以版本提交 `b3e8cf16`（`pubspec.yaml` 为 `1.2.9+0`）对比。后续 `eb40c399` 将播放器改为 EDL 双轨、SDK 事件与跨源复用时，删除了 `configureNativeRateAudio` 及其回归测试，生产路径恢复后端默认音频策略。临时倍速的会话／手势入口没有相应行为变化，最新共享状态机仍直接下发倍速。

删除的配置分别影响两个方向：

- `audio-buffer=0.05` 限制按旧速度处理的待输出音频。恢复默认较大队列会增加加速时的视频等待；它与网络预读缓存不同。
- 常驻 `af=scaletempo2` 避免跨 1x 时自动插入／移除变速滤镜，保持音调校正。
- `autosync=30`、`video-sync=audio` 平滑输出音频时钟的修正，减少松开恢复时的视频追赶和突发丢帧。

机制与历史设备证据见[输出缓冲记录](hold-rate-output-buffer-2026-11-01.md)、[时钟平滑对照](hold-rate-web-native-2026-11-06.md)和[Android 设备归因](android-rate-switch-device-2026-11-06.md)。这些历史测量不代表本次工作区已完成设备验收。

## 适配当前实现

[NativeRateAudio](../../packages/bili_player/lib/src/native_rate_audio.dart) 由 [MediaKitBackend](../../packages/bili_player/lib/src/media_kit_backend.dart) 持有，与原生播放器同寿命。每次 `preparePaused` 在打开媒体、开始解码之前应用有声点播策略；手势按下／松开仍只调速，不修改滤镜、不 seek、不暂停或重开媒体。

首次应用前保存后端实际的四项默认值。同一实例复用到有声视频／影视／离线／听视频时重新应用；切到直播、静音 DASH 或无声预览时恢复首次默认值，而非把前一源的点播策略当成默认。首次就是直播／静音源时不写入音频策略。保留 EDL、SDK 事件、原生实例复用、解码选择、网络预读、用户音量及独立增益。

每项写入后回读验证，接受数值标准化，拒绝 SDK 静默丢弃的属性写入。原值读取、应用和恢复共享打开剩余 deadline，异步边界检查源代次、取消及实例身份，超时后迟到的操作不能继续写后续属性。显式诊断 `experimentalAudioAutosync` 也通过同一回读流程。

## 验证与边界

使用 Flutter 3.47.6／Dart 3.13.5，五份锁文件严格解析且未修改。新增 26 项配置回归覆盖默认策略恢复、反复换源、属性拒绝、数值标准化、逐步取消与超时迟到操作。新增 2 项可选原生回归使用仓库锁定 media-kit、本地分轨和 Debian libmpv 0.40.0：一项直接经过生产后端的 `preparePaused`／`resetForNextSource`，验证同一实例在点播→点播→直播→点播时正确应用／恢复策略并实际解码音频；另一项验证 EDL 双轨解码、连续调速及滤镜和音调校正保持。既有原生 EDL 用例也已启用通过。

另在工作区外的隔离副本仅删除生产后端的配置调用，新增生产路径用例按预期失败：请求值应为 `0.05`，实际回读 `0.2`。修复路径通过，避免仅测试辅助类而漏掉调用接线。日志为本地 `build/validation/hold-rate-negative-control.log` 与 `hold-rate-native-backend-tests.log`。

原生专项可从 `packages/bili_player` 复跑：

```sh
BILI_TEST_NATIVE_MPV=/path/to/libmpv.so.2 \
BILI_TEST_MEDIA_DIR=/path/to/test/fixtures/media \
flutter test --no-pub test/native_rate_audio_playback_test.dart test/native_edl_playback_test.dart
```

Linux headless 使用空音视频输出，只验证原生状态、解码和复用契约。补充独立 libmpv ABBA 探针在默认策略的两轮恢复阶段分别统计到 20／21 个显示掉帧，恢复策略的两轮均为 0；但空 AO 的模拟队列不等于 `audio-buffer` 请求值，加速等待仍可复现，不能由此宣称真实设备已零停顿／零掉帧，也不能将时钟平滑理解为消除了输出延迟。该诊断日志与数据仅保存在本地 `build/validation/hold-rate-null-abba.json`。

根应用通过 `tool/check.ps1 -SkipPub -Stage RootTests`：5,277 项通过，6 项按条件跳过。四个包分别为 `bili_api` 917、`bili_player` 241（包含已启用的 3 项原生用例）、`bili_danmaku` 161、`bili_mux` 5 项通过，共计 6,601 项通过；mux 的 10 项原生用例未配置 `BILI_MUX_LIBRARY`，按条件跳过。最终日志为本地 `build/validation/hold-rate-root-tests.log`、`hold-rate-bili_player-final.log` 与其余各包的 `hold-rate-*.log`。

根检查入口在未修改的 `tool/test-macos-release-validation.ps1:320` 因 `The independent parent failed to terminate a stalled worker and its child.` 失败，与既有[换源复用记录](player-source-reuse-2026-11-12.md)中的 Linux 环境阻塞相同。随后按入口分别执行其余检查，不将总入口标为通过。全库格式（1,135 个文件）、根分析／Linux 适配器分析及最终播放器包分析通过；剩余打包边界脚本已分别运行，iOS 的 2 项 Swift 原生测试因缺少 `swiftc` 按条件跳过。

已尝试 `flutter build linux --release`，CMake 因缺少 `gtk+-3.0` 开发库失败，未生成本次 Release 产物。本机没有 Windows／Apple 构建工具链或连接的移动设备。实际声卡、Flutter 纹理合成、蓝牙输出和 Windows／Android／Apple 设备的按下／松开流畅度仍待实机验收；上述离线测试和空输出诊断不代替这些结论。
