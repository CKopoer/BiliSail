# Android 4K60 HEVC／AV1 编码对照

日期：2026-11-05（Asia/Shanghai）。承接 [AVC 播放热点与 HTTP 流模拟](android-4k60-playback-2026-11-05.md)，在同一台 Xiaomi 13（SM8550／骁龙 8 Gen 2、Android 16、120Hz）上增加 HEVC Main、HEVC Main10、AV1 Main 8-bit／10-bit，并重测 H.264 基线。

## 结论

**五种流都实际创建了高通硬件解码组件，3840×2160／60fps 本地分轨播放未出现稳态视频或解码掉帧。** HEVC／AV1 的 10-bit 路径也能正常出图，没有观察到黑屏或明显偏色。该结论对应本机、本文样片及采样 APK，不代表其他设备或所有 4K 码流。

**本轮没有发现新增的持续解码瓶颈，主要余量压力仍在高刷合成。** 纯 Surface 呈现约 60fps；叠加弹幕与控件后，raster P95 为约 9–11.5ms，超过 120Hz 的 8.33ms 预算，合成呈现随运行状态在约 89–120fps 之间波动。视频源仍为 60fps，合成刷新率不能直接当作视频解码帧率或视频掉帧率。

## 样片与方法

- 来源是 [Blender 官方公开 Big Buck Bunny Sunflower](https://download.blender.org/demo/movies/BBB/bbb_sunflower_2160p_60fps_normal.mp4.zip)，不使用 B 站或会员资源。原片 SHA-256 为 `35db9a007021f1b0066993e1d2c4448c83a8b279f799c97d33cbba73980a8a36`；署名：© 2008 Blender Foundation / www.bigbuckbunny.org，许可见 [CC BY 3.0 说明](https://peach.blender.org/about/)。
- [制备脚本](../../tool/validation/prepare_4k60_codec_samples.ps1)截取约 90 秒：H.264 视频流直接复制；其他四份由同一已压缩 SDR 原片通过 NVENC 重新编码，目标 8Mbps、峰值 12Mbps、GOP 120，实际平均视频码率约 8.5–9.0Mbps。H.264 基线约 7.7Mbps。共享同一份 AAC-LC 音轨，避免音频差异影响比较。
- Main10／AV1 10-bit 样片由 8-bit SDR 转为 `p010le` 后编码，解码格式确认为 `yuv420p10le`。它们用于覆盖 10-bit 解码／纹理路径，**不增加原片色彩精度，也不是 HDR／杜比视界验收或编码画质比较**。样片未标注 HDR transfer；色彩截图仅作明显异常检查。
- 同一 Profile/AOT APK，复用生产 `PlaybackSession`、`MediaKitEngine`、`VideoSurface` 和 `PlaybackPanel`。每组运行纯 Surface、弹幕＋控件两个场景；seek 到 37 秒，预热 8 秒，采样约 30 秒。弹幕设置为 Android 默认字号比例 0.6、区域 0.5、透明度 0.8，每秒输入 20 条，80% 滚动、20% 固定；记录实际可见条数，不把输入条数当作成功上屏数。
- 首轮 10 个场景，针对合成帧率差异交换顺序复测两个场景，共约 360 秒稳态采样、360 个原生状态样本。均成功播放音视频、无缓冲样本、无探针错误。每组的实际解码与输出纹理均为 3840×2160；手机横屏为 2400×1080，未做原生 4K 屏幕验收。
- GPU busy 为整机 `/sys/class/kgsl/kgsl-3d0/gpubusy` 时间比例。GPU 频率不可读，未锁频或 root；所有前后 Thermal Status 均为 0，但不能据此认为每组频率一致。Profile、Perfetto 和 1ms Dart CPU 采样有额外开销，未增加关闭追踪的普通 Release 对照。
- 纯 Surface 与完整面板的画布宽度不同，因此表中差额包含布局、弹幕、控件和合成路径的共同影响，不能全归到某一个控件。外部视频纹理更新没有相应的 Dart FrameTiming；纯 Surface 的 raster 空值表示没有该口径数据。

## 硬解核对

没有仅凭 `hwdec-current=mediacodec` 判定硬解：[能力探针](../../tool/validation/android_codec_capabilities.java)读取设备 `MediaCodecInfo`，再由[匹配工具](../../tool/validation/summarize_android_codec_selection.py)将每个场景的 `Created component [...]` 日志按时间与实际能力条目对应。设备同时有 `c2.android.*` 软件组件，本轮没有创建这些视频软件组件。

| 样片 | 实际创建的视频组件 | 系统硬件／纯软件标记 | 稳态视频／解码掉帧增量 |
| --- | --- | --- | ---: |
| H.264 High 8-bit | `c2.qti.avc.decoder` | true／false | 0／0 |
| HEVC Main 8-bit | `c2.qti.hevc.decoder` | true／false | 0／0 |
| HEVC Main10 | `c2.qti.hevc.decoder` | true／false | 0／0 |
| AV1 Main 8-bit | `c2.qti.av1.decoder` | true／false | 0／0 |
| AV1 Main 10-bit | `c2.qti.av1.decoder` | true／false | 0／0 |

上述组件的设备能力也声明支持 3840×2160／60，实际两类场景均完成。硬件标记来自厂商提供的 [Android MediaCodecInfo API](https://developer.android.com/reference/android/media/MediaCodecInfo#isHardwareAccelerated())，结合实际创建日志和播放结果确认当前选择；没有独立读取硬件视频单元的性能计数器。

## 首轮性能

| 编码 | 纯 Surface GPU busy | 纯 Surface 呈现 | 弹幕＋控件 GPU busy | 弹幕＋控件 raster P95 | 弹幕＋控件呈现 |
| --- | ---: | ---: | ---: | ---: | ---: |
| H.264 8-bit | 25.3% | 60.0fps | 75.4% | 9.04ms | 119.7fps |
| HEVC 8-bit | 25.5% | 60.0fps | 75.6% | 9.06ms | 119.9fps |
| HEVC 10-bit | 27.9% | 60.0fps | 77.4% | 9.41ms | 118.3fps |
| AV1 8-bit | 25.8% | 60.0fps | 75.2% | 9.10ms | 119.4fps |
| AV1 10-bit | 28.0% | 60.0fps | 70.0% | 11.32ms | 105.6fps |

10-bit 纯播放比本轮 8-bit 组的 GPU busy 高约 2–3 个百分点，但样片码率、纹理格式和动态频率未完全隔离，不据此给出编码器或硬件解码效率排名。GPU busy 较低也可能伴随合成帧数减少，不能据此说叠加更省资源。

AV1 10-bit 首轮前半段 raster 均值约 8.1ms，后半段升至约 11ms，因而补做反序对照：

| 复测顺序 | GPU busy | raster P95 | 实际合成呈现 | 视频／解码掉帧 |
| --- | ---: | ---: | ---: | ---: |
| AV1 10-bit＋弹幕控件 | 71.3% | 11.30ms | 108.1fps | 0／0 |
| H.264＋弹幕控件 | 58.1% | 11.49ms | 89.0fps | 0／0 |

H.264 基线也出现相同方向的合成性能下降，所以不能将 AV1 的约 106fps 单独归因为该编码解码较慢。运行状态／调频是未排除因素；当前数据没有证明具体是哪一种因素导致变化。

## 热点与同步边界

- 首轮叠加组 raster 线程占单核约 38–41%，纯 Surface 约 22–23%。AV1 10-bit 叠加的 30 秒 trace 中，raster `QueuePresentKHR` 累计约 8.12 秒，视频渲染线程 `eglSwapBuffers` 累计约 5.25 秒；它们是包含等待的墙钟切片，嵌套切片不能相加当作 CPU 或 GPU 计算时间。
- UI P95 约 1.37–1.40ms，明显小于 raster。Dart 采样仍集中在弹幕帧访问、图层收集、集合操作和绘制失效；没有看到 CPU 软件视频解码成为主要热点。结合未增加的视频掉帧和实际硬件组件，后续优化应优先验证纹理输出尺寸、raster／提交和高刷合成链路。未修改产品代码、Ticker 节奏或硬解策略。
- 各场景每秒都有后端 `avsync` 值，最大绝对值约 **0.289ms**；没有记录到持续后端时钟漂移。音量为 0，未外录屏幕与扬声器，不能从该指标确认物理输出音画同步。详见[既有同步边界](android-4k60-playback-2026-11-05.md)。
- 本轮仅隔离本地解码／合成；HEVC／AV1 没有重复 HTTP 弱网矩阵。未覆盖 VP9、HDR／杜比视界、高码率原生 10-bit 内容、倍速、蓝牙音频、长时间发热／功耗或其他手机。

## 数据、复现与恢复

[机器数据](data/android-4k60-codecs-2026-11-05.json)包含样片 SHA-256／ffprobe 元信息、设备能力、实际组件匹配、场景配置、完整首轮与复测摘要。原始数据和本地样片在忽略目录 `build/validation/android-4k60-codecs/`、`build/validation/android-4k60/{codecs_a,codecs_recheck,codecs_debug}/`；预热截图没有纳入稳态采样，也不作为逐帧呈现证明。

```powershell
./tool/validation/prepare_4k60_codec_samples.ps1 -Output <fresh-media-folder>
# 将视频／共用音轨放入测试包 files/4k60/codecs，并使用数据中的 scenario 配置。
./tool/test-android-4k60.ps1 -DeviceId <adb-id> -ConfigPath <config.json> -Label <fresh-label>
python tool/validation/summarize_android_4k60.py <run-folder> --trace-processor <trace_processor_shell.exe> --output <summary.json>
python tool/validation/summarize_android_codec_selection.py <run-folder> --capabilities <codec-capabilities.json> --output <selection.json>
```

- 正式数据来自同一 Profile APK：SHA-256 `701e2b42db968c1afed8bc24084f7d1df8d2233ce36e871059fba7c626643c08`，包含 AOT `libapp.so`、没有 Debug kernel。场景记录 HEAD 为 `987e4cda1d612e6a8d8b097629e336eeefdf432d`；该轮没有修改产品播放链路。采样期间存在其他功能的并行提交，结果绑定此 APK，不代表后续全工作区状态。
- 根 `tool/check.ps1 -SkipPub` 在本轮检查快照中通过：根应用 4266、bili_api 630、bili_player 148、bili_danmaku 161、bili_mux 5，共 **5210 项**；根应用 13 项和 mux 原生 10 项按环境条件跳过。未配置 `BILI_MUX_LIBRARY`，不将跳过算作 mux 原生验证。探针格式／静态分析、Python 编译／HTTP 行为测试 3 项和 PowerShell 语法检查通过。
- 12 个正式场景的 Perfetto 有效 CPU 覆盖均约 30 秒，没有报告 ring overwrite。Debug 探针另做全量 kernel `reloadSources` 和 `ext.flutter.reassemble`，均成功；Debug 帧率不进入上述结论。专项 Profile／Debug APK、哈希和模式元信息保存在 `build/development/android-arm64/BiliSail-test-arm64-4k60-codecs-{profile,debug}.apk*`。
- 每轮均先保留普通 `lib/main.dart` 开发 Release，再使用同签名覆盖安装专项入口，最后覆盖恢复。恢复 APK 为 `dev.bilisail.bilisail.test`、1.2.6／12606、不可调试，SHA-256 `2f0a4dab94c0ca55842037cdb8592731d32989b57353f55ce8c3c82db5f9f39a`，与设备拉回文件核对一致。没有卸载、清数据或复制正式包凭据。屏幕常亮恢复为 0，本轮创建的 reverse／VM 转发已清理，原有未归属本轮的转发保留。
