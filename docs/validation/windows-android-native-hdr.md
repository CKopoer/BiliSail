# Windows 与 Android 的原生 HDR 视频输出

本文记录 media_kit 的视频呈现路径。带全景声音轨的 Android 节目还可选用单个系统音视频播放器，Dolby Vision 与音频同时存在时的实测见[杜比全景声播放方案](../dolby-atmos-playback.md)。

BiliSail 沿用 media_kit、mpv 的播放时钟与独立音轨。Windows 和 Android 在确认视频色彩信息及当前显示设备的输出能力后，由同一播放器切换到专用 HDR 显示面。gpu-next 使用 libplacebo 解释杜比视界 RPU，并将画面映射到系统支持的 HDR 输出。系统或电视收到已经渲染的 HDR 像素；这条路径不向外置显示器发送 Dolby Vision 码流。

| 平台 | 启用条件 | 视频输出 |
| --- | --- | --- |
| Windows | 窗口所在显示器已开启系统 HDR，D3D11 交换链支持 BT.2020/PQ 呈现 | DirectComposition 合成 RGB10A2 视频。保留用户解码偏好，杜比硬解丢失 RPU 时尝试软件解码。 |
| Android | Android 10（API 29）起，当前显示器报告 HDR10 或 HLG，Vulkan 能建立对应输出 | gpu-next 写入独立的 10 位 Surface。优先 PQ，仅支持 HLG 的设备请求 HLG。杜比视频使用软件 HEVC 解码保留 RPU，普通视频沿用解码偏好。 |

按当前所选视频轨识别 Profile 5、Profile 8、PQ 和 HLG，包括缺少业务层 HDR 标记的离线文件。Profile 5 需要杜比色彩重建，Profile 8 优先使用 RPU；如果解码器只能提供明确标为 BT.2020/PQ 或 BT.2020/HLG 的兼容基础层，仍可输出 HDR。原生输出协商失败或 Windows 关闭 HDR 时恢复原有纹理呈现，Profile 5 的 SDR 色彩映射继续生效。播放诊断中的 `nativeHdrSurface`、`targetTransfer` 和 `videoOutputMatrix` 分别反映呈现路径、输出传递函数和渲染输入矩阵。

## 验证范围

| 设备 | 实际观测 |
| --- | --- |
| Windows x64，RTX 4070 Ti SUPER，X41 | 系统 HDR 开启时，Profile 5、8.4、HDR10、HLG 都以 D3D11VA 解码并输出 PQ。两段杜比样片报告 `dolbyvision` 矩阵。Windows Graphics Capture 的 FP16 合成图中，视频高光超过同一画面的 SDR 白点。播放中关闭系统 HDR 后恢复纹理，重新开启后恢复 PQ。测试恢复了显示器原有的 HDR 关闭状态。 |
| 小米 13，Android 16 | Profile 5（1080p）及 8.4（4K）都由 gpu-next 输出 PQ。SurfaceFlinger 的视频层为 RGBA_1010102、BT.2020/PQ，系统报告 HDR 层存在。切至 SDR 后该层消失，MediaCodec 硬解恢复。使用独立开发包，测试后覆盖恢复普通入口。 |

两端都在应用播放器内使用分轨音视频测试暂停、seek 和恢复。Windows 另外用不透明和半透明色块覆盖视频，检查桌面最终合成的像素，验证窗口移动、最小化、恢复与换回 SDR 后的显示面释放。原生视频面位于 Flutter 窗口下方，采集整个显示器能得到完整画面，只抓取 Flutter 窗口的第三方工具可能漏掉视频层。

Windows Release（AOT）最后一轮在相同屏幕设置和采样区域内，SDR 白色的线性 scRGB 值为 3.0，Profile 5 和 8.4 的最高 RGB 分量分别为 57.94 和 12.05。这些数值来自桌面合成缓冲区，物理面板亮度需要光度计测量。Profile 5 转 SDR 的独立参考图测试在自动与软件解码下 RGB 平均绝对误差均约 8.94，低于阈值 12。

Windows 可运行 `tool/test-windows-dolby-vision.ps1`，Android 可运行 `tool/test-android-dolby-vision.ps1 -DeviceId <设备序列号>`。首次运行带 `-PrepareSample` 准备公开的 Profile 5 样片。脚本先将 SDR 映射与参考图对照，再按实际显示设备能力验证 HDR 输出及暂停定位。

小米 13 在杜比样片复测完成后断开连接，独立 HDR10、HLG 样片及最后构建的 Android 安装包尚待真机复验。仅支持 HLG 的屏幕也未实测。上述观测覆盖系统合成层，面板实际峰值亮度、持续 4K 播放的帧率与功耗需单独测量。

根应用和四个包共通过 7,493 项 Dart／Flutter 测试，21 项按测试条件跳过。检查已配置 Windows 原生 mux 和 ffprobe。Windows 的分轨音视频、暂停与 seek、缓冲恢复、独立窗口及 HTTP 音频等受控回归通过。Windows x64 普通入口与 Android arm64 独立开发包均完成 Release 构建。

Windows 的交换链色彩空间与 Android 的显示能力、SurfaceView 约束分别见平台文档。[Windows Advanced Color](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/high-dynamic-range) · [Android HDR 播放](https://developer.android.com/media/grow/hdr-playback)
