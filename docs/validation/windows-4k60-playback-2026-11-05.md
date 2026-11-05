# Windows 公开 4K60 素材：播放、弹幕与控件性能

日期：2026-11-05。源码基线 `55601c393ea093ebe65c2759ac607f51df6206ec`，开始时工作区干净。本轮新增离线探针、采样及汇总工具，不改产品播放器、弹幕、依赖、原生补丁或用户设置。

## 素材与复现

使用 Blender Foundation 的 **Big Buck Bunny Sunflower 2160p / 60fps / normal**，从[官方公开目录](https://download.blender.org/demo/movies/BBB/)下载，[ZIP 直链](https://download.blender.org/demo/movies/BBB/bbb_sunflower_2160p_60fps_normal.mp4.zip)。不经过 Bilibili、不需要登录或会员，也不接入用户账号。项目的[许可说明](https://peach.blender.org/about/)为 CC BY 3.0；归属：© 2008 Blender Foundation / www.bigbuckbunny.org。测试素材不提交 Git，保留完整片尾署名。

`ffprobe` 实读：3840×2160、`60/1` fps、H.264 High Level 5.1、8-bit `yuv420p`，视频平均约 8.00Mbps；容器时长 634.567 秒，含 MP3 双声道与 AC-3 六声道音轨。播放器实际验证音频已解码，音量设为 0，保留正常音视频时钟。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| 官方 ZIP | 671868845 | `8f1d53cf56a314be08206ae730546ef26db9fd0114b33ff2528f522bc3714d19` |
| 解压 MP4 | 673223862 | `35db9a007021f1b0066993e1d2c4448c83a8b279f799c97d33cbba73980a8a36` |

本机文件位于 `build/validation/4k60/bbb_sunflower_2160p_60fps_normal.mp4`，`media.ffprobe.json` 保存完整媒体参数。

```powershell
flutter build windows --profile --no-pub -t tool/validation/windows_4k60_probe.dart
./tool/test-windows-4k60.ps1 -Label sparse_a -MediaPath build/validation/4k60/bbb_sunflower_2160p_60fps_normal.mp4 -Arrivals 2
./tool/test-windows-4k60.ps1 -Label dense_a -MediaPath build/validation/4k60/bbb_sunflower_2160p_60fps_normal.mp4 -Arrivals 20
./tool/test-windows-4k60.ps1 -Label dense_b -MediaPath build/validation/4k60/bbb_sunflower_2160p_60fps_normal.mp4 -Arrivals 20 -Reverse
python tool/validation/summarize_windows_4k60.py sparse_a dense_a dense_b
```

每次使用新 label。探针使用[生产 PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart)、`PlaybackSession`、`MediaKitEngine`、`VideoSurface` 及生产弹幕绘制，只把源解析、弹幕来源和进度存储替换为本地夹具／空上报端口。没有加载正式账号或数据库。

## 条件与采样口径

- Windows，Ryzen 7 7700（8 核 16 线程）、RTX 4070 Ti SUPER，NVIDIA 617.42；Flutter 3.47.6 / Dart 3.13.5，**Profile**，沿用现行 Skia 后端。
- 实际解码 `d3d11va`，解码尺寸 3840×2160；全屏视频输出与 Flutter surface 均为 1920×1080，DPR 1。**这是 4K 解码、1080p 输出，不是 4K 显示器上的原生 4K 合成。**
- Win32_VideoController 报告物理显示模式 1920×1080 / 165Hz，但本轮 Flutter Display API 报告 60Hz，采样 Flutter 帧数也约 60fps。保留两项原始证据，不用硬件标称值冒充实际合成速率，也不据此断言高刷渲染性能。
- 四阶段：视频（控件隐藏、弹幕关闭）、仅控件、仅弹幕、弹幕＋控件。每阶段重新 seek 到 37 秒，播放预热 8 秒后取相同的约 45–75 秒片段，稳态采样 30 秒。密集场景另反向执行，以检查顺序及频率漂移。
- 弹幕每秒 2／20 条，80% 滚动、20% 顶／底固定，默认系统字体、25px、shadow、透明度 0.8、区域 0.75，使用互不相同的中文文字；不改变刷新 Ticker。记录实际同屏条数及缓存统计。
- 沿用[控制器](../../packages/bili_danmaku/lib/src/danmaku_controller.dart)默认上限：同屏 120 条、待处理 500 条、文字布局 256 项。密集测试触及同屏上限；不是所有注入消息都能显示。`droppedComments` 包括重复更新窗口时的超限裁剪和入轨拒绝，是控制器累计工作计数，不能当作唯一弹幕丢失数，更不能当作视频掉帧。
- 控件通过生产点击入口展开，沿用生产 hover 保持逻辑，逐秒断言实际 `FadeTransition`／`IgnorePointer` 可见状态。原有 GPU 探针点击后可能自动隐藏，故不能直接用它的整个 controls 阶段代表持续显示控件。
- Flutter FrameTiming 的 UI/raster 与原生 mpv 视频输出／解码掉帧分别记录。掉帧使用预热结束至采样结束的**增量**；[mpv 属性说明](https://mpv.io/manual/stable/#command-interface-frame-drop-count)不等于显示器逐帧呈现验证。
- FrameTiming 的 raster 是 Flutter raster 线程计时，不等同于 GPU 全部工作或最终呈现耗时。UI/raster 超预算计数只比较线程工作量，不能据此保证端到端显示延迟或更高刷新率下的表现。
- GPU Engine 使用一条连续 PDH query，同时保存目标 PID、DWM 与整个物理 engine；只计入前后两个时间点完整落在阶段内的区间。CPU 以一个逻辑核满载为 100%，换算任务管理器全机占用需除以 16。整卡时钟／功耗来自 `nvidia-smi`，未锁频，也未把整卡其他进程负载归给应用。
- 正式采样期间没有同时运行构建、测试或截图。两轮短预检包含截图和后台自动检查，均排除在正式汇总外。首轮预检在进程退出、GPU 实例消失时触发 PDH 错误；采样器已改为跳过无效计数并由汇总检查有效覆盖率，第二轮验证正常退出。

## 结果

正式 label 为 `sparse_a_20261105`、`dense_a_20261105`、`dense_b_20261105`；后一轮顺序反转。三轮使用相同 Profile bundle，`data/app.so` SHA-256 均为 `2fd754c81e3f7d03c565b9dcd7d4c4fe05218a1a53489d20fc8746e40fecf459`。共 12 阶段、360.010 秒稳态数据、21593 个 Flutter FrameTiming、335 个完整阶段内 PDH 区间。完整指标见[机器可读汇总](data/windows-4k60-playback-2026-11-05.json)。

下表每行均采样 30 秒；密集场景列出两轮范围，范围表示两轮各自的阶段统计值，不把两个 P95 再平均成一个分位数。3D 是应用 PID 的 engine 占用。

| 弹幕输入／场景 | 实际同屏均值 | 进程 3D 均值 | UI P95 ms | raster P95 ms |
| --- | ---: | ---: | ---: | ---: |
| 稀疏轮：视频 | 0 | 0.67% | 0.189 | 0.392 |
| 稀疏轮：仅控件 | 0 | 0.67% | 0.254 | 0.559 |
| 2 条／秒：仅弹幕 | 14.4 | 0.80% | 0.268 | 0.563 |
| 2 条／秒：弹幕＋控件 | 14.4 | 1.10% | 0.328 | 0.724 |
| 密集轮：视频 | 0 | 0.83–1.09% | 0.180–0.182 | 0.385–0.395 |
| 密集轮：仅控件 | 0 | 0.63–1.20% | 0.249–0.258 | 0.535–0.568 |
| 20 条／秒：仅弹幕 | 119.9 | 1.93–2.21% | 0.587–0.606 | 1.051–1.184 |
| 20 条／秒：弹幕＋控件 | 117.1–117.3 | 1.64–1.92% | 0.629–0.642 | 1.161–1.166 |

所有正式阶段的实际解码器均为 `d3d11va`，音视频解码正常，无缓冲、seek 状态或 Flutter 错误；mpv 视频输出掉帧和解码掉帧增量均为 **0**。播放位置按墙钟约 1.000× 推进，没有慢放证据。最大上报音画时钟差绝对值为 **1.234ms**；这是后端时钟指标，不替代扬声器／显示器的人工同步验收。

Flutter 采样帧率为 59.8–60.2fps。所有采样 UI/raster 线程耗时均未超过 16.67ms，最高 raster 为 4.251ms；密集弹幕＋控件的 raster P99 为 1.303–1.378ms。即使线程耗时也均未超过 6.06ms，仍不能由此宣称已完成 165fps 的真实呈现测试。

三轮视频解码 engine 的阶段均值为 43.55–46.41%；应用 CPU 折合整机 16 逻辑线程为约 0.86–1.53%。密集弹幕＋控件的 CPU 为单核 22.6–24.6%，折合整机 1.41–1.53%。工作集峰值约 636MiB；该短测不能证明长期内存稳定性。

密集弹幕稳态图片缓存命中率约 99.73%，没有直接绘制回退，采样期文字栅格缓存峰值约 19.12MiB，低于 32MiB 的缓存预算。反向轮次从带弹幕阶段开始，仍得到相近的缓存命中率及 raster P95，不依赖先跑一次相同片段的缓存预热。

GPU 未锁频：各阶段核心频率均值约 1479–1778MHz、整卡功耗约 24.4–26.0W。DWM 3D 均值约 0.31–0.51%，对应整物理 3D engine 均值约 1.01–2.53%。两轮均出现“带控件的 3D 低于仅弹幕”，但控件会改变弹幕可用底部区域和实际同屏数量，且 GPU 频率／提交调度有波动，**不能据此声称显示控件降低了 GPU 成本**。

## 瓶颈判断

**本机在当前 60fps 合成、4K60 AVC 解码／1080p 全屏输出和默认弹幕上限下，没有发现限制正常播放的 CPU、解码或合成瓶颈。** 结论以稳态片段为范围，不是其他机器、其他编码或无限弹幕密度的保证。

1. **解码和视频交付未被弹幕拖慢。** 实际为 `d3d11va`，稳态掉帧增量为零，解码 engine 负载没有随弹幕／控件显著增加。原生日志的 `GPU delivery: copied` 是输出纹理交付路径，不应当作 `d3d11va-copy` 的 CPU 回读证据。
2. **最明显的叠加成本在 Flutter 绘制。** 仅控件将 raster P95 从约 0.39ms 提高到 0.54–0.57ms；密集弹幕加控件约 1.16ms。当前仍有明显线程预算余量。高缓存命中、零直接绘制回退说明没有观察到文字栅格缓存失效风暴；从源码看，[滚动／固定绘制层](../../packages/bili_danmaku/lib/src/danmaku_layers.dart)及[整组透明度](../../lib/features/playback/presentation/playback_panel.dart)仍参与合成。图片绘制／透明合成是进一步排查弱 GPU 时的候选，现有计数没有分离它们各自的 GPU 耗时，不能定量认定某一项就是瓶颈。
3. **密度先遇到容量保护。** 密集场景最高 120 条同屏，待处理队列保持在 500 条以内。性能结果包含了正常限流与入轨拒绝的收益；要评价超过这一数量的绘制能力，必须另做明确的压力配置，不能拿每秒输入数代替全部绘制数。本轮保留产品限制，没有为追求压力数字修改其策略。
4. **当前证据不支持立即改播放器或降低弹幕刷新率。** 更值得补充的条件是原生 4K 输出、确认实际高刷呈现、其他显卡以及 HEVC/AV1/HDR；这些条件可能暴露本轮没有覆盖的像素填充、互操作或解码能力边界。

## 自动检查与边界

- `dart format` 与专用探针 `dart analyze --fatal-infos` 通过；Debug 探针热重载成功。Debug 数据不用于性能结论。
- `tool/check.ps1 -SkipPub` 的格式、分析和打包边界检查通过；根测试 4176 项通过、13 项跳过、1 项失败。失败为未修改的 `test/features/settings/font_selection_test.dart:125`，`appearance saves bundled and installed fonts independently` 期望 `HarmonyOS Sans`、实际 null。单独重跑同样失败，未改无关字体代码以凑通过。
- 补跑 `tool/check.ps1 -SkipPub -Stage PackageTests`：`bili_api` 586、`bili_player` 148、`bili_danmaku` 161、`bili_mux` 5，共 900 项通过。`BILI_MUX_LIBRARY` 未配置，10 项原生封装测试跳过，不算原生覆盖。
- 本轮不是产品功能或原生释放修改，不重跑所有历史原生脚本。实际 Windows Profile 生产面板采样、音视频解码与播放状态断言是本轮的原生运行证据。普通 `lib/main.dart` Release 目录未被替换成探针。
- 测试限定于此机器、本地 AVC 8-bit 文件、默认样式合成弹幕、正常倍速与持续可见控件。未覆盖 HEVC/AV1、HDR/Main10、高码率、网络 DASH、真实服务器弹幕、seek/清晰度切换期间的卡顿、复杂控件交互、长期播放、其他显卡／驱动和其他平台。

原始本地记录：`build/validation/4k60/{label}.{playback.jsonl,counters.jsonl,fixture.json,clocks.csv,stdout.log,stderr.log}`，构建／检查日志亦在该目录。各 bundle 哈希随 fixture 保存，libmpv SHA-256 为现行清单中的 `222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`。
