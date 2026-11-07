# Android 解码直出纹理与 SurfaceView 对照

日期：2026-11-07。范围：Android 的 media_kit／libmpv、fvp／MDK 增加可选解码直出 Surface，继续由 Flutter 纹理与现有弹幕、字幕、控件合成；另以独立原型评估 SurfaceView 的 HC／HCPP。默认仍为兼容渲染，SurfaceView 未作为产品设置开放。

同日后续修正 fvp 直出打开时空纹理消费被误认作首帧的竞态，详见[启动黑屏修复](android-fvp-direct-black-2026-11-07.md)。本页性能数据属于修复前版本，没有重新测量。

## 使用与实现

「设置 → 播放 → 视频编解码 → Android 视频输出」可选择「兼容渲染（默认）」或「解码直出纹理（实验）」。播放后端仍独立选择 media_kit／fvp；保存成功后，下次打开或重新加载源生效，保存失败回退。缺失／非法值、恢复默认均使用兼容渲染，有效旧设置保留。设置快照升为 42，不修改数据库表版本。该设置用于视频／影视／直播／离线播放会话；悬停预览继续沿用兼容输出。

- mpv：自动解码时选择 `mediacodec_embed`，仍绑定现有 SurfaceTexture。软件解码保留 GPU 输出；已有杜比视界 hook 继续优先选择 `gpu-next`。
- fvp：通过固定 fvp 提交的 Surface 桥启用直接解码输出；保留独立 worker、外部音轨、源代次及释放屏障。软件解码及已识别 HDR 色彩空间沿用原渲染路径。直出仅在实际纹理帧被 Flutter 消费后确认首帧，不依赖被绕过的 MDK GL 渲染回调。seek 前补充非阻塞的原生暂停确认，仍受原有取消和 deadline 约束。
- 解码直出继续使用 Flutter Texture，现有弹幕、B 站字幕、控件、手势与会话时钟不迁移到原生。视频、音频仍由同一个后端同步，不创建第二路音频。
- 实验模式要求可用的硬解输出。自动硬解失败、特殊格式或色彩异常时，应切回兼容模式；不把失败伪装为已成功直出。本轮设备性能仅验证 SDR H.264。

能力依据：[fvp 直出选项](https://pub.dev/documentation/fvp/latest/fvp/registerWith.html)、[mpv mediacodec_embed](https://mpv.io/manual/master/#video-output-drivers-mediacodec-embed)。原生内置字幕／OSD 的限制不等于 Flutter 前景不可叠加。

## 实机与素材

- Xiaomi 13／2211133C，Snapdragon 8 Gen 2，Android 16／API 36；横屏 2400×1080，Impeller Vulkan，显示目标 120 Hz。
- Flutter 3.47.6／Dart 3.13.5；Profile／AOT 测量，Debug 不参与性能结论。media-kit 固定 `9abd8a56f24371fd8c9628b70eba5e84c29e86c8`，fvp 固定 `e81637411c58a9ae28de246ee73ad06e3418f10e`，MDK 0.39.0。
- 公开 [Big Buck Bunny Sunflower](https://download.blender.org/demo/movies/BBB/bbb_sunflower_2160p_60fps_normal.mp4.zip)，© 2008 Blender Foundation／www.bigbuckbunny.org，[CC BY 3.0](https://peach.blender.org/about/)。取约 25–45 秒片段，循环编码为 180 秒 H.264 High、3840×2160、60 fps、yuv420p／BT.709，实际视频码率 **24,981,946 bit/s**，独立 AAC 音轨。所有模式使用同一对本地文件，手机与主机 SHA-256 相同。
- 视频 SHA-256：`378fd9df3f23e78e78a61dded68a1903246515ccdf31f00102cdce348673172d`。
- 固定 3×、音量 0（保留音频解码和时钟）、普通缓存窗口 120 秒、真实播放面板全屏、20 条／媒体秒弹幕、两媒体秒一条 Flutter 字幕，控件持续显示。每场预热约 8 秒，正式测量 20 秒；纹理四组正序后反序复测，传统 SurfaceView 两组正反序复测。

读取应用 UID 的 Perfetto CPU 时间，包含 fvp 独立 worker；100% 表示一个 CPU 核心。GPU 为整机 KGSL 忙碌比例，不是应用独占 GPU 或功耗。Flutter 帧率来自 FrameTiming，**不是实际独立视频帧率**。屏幕最终合成层另有采样，但纹理场景是 Flutter 层、SurfaceView 场景可能是视频层，不能直接当作同一 FPS 指标比较。CPU 追踪覆盖率至少 99.96%。未锁定 CPU／GPU 频率。

## 结果

下表为相同场景的两轮范围，CPU 同时计入 UI 与 fvp worker。各完成窗口均维持约 3.003× 媒体推进，窗口内无缓冲／Flutter 异常，字幕、控件持续存在，屏幕弹幕至少 21 条。逐场数据见[脱敏结果](data/android-surface-output-2026-11-07.json)。

| 后端与呈现 | CPU（单核 100%） | 整机 GPU 忙碌 | Flutter 帧率 | raster P95 |
| --- | ---: | ---: | ---: | ---: |
| mpv 兼容纹理 | 133–158% | 64–74% | 87–120 fps | 8.83–11.70 ms |
| mpv 解码直出纹理 | 118–131% | 55–71% | 89–116 fps | 9.41–11.36 ms |
| fvp 兼容纹理 | 117–137% | 61–82% | 89–113 fps | 10.19–11.52 ms |
| fvp 解码直出纹理 | 103–103% | 66–66% | 120–121 fps | 8.00–8.04 ms |
| mpv SurfaceView／HC | 131–140% | 35–47% | 44–58 fps | 19.16–19.52 ms |
| fvp SurfaceView／HC | 128–129% | 35–35% | 44–44 fps | 19.98–20.04 ms |

按两轮 CPU 均值，mpv 解码直出纹理约降低 14%，fvp 约降低 19%。fvp 直出纹理的 Flutter 叠加帧率最稳定；mpv 没有建立相同程度的帧率收益。GPU 百分比随实际合成帧率与频率调度变化，不能把范围或均值直接换算成耗电改善，也不能宣称 fvp 在所有设备上一定更快。

## SurfaceView 原型与 HCPP

原型只在 `.test` 应用注册，通过现有 `VideoCompositionAdapter` 替换视频呈现。先在纹理路径完成准备、seek，再暂停并交接解码输出到 SurfaceView；测量前恢复播放并预热。前景仍使用真实 Flutter 弹幕、字幕和控件；保持 16:9 显示区域，退出先关闭 engine，再卸载视图／释放 JNI Surface 引用。未向产品设置暴露该原型。

传统 HC 确实降低了本场景的 GPU 忙碌比例，但 Flutter 叠加仅约 44–58 fps，CPU 也高于 fvp 直出纹理，不作为默认方案。

HCPP 通过测试构建临时 manifest 启用，并从 `PlatformViewsController2.isHcppEnabled` 确认实际为 true；源 manifest 在构建后恢复。Flutter 要求 Android API 34+、Impeller Vulkan，仍属实验功能，见[官方说明](https://docs.flutter.dev/platform-integration/android/platform-views)。

首轮固定 4K Surface 在 HCPP 中出现画面缩到左上角的问题，改用随布局的 Surface 尺寸后恢复正确比例。随后完整追踪的单轮结果为：mpv CPU 171%／GPU 78%／Flutter 114 fps，fvp CPU 144%／GPU 68%／Flutter 84 fps。复测第二次打开 fvp 时，worker 在进入测量前原生崩溃：Android 退出记录为 `APP CRASH(NATIVE)`、status 11（20:08:02），UI 进程仍存活。该结果只能说明当前原型存在生命周期／兼容性问题，不能据此断定某个 SDK 或 GPU 是唯一原因，也不作 HCPP 稳定性通过或性能优势结论。HCPP 的追踪数据量明显更大，仪器开销也未被独立排除。

## 验证与复现

```powershell
./tool/check.ps1 -SkipPub
# 先在独立目录保留普通入口开发 Release；ConfigPath 为受控本地样片场景列表。
./tool/test-android-surface.ps1 -DeviceId <device> -ConfigPath <config.json> -Label <fresh-label>
# 仅评估受支持设备的 HCPP；普通入口恢复包仍不启用 HCPP。
./tool/test-android-surface.ps1 -DeviceId <device> -ConfigPath <config.json> -Label <fresh-label> -EnableHcpp
python tool/validation/summarize_android_surface.py <run-folder> --trace-processor <trace_processor_shell.exe> --output <summary.json>
```

完整根检查通过：根应用 4600（13 跳过）、bili_api 678、bili_player 225、bili_danmaku 161、bili_mux 5。`BILI_MUX_LIBRARY` 未配置，10 项 mux 原生用例跳过，不计为原生通过。后续 Android 暂停时序改动另通过 30 项播放器定向测试；新增设置 UI 保存／回退、迁移／默认值等 4 项通过；HTTP Range 3 项及追踪退出屏障 3 项通过。普通入口 Android Release、Profile 探针、普通入口 Debug 构建通过，普通入口 Debug 热重载成功、无运行时错误。

上述全套检查完成后，最终 `-Stage Lint` 复查被同期修改的 `test/core/platform/mini_player_window_service_test.dart` 格式问题阻塞。本任务未修改该文件；本任务文件另行执行定向格式／静态分析。该最终复查不记为全量通过。

采样过程中修正了探针的 HTTP Content-Length、控件可见性等待和 APK 版本参数。Perfetto 原先停止后固定等待 400 ms，部分 HCPP 文件仍在写入，CPU 样本不完整；现等待追踪进程退出／进入 zombie 后再拉取，超时明确失败。无完整窗口的场次和画面尺寸错误的场次不进入正式表；失败／排除列表保留在结果 JSON。

本机已安装测试包版本码为 12801。为保持覆盖安装及数据，只在隔离目录采用本地开发版本 `1.2.8+1`；仓库版本仍为 `1.2.8+0`。全过程使用 `dev.bilisail.bilisail.test` 和已有开发证书，无卸载、清数据、正式包操作或签名更换。测试后恢复普通入口 Release，未留下测试 fixture。

最终普通入口 Release 为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256 `b6fd29c95fe4fa687de04dc5661b7bdd397ca8d74ded42683c352f2cf7a7b776`。从设备拉回的最终 APK 摘要一致；不可调试、开发签名与测试身份校验通过。设备上的两份临时媒体已清理，主机样片及原始结果保留；复现前需重新将样片推送到场景配置指定的测试包目录。

原始场景、APK 身份、截图、GPU 采样、Perfetto 与恢复摘要保存在忽略目录 `build/validation/android-surface/`。本轮没有验证其他机型、HDR／杜比、软件解码的实机画面、长期温升／功耗、物理音画同步、在线 CDN、后台／PiP 或 SurfaceView 的完整手势与页面生命周期。fvp 原生掉帧和独立外部音轨时钟持续读数不可用，保持缺失值，不能填零或当作同步通过。
