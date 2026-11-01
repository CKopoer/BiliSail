# BiliSail 与 PiliPlus 播放音量对照调查

日期：2026-11-01。范围：当前源码、依赖锁文件及离线定向测试；没有构建应用、操作设备、请求在线账号接口或比较实际听感。

## 结论

**未发现 BiliSail 在默认设置下额外衰减音量的可证实问题，不能据此认定它正常播放必然比 PiliPlus 小。** 两者默认传给原生播放器的音量均为 `100`，音量均衡均默认关闭。BiliSail 的百分比直接传给 media-kit，再写入 mpv 的 `volume`，没有重复除以 100、固定减半或默认负增益。

已经确认的差异是音量控件的含义、可选放大范围、记忆值和默认音轨偏好。这些差异可以造成不同的输出条件；它们不等同于在同一音频源、同一原生音量和同一系统音量下存在解码衰减。本调查没有修改音频策略、提高上限、添加滤镜或覆盖用户配置。

## 来源与固定版本

| 项目 | 本轮核对的快照和入口 |
| --- | --- |
| BiliSail | 调查起点 `78e452a`；[根清单](../../pubspec.yaml)、[根锁文件](../../pubspec.lock)、[播放器包清单](../../packages/bili_player/pubspec.yaml)、[播放器包锁文件](../../packages/bili_player/pubspec.lock) |
| BiliSail media-kit | 根 override、包清单及两份锁文件均固定 `Predidit/media-kit` 的 `83b7ca63772856e1ea0158916177e136f7b7b0be`；核对了 `.dart_tool/package_config.json` 实际解析到的只读源码 |
| PiliPlus | 相邻仓库 `936072449e82e3d90c28c728c0087bf5136fa441`，调查时工作区干净；[清单](../../../PiliPlus/pubspec.yaml)、[锁文件](../../../PiliPlus/pubspec.lock) |
| PiliPlus media-kit 核心和原生库插件 | 清单中的 `native` 是浮动 ref；本轮依据锁文件的 `My-Responsitories/media-kit` 精确提交 `73771ec38176be2d984a3049c28177bce23b54a0` 只读检查 Git 对象 |
| PiliPlus media-kit 视频插件 | 锁文件为 `bggRGjQaUbCoE/media-kit` 的 `fd8421d21eade4d6d12de137fa7df902fec20292`；不把视频插件提交当成核心音量实现的提交 |

相邻 `media-kit` 工作区 HEAD 是 `63b7ea7dd95fc348cecf250df5f54ff87d69d8a9`，本轮没有将它当作 BiliSail 当前依赖或 PiliPlus 锁定核心。PiliPlus 本地没有 `.dart_tool/package_config.json`，所以关于它的结论针对上述源码和锁定依赖，不能代替用户已安装 APK 的版本与运行配置。

PiliPlus 应用为 GPLv3，media-kit 源码为 MIT，分别处理。本轮只记录行为、参数和来源，没有复制 PiliPlus 应用实现或资源，没有修改相邻仓库、Pub 缓存、依赖或原生二进制。

## 音量与恢复链路

| 对照项 | BiliSail | PiliPlus |
| --- | --- | --- |
| 未配置的初始音量 | `AppSettings.defaultVolume = 100`；设置读取和非法值回退一致 | 桌面 `Pref.desktopVolume = 1.0`，初始化乘 100；移动端独立 `Pref.playerVolume = 100` |
| 播放页显示值 | 桌面、移动端都是播放器音量 0–100% | 桌面是播放器音量；Android/iOS 播放页读取、监听和调整系统音量 |
| 原生映射 | `MediaKitEngine.open` 和 `setVolume` 原值传给 `Player.setVolume` | 桌面控件的 0–1 值乘 100；移动端 mpv 初值取独立的播放器音量设置，播放页手势经 `FlutterVolumeController` 调系统音量 |
| 放大范围 | 会话快捷键、控件、引擎限制为 0–100，不默认放大 | 桌面控件默认最高 200%；移动端额外“播放器音量”设置允许 100–300%，默认 100%；是否被用户启用及原生实际应用值仍需运行时核对 |
| 记忆与新源 | 同次运行内继承最近成功的手动选择；全局记忆默认关闭，开启后跨运行恢复；已有源恢复或换清晰度保留自己的音量 | 桌面调整后写入 `desktopVolume`；移动端系统音量及独立持久化 `playerVolume` 分别参与 |

BiliSail 入口：[设置默认值与校验](../../lib/features/settings/domain/app_settings.dart)、[设置读写](../../lib/features/settings/data/sqlite_settings_repository.dart)、[PlaybackVolumeMemory.volumeFor](../../lib/features/playback/application/playback_volume_memory.dart)、[PlaybackSession 的打开与音量命令](../../lib/features/playback/application/playback_session.dart)、[音量手势](../../lib/features/playback/presentation/player_swipe_controls.dart)、[引擎](../../packages/bili_player/lib/src/media_kit_engine.dart)。控件直接显示快照百分比，手势先换成 0–1 的交互值，提交时乘回 100，没有再次缩小原生值。全局记忆的完整规则见[既有记录](session-playback-rate.md#全局音量记忆2026-10-27)。

PiliPlus 入口：[PlPlayerController 的 `volume`、`_initPlayer`、`setVolume`](../../../PiliPlus/lib/plugin/pl_player/controller.dart)、[移动端系统音量监听](../../../PiliPlus/lib/plugin/pl_player/view/view.dart)、[默认值](../../../PiliPlus/lib/utils/storage_pref.dart)、[额外音量设置范围](../../../PiliPlus/lib/pages/setting/models/play_settings.dart)。两个锁定 media-kit 核心的 `media_kit/lib/src/player/native/player/real.dart` 中，`setVolume` 都将值写入 mpv 的 `volume`，没有应用侧隐藏比例。

因此，手机上只把两边播放页都调成“50%”不能视为同音量对照。例如系统媒体音量已为 50% 时，BiliSail 播放器再设 50% 会增加播放器内的衰减；PiliPlus 播放页显示的 50% 本身就是系统音量，其独立播放器设置仍可能是 100%。这是已确认的控制对象差异，不能仅凭界面数字相同判定输出异常。反之，将 BiliSail 播放器设为 100%，并将 PiliPlus 的独立播放器音量设为 100%，才对齐这一级控制。

## 均衡、音轨与系统输出

| 对照项 | 源码事实及含义 |
| --- | --- |
| 默认均衡 | BiliSail `AudioNormalizationMode.off`、PiliPlus `Pref.audioNormalization = '0'`，默认都不施加均衡；获取响度元数据不等于已经应用增益 |
| BiliSail 的非默认均衡 | [AudioLoudness.gainDb](../../lib/domain/audio_normalization.dart) 按接口目标响度减测量响度计算固定 dB 增益；“高动态”可能降低音量，“标准”也不是只增不减。直播、离线源和无合法元数据源为 0 dB。引擎经独立 [NativeAudioGain](../../packages/bili_player/lib/src/native_audio_gain.dart) 设置并读回 `replaygain=no`、`replaygain-fallback`，不修改用户百分比 |
| PiliPlus 的非默认均衡 | [AudioNormalizationMixin](../../../PiliPlus/lib/models/common/audio_normalization.dart) 仅在 Android 开启；对有独立音轨的打开链路添加 `lavfi-complex`，可用 `dynaudnorm`、`loudnorm` 或自定义参数。算法与 BiliSail 的两种目标响度模式不同，不能按名称视为等价 |
| 倍速处理 | 本轮检查时的工作区包含点播预置 `af=scaletempo2` 的同期倍速改动，用于音高处理并避免跨 1x 时插拔滤镜；没有将该滤镜当成音量放大或衰减配置。该实现不在本任务提交内，最终构建的实际输出仍需统一 A/B 验收 |
| 默认音轨 | BiliSail [音质设置](../../lib/features/settings/domain/app_settings.dart) 默认 AAC 192K，[选轨](../../lib/features/playback/data/dash_media_selection.dart) 按偏好及回退序列选轨；PiliPlus `Pref.defaultAudioQa` 默认为 Hi-Res/30251，由[视频控制器](../../../PiliPlus/lib/pages/video/controller.dart)按可用轨道回退。相同视频并不保证选中相同音轨；码率高低本身不能证明响度高低 |
| Android 输出 | BiliSail 固定 media-kit 核心在物理设备默认 `ao=opensles`；PiliPlus 将 [Pref.audioOutput](../../../PiliPlus/lib/utils/storage_pref.dart) 注入初始化，默认候选顺序为 [opensles、aaudio、audiotrack](../../../PiliPlus/lib/plugin/pl_player/models/audio_output_type.dart)。未发现 BiliSail 应用层另设持续降音量的输出参数；不能从默认候选推定设备最终输出完全相同 |
| 媒体流与焦点 | BiliSail 的[系统媒体控制适配](../../lib/core/platform/audio_service_media_controls.dart)不做音量缩放；锁定 `audio_service` 0.18.19 的 Android 本地媒体会话使用 `STREAM_MUSIC`。PiliPlus 的[音频会话处理](../../../PiliPlus/lib/services/audio_session.dart)配置 music session，播放时请求激活、主动暂停时让出，duck 中断会减半，结束再恢复。BiliSail 应用层没有同样的 duck 减半逻辑；这不构成它正常情况下固定更小的证据，系统中断、厂商音效和实际路由仍需设备确认 |

BiliSail 每次打开新源会创建新的 native player，非零均衡在播放前应用；后续切换均衡走独立命令。没有发现前一个源的负均衡被默认当作新源音量继承的链路。已有[均衡文档](audio-normalization.md)中的 Windows 历史原生测试只作为实现背景，本轮没有重复执行，不能将其算作本轮听感或设备验收。

## 本轮定向验证

1. 根目录执行 `flutter test --no-pub test/features/playback/player_audio_settings_test.dart test/features/playback/playback_volume_memory_test.dart test/features/playback/audio_normalization_test.dart --reporter expanded`：**7 项通过**。
2. 根目录执行下列会话筛选命令：**16 项通过**，覆盖音量继承、源恢复、静音、命令合并与竞态隔离，以及 UGC/PGC 均衡切换。
3. `packages/bili_player` 下执行 `flutter test --no-pub test/native_audio_gain_test.dart --reporter expanded`：**6 项通过**。

本机 PowerShell 经 `flutter.bat` 传含 `|` 的正则会被批处理重新解释，首次筛选命令未启动测试；改为直接调用同一 Flutter 工具快照后完成第 2 项：

```powershell
& 'C:/Users/14562/flutter/bin/cache/dart-sdk/bin/dart.exe' `
  'C:/Users/14562/flutter/bin/cache/flutter_tools.snapshot' `
  test --no-pub test/features/playback/playback_session_test.dart `
  --name 'volume|gain|normalization' --reporter expanded
```

合计 **29 项离线单元／组件测试通过**，无测试跳过。`native_audio_gain_test.dart` 使用假的属性读写端口，验证命令和读回语义，**没有加载真实 mpv 进行音频输出测试**。新增文档的 28 处相对链接目标存在，文档索引入口与 `git diff --check` 通过。本轮只有文档改动，不新增行为测试、不运行整仓 `check.ps1`、应用构建或原生集成测试；未对其他同期任务给出测试通过结论。

## 用户统一测试的 A/B 条件

先在同一设备、同一输出设备和同一系统媒体音量下顺序播放，避免两个应用并发引发音频焦点中断；桌面还需对齐系统音量混合器中各应用的音量及音效配置。使用同一视频的同一 P、同一音轨及同一时间段，先统一到 AAC 192K，倍速为 1x。两边均关闭音量均衡；BiliSail 当前播放器设为 100%，PiliPlus 桌面播放音量或移动端独立“播放器音量”均设为 100%。以实际当前值为准，避免记忆值干扰，不需要清数据或覆盖有效设置。

在这组条件下若仍有差异，记录应用／构建版本、系统媒体音量、实际原生 `volume` 与均衡增益、音轨 ID/codec/声道、最终 `ao` 和输出路由，再比较同段输出的响度与峰值。需要运行时证据才能继续判断依赖二进制、设备处理或音轨内容造成的差异；本轮没有这些测量，不能报告“已经同样响”或量化分贝差。

默认条件对齐后，可分别恢复平时的音量记忆、PiliPlus 额外放大或均衡模式，以确认差异来自哪一项配置。若差异只在 BiliSail“高动态”或 PiliPlus 的非默认放大／滤镜下出现，应先按所选策略解释，不直接归为默认播放音量缺陷。
