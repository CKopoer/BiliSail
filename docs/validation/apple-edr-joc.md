# Apple 视频输出与 JOC 音频原型

## 视频

macOS 和 iOS 共用 BiliSail 的 media_kit 播放会话、分轨请求、缓冲、seek 和音频时钟。选中的视频轨为 Dolby Vision Profile 5、Profile 8、HDR10 或 HLG 时，Flutter 平台视图承载独立的 CAMetalLayer。mpv 的 gpu-next 和 libplacebo 通过 MoltenVK 向该层提交画面。普通 SDR 源沿用原有纹理。Apple 原生依赖包含可重建配方、源码版本、补丁和许可。[应用显示面](../../apple/AppleVideoSurface.swift) · [固定依赖及校验值](https://github.com/CKopoer/libmpv-darwin-build/releases/tag/apple-edr-joc-2026-11-27)

| 源与设备 | 接入行为 | 如何判读 |
| --- | --- | --- |
| Profile 5 | 软件 HEVC 保留逐帧 RPU，播放器完成 IPTPQc2 色彩重建 | 诊断中的 `videoOutputMatrix=dolbyvision` 配合 `videoOutput=gpu-next` |
| Profile 8 | 优先使用 RPU。没有可用 RPU 时允许有明确 BT.2020 和 PQ／HLG 标记的兼容基础层 | 仅有 PQ／HLG 说明基础层可用；做 RPU 验收时要求 `dolbyvision` |
| HDR10、HLG | 沿用解码偏好，按当前显示器输出能力映射 | 核对源、`targetTransfer` 和 `nativeHdrSurface` |
| 有 EDR 能力的屏幕 | macOS 查当前 Flutter 窗口所在屏幕；iOS 16 起查当前场景屏幕。优先输出 BT.2020/PQ | mpv 协商 PQ、原生层采用高精度 PQ 色彩空间、Metal 首帧提交呈现后才报告原生 HDR |
| SDR 屏、较早的 iOS 或 PQ 协商失败 | 尝试同一渲染器输出 BT.709/sRGB。显示面建立失败时采用纹理路径，Profile 5 需要可验证的色彩转换 | sRGB 输出时 `nativeHdrSurface=false` |

SDR 路径在带 sRGB 标记的 Metal drawable 被提交呈现后确认交接。iOS 模拟器使用该路径。真机 PQ 路径另要求窗口挂载、高精度 PQ 图层及非零呈现时间戳。

这条视频路径在播放器内解释杜比元数据，再把渲染结果交给 Apple 合成器。显示器是否进入 Dolby Vision 专有信号模式须另行观测。窗口移动或全屏切换会重新确认显示目标。显示器的 EDR 能力、当前亮度余量及画面实际高光分别验证。[Apple 对 Metal EDR 的说明](https://developer.apple.com/videos/play/wwdc2022/110565/) · [MoltenVK 交换链实现](https://github.com/KhronosGroup/MoltenVK/blob/v1.4.2/MoltenVK/MoltenVK/GPUObjects/MVKSwapchain.mm)

## JOC 原型

对单独运行的原型，mpv 在其 E-AC-3 解码入口复制成功接收的原始压缩包和 PTS。AVFoundation 从同一个本地 MP4 的唯一音轨取得带解码配置的格式描述。探针构造有时间戳的压缩 CMSampleBuffer，送入 AVSampleBufferAudioRenderer。mpv 的静音空输出维护主时钟，暂停或缓冲时同步器停走，seek 刷掉旧包后重新对时。原型会报告 Apple 的 Atmos 格式标识、提交包数、跳转后的进度和渲染器错误码。正常应用播放以现有音频输出工作。原型尚限单音轨 MP4，产品还需处理分轨配置、路由热插拔、音量和倍速。[探针源码](https://github.com/CKopoer/libmpv-darwin-build/blob/8c14f3c7e6367ce425667759724a5a20b66b3a8e/bilisail/joc_probe.m) · [Apple 音频渲染接口](https://developer.apple.com/documentation/avfoundation/avsamplebufferaudiorenderer)

## 构建与验证

| 环境 | 实际观测 |
| --- | --- |
| macOS、iOS 原生依赖 | macOS arm64、x86_64，iOS 真机 arm64，以及同一归档中的两种模拟器架构均编译链接完成。归档 SHA-256 与发布摘要一致。[构建记录](https://github.com/CKopoer/BiliSail/actions/runs/45861827586) |
| macOS 应用视频 | Release 通过实际播放器打开 Profile 5、8.4、HDR10、HLG，四种片源均运行 gpu-next，暂停、定位、继续播放和音轨检查通过。前两种的输入矩阵为 `dolbyvision`，同源 HLG 为 `bt.2020-ncl`。当前屏幕支持 sRGB，四次输出均为 SDR。[播放日志](https://github.com/CKopoer/BiliSail/actions/runs/45872185913/job/140090161070) |
| iPhone 模拟器应用视频 | 使用 iOS Runner 打开相同四段素材。四次均向 Metal 提交 sRGB 图像，P5 和 P8.4 收到 Dolby Vision 矩阵，分轨音频、暂停定位和继续播放通过。[播放日志](https://github.com/CKopoer/BiliSail/actions/runs/45872185913/job/140090160715) |
| 应用打包 | macOS [arm64](https://github.com/CKopoer/BiliSail/actions/runs/45872186024/job/140091685377)、[Intel x64](https://github.com/CKopoer/BiliSail/actions/runs/45872186024/job/140091685440) 安装包和 [iOS arm64 未签名 IPA](https://github.com/CKopoer/BiliSail/actions/runs/45872186024/job/140091685447) 均构建成功。 |
| macOS JOC 原型 | Dolby 公开样片识别为 Atmos，格式配置 15 字节；接收 87 包、222720 字节，跳转后接收 48 包。渲染器进入 rendering，时钟随 mpv 恢复，错误码 0。[原型日志](https://github.com/CKopoer/BiliSail/actions/runs/45861827586) |
| iPhone 模拟器 JOC 原型 | 同一样片识别为 Atmos，末次接收 84 包、215040 字节，跳转后接收 46 包，时钟检查通过，错误码 0。[模拟器日志](https://github.com/CKopoer/BiliSail/actions/runs/45872185913/job/140090160715) |

早期有一次模拟器冷启动后 JOC 探针返回 1，该次日志没有保留计数。现行工作流分别检查视频和音频，并在探针失败时保留统计量。[早期运行](https://github.com/CKopoer/BiliSail/actions/runs/45871103125/job/140086424516)

实际 HDR 面板需验看高光和 Profile 5 色彩。Profile 8 可使用带／去 RPU 的同源对照。耳机、内置扬声器的对象渲染和 HDMI 接收端的 Atmos 指示均需在对应硬件分别验收。

## 在设备上复验画面

[独立验证入口](../../tool/validation/apple_hdr_probe.dart) 通过正式 macOS 窗口或 iOS Runner 打开样片，检查实际 Metal 输出、暂停定位、继续播放及解码音轨。先按 [bili_mux 说明](../../packages/bili_mux/README.md) 准备该设备的组件。对实机选设备 ID，样片 URL 必须可被该设备访问。下例中的 URL 代表各自含音轨、时长超过两秒的受控片源。

```sh
flutter run --release -d macos -t tool/validation/apple_hdr_probe.dart \
  --dart-define=APPLE_P5=https://example.org/p5.mp4 \
  --dart-define=APPLE_P8=https://example.org/p8.mp4 \
  --dart-define=APPLE_REQUIRE_HDR=true
```

可另传 `APPLE_HDR10`、`APPLE_HLG`。Profile 5 样片使用自带音轨，其余样片可用 `APPLE_COMPANION_AUDIO` 指定独立音轨。Apple Silicon 上测试 iPhone 模拟器先运行 `bash packages/bili_mux/tool/build.sh ios-simulator-arm64`，再为模拟器执行 debug 构建。要求 HDR 的检查在仅支持 SDR 的屏幕上会失败。测试入口打印实际输出，执行完毕退出。
