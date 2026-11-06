# Android 倍速切换掉帧：定位与优化候选

日期：2026-11-06。承接 [H.264 4K60 双倍速与长按实测](android-4k60-h264-2x-hold-2026-11-06.md)。按用户后续要求，本轮只完成代码分析、离线回归与构建，**没有重新安装或采样手机**。下文旧实测归因和新候选代码分开记录；没有优化后的实机性能数字。

后续已按用户要求完成 [20 场、160 次长按的实机因素对照](android-rate-switch-device-2026-11-06.md)：时钟平滑减少松手掉帧，视口限制降低 GPU 压力，仍存在提交间隔及音画同步未验项。本文保留先前离线阶段的记录；设备效果以该后续报告为准，视口候选仍默认关闭。

## 先区分两种掉帧

原采样每场同时存在按住、松手和正常播放。只看场景累计掉帧，会把持续 2x 的吞吐限制与恢复 1x 时的突发掉帧混在一起。新增[归因工具](../../tool/validation/analyze_android_rate_switches.py)，按应用收到的原生 DOWN／UP 单调时间，划分“按住期间”和“松手后 500ms”；后一窗口在下一次 DOWN 前截止，防止重复计数。计数仍是 mpv `frame-drop-count`，不冒充显示器逐帧检测。

[归因数据](data/android-rate-switch-attribution-2026-11-06.json)：

| 场景 | 按住期间掉帧 | 松手后 500ms 掉帧 | 总数 | 松手窗口占比 |
| --- | ---: | ---: | ---: | ---: |
| 普通长按，隐藏叠加 | 148 | 220 | 368 | 59.8% |
| 快速反复，隐藏叠加 | 0 | 388 | 388 | 100.0% |
| 普通长按，弹幕＋控件 | 156 | 237 | 393 | 60.3% |
| 快速反复，弹幕＋控件 | 1 | 417 | 418 | 99.8% |
| 按住约 18 秒，隐藏叠加 | 537 | 32 | 569 | 5.6% |
| 按住约 18 秒，弹幕＋控件 | 538 | 37 | 575 | 6.4% |

这六场的窗口外剩余掉帧均为 0。快速场景几乎完全是**恢复 1x 后的突发追赶**；长时间按住则以**2x 持续供帧／输出限制**为主。不能用单一“长按导致重建”解释所有现象。

对旧 logcat 按正式采样起止时间过滤：六场均没有新创建视频解码组件，AudioTrack 也没有 flush／pause／stop。Dart 会话的长按入口只通过有代次隔离的速率命令队列调用 `setRate`，没有主动 seek 或重开源。因此现有证据不支持把它归因于每次手势重新初始化解码器。

## 恢复 1x：音频时钟衔接是首要待验证原因

当前固定 media-kit 核心在 `PlayerConfiguration.pitch=false` 时，`setRate` 最终写入 mpv 的 `speed`；不会每次替换 `af`。应用已在打开前安装 `scaletempo2`、将 `audio-buffer` 请求值设置为 0.05 并回读验证。核心注释仍写着 Android 使用 OpenSL ES，但当前初始化代码没有设置 `ao=opensles`；**不能拿旧注释判定实际 AO**。

旧 APK 中 libmpv 的版本串为 `mpv v0.41.0-dirty`。对应上游 [v0.41.0 音频时钟实现](https://github.com/mpv-player/mpv/blob/v0.41.0/player/audio.c)使用“已写音频的末尾 PTS，减去当前音频倍速乘以 AO 延迟”推算正在播放的音频 PTS。恢复 1x 后，队列中尚存旧倍速音频，而用于延迟换算的倍速已改变，可以产生瞬态时钟偏移；视频同步会追赶新的音频时钟。这与松手附近 0.48–0.55 秒 `avsync` 峰值、随后集中丢弃约几十帧的时序一致。

**这是源码机制支持的强候选，尚未完成实际 AO／队列延迟的因果 A/B。** `-dirty` 版本串不能给出精确二进制源码提交；现有探针也没有记录 `current-ao`、原生 `speed` 和独立音／视频 PTS，不能宣称已经证实是某个 AO 或 scaletempo2 参数的单点缺陷。

旧 Android 日志的 AudioTrack 创建请求为 48000Hz、7200 帧，算术上对应 150ms 的请求队列。上游 [AudioTrack 输出实现](https://github.com/mpv-player/mpv/blob/v0.41.0/audio/out/ao_audiotrack.c)自行选择约 75–150ms 的设备缓冲和写入块。该日志不是实测扬声器延迟，也不能单独证明选中了 mpv 的 audiotrack AO；但足以说明 `audio-buffer=0.05` 的回读不能当成设备端只有 50ms 排队的证据。[mpv 对 audio-buffer 的说明](https://mpv.io/manual/master/#options-audio-buffer)同样将其定义为最小缓冲，设备可以采用更大的值。

另外，`MediaKitEngine.setRate` 使用了乐观快照；此前“松手后约 5–49ms 恢复”描述的是应用状态，不是 mpv 实际速率或扬声器完成转换。新增观测读取原生 `speed`、`audio-pts`、`video-pts`，并保留开始／结束读取的单调时间。汇总工具在全部样本都有原生速率时才用它计算延迟；旧数据明确标注 `snapshot-optimistic`，不补造原生确认。

## 持续 2x：减少不必要的 4K 中间渲染目标

旧固定 2x 完整面板样本中，30 秒约 89fps、930 个输出掉帧、解码掉帧 0。raster P95 约 11.7ms，`eglSwapBuffers` 与 `QueuePresentKHR` 大量时间处于提交／等待；前者约提交 2672 次，与约 89fps 相近。这里仍要保留设备调频和运行顺序的混杂，不能把所有差额定量归给某个 shader。

确定的额外工作是：Android 的输出纹理一直跟随 3840×2160 解码尺寸，而实际横屏只有 2400×1080、16:9 视频占 1920×1080。4K 解码本身需要保留；两次渲染／合成之间不必持续传递 4K 的中间图像。

新增[尺寸策略与串行器](../../packages/bili_player/lib/src/android_video_viewport.dart)，并接入[输出适配器](../../packages/bili_player/lib/src/media_kit_video_output.dart)：

- 根据实际物理视口和已保留的 paintScale 计算输出尺寸，保持宽高比、不放大小源；该场景目标为 1920×1080，像素数为原来的 25%。**这是像素规模变化，不是已测得 75% 性能提升。**
- 仍解码原始 4K，不改清晰度、硬解选择、用户倍速或随屏幕运行的弹幕 Ticker。缩放手势预留相应像素，最多回到源尺寸；旋转后的显示尺寸、方形／竖屏源单独覆盖。
- 固定 Android 插件的 `setSize` 不支持 Android，且其 videoParams 回调会恢复解码尺寸。因此不能只改一次 SurfaceTexture 大小。应用在该回调完成 rect 通知后重新协调 SurfaceTexture 与 `android-surface-size`，回读验证后者；原生值已正确时跳过，防止重入循环。
- 串行化异步 resize，覆盖未开始的旧布局；源替换、输出 owner 变更与释放会使旧请求失效，写原生属性前再次检查 binding。失败传给当前调用方，后续请求可以重试，不让失败的 Future 毒化整个队列。
- Dolby Vision 的专用输出尺寸保留原路径；暂停首帧、旋转／全屏、缩放视觉和平台释放仍须实机验收。

候选通过 `MediaKitEngine(experimentalAndroidViewport: true)` 或 `--dart-define=BILISAIL_ANDROID_VIEWPORT=true` 启用，默认 **false**。这是本轮尚无设备验收的原生呈现候选；普通构建不默认切换。探针支持按场景设置 `viewport: true/false`，同一 APK 即可对照，避免换包造成额外变量。

## 已完成的离线验证

- 新增 15 项 Dart 测试，覆盖 4K→1080p、低分辨率不放大、竖屏／方形、缩放预留、非法布局、异步旧请求覆盖、源失效、失败重试与插件重置后的恢复。定向输出相关测试 29 项通过。
- 归因工具新增 4 项测试，覆盖松手／按住拆分、窗口不重叠、缺少 UP、计数重置及原生速率可用性；加上既有 HTTP 测试共 7 项通过。
- `tool/check.ps1 -SkipPub` 通过：根应用 4423、API 659、播放器 163、弹幕 161、mux 5，共 **5411 项**。根应用 13 项、mux 原生 10 项按环境跳过；未配置 `BILI_MUX_LIBRARY`，不算 mux 原生通过。
- 最终 Dart 格式／静态分析、Python 编译和 `git diff --check` 通过。Windows 空白离线探针执行实际热重载成功、无运行时错误，随后关闭；它不播放媒体，也不用于 Android 性能或呈现验收。
- 普通入口 Android arm64 开发 Release 与专项 Profile/AOT 都构建通过，身份和原开发签名核对通过。没有安装到手机，手机仍保留上一轮恢复的普通测试版。

已准备 `build/development/android-arm64/BiliSail-test-arm64-rate-optimization-profile.apk` 及 `.sha256`／`.json`，普通 Release 在同目录默认文件名下。专项 Profile SHA-256 为 `f8c4f50fcff9d74c042966d621cacde4a3b64b2ff6e749cfe773415f3837668c`，本轮版本为 1.2.6／12607。

## 后续设备验证入口

[ABBA 配置](data/android-rate-viewport-abba-scenarios-2026-11-06.json)在同一 APK 中交错关闭／开启／开启／关闭候选，覆盖固定 2x、快速长按、快速长按＋弹幕控件。应在充电和运行状态可对齐的条件下执行；保持相同 H.264 源、音轨、屏幕及弹幕设置，记录实际 AO、原生速率和两条时钟。不能将本文旧数据当作该候选的效果。

使用本轮已准备的包时，必须先更新运行器的两个保留文件，不能误用上一轮旧探针：

```powershell
Copy-Item build/validation/android-rate-optimization/ordinary-release.apk build/validation/android-4k60/ordinary-release.apk
Copy-Item build/development/android-arm64/BiliSail-test-arm64-rate-optimization-profile.apk build/validation/android-4k60/probe-profile.apk
./tool/test-android-4k60.ps1 -DeviceId <adb-id> -ConfigPath docs/validation/data/android-rate-viewport-abba-scenarios-2026-11-06.json -Label <fresh-label> -UsePreparedApks
```

也可去掉 `-UsePreparedApks`，让运行器重建当前源码对应的普通 Release 和专项 Profile。结果必须包含 `nativeOutput`，切换延迟口径须为 `rateLatencyBasis: native-speed`；缺少这些观测或纹理尺寸没有实际改变，不能接受为候选有效的 A/B。

若视口缩小后持续 2x 接近目标而松手尖峰仍在，就可以进一步将时钟衔接与渲染压力隔离。此时再依据实际 AO、原生速率和 PTS 变化设计音频输出／缓冲对照；不能靠关闭同步、忽略掉帧计数、松手 seek 或改变用户倍速制造“改善”。候选开启前还须补跑首帧／暂停打开、自动／软件解码、旋转、全屏、缩放、SDR 色彩及关闭重开。其他平台没有新增验收结论。
