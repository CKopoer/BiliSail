# Windows 全屏弹幕：PiliPlus 硬解与渲染后端核对

日期：2026-11-01。基线为 `62a422f`，已经完成 [PiliPlus 依赖对齐](piliplus-dependencies-2026-11-01.md)。本轮只改变 Windows runner 的 Flutter 渲染后端，不再替换库、强制硬解模式或改变弹幕透明度／密度／Ticker。

## 源码与运行证据

只读参考 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441`：

- `lib/plugin/pl_player/models/hwdec_type.dart` 的桌面默认值是 `auto`；`storage_pref.dart` 读取用户保存值，`controller.dart` 将它交给 `VideoController.create`。因此默认配置不能证明每个视频都用 `d3d11va-copy`。
- `lib/pages/video/widgets/header_control.dart` 的“播放信息”读取 **`hwdec-current`**，这是确认实际解码器的依据。[mpv 文档](https://mpv.io/manual/stable/#command-interface-hwdec-current) 明确区分配置 `hwdec` 和运行中的 `hwdec-current`；`d3d11va-copy` 会将解码结果复制回系统内存。
- [Windows 入口](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/936072449e82e3d90c28c728c0087bf5136fa441/windows/runner/main.cpp#L30)明确调用 `set_impeller_switch(Disabled)`，该选择来自 `c92476e67`（2026-08-14）。本项目此前未设置开关，当前 Flutter 3.47.6 的运行日志确认启用了 **Impeller OpenGLESSDF**。
- PiliPlus 主要视频显示路径使用 `SimpleVideo`，本项目使用 `Video`；两者最终都是默认 `FilterQuality.low` 的 `Texture`。本轮保留已有 Video 的生命周期、字幕和会话边界，单独检验渲染后端。

本机已安装 PiliPlus `2.1.6+5472`。实播 `BV1jWxJ6UEdW`，确认全屏弹幕可见；自动化未能打开“播放信息”，**没有取得该进程的实际 hwdec 值**，不将源码默认值写成实测结论。安装目录与本项目 Release 的三份二进制 SHA-256 完全相同：

| 文件 | SHA-256 |
| --- | --- |
| libmpv-2.dll | `4b517ce76493c7d6b6568dde6e2839e3bb6a41c4b46b0e972492f354ad444ba4` |
| libEGL.dll | `b2590bd0692f0381fc45c20bf1c7f7f713c9ea19c7ea6bab62efdd1fadc4eaac` |
| libGLESv2.dll | `620bb6e38d7ed6c760a0cf4a8eb6a8f64b259b96ff286551cd32cefc6c35ca39` |

切换后本项目实读的硬解仍为 `d3d11va-copy`。原生日志中的 `GPU delivery: copied` 是视频输出纹理的 GPU 复制路径，与解码器的系统内存回读是两个环节。

本轮仅参考后端选择并独立调用 Flutter 公开 API，未导入 PiliPlus 的 GPLv3 控件或业务实现，未修改相邻参考仓库。

## 对照方法

使用现有 `tool/validation/windows_real_video_gpu_probe.dart` 和 `tool/test-windows-real-video-gpu.ps1`，运行真实 BiliApp／VideoScreen／PlaybackPanel、DASH 音视频和服务器弹幕。设置与凭据只在内存中使用；进度上报端口停用，不写用户设置、观看进度或账户互动。记录不包含签名 URL 或凭据。

- GPU：RTX 4070 Ti SUPER；Flutter 3.47.6／Dart 3.13.5，**Profile**。
- 视频：`BV1jWxJ6UEdW`，清晰度 80（1080P），AVC／AAC，同一 30–60 秒片段；每阶段预热 8 秒、采样 30 秒。
- 原用户弹幕样式保持一致，透明度固定 0.8。实际同屏均值约 1.8 条，属于较稀疏的真实弹幕，不能外推至高密度场景。
- 全屏视频输出及 Flutter surface 均为 1920×1080、DPR 1。普通页面输出为 896×504。
- 两份完整 bundle 的 `data/app.so` SHA-256 同为 `fd933113740f1d6c459b62c2dcd4310f8e9633843c6b041209bc82ba7c2ad1d7`，Flutter 引擎同为 `6ef56159a88686a05f0a70497c79607882644fcdb477ed9591a3acb8cb1a5e83`。只有 runner 的 Impeller 开关不同。
- 计划按 Impeller → Skia → Skia → Impeller 交叉复测，最终取得一轮 Impeller、两轮 Skia 的完整数据；反向基线受在线输入异常阻塞，不能描述成完整 AB/BA 验收。GPU Engine 按对应进程和完整采样区间筛选。频率和功耗来自 `nvidia-smi` 的整卡数据。

原始日志位于本机 `build/validation/windows-real-{label}.*`、`windows-real-playback-{label}.jsonl`、`windows-gpu-engine-{label}.jsonl`、`windows-real-clocks-{label}.csv`。汇总使用 `tool/validation/summarize_windows_real_video_gpu.py`；各 label 及完整指标随最终结果保存。

## 结果与验收

成功采样顺序为 `impeller_real_a_20261101`、`skia_real_a_20261101`、`skia_real_c_20261101`。下表均为全屏开弹幕的同一片段，完整普通／全屏、开关弹幕指标及 bundle 哈希见[机器可读汇总](data/windows-skia-playback-2026-11-01.json)。

| 后端／轮次 | 进程 3D 均值 | Dart 帧／秒 | raster P95 ms | GPU MHz 均值 | 整卡功耗 W |
| --- | ---: | ---: | ---: | ---: | ---: |
| Impeller A | 16.77% | 151.03 | 2.032 | 645.52 | 25.94 |
| Skia A | 5.45% | 151.10 | 0.948 | 482.14 | 22.13 |
| Skia C | 5.25% | 150.90 | 0.900 | 469.82 | 22.23 |

三轮全屏有／无弹幕阶段的视频掉帧和解码掉帧均为 0；全屏开弹幕最大 A/V 差绝对值为 1.003ms。同屏均值均为 1.8 条，未降低弹幕刷新率。Skia A 的普通页面有弹幕阶段出现过 1 个视频掉帧，其余成功阶段为 0，不能省略这一结果。

Skia 两轮较接近，3D 占用下降同时伴随 raster P95、平均频率及整卡功耗下降，支持保留该修复，不能将结果描述成同等比例的通用 GPU 效率提升。GPU 未锁频，整卡数据包含桌面和其他进程；Skia 有弹幕的占用低于其无弹幕占用，也不能据此推导弹幕不消耗 GPU。

`skia_real_b_20261101`、`impeller_real_b_20261101`、`impeller_real_c_20261101` 均在首次 seek 后等待恢复时失败，尚未进入采样。原生 HTTP 输入日志报告流提前结束、重连及包／NAL 损坏，两种后端均出现；未进一步归因于服务器或输入链路，不混入性能均值，也不为凑齐轮次无限重试。原始失败记录保留在 `build/validation`，汇总列出排除原因。先前 1024×576 的合成弹幕预探针不混入全屏结果，也不与历史 Predidit 构建计算收益。

`tool/check.ps1 -SkipPub` 通过：根应用 3908、bili_api 538、bili_player 121、bili_danmaku 153、bili_mux 5，共 4725 项通过；格式、分析及打包边界检查通过。根应用 13 项因 Windows 符号链接权限跳过，mux 原生 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，不计作原生封装通过。日志：`build/windows-skia-check.log`。

Windows 本机自动回归通过：`tool/test-windows-media.ps1` 33 项、`tool/test-windows-content.ps1` 4 项，以及 `windows_video_resize_test.dart` 1 项，共 38 项原生播放集成测试。缩放实测 `sameSurface=true`、`sameTexture=true`、`pixels=true`、`pausedAndPlaying=true`。`tool/test-windows-video-dispose.ps1` 的 9 项 C++ 生命周期／队列／尺寸回归通过。日志分别为 `build/windows-skia-media.log`、`windows-skia-content.log`、`windows-skia-resize-rerun.log`、`windows-skia-dispose.log`。

缩放用例第一次直接调用时漏设 `BILI_TEST_MEDIA_DIR`，在初始化断言处失败；补齐本地 fixture 目录后重跑成功，未修改产品代码或测试断言。此失败日志另保留为 `build/windows-skia-resize.log`。

普通 Windows Release 构建通过，原生集成测试结束后再次以 `lib/main.dart` 重建，入口为 `build/windows/x64/runner/Release/bilisail.exe`，须保留完整 Release 目录。最终日志为 `build/windows-skia-release-final.log`。本轮无 Dart 代码变更，原生后端开关通过重启引擎及本机集成测试验证，不依赖热重载。

本轮只验证 Windows。该对照用于判断本项目后端切换的影响，不等同于对 PiliPlus 与本项目全部播放实现的端到端比较；未验证其他 GPU、4K／HDR、高密度弹幕、直播、长期播放、Android 或 macOS。
