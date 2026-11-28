# Apple 视频输出与 JOC 音频播放

## 视频

macOS 和 iOS 共用 BiliSail 的 media_kit 播放会话、分轨请求、缓冲、seek 和音频时钟。选中的视频轨为 Dolby Vision Profile 5、Profile 8、HDR10 或 HLG 时，Flutter 平台视图承载独立的 CAMetalLayer。mpv 的 gpu-next 和 libplacebo 通过 MoltenVK 向该层提交画面。普通 SDR 源沿用原有纹理。Apple 原生依赖包含可重建配方、源码版本、补丁和许可。[应用显示面](../../apple/AppleVideoSurface.swift) · [固定依赖及校验值](https://github.com/CKopoer/libmpv-darwin-build/releases/tag/apple-joc-spatial-audio-2026-11-28)

| 源与设备 | 接入行为 | 如何判读 |
| --- | --- | --- |
| Profile 5 | 软件 HEVC 保留逐帧 RPU，播放器完成 IPTPQc2 色彩重建 | 诊断中的 `videoOutputMatrix=dolbyvision` 配合 `videoOutput=gpu-next` |
| Profile 8 | 优先使用 RPU。没有可用 RPU 时允许有明确 BT.2020 和 PQ／HLG 标记的兼容基础层 | 仅有 PQ／HLG 说明基础层可用；做 RPU 验收时要求 `dolbyvision` |
| HDR10、HLG | 沿用解码偏好，按当前显示器输出能力映射 | 核对源、`targetTransfer` 和 `nativeHdrSurface` |
| 有 EDR 能力的屏幕 | macOS 查当前 Flutter 窗口所在屏幕；iOS 16 起查当前场景屏幕。优先输出 BT.2020/PQ | mpv 协商 PQ、原生层采用高精度 PQ 色彩空间、Metal 首帧提交呈现后才报告原生 HDR |
| SDR 屏、较早的 iOS 或 PQ 协商失败 | 尝试同一渲染器输出 BT.709/sRGB。显示面建立失败时采用纹理路径，Profile 5 需要可验证的色彩转换 | sRGB 输出时 `nativeHdrSurface=false` |

SDR 路径在带 sRGB 标记的 Metal drawable 被提交呈现后确认交接。iOS 模拟器使用该路径。真机 PQ 路径另要求窗口挂载、高精度 PQ 图层及非零呈现时间戳。

这条视频路径在播放器内解释杜比元数据，再把渲染结果交给 Apple 合成器。显示器是否进入 Dolby Vision 专有信号模式须另行观测。窗口移动或全屏切换会重新确认显示目标。显示器的 EDR 能力、当前亮度余量及画面实际高光分别验证。[Apple 对 Metal EDR 的说明](https://developer.apple.com/videos/play/wwdc2022/110565/) · [MoltenVK 交换链实现](https://github.com/KhronosGroup/MoltenVK/blob/v1.4.2/MoltenVK/MoltenVK/GPUObjects/MVKSwapchain.mm)

### 普通窗口与全屏的画面裁切

旧实现把 Metal 图层的 `bounds` 缩到播放器大小，同时把 `drawableSize` 设回片源分辨率。mpv 用后者设置绘制区域。MoltenVK 用 `bounds × contentsScale` 计算表面的自然像素尺寸，两者不一致时，libplacebo 可以按较小的表面重建交换链。此时 mpv 仍按原来的区域绘制，小窗只显示画面的一部分，扩大窗口后可见范围随之增大。[mpv 的 MoltenVK 上下文](https://github.com/mpvkit/MPVKit/blob/d9194243bdc68b87d8989376ab52aee7da6c8e0b/Sources/BuildScripts/patch/libmpv/0001-player-add-moltenvk-context.patch) · [MoltenVK 表面尺寸](https://github.com/KhronosGroup/MoltenVK/blob/v1.4.2/MoltenVK/MoltenVK/OS/CAMetalLayer%2BMoltenVK.mm) · [libplacebo 交换链](https://github.com/haasn/libplacebo/blob/v7.360.1/src/vulkan/swapchain.c)

现在 Metal 图层的本地坐标与 drawable 使用相同的片源显示尺寸。窗口布局只更新图层的中心和等比缩放，Core Animation 将完整画面合成到播放器内。播放回归在 P5、P8.4 暂停时依次切到小窗大小、整个窗口、再回到小窗，读取实际图层，检查交换链尺寸和投影后的四边。[Apple 显示层](../../apple/AppleVideoSurface.swift) · [回归入口](../../tool/validation/apple_hdr_probe.dart)

macOS Release 上，1920×1080 的 P5 从 320×180 点放大至 1024×576 点，再缩回原大小，三次 drawable 均为 1920×1080。iPhone 模拟器的 402×874 点竖屏窗口内，画面居中占约 402×226 点。两端均通过 P5、P8.4 的尺寸检查，以及 HDR10、HLG 的播放回归。运行环境使用 sRGB 输出。[macOS 记录](https://github.com/CKopoer/BiliSail/actions/runs/46012058890/job/140549795858) · [iOS 记录](https://github.com/CKopoer/BiliSail/actions/runs/46012058890/job/140549795291)

另用一段 1280×720 的 P8.4 样片对照修复前后的系统截图。样片在黑色背景的四角各有一个白块。macOS 和 iPhone 模拟器的旧版小窗都只显示局部，修复后小窗和铺满窗口都能在四个预期位置采到白块，中心保持黑色。[macOS 截图对照](https://github.com/CKopoer/BiliSail/actions/runs/46014122536/job/140557068159) · [iOS 截图对照](https://github.com/CKopoer/BiliSail/actions/runs/46017805345)

## 正式播放器的 JOC 输出

在线 DASH、离线分轨和本地 MP4／MKV 都使用现有 media_kit 会话。mpv 检查选中音轨的实际 E-AC-3 profile，将确认的 JOC 原始压缩包交给 `apple-joc` 音频输出。输出驱动从码流重建带 `dec3` 的格式描述，并确认 Apple 返回 `ec+3`。随后由 `AVSampleBufferAudioRenderer` 消费压缩样本，队列延迟反馈给 mpv 音频时钟。请求头、Range、缓存和视频仍由同一次打开操作管理。[原生输出源码](https://github.com/CKopoer/libmpv-darwin-build/blob/38c376b0885ae3a209b6a22607b6a1629980c3cf/bilisail/ao_apple_joc.m) · [播放器回归入口](../../tool/validation/apple_joc_playback.dart)

在 1×、0 dB 时自动选择 JOC 输出。音量和静音作用于系统渲染器。变速、额外增益使用 PCM，恢复设置后可以重新启用 JOC。普通 DD+、AAC 走已有解码输出。播放信息在当前音频输出为 `apple-joc` 且 Apple 渲染器进入 rendering 并收到样本后，显示「Apple 系统渲染 JOC」。耳机、扬声器及 HDMI 的最终输出取决于系统和当前路由。[Apple 音频渲染接口](https://developer.apple.com/documentation/avfoundation/avsamplebufferaudiorenderer)

### AirPods 切换固定与头部追踪（2026-11-28）

用户报告在控制中心切到「固定」或「关闭」后，JOC 播放听起来仍在追踪头部。旧版 `apple-joc` 只检查渲染状态和播放时钟。Apple 自动清空渲染队列时，时钟可以继续走，驱动仍把已经清掉的压缩包计入剩余音频。Apple 在输出配置与已排队格式不匹配时也会通知客户端重新提交样本。[Apple 自动清队列说明](https://developer.apple.com/documentation/avfoundation/avsamplebufferaudiorendererwasflushedautomaticallynotification) · [输出配置通知](https://developer.apple.com/documentation/avfoundation/avsamplebufferaudiorendereroutputconfigurationdidchangenotification) · [macOS 切换三种模式时的实机通知日志](https://github.com/iina/iina/issues/4920)

两端的 JOC 驱动按渲染器实例接收这两种通知。音频输出在与送包串行的位置清空队列，按原时间戳重新提交半秒缓冲中尚未开始播放的完整压缩包，继续使用同一播放时钟和暂停状态。iOS 也监听系统空间播放能力变化，并在应用启动时声明可提供多声道内容。固定、头部追踪和关闭都由系统控制中心选择。[原生实现](https://github.com/CKopoer/libmpv-darwin-build/blob/38c376b0885ae3a209b6a22607b6a1629980c3cf/bilisail/ao_apple_joc.m) · [Apple 空间音频接口](https://developer.apple.com/videos/play/wwdc2021/10265/)

macOS arm64 上用同一段 Dolby 样片向正式渲染器注入通知。旧版 r3 在播放中收到配置变化、暂停中收到自动清队列通知后，均未重新提交待播样本。新版两次均重新提交了原样本，暂停时渲染时钟速率保持为零，恢复后仍使用 `apple-joc`。[新旧二进制对照日志](https://github.com/CKopoer/BiliSail/actions/runs/46125231286/job/140918256864)

macOS Release 和 iPhone 模拟器使用本次发布的归档，通过在线／离线 DASH、MKV、MP4、普通 DD+ 和 48 kHz AAC 播放回归。macOS 的正常播放和延迟就绪提示两种条件下，左右声道回录均有 60/60 个时间窗匹配 PCM 参考。[macOS 播放与波形](https://github.com/CKopoer/BiliSail/actions/runs/46125266765/job/140919180908) · [iPhone 模拟器播放](https://github.com/CKopoer/BiliSail/actions/runs/46125266765/job/140919181176)

实体 AirPods 验收使用同一段带居中对白的 JOC 视频，保持设备静止，在连续播放中依次选「头部追踪 → 固定 → 关闭 → 头部追踪」并转头。固定模式下对白应随头保持居中，重新启用追踪后对白应随转头偏向屏幕方向。另在暂停时切换一次，确认恢复播放后采用新模式。两端的实际耳机听感仍待确认。[Apple 的 AirPods 模式说明](https://support.apple.com/guide/airpods/dev00eb7e0a3/web)

### macOS 的 48 kHz PCM 输出（2026-11-28）

在报告者的 M5 MacBook Air 内置扬声器上，播放 48 kHz 立体声 AAC 时，CoreAudio 为平面浮点（`floatp`）设置输入声道布局返回 `-50`。应用已获得视频帧，但必需音轨一直没有就绪。同机、同一音轨改用交错浮点（`float`）后能正常初始化。重载时的 libmpv 错误码 `-14` 也表示音频输出初始化失败。[复现与单变量对照](https://github.com/CKopoer/BiliSail/issues/183)

macOS 播放器在打开媒体前设置 `audio-format=float`，采样率和声道数继续协商。mpv 只对解码后的 PCM 应用此选项，JOC 压缩包仍交给 `apple-joc`。单个驱动初始化失败时允许 mpv 继续尝试后备输出。mpv 确认所有输出失败时，播放器结束等待并提示检查系统声音输出设备。[mpv 音频输出协商](https://github.com/mpv-player/mpv/blob/41f6a6450/player/audio.c)

Windows 上用同一段 48 kHz 双声道 AAC 和 libmpv 空输出对照，默认输出为 `floatp`，设置后为 `float`，两次均为 48 kHz 双声道。原生故障回归另行验证输出初始化失败可到达设备错误提示。本次 macOS Release 回归已确认 48 kHz 立体声 AAC 实际输出为 `coreaudio / float`。报告者的内置扬声器仍待复测。[macOS 播放日志](https://github.com/CKopoer/BiliSail/actions/runs/46125266765/job/140919180908)

## 构建与验证

| 环境 | 实际观测 |
| --- | --- |
| macOS、iOS 原生依赖 | macOS arm64、x86_64，iOS 真机 arm64，以及同一归档中的两种模拟器架构均编译链接完成。归档 SHA-256 与发布摘要一致。[构建记录](https://github.com/CKopoer/BiliSail/actions/runs/45861827586) |
| macOS 应用视频 | Release 通过实际播放器打开 Profile 5、8.4、HDR10、HLG，四种片源均运行 gpu-next，暂停、定位、继续播放和音轨检查通过。前两种的输入矩阵为 `dolbyvision`，同源 HLG 为 `bt.2020-ncl`。当前屏幕支持 sRGB，四次输出均为 SDR。[播放日志](https://github.com/CKopoer/BiliSail/actions/runs/45872185913/job/140090161070) |
| iPhone 模拟器应用视频 | 使用 iOS Runner 打开相同四段素材。四次均向 Metal 提交 sRGB 图像，P5 和 P8.4 收到 Dolby Vision 矩阵，分轨音频、暂停定位和继续播放通过。[播放日志](https://github.com/CKopoer/BiliSail/actions/runs/45872185913/job/140090160715) |
| 应用打包 | macOS [arm64](https://github.com/CKopoer/BiliSail/actions/runs/45872186024/job/140091685377)、[Intel x64](https://github.com/CKopoer/BiliSail/actions/runs/45872186024/job/140091685440) 安装包和 [iOS arm64 未签名 IPA](https://github.com/CKopoer/BiliSail/actions/runs/45872186024/job/140091685447) 均构建成功。 |
| macOS 正式播放 JOC | Release 播放在线 DASH、离线分轨、MKV 和 MP4，四组均在暂停定位后恢复为 `apple-joc / E-AC-3 JOC`。普通 DD+、AAC 均输出 `coreaudio / floatp`，JOC 计数为 0。MKV 验证了静音、音量、1.25× 与 +3 dB 回退，以及恢复 1×、0 dB 后重新输出 JOC。[播放日志](https://github.com/CKopoer/BiliSail/actions/runs/45995280770/job/140493360999) |
| iOS 正式播放 JOC | iPhone 模拟器运行相同的播放器和六组样片。四组 JOC 在暂停、跳转和恢复后均报告 `apple-joc / E-AC-3 JOC`，各次采样已有 7 至 8 个已提交包。普通 DD+、AAC 均输出 `audiounit / floatp`，JOC 计数为 0。MKV 音量、倍速和增益切换通过。[播放日志](https://github.com/CKopoer/BiliSail/actions/runs/45995280770/job/140493361402) |
| 本次 Apple 打包 | iOS arm64 未签名 IPA、macOS arm64 与 x64 构建均通过。[iOS](https://github.com/CKopoer/BiliSail/actions/runs/45995276570/job/140494559148) · [macOS arm64](https://github.com/CKopoer/BiliSail/actions/runs/45995276570/job/140494559203) · [macOS x64](https://github.com/CKopoer/BiliSail/actions/runs/45995276570/job/140494559465) |
| macOS JOC 原型 | Dolby 公开样片识别为 Atmos，格式配置 15 字节；接收 87 包、222720 字节，跳转后接收 48 包。渲染器进入 rendering，时钟随 mpv 恢复，错误码 0。[原型日志](https://github.com/CKopoer/BiliSail/actions/runs/45861827586) |
| iPhone 模拟器 JOC 原型 | 同一样片识别为 Atmos，末次接收 84 包、215040 字节，跳转后接收 46 包，时钟检查通过，错误码 0。[模拟器日志](https://github.com/CKopoer/BiliSail/actions/runs/45872185913/job/140090160715) |

表中的 JOC 原型记录来自独立的单音轨 MP4 程序。现行工作流使用应用内的同一个 `MediaKitEngine` 与 `VideoSurface` 播放全部样片，每次换源和跳转后读取当前音频输出。在线分轨服务要求携带 Referer 并接受 Range，离线组先把文件写入应用沙盒，再以文件 URI 打开。[工作流与样片生成命令](../../.github/workflows/apple-playback.yml)

实际 HDR 面板需验看高光和 Profile 5 色彩。Profile 8 可使用带／去 RPU 的同源对照。耳机、内置扬声器的对象渲染和 HDMI 接收端的 Atmos 指示均需在对应硬件分别验收。

## JOC 播放破音

在 `fa793d86` 的原生依赖上，48 kHz 的 Dolby《Glass Blowing》样片每个压缩包包含 1,536 个采样，时长 32 ms。旧驱动遇到 `readyForMoreMediaData=false` 就停止送包，下一次定时检查按标称设备缓冲计算，间隔可达 62.5 ms。当系统直到播放队列接近耗尽才重新给出就绪提示时，剩余音频可能撑不到下次补包。mpv 报告 underrun 并反复重启音频。先前的短时包数检查在队列首次填充后即可通过。[Apple 对就绪提示和有界入队的说明](https://developer.apple.com/documentation/avfoundation/avsamplebufferaudiorenderer/isreadyformoremediadata?language=objc)

新驱动使用 Apple 的预缓冲机制启动音频，再按队列的实际剩余时长安排补包。驱动用已排定音频的剩余时长控制送包，目标上限为 500 ms。只要队列仍有音频，每隔 4 至 16 ms 检查一次余量，并按完整压缩包补充。半秒上限同时限制片尾暂停时排空队列所需的时间。音量只在值变化时写入。压缩包时长与解码帧覆盖的时长不一致，或有数据且应当播放时渲染时钟持续停滞，会触发已有的 PCM 回退。[原生修复与重建配方](https://github.com/CKopoer/libmpv-darwin-build/tree/1146169ce340ddec08d2f139de830dc301d76e28/bilisail)

macOS 用 BlackHole 回录同一段八秒样片。压力测试在起播一秒后延迟就绪提示，继续使用系统解码、时钟和音频输出。基准取自同一音轨，由 FFmpeg 离线解码并按 Lo/Ro 混成立体声。测试将回录整段对齐一次，左右声道分别按 100 ms 有声窗口比较，匹配门槛为相关系数 0.95。

| macOS 回录条件 | 旧依赖 | 新依赖 |
| --- | --- | --- |
| 正常接包 | 播放至结尾，波形与参考匹配 | 四轮中三轮为 60/60，另一次为 57/60，左右声道一致 |
| 剩余音频低于 20 ms 才给出就绪提示 | 出现队列断供，重复测试中录得静音并超时 | 四轮均为左右声道各 60/60 个窗口匹配，保持 `apple-joc` 直至播完 |

中间版本在系统暂缓接包时只保留 250 ms 音频。一次压力回录中，原生驱动保持 JOC 输出直至播完，所有入队时间戳连续；实际录音仍在多个压缩包边界附近出现约 6 至 37 ms 的静音。最终驱动在两种条件下都维持半秒队列，给系统解码留出相同余量。失败的回归会保留原始录音和 PCM 参考。[中间版本的时间戳和原始回录](https://github.com/CKopoer/BiliSail/actions/runs/46021975222/job/140583631641)

六个播放位置的原生暂停耗时为 0.038 至 0.991 秒。macOS Release 与 iPhone 模拟器的应用回归覆盖在线分轨、离线分轨、MKV 和 MP4，以及暂停、跳转和音频模式切换。实体 iPhone、Mac 扬声器、耳机及 HDMI 接收端仍需分别试听。[旧驱动断供与时间戳中断](https://github.com/CKopoer/BiliSail/actions/runs/46024220187) · [压力回录对照](https://github.com/CKopoer/BiliSail/actions/runs/46024019716) · [暂停耗时](https://github.com/CKopoer/BiliSail/actions/runs/46023790133) · [五个原生切片构建](https://github.com/CKopoer/BiliSail/actions/runs/46023603560)

## 在设备上复验

[独立验证入口](../../tool/validation/apple_hdr_probe.dart) 通过正式 macOS 窗口或 iOS Runner 打开样片，检查实际 Metal 输出、暂停定位、继续播放及解码音轨。先按 [bili_mux 说明](../../packages/bili_mux/README.md) 准备该设备的组件。对实机选设备 ID，样片 URL 必须可被该设备访问。下例中的 URL 代表各自含音轨、时长超过两秒的受控片源。

```sh
flutter run --release -d macos -t tool/validation/apple_hdr_probe.dart \
  --dart-define=APPLE_P5=https://example.org/p5.mp4 \
  --dart-define=APPLE_P8=https://example.org/p8.mp4 \
  --dart-define=APPLE_REQUIRE_HDR=true
```

可另传 `APPLE_HDR10`、`APPLE_HLG`。Profile 5 样片使用自带音轨，其余样片可用 `APPLE_COMPANION_AUDIO` 指定独立音轨。Apple Silicon 上测试 iPhone 模拟器先运行 `bash packages/bili_mux/tool/build.sh ios-simulator-arm64`，再为模拟器执行 debug 构建。要求 HDR 的检查在仅支持 SDR 的屏幕上会失败。测试入口打印实际输出，执行完毕退出。

在 macOS 或 iPhone 模拟器复验 JOC 时，按工作流准备测试文件，运行 `python3 tool/validation/apple_fixture_server.py build/fixtures`，并向同一 Flutter 入口传入 `--dart-define=APPLE_JOC_BASE=http://127.0.0.1:18085/`。使用实体 iPhone 时可将同一套素材及分轨路由部署到设备可达的 HTTPS 地址。普通用户在播放信息中可查看「音轨格式」「音频输出格式」和「音频传输」。
