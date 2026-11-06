# 长按倍速：官网调用链、音频时钟与回切追帧

日期：2026-11-06。承接 [50ms 输出缓冲优化](hold-rate-output-buffer-2026-11-01.md)和 [Android 倍速归因](android-rate-switch-optimization-2026-11-06.md)。本轮保留工作区已有的 Android 视口实验；该实验仍默认关闭。

本文记录官网与 Windows 机制对照阶段。后续已完成 [Android H.264 4K60 实机复测](android-rate-switch-device-2026-11-06.md)，包含同一 APK 的时钟平滑／视口因素对照及 160 次长按；文末“Android 未连接”仅指本文阶段。

## 官网实际实现

本轮以独立、无账号的 Edge 浏览器打开[公开视频](https://www.bilibili.com/video/BV1xx411c7mD/)，读取当天实际加载的官方脚本，随后对真实方向键长按记录原生媒体属性 setter 与媒体事件。没有使用用户脚本代替官网实现，没有导入官网源码。

- 核心脚本：[core.1782590f.js](https://s1.hdslb.com/bfs/static/player/main/core.1782590f.js)。`setPlaybackRate` 将值限制在 0.25–4，设置当前同一媒体元素的 `playbackRate` 和 `defaultPlaybackRate`。
- 手势／快捷键脚本：[npd.911.8ae98c84.js](https://s1.hdslb.com/bfs/static/player/main/widgets/npd.911.8ae98c84.js)。右方向键首次 DOWN 启动 300ms 定时器；`setThreePlayrateHint(true)` 保存原速率并应用临时速率，UP 时恢复原值。所见样本是 1x→3x→1x；其他实验分组可选择不同临时速率。默认阈值和倍速不应视为全站永久不变的规定。
- 实际事件：DOWN 后 301.2ms 调用 3x setter、301.8ms 收到 `ratechange`；UP 附近恢复 1x，约 4ms 后收到事件。切换窗口没有 `pause`、`waiting`、`seeking` 或 `emptied`。恢复 setter 的捕获监听比本探针的冒泡 UP 监听早 0.2ms，不能据此声称在物理松手前恢复。

这证明官网在本次受控动作中复用原媒体元素、直接切速，不以暂停／seek／换源实现长按。事件和 setter 完成不等于声音已从扬声器按新速率输出，也没有用不同素材的网页和本机数据计算性能提升比例。

## 不同实现的关键差异

Exa 共检索 30 个结果（含重复），按官网、原生时钟、其他后端三个方向筛选一手源码与维护者说明；还直接读取官网脚本和本地固定依赖。

| 实现 | 切速路径与时钟 | 对本项目的意义 |
| --- | --- | --- |
| B 站 Web／Chromium | 同一 `<video>` 改速；Chromium 的 `AudioClock` 为待播音频段记录各自速率，按实际出队累计媒体时长 | 平滑的关键在音频队列的时间换算，网页的一行 setter 不能直接说明原生后端同样无停顿 |
| 当前 media-kit／mpv | `PlayerConfiguration.pitch=false` 时写 `speed`；本项目已常驻 `scaletempo2`，长按时不重写滤镜 | 不支持“每次长按重建音频滤镜或视频解码器”的归因 |
| PiliPlus | 跳过同速率调用，开始／恢复直接调用 `setRate`；Android 默认 `autosync=30`，其他平台默认 0；默认同步策略另为 `display-resample` | 可以参考音频时钟平滑；不能将两项配置混为同一机制，或称已完成 PiliPlus 整个应用的性能 A/B |
| Android Media3 | 音频处理链按播放参数衔接并换算媒体／输出时长；还可使用设备的 PlaybackParams | 官方说明设备参数路径延迟较低，但可靠性、可用速率依设备而变；更换后端不是无需验证的一行修复 |

Chromium 一手来源：[AudioClock](https://chromium.googlesource.com/chromium/src/media/+/refs/heads/main/filters/audio_clock.cc)、[AudioRendererImpl](https://chromium.googlesource.com/chromium/src/media/+/refs/heads/main/renderers/audio_renderer_impl.cc)。其队列以音频帧数和该段的有效速率累计媒体时间，且专门处理 WSOLA 目标速率与实际处理速率的小偏差。这与给整个旧队列统一乘新速率存在实质区别。

本地 PiliPlus 只读核对提交 `265f879fa85973b4bf885bde2562f1007f1013b8` 的 `lib/plugin/pl_player/controller.dart`、`lib/utils/storage_pref.dart`。协议／交互职责参考，没有复制 GPLv3 应用实现或修改相邻仓库。media-kit 核心仍固定 `73771ec38176be2d984a3049c28177bce23b54a0`，本轮不更新依赖或二进制。

Media3 来源：[DefaultAudioSink.Builder](https://developer.android.com/reference/androidx/media3/exoplayer/audio/DefaultAudioSink.Builder)、[SonicAudioProcessor](https://developer.android.com/reference/androidx/media3/common/audio/SonicAudioProcessor)。文档能力不作为本项目已支持 Media3 的证明。

## 本项目卡顿在哪里

`PlaybackShortcutController` → `PlaybackSession` 的有界命令泵 → `MediaKitEngine.setRate` 已有去重、快速松手恢复、永久／临时速率隔离与源代次检查。触摸和键盘走同一会话，未发现本轮需要重写的应用层等待或重复开源。手势阈值是开始前的识别时间，不能解释松手后的画面追帧。

项目[默认识别时间](../../lib/features/settings/domain/shortcut_settings.dart)是 400ms，本次官网样本为 300ms；识别期间应继续按原速播放，和速率切换后的停帧是两回事。本轮保留用户已有阈值与 2x 默认临时速率，不用缩短识别时间冒充播放连续性改善。

mpv [v0.41.0 音频时钟](https://github.com/mpv-player/mpv/blob/v0.41.0/player/audio.c)在 `playing_audio_pts` 中用已提交音频的结束 PTS 减去“当前速率 × AO 延迟”。设备队列尚含旧速率音频时，速率改变可能导致临时音频时钟偏移；视频会等待或丢弃落后帧。Android 既有实测的快速长按掉帧集中在松手后，与此机制相符，但不能将其当作已在手机上完成因果 A/B。

[audio-buffer](https://mpv.io/manual/stable/#options-audio-buffer)是最小输出队列请求，设备可以采用更大的缓冲；回读 0.05 不能证明实际设备只排队 50ms。`audio-pts` 也仍是 mpv 估计，不能冒充独立扬声器测量。当前 Windows libmpv 的属性表不含 `video-pts`，所以本轮探针明确用 `time-pos` 作为位置连续性代理，不将其命名为独立视频 PTS。

持续 4K60 若要在 2x 保留每帧，需要达到 120fps 的解码和输出；显示刷新率不足时的必要丢帧也不能直接算作异常卡顿。这是吞吐／显示能力问题，与每次松手后短暂追帧分别处理。本轮不默认启用已有的 Android 视口实验，也不调低用户画质或弹幕刷新率。

## 优化及取舍

[configureNativeRateAudio](../../packages/bili_player/lib/src/native_rate_audio.dart)在有音轨的点播打开前，保留 `audio-buffer=0.05` 和 `af=scaletempo2`，新增经回读确认的 `autosync=30`。mpv [视频调度源码](https://github.com/mpv-player/mpv/blob/v0.41.0/player/video.c)的 `update_avsync_before_frame` 将 AO 报告值与基于已播放时间的预测作平均，降低时钟突变触发的一次性回切追帧。30 是平均因子，不是 30ms 延迟、30fps 或速率渐变。

三项配置共用原打开 deadline，源失效、超时或原生静默拒绝均不能继续发布成功。配置沿用原范围：有音轨点播、离线和听视频；直播、无声 DASH、静音视频预览不变。调速过程仍只写一次目标 `speed`，不增加定时调速、暂停、seek 或滤镜重建。

生产路径只在打开时增加一次属性写入和一次回读，没有新增 Dart 逐帧轮询、全局状态刷新或速率渐变任务。密集原生属性采样仅存在于显式运行的验证探针。

这不是 Chromium 那种逐段音频时钟修复，也不能清空声卡中的旧速率音频。因此目标是减少回切突发掉帧，**不声称完全消除升速等待、音频物理延迟或短时 A/V 偏差**。平滑可能使误差以多帧缓慢收敛，测量同时保留 A/V 峰值及窗口末尾值，不能只看掉帧总数。

上游还注明该平均逻辑依赖调度调用频率，因而本机的收敛毫秒数不能外推为 Android 60／120Hz 或其他后端的固定保证。

没有采用以下候选：

- 把 `scaletempo2` 搜索窗口从 40ms 改为 20ms。上游[默认参数的依据](https://github.com/mpv-player/mpv/pull/12580)说明较短窗口会损害低频匹配；不能用合成正弦音轨的低延迟数字代替音乐音质验收。
- 把最小输出缓冲继续压至 20ms，或强制改用 OpenSL ES。前者可能增加欠载；后者另有驱动缓冲与蓝牙兼容性，不是无条件的低延迟路径，参见[上游 OpenSL 缓冲讨论](https://github.com/mpv-player/mpv/pull/5628)。
- 关闭音调校正、关闭 A/V 同步、改播放位置掩盖掉帧，或重写速率滤镜。它们会改变播放语义或引入音质／同步问题。

上游 [scaletempo2 历史修复](https://github.com/mpv-player/mpv/pull/12052)已处理其内部 PTS 累积等问题，不能不核对版本就把 2023 年缺陷当作当前唯一原因。

## 测量与自动验证

同一 Flutter Profile 二进制、本地 320×180／24fps H.264 与 48kHz AAC 正弦分轨，音量 0 但实际解码并经过 WASAPI。每场预热 1 秒，三次 1x→2x→1x，每个切换窗口采样 750ms。实际 libmpv 为 `v0.41.0-1150-g88eb9f2e7`，硬解回读 `d3d11va`，`video-sync=audio`，音调校正为 yes；本轮没有跨显卡／声卡推论。

在其余本轮自动检查结束后，单独串行进行最终 ABBA，避免把前一轮与静态分析同时运行的探索数字用作最终性能结论。[汇总数据](data/hold-rate-clock-smoothing-2026-11-06.json)保留各次切换、环境与边界；原始位置轨迹位于本地 `build/validation/hold-rate-flutter-20261106-autosync-final.json`。计数在发送命令**前**读取，包含异步 setter 完成期间发生的掉帧，并验证各窗口增量之和等于全场增量。

| 请求队列／顺序 | autosync | 升速最大位置间隔 ms | 松手／全场新增显示掉帧 | 最大 A/V 差 ms | 750ms 窗口末尾最大绝对 A/V 差 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 50ms A1 | 0 | 61.94 | 3／3 | 61.66 | 1.90 |
| 50ms B1 | 30 | 67.80 | 0／0 | 79.71 | 2.41 |
| 50ms B2 | 30 | 62.89 | 0／0 | 84.27 | 3.10 |
| 50ms A2 | 0 | 64.65 | 3／3 | 58.68 | 1.70 |
| 150ms A1 | 0 | 119.75 | 10／10 | 157.36 | 2.65 |
| 150ms B1 | 30 | 120.70 | 0／0 | 193.79 | 2.20 |
| 150ms B2 | 30 | 123.55 | 0／0 | 190.00 | 2.64 |
| 150ms A2 | 0 | 121.37 | 12／12 | 176.37 | 2.52 |

8 场解码掉帧均为 0，原生速率采样均匹配当次目标。**明确的改善是松手后的突发显示掉帧消失；没有升速最大位置间隔改善。** 50ms 的 B 场误差超过 40ms 的最后样本在切换后约 119–126ms，150ms 的 B 场约 157–161ms；A 场主要通过瞬间丢帧收敛。这是以短暂、渐进的同步修正换取视频连续性的取舍，不能只展示掉帧为 0 而隐藏更高的瞬态 A/V 峰值。它也不证明音频没有爆音、真实屏幕零丢帧或 Android 已改善。

- 根检查脚本分别执行 `-SkipPub -Stage Lint`、`RootTests`、`PackageTests`，均通过。根应用 **4502**、API **672**、播放器 **170**、弹幕 **161**、mux **5**，共 **5510 项通过**；根应用 13 项按环境跳过，mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不能算作原生封装通过。
- 速率音频配置专项现有 24 项通过，本轮新增 7 项覆盖原生拒绝平滑配置及新增异步边界的源替换。保留全部准备步骤共用 deadline、迟到写入不能继续、音量／增益／网络缓存不被修改等断言。最终 `flutter analyze --no-pub packages/bili_player` 通过。
- `tool/test-windows-media.ps1` 完整通过 **32 项**，另有 1 项交互桌面用例按开关跳过；`tool/test-windows-content.ps1` 通过 **4 项**，覆盖 PGC、音质切换和直播弱网恢复。均为本地分轨／HTTP fixture，没有启用 Online 或真实账号流程。
- 启动本地 Debug 空白 surface 入口，连接 DTD 后执行实际热重载成功，随后查询无运行时错误并退出。它仅验证工具连接／重载，不播放媒体、不计入性能或 Android 验收；真实播放由上述 36 项原生用例覆盖。
- `flutter build windows --release -t lib/main.dart` 通过，恢复普通应用入口 `build/windows/x64/runner/Release/bilisail.exe`。AOT 文件、原生组件和许可文件齐全；最终 `libmpv-2.dll` SHA-256 仍为固定的 `222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`，没有混入插件旧 DLL。运行／分发须保留整个 Release 目录。
- `tool/build-android-development.ps1 -Mode Release` 通过，包含 arm64 mux 重建、AOT、不可调试、包名／名称／版本与原开发签名检查。普通入口 APK 为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，身份 `dev.bilisail.bilisail.test`／`BiliSail 测试版`，版本 1.2.6／12607；SHA-256 为 `4fc0f636312fcb5ce68ab72fd584b667be25acc9a74a145e33493fd2973c12e5`。没有安装到设备或操作应用数据。
- 根检查、原生回归及构建日志保存在本地 `build/validation/hold-rate-*.log`。新增文档相对链接、数据汇总一致性及 `git diff --check` 通过。最初 Windows 构建遇到本地原生归档缓存、NuGet PATH 和生成缓存的安装前缀问题，补齐已验证缓存／工具路径并将生成前缀恢复到工作区 bundle 后重跑成功；没有修改第三方源码或关闭来源／哈希验证。

复现入口为 [rate_transition_probe.dart](../../packages/bili_player/tool/rate_transition_probe.dart)。`BILI_RATE_EXPERIMENT=autosync` 在同一 Profile 二进制内依次比较 50ms／150ms 输出队列的 0→30→30→0 平均因子；150ms 只是机制对照，不代表 Android AO。`buffer` 保留原 200／50ms 实验；`search` 保留 40／20ms 的已拒绝候选。原生 `speed`、AO、pitch correction、A/V 差、每个切换窗口的掉帧增量和 `audio-pts` 均留在报告中，快照的乐观 rate 不用于原生确认。

Android 未连接设备；macOS／iOS／Linux、蓝牙及 USB 声卡、多声道／高采样率、真实对白和音乐听感仍需对应设备验收。Windows 自动回归也不能替代这些验收。
