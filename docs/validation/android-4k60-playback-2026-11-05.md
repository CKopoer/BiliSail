# Android 4K60 播放热点、HTTP 流模拟与音画同步边界

日期：2026-11-05（Asia/Shanghai）。设备为 Xiaomi 13（2211133C）、SM8550／骁龙 8 Gen 2、Android 16，1080×2400、DPR 2.75、120Hz。使用独立 `dev.bilisail.bilisail.test`、同一本机开发签名的 Profile/AOT 探针，不使用正式包账号或数据库。

## 结论

**本机 Profile 采样下最明显的热点在 120Hz 的视频、弹幕与控件合成，未发现该 AVC 样片的持续解码瓶颈。** 本地 4K60 各阶段的 mpv 视频／解码掉帧增量均为 0；密集弹幕＋控件的 Flutter raster P95 约 10.2ms，超过 120Hz 的 8.33ms 线程预算，实际 Flutter Surface 呈现约 108fps。这里的 108fps 是最终合成层刷新，不是 60fps 视频的解码帧率。

受控 HTTP 分轨流也已运行：32Mbps 正常播放；共享 2Mbps 的阶段持续缓冲，30 秒墙钟内位置只推进 2.4 秒，并出现 10 个视频输出掉帧、0 个解码掉帧。该场景的首要限制是输入供给，不能把它算作解码或弹幕性能退化。

**没有采到播放器内部音视频时钟持续偏离的证据，但尚不能保证实际屏幕与扬声器的输出同步。** 相关证据和限制见下文。

## 素材、探针和采样

- 使用上一轮[公开素材记录](windows-4k60-playback-2026-11-05.md)中的 Big Buck Bunny Sunflower，3840×2160、60fps、H.264 High 5.1、8-bit；版权归属 Blender Foundation，原片 CC BY 3.0，来源见[官方目录](https://download.blender.org/demo/movies/BBB/)和[许可说明](https://peach.blender.org/about/)。1080p60 对照为同片的公开 1920×1080／60fps AVC 版本。
- 4K／1080p 视频用 FFmpeg `-c copy -an` 拆出，不重新编码；独立音频由原片 MP3 转为 AAC。HTTP 测试另用 `-c copy -movflags +faststart` 将索引移到前部，以支持原生播放器的真实 Range／seek 请求。文件保存在 `build/validation/android-4k60/`，手机本地文件位于测试包自己的 external files 目录。
- [Dart 探针](../../tool/validation/android_4k60_probe.dart)复用生产 `PlaybackSession`、`MediaKitEngine`、`VideoSurface` 和 `PlaybackPanel`；媒体解析与弹幕来源为夹具，进度上报为空实现。所有用户设置只在内存中创建，弹幕使用 Android 默认区域 0.5、字号比例 0.6、透明度 0.8；每秒输入 20 条，80% 滚动、20% 固定，实际同屏条数单独记录。
- 同一约 45–75 秒片段，每阶段 seek 到 37 秒后预热 8 秒，再采样 30 秒。19 个正式阶段累计约 **571.4 秒**。缓冲场景仍按墙钟采样，不把等待时间剔除后再声称流畅。
- [运行脚本](../../tool/test-android-4k60.ps1)和[采集器](../../tool/validation/android_4k60_collector.py)记录逐秒原生状态、Flutter FrameTiming、GPU busy、Perfetto 调度／图形事件、Dart CPU 栈、温度与内存。[汇总工具](../../tool/validation/summarize_android_4k60.py)和[完整数据](data/android-4k60-playback-2026-11-05.json)随本记录保留。
- GPU busy 是 `/sys/class/kgsl/kgsl-3d0/gpubusy` 的**整机 GPU 忙碌时间比例**，不是 Windows 任务管理器的单进程 3D 指标，不能跨平台直接比倍数。GPU 时钟读取被系统拒绝；未 root、锁频或绕过权限。各阶段 Thermal Status 为 0，不据此保证所有频率完全相同。
- 结果包含 Profile、逐秒遥测、Perfetto 和 1ms 周期 Dart CPU 采样的开销，适合本轮组内定位。没有另外采集关闭追踪的普通 Release 对照，因此不将绝对占用／帧率写成用户日常构建的保证。
- 所有源的实际硬解均为 `mediacodec`。4K 解码与输出纹理实读均为 3840×2160，显示器实际为 1080 高；不是手机原生 4K 显示验收。横屏纯 Surface 的布局宽度为 698.18 logical px，正式全屏面板为 872.73 logical px，高度同为 392.73；两者画布不同，不能把全部 GPU 差额归因于面板控件。

## 本地文件结果

下表均为正式 Profile 数据，GPU 为阶段均值，raster 为该阶段自身 P95。纯 Surface 的外部纹理更新不会产生相应的 Dart FrameTiming；空值表示该指标没有数据，**不是渲染耗时为零**。

| 场景 | GPU busy | raster P95 | Dart FrameTiming／秒 | 稳态视频／解码掉帧增量 |
| --- | ---: | ---: | ---: | ---: |
| 1080p60，纯 Surface | 20.9% | 无 Dart 数据 | 0 | 0／0 |
| 4K60，纯 Surface | 25.5% | 无 Dart 数据 | 0 | 0／0 |
| 4K60，关闭帧队列 | 25.5% | 无 Dart 数据 | 0 | 0／0 |
| 4K60，单文件而非分轨 | 25.4% | 无 Dart 数据 | 0 | 0／0 |
| 4K60，全屏面板，控件隐藏 | 37.9% | 7.380ms | 60.3 | 0／0 |
| 4K60，显示控件 | 39.2% | 7.925ms | 60.7 | 0／0 |
| 4K60，弹幕 | 69.7% | 9.568ms | 113.9 | 0／0 |
| 4K60，弹幕＋控件 | 68.9% | 10.234ms | 108.1 | 0／0 |
| 4K60，竖屏面板 | 20.2% | 6.871ms | 60.7 | 0／0 |

弹幕实际同屏均值为仅弹幕约 36 条、带控件约 30 条；没有用“输入 20 条／秒”冒充全部显示。Android 默认仍受同屏 120 条／待处理 500 条等上限保护。密集场景缓存接近 32MiB 预算，但稳态命中约 99.77%，直接绘制回退为 0，尚无缓存失效风暴的证据。

重复轮次得到仅弹幕 raster P95 9.595ms。关闭已有 `showCollapsedProgress` 设置后，仅面板的 Dart 帧回调从约 60／秒降为 0，但 GPU busy 为 37.6% → 37.4%；有弹幕时为 69.5% → 69.7%，raster P95 9.595 → 9.492ms。**细进度条会触发 Dart 工作，但本次未证明关闭它能降低主要 GPU 成本。** 设置仅在探针内切换，未保存到用户配置。

补充轮使用正确的 SurfaceFlinger 完整图层名（包含前导 SurfaceView 对象标识），取得约 29.3 秒有效实际呈现时间戳：

| 场景 | Flutter Surface 实际呈现／秒 | 呈现间隔 P95 | >50ms 间隔 |
| --- | ---: | ---: | ---: |
| 4K 纯 Surface | 60.01 | 24.81ms | 0 |
| 4K 面板、细进度关闭 | 59.93 | 24.81ms | 0 |
| 4K 弹幕＋控件 | 107.62 | 16.54ms | 0 |

这些时间戳描述最终 Surface，不能识别每张画面是否为不同的视频帧；源视频仍是 60fps。平均帧率也不能替代间隔分布或长期稳定性。

## 热点定位与优先级

1. **优先排查视频纹理与弹幕的高刷合成。** 补充轮的 `1.raster` CPU 从单核约 24.2%（纯 Surface）／26.2%（面板）升至 52.7%（弹幕＋控件）；主线程约 22.8%、MediaCodec_loop 约 10.1%。同期 GPU busy 约 68.5%，raster P95 10.212ms，3224 个 raster 样本中 2536 个超过 8.33ms、没有超过 16.67ms。即 60fps 视频正常，不等于 120Hz 弹幕合成可以满速。
2. **图形交付与完成等待明显增加。** Perfetto 的 GPU completion `waitForever` 累计由每墙钟秒约 76.5ms（纯 Surface）／191.8ms（面板）升至 396.0ms（弹幕＋控件）；raster 的 `queueBuffer`、`QueuePresentKHR` 累计也增加。这些是各线程的等待／调用区间，不是可相加的总 CPU 时间，也不足以把成本精确拆成某个 shader。实测支持“渲染／合成链路吃紧”，尚不支持断言某个驱动函数单独就是根因。
3. **4K 输出纹理是值得做 A/B 的候选。** [视频输出](../../packages/bili_player/lib/src/media_kit_video_output.dart)在 Android 按解码尺寸维护 Surface；`_updateViewportCap` 当前只对 Windows 生效。默认 SDR 依赖源码使用 `vo=gpu`／Android GPU context，另有 Flutter 的纹理合成链路；实际已确认硬解和 4K 输出尺寸，但没有单独读取运行中的 vo 属性。可以在后续实验中保持 4K 解码，只按显示视口限制输出，测量是否减少 GPU 工作。**本轮尚未做该候选的原生 A/B，不将它写成已证实的修复。** 实施前必须保留首帧、暂停打开、旋转、全屏、HDR 与释放的现有边界。
4. **弹幕的 CPU 热点已定位，优先级低于 raster。** Dart 采样栈集中在 [DanmakuPaintLayers.add](../../packages/bili_danmaku/lib/src/danmaku_layers.dart)及 [DanmakuController._visitFrame](../../packages/bili_danmaku/lib/src/danmaku_controller.dart)的逐帧准备／绘制访问。UI P95 约 1.9–2.0ms，明显低于 raster；缓存命中率也较高。建议先量化图片绘制、组透明度和视频纹理重复合成，避免先重写调度或降低已经约定的随屏幕 Ticker。
5. **弱网缓冲动画还有额外渲染成本。** [播放面板](../../lib/features/playback/presentation/playback_panel.dart)在缓冲时显示持续动画的 `CircularProgressIndicator`。2Mbps 阶段的 Dart 帧约 116／秒、GPU busy 63.2%，反而高于正常 HTTP 流的 38.3%。这是加载态高刷合成的排查线索，不把它等同于原生解码变慢；还需在相同缺流条件下做静态提示／视频层保留的 A/B，才可量化动画与其他恢复工作的各自占比。

## 模拟真实流加载与播放

HTTP 对照使用本机 loopback 服务，经 adb reverse 到手机；音视频分别由原生播放器发起 HTTP 请求，实际执行 `Range`、206／Content-Range、seek、预缓冲与缓冲恢复。源文件是同一公开样片，不需要 Bilibili 大会员。

| 条件 | 后端 playing＋音频解码就绪 | 缓冲逐秒样本 | 30 秒位置推进 | 视频／解码掉帧增量 |
| --- | ---: | ---: | ---: | ---: |
| 音视频共享 32Mbps，首字节额外延迟 50ms | 573ms | 0／30 | 30.017s | 0／0 |
| 共享 2Mbps，延迟 120ms，周期性小抖动 | 3160ms | 27／30 | 2.400s | 10／0 |
| 32Mbps，采样第 8–20 秒停止供数 | 577ms | 0／30 | 30.016s | 0／0 |

“就绪”从探针挂载计到后端 playing 且音频已解码，不是屏幕实际首像素时间。12 秒停供阶段中缓存指标停止更新，恢复供数后继续增加，播放未进入缓冲，说明该条件被已有缓存覆盖。2Mbps 阶段则真实触发缺流，不能因为缓冲期间仍有约 116 次 Dart 帧回调就说视频流畅。

服务支持共享带宽限速、请求首字节延迟、抖动和停供；[三个 HTTP 行为测试](../../tool/validation/test_android_4k60_collector.py)覆盖 HEAD、精确／suffix Range、416 和路径隔离。它模拟应用层输入条件，**不完整模拟蜂窝无线、TLS／HTTP2、TCP 拥塞、真实 CDN 路由、账号鉴权或播放地址解析**。请求日志只记录公开夹具的字节范围和耗时。

## 是否存在音画不同步

- 19 个正式阶段逐秒读取的 mpv `avsync` 最大绝对值为 **0.083ms**；本地、正常 HTTP 和短暂停供均未看到持续时钟偏离。2Mbps 弱网也没有记录到持续偏离，主要表现为缓冲和迟到视频帧丢弃。[mpv 的时钟与掉帧属性](https://mpv.io/manual/stable/#command-interface-avsync)不能替代最终呈现检测。
- 采样频率为 1Hz，可能漏掉很短的偏移；读取的是后端时钟，不是某个视频帧从显示器发光到声音从扬声器发出的实测时间。Flutter/Vulkan 合成队列、显示扫描、AudioTrack／蓝牙输出等都可能引入后端指标没有完整反映的延迟。
- 探针音量为 0，保留音频解码和时钟，但没有做主观听辨或外部同步录制。因此结论是**未发现持续后端漂移，实际感知同步尚未验收**。要确认肉眼／人耳感受到的偏移，应使用同帧闪光与短音标记素材，用同一录制时基拍到屏幕并录到扬声器，再比较正常播放、密集叠加和缓冲恢复前后的偏移。

## 复现、验证与恢复

```powershell
# 首次准备目标组件和普通开发 Release；运行入口会保留恢复用 APK。
./tool/build-download-mux.ps1 -Target android-arm64
./tool/test-android-4k60.ps1 -DeviceId <adb-id> -ConfigPath <scenario.json> -Label <fresh-label> -SkipMuxBuild
python tool/validation/summarize_android_4k60.py <run-folder> --trace-processor <trace_processor_shell.exe> --output <summary.json>
python -m unittest discover -s tool/validation -p test_android_4k60_collector.py -v
```

场景字段与实跑配置见[可复用场景列表](data/android-4k60-scenarios-2026-11-05.json)，原分轮配置保存在 `build/validation/android-4k60/{formal_a,formal_b,formal_c}/config.json`；包括 video/audio 的本地路径或 HTTP URI、panel、comments、controls、portrait、queue、progress、seconds。collector 固定监听本机 18965，媒体端点只开放两份指定公开夹具；HTTP 文件需置于 run folder 的父目录，命名为 `http-video-4k60.mp4`／`http-audio.m4a`。

- `tool/check.ps1 -SkipPub` 在本轮检查快照中通过：根应用 4177、bili_api 586、bili_player 148、bili_danmaku 161、bili_mux 5，共 **5077 项**。根应用 13 项及 mux 原生 10 项按环境条件跳过；没有把 mux 跳过当作原生验证。最终探针格式／静态分析、打包边界 lint 和 HTTP 行为测试通过。
- Profile 正式轮全部完成。另有 Debug 探针的 `reloadSources` 全量 kernel 热重载和 `ext.flutter.reassemble` 成功记录；Debug 数据不用于性能结论。
- Profile／Debug 夹具 APK、SHA-256 和模式元信息另保存在 `build/development/android-arm64/BiliSail-test-arm64-4k60-{profile,debug}.apk*`，它们是专项入口，不留作手机日常测试入口。
- A／B 的密集场景 Perfetto 96MiB 环形缓冲发生覆盖，CPU 统计按仍覆盖的约 26–27 秒归一化，原始统计保留覆盖提示。C 轮改为 192MiB，约 30 秒 CPU 区间完整、没有覆盖，重现相近结果。Android FrameTimeline 含系统显示帧，但没有该 Flutter app 的可归属 SurfaceFrame，不据此生成 app 的 jank 百分比；实际呈现改由 SurfaceFlinger 时间戳验证。[Perfetto 的时间线与调度定义](https://perfetto.dev/docs/analysis/sql-tables/)用于解释这些口径。
- 前几次短预检曾遇到遥测 chunked body、启动 PID 等待、Android Perfetto 配置读取权限和构建产物复制时序问题；均在正式轮之前修正或隔离，不将这些失败记作播放回归。所有安装均覆盖、同签名；没有卸载、清数据、复制正式包凭据或绕过系统权限。
- 三轮均保留自己的 APK 哈希／元信息。A／B 的运行脚本记录 HEAD 为 `3565a2031fbdca180d03fad9999e48b4b0f7a4b5`，C 为 `af38c9f688a409dfbb712604829c50b75551e3eb`；测试期间存在个人页／消息／评论等并行工作，未改动或回退它们。结果对应采样 APK 及相关未变的播放链路，**不代表后续整个工作区已获得同样验证**。
- 最终已覆盖恢复开测前保留的普通入口开发 Release：`dev.bilisail.bilisail.test`、1.2.6+6／12606、不可调试；设备拉回 APK 与恢复文件 SHA-256 均为 `79b60b13b67b1eedcb315de83fcca742acbe4e961ca9ddcd9f7079a1ca5f63bf`。屏幕常亮恢复为 0，本任务创建的 reverse 和记录的 VM 转发已清理；其他未归属本任务的转发不改动。

原始 JSONL、Perfetto、CPU 栈、Range 请求、签名及恢复证明在忽略目录 `build/validation/android-4k60/`。本轮未修改产品播放代码或依赖，也未验证其他手机、HEVC／AV1／HDR、蓝牙音频、长时间发热／功耗或真实账号 CDN。后续 HEVC／AV1 8-bit／10-bit 的本地样片验证另见[编码对照记录](android-4k60-codecs-2026-11-05.md)，不回填为本轮已测范围。
