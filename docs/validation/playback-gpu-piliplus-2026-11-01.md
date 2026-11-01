# 播放 GPU 与 PiliPlus 对照

日期：2026-11-01。基线为本仓库 `7c6755e`，PiliPlus 只读检出为 `936072449e82e3d90c28c728c0087bf5136fa441`。本轮定位并修复播放控件的重复绘制，保留依赖、弹幕刷新率、字体效果、组透明度和用户设置。没有修改相邻仓库或 Pub 缓存。

## 来源与判断

| 项目 | BiliSail | PiliPlus 实际锁定来源 |
| --- | --- | --- |
| canvas_danmaku | Predidit `401915a11ae113cddb5409632cd99729f4b0a301` | bggRGjQaUbCoE `275046d8647a6a26cba1d0dadb9e28688cb3dbf1` |
| media-kit 核心 | Predidit `83b7ca63772856e1ea0158916177e136f7b7b0be` | My-Responsitories `73771ec38176be2d984a3049c28177bce23b54a0` |
| media-kit 视频 | 同一 Predidit 提交 | bggRGjQaUbCoE `fd8421d21eade4d6d12de137fa7df902fec20292` |

来源依据为两边当前清单、锁文件、解析后的源码，以及固定提交的 [PiliPlus 弹幕 painter](https://github.com/bggRGjQaUbCoE/canvas_danmaku/blob/275046d8647a6a26cba1d0dadb9e28688cb3dbf1/lib/base_danmaku_painter.dart)、[Predidit painter](https://github.com/Predidit/canvas_danmaku/blob/401915a11ae113cddb5409632cd99729f4b0a301/lib/base_danmaku_painter.dart) 和 [SimpleVideo](https://github.com/bggRGjQaUbCoE/media-kit/blob/fd8421d21eade4d6d12de137fa7df902fec20292/media_kit_video/lib/src/video/simple_video_texture.dart)。PiliPlus 应用为 GPLv3，只参考职责与行为；两个库的 MIT 许可分别处理，没有复制应用实现。

- 两边都缓存文字图片、随刷新率更新滚动弹幕，也都存在密集弹幕临时 Picture 路径。PiliPlus 的 SimpleVideo 仍使用双线性视频纹理采样，不能把简化 Widget 等同于原生合成或零复制。
- PiliPlus 的滚动 CustomPaint 标记 `willChange`，本项目此前没有。点播、直播补齐动态绘制提示；它不创建帧、不改变原有空闲停帧、暂停和 seek 行为。单独提示的本机结果只有小幅变化，不将其解释为主要 GPU 收益。
- PiliPlus [默认不透明度](../../../PiliPlus/lib/utils/storage_pref.dart)为 `1.0`，本项目 [默认值](../../lib/features/settings/domain/app_settings.dart)为 `0.8`。本项目使用整层 Opacity，文字图片效果留白与交错内容可能使绘制范围重叠，透明混合需要额外中间层。把不透明度设成 1 的诊断对照明显较轻，但修改用户设置或改成逐条 alpha 会改变现有重叠语义，因此没有采用。
- 未发现足以要求替换依赖的实测证据。另在忽略目录检出上述两份 media-kit 精确提交，解析最小播放器的依赖并尝试 Windows Profile 构建；上游固定 libmpv `mpv-dev-x86_64-20260607-git-43b14a4.7z` 未下载成功，预期 MD5 为 `b84900bbc6fcb995ca6a24f62bee671f`。CMake 正确拒绝了不匹配的下载；经系统／OpenSSL 下载重试仍在 GitHub 资产 TLS 连接处失败，未用其他二进制冒充该依赖。因此没有完整 PiliPlus 或原生分支的有效运行 A/B，不能排除所有平台、驱动或后端差异。已复现且由修复前后测试确认的问题属于本项目控件绘制链路。

## 控件重绘原因与修复

原来的 [播放面板](../../lib/features/playback/presentation/playback_panel.dart) 已将底部 HUD 与视频隔离，但进度条、时间文字没有进一步隔离。进度、缓冲和时间更新会让底栏渐变、按钮及同层文字重新录制。仅加 RepaintBoundary 仍不足够：进度 LayoutBuilder 的松宽约束会向上传播布局失效。

修复由两部分组成：

1. [进度组件](../../lib/features/playback/presentation/playback_timeline_bar.dart)拥有独立绘制边界，父层按真实章节／高能曲线高度给出固定宽高。高能数据到达、宽度跨过 600、章节和时长改变仍重新计算高度；进度和缓冲更新保留在边界内。
2. 时间文字复用已有排版测量取得宽高，固定布局并独立绘制。渐变、按钮与字幕的位置和交互保持原样。

新增普通／全屏回归捕获底栏静态 Picture 的身份；连续 12 次位置及缓冲变化后，时间和进度继续更新、静态内容保持原 Picture。两项测试在原始实现上失败，在最终实现上通过。原有进度拖动、seek 确认、触摸预览、字幕避让与响应式控件测试一并执行。

## Windows Profile 方法

使用 [本地探针](../../tool/validation/playback_gpu_comparison_probe.dart)挂载生产 PlaybackPanel、PlaybackSession、MediaKitEngine 和 DanmakuOverlay。仓储只返回本地合成 H.264/AAC 文件与合成文字；不读取账号、用户数据库，不写用户设置。实际解码为 `d3d11va`，素材 1920×1080、60fps，音量 0。

每次先预热纯视频 4 秒，采样 15 秒，再 seek 至 10 秒、预热弹幕 5 秒，采样弹幕 15 秒，最后显示控件并采样 15 秒。输入每秒 20 条，字号 25、75% 区域、不透明度 0.8；显示控件时预留底部空间，因此可见弹幕数略少。每种实现使用同一探针、素材和阶段。

请求播放器区域 960×540，早期桌面工作区将窗口压窄，原生输出为 **448×252**，后续出现 **960×540** 输出。按实际输出尺寸及可见数量分别比较；`fixed-b` 的 960×540 结果没有与此前 448×252 原版相除计算收益。之后补跑相邻原版 `before-d` 与修复版 `fixed-c`，两者均为 960×540。Computer Use 检查确认早期窗口可见、视频与弹幕显示。GPU 为 RTX 4070 Ti SUPER，Flutter 3.47.6 / Dart 3.13.5，Impeller OpenGLES。GPU 未锁频，另采 `nvidia-smi` 的频率／功耗，进程 GPU Engine 与整卡数据分别保留；这些百分比不能外推至其他 GPU 或全屏。

原始 JSONL、频率 CSV、完整 AOT bundle、实验 painter 和修复前失败日志保存在忽略目录 `build/validation/` 与 `build/gpu-*.log`。脱敏汇总见 [数据](data/playback-gpu-piliplus-2026-11-01.json)。

对照依次包含：原实现两轮；只去掉临时 Picture；再改用 PiliPlus painter 的最近邻文字采样方式；仅将不透明度设为 1；仅增加动态绘制提示；最终修复、原实现、最终修复的串行复测。实验修改只存在于保存的测试 bundle，生产渲染器保持原来的图片采样与批处理。

```powershell
flutter build windows --profile --no-pub -t tool/validation/playback_gpu_comparison_probe.dart
# 保存整个 Profile 目录后执行，标签必须唯一。
.\tool\test-windows-gpu-playback.ps1 -Label <label> -Seconds 15 `
  -ExePath <保存的完整bundle>/bilisail.exe -MediaPath <本地1080p60素材>
```

## 结果与验收边界

448×252 诊断组（同一视频、同一密度；GPU 为进程 3D 引擎均值）：

| 实现／设置 | 仅弹幕 GPU % | 有控件 GPU % | 有控件 raster 均值 µs |
| --- | ---: | ---: | ---: |
| 原版 `before-b` | 6.77 | 7.76 | 630 |
| 去掉临时 Picture | 6.56 | 7.79 | 626 |
| 再用最近邻文字采样 | 6.41 | 7.50 | 611 |
| 原版，仅不透明度改为 1 | 4.88 | 6.49 | 543 |
| 仅动态绘制提示 | 6.43 | 7.56 | 613 |
| 最终修复 `fixed-a` | 6.21 | 7.63 | 614 |
| 随后复测原版 `before-c` | 6.01 | 7.48 | 614 |

库内 Picture 批处理和采样差异没有复现“高不少”的主要差距。相同默认组透明度下，最终修复与原版的 GPU 结果有波动，不能认定稳定下降；因此没有为小幅变化改变采样质量或替换库。不透明度 1 的诊断减少了合成负担，但不作为产品修复的收益。

960×540 相邻复测：

| 场景 | 指标 | 原版 `before-d` | 修复版 `fixed-c` |
| --- | --- | ---: | ---: |
| 纯视频 | GPU % | 2.77 | 2.72 |
| 弹幕 | GPU % | 9.61 | 9.60 |
| 弹幕 | UI 均值 µs | 194 | 172 |
| 弹幕 | raster 均值 µs | 619 | 562 |
| 弹幕＋控件 | GPU % | 12.30 | 12.11 |
| 弹幕＋控件 | UI 均值／P95 µs | 219／530 | 192／443 |
| 弹幕＋控件 | raster 均值／P95 µs | 818／1346 | 804／1340 |

两边弹幕阶段同屏均值均为 30.73，有控件阶段均为 27.53，帧率约 164～165；所有采样的硬解均为 `d3d11va`，视频／解码掉帧计数均为 0。960×540 控件阶段整卡核心频率均值为 284 → 290 MHz，GPU 占用差只有约 0.19 个百分点，不能单凭该比例声称显著 GPU 提升。结构测试确认了重复静态绘制已经移除；端到端结果主要体现为 UI 工作量减少，合成像素量与高刷成本仍存在。

- `tool/check.ps1 -SkipPub` 通过：根应用 3907、API 538、播放器 115、弹幕 145、mux 5，共 **4710 项通过**。根应用 13 项沿用条件跳过，mux 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。
- 新增普通／全屏 Picture 保留回归，以及两种宽度下章节、高能曲线和无曲线的高度回归；修复前的两项 Picture 回归失败、修复后通过。最终格式、静态分析、打包边界与既有离线行为测试通过。
- Windows Profile 构建及受控本地视频＋弹幕＋控件运行完成；另以正常 Windows binding 启动 Debug 夹具，热重载成功，Dart 工具未发现运行时错误，夹具正常结束。Debug 帧耗时没有参与上述性能表。最后的 `tool/check.ps1 -Stage Lint -SkipPub` 再次通过，文档相对链接与 `git diff --check` 通过。

本轮没有修改解码、DASH 协议、原生纹理交付、库提交或持久化格式。没有连接的 Android 设备；Android/macOS 实机、PiliPlus 整应用同机对照、真实账号／网络、全屏高分辨率及长时间播放仍未验收。修复的是已复现的额外开销，不能宣称所有设备上与 PiliPlus 的 GPU 差距已经消失。
