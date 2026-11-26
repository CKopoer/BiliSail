# 杜比全景声播放方案

首期针对 B 站点播和离线媒体常用的 Dolby Digital Plus with Dolby Atmos（E-AC-3 JOC）。Windows 优先让 HDMI 功放解码，Android 优先使用手机已有的系统杜比解码器，也覆盖兼容的外接接收端。TrueHD Atmos、AC-4 和 Windows 耳机对象渲染分别验收。五端沿用已有音质偏好，选择「杜比音频」后才优先取服务端提供的杜比轨。默认 AAC 192K 和账号可见的清晰度、音质仍由现有选轨逻辑决定。

## 能力与证据

播放信息应分别记录音轨、实际输出和接收端能确认的内容。B 站音轨 ID、`ec-3` 和声道数只能识别杜比候选。MP4 的 `dec3` 对象扩展、码流的 JOC 标志或解封装器据此识别的 JOC profile 可以确认片源。普通扬声器收到 PCM 也能发声。接收端报告 Atmos 输入，或系统杜比解码器实际处理带对象的音轨，才有相应设备路径的证据。系统空间音效开关和主观听感不能单独证明对象到达。[Dolby 的容器标记](https://ott.dolby.com/OnDelKits/DDP/Dolby_Digital_Plus_Online_Delivery_Kit_v1.5/Documentation/Playback/SDM/help_files/topics/c_id_ddp_atmos_isobmff.html) · [JOC 码流标记](https://ott.dolby.com/OnDelKits/EC-3_Online_Delivery_Kit_1.6/Documentation/Playback/SDM/help_files/topics/c_ddp_structure.html)

| 平台 | 实施路线 | 验收设备和依据 |
| --- | --- | --- |
| Windows，首期 | media_kit 保持现有视频、时钟和渲染。确认实际 WASAPI 默认播放端点接受 E-AC-3 的 IEC 61937 载波后，启用 mpv 的 E-AC-3 透传。普通 DD+ 子格式亦能承载 JOC。 | HDMI 接 Atmos 功放或回音壁，比对 JOC 与无 JOC 两条音轨的接收端输入格式。拔线、独占失败、静音、调音量和切倍速验证 PCM 回退。 |
| Android，首期 | 杜比候选源交由单个 Media3 ExoPlayer 准备音视频，分轨合并到同一时间线。系统 MediaCodec 负责本机杜比解码，Media3 的音频接收器负责外接路由协商。无匹配解码器、片源不适配或视频不能正确呈现时回到 media_kit。 | 小米 13 分别记录实际音轨 MIME、系统解码器或编码输出、首帧、暂停及 seek。扬声器、耳机及 HDMI 分别记结果。HDMI 需接收端输入格式，手机渲染需系统或厂商可观测证据。 |
| Linux，后续 | 复用 mpv 透传策略，按实际 ALSA HDMI 或支持编码格式的音频栈协商。 | 实体 Linux 主机、发行包和 HDMI 功放。检查沙箱中的可用输出与热插拔。 |
| iOS，原型 | 保留 mpv；在 E-AC-3 解码入口取得压缩包和时间戳，由 Apple 样本渲染器消费。 | iPhone 模拟器已用 JOC 样片验证格式、暂停和跳转。实机对象输出与应用音频接入待验。[Apple 验证记录](validation/apple-edr-joc.md) |
| macOS，原型 | 使用同一压缩音频探针与播放时钟。 | macOS runner 已验证 Apple 识别 Atmos 和压缩包渲染。内建输出、耳机和 HDMI 路由分别验收。[Apple 验证记录](validation/apple-edr-joc.md) |

Windows 的耳机或内置扬声器需要能够解读 JOC 的解码器，随后才可将对象样本和位置交给系统空间音频。单独调用 `ISpatialAudioClient` 无法从普通 5.1 PCM 重建原对象。后续用同一片源和系统播放器建立基准，再评估可供第三方使用的系统解码路径或授权解码 SDK。Linux 本机对象渲染也需独立的解码器和渲染器。[Microsoft 空间音频](https://learn.microsoft.com/windows/win32/coreaudio/spatial-sound) · [WASAPI 编码格式](https://learn.microsoft.com/windows/win32/coreaudio/representing-formats-for-iec-61937-transmissions)

## 播放契约

- 保持每标签一个播放所有者。音质负责选轨，平台能力负责选择输出。切清晰度、换音轨、提高倍速、音量均衡、静音、输出设备变化或端点被占用时，优先保留用户的位置、播放意图和实际音量。压缩透传不能应用 PCM 增益，用户要求处理时恢复 PCM。
- Android 的两个独立 URL 必须携带既有请求头，使用同一播放器同步。打开期间准备失败才在剩余超时预算内尝试原播放器，取消和换源应释放旧播放器。杜比视界 Profile 5 需要系统确实选择杜比视频解码及适配的显示面，避免为切音频破坏既有 HDR 播放。
- 自动测试覆盖来源分类、路由选择、透传与 PCM 的切换和普通音源。设备验收使用有明确 JOC 标记的样片、普通 E-AC-3、AAC 三组，覆盖本地封装和分轨、暂停、seek、恢复。此前 HDR 测试为独立 AAC 音轨，原始 Dolby 演示文件自带的 JOC 音轨可单独用于本专项。

Android 系统解码和外接设备直出有不同的能力查询和验收方法；Apple 提供可公开播放的 HLS Atmos 参考流。[Dolby Android 接入说明](https://professionalsupport.dolby.com/s/article/Enabling-Dolby-Atmos-in-Android-Mobile-media-apps) · [Android 路由与直出能力](https://developer.android.com/training/tv/playback/audio-capabilities) · [Media3 媒体源](https://developer.android.com/media/media3/exoplayer/media-sources) · [Apple 示例](https://developer.apple.com/streaming/examples/) · [mpv 音频透传](https://mpv.io/manual/stable/#options-audio-spdif)

## 首期实现和设备记录

Windows 原依赖接受 `audio-spdif=eac3`，随包 FFmpeg 却关闭了全部封装器。新 x64 和 ARM64 归档恢复 `spdif`，沿用固定 mpv 和 FFmpeg 提交。播放时核对默认 WASAPI 端点是否接受双声道、192 kHz、16 位的 DD+ 载波。在 100% 音量、1 倍速、0 dB 增益时允许透传；音量、静音、倍速或增益变化时切回可处理的 PCM。播放信息中的音轨格式来自解码或码流探测，输出格式来自实际音频设备。[归档与构建来源](../windows/native/PREDIDIT_SOURCE.md)

Windows x64 实际打包的 DLL 将 8 秒 JOC 样片输出为 250 个 IEC 61937 突发。还原出的 640,000 字节与原始 E-AC-3 帧逐字节一致，SHA-256 为 `9eeb11cf7d75d3da899fec304e9580c00499a45ccd6e2d0da405362024583378`。本机默认音频端点未接受该载波，BiliSail 实际使用 WASAPI float PCM。分轨、HTTP 重定向分轨、离线 MKV 和纯音频均识别 JOC，普通 DD+、AAC 对照均未标记全景声。ARM64 已构建，仍待 ARM64 实机验证。实体 HDMI 功放的 Atmos 输入指示、热插拔和独占冲突仍待接线验收。[码流校验程序](../tool/validation/windows_ddp_carrier.py)

Windows 换库后的首帧回归还发现，D3D11 纹理可能在首次绘制完成前就向 Flutter 报告视频尺寸。现在等 GPU 完成新尺寸的首帧再通知 Flutter。使用普通 AAC 分轨对照，验证了从冷启动到拖动进度条时的画面和音画同步。

Android 10（API 29）及以上向 Media3 提交原始媒体。分轨共用一个 ExoPlayer 和一套时钟。Matroska 标记为普通 E-AC-3 时，读取首个音频包的同步帧头确认 JOC。播放器在暂停状态下等待轨道选中、JOC 解码器或编码输出、所需的视频首帧，最多使用打开预算的三分之一且不超过 8 秒。软件视频解码偏好、非零启动音量增益及更早的 Android 版本沿用 media_kit。

小米 13（Android 16）用同一份 Dolby 样片分别验证了独立音视频、离线 MKV、Profile 5＋Atmos MP4 和纯音频。另以本机 HTTP 服务验证了独立视频和 JOC 音轨的 Referer、重定向和非零偏移 Range 读取。五项均报告 `audio/eac3-joc`、`c2.dolby.eac3.decoder.eac3-joc` 和 12 声道 PCM 16-bit AudioTrack。Profile 5 同时选中了 `video/dolby-vision` 并输出首帧。普通 DD+ 和 AAC 对照组均使用 media_kit，七项均测试了暂停、定位和恢复。12 声道是交给系统音轨的格式，机身扬声器的最终声场、耳机空间化及 HDMI 接收端显示仍待分别验收。复现入口为 [设备回归脚本](../tool/test-dolby-atmos.ps1)。
