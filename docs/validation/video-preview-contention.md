# 悬停预览与主视频出帧争用

日期：2026-10-08。播放页相关推荐沿用共享悬停预览；主视频和预览继续使用 GPU 渲染。

## 原因与修复

锁定的 `media_kit_video 2.0.1` 在 Windows 上使用一条线程串行执行各播放器的 ANGLE 创建、尺寸检查和渲染。预览的 `CheckAndResize` 调用 `GetVideoWidth/GetVideoHeight`，在渲染线程同步执行 `mpv_get_property("video-out-params")`。启动时 mpv 核心可能正在等待渲染线程完成工作；同步查询反过来等待核心，触发约 200 毫秒的超时等待，并阻塞同队列上的主视频。

[mpv 官方 render API 的线程约束](https://github.com/mpv-player/mpv/blob/master/include/mpv/render.h) 要求渲染线程避免调用普通核心 API，并说明违反约束会产生通过超时解除的等待和播放质量下降。本地 Profile 记录直接观察到每次预览的尺寸检查耗时 200–201 毫秒，主视频在同一时间出现 206–226 毫秒出帧间隔；播放位置仍推进、没有 buffering。因此仅检查播放 phase、位置或 Flutter FrameTiming 无法发现这次纹理出帧停顿。

Windows 构建补丁改为直接使用 `NativeVideoController` 已通过 `SetSize` 发送的显示尺寸。这些尺寸已包含像素宽高比及旋转处理。首次尺寸未知时保留占位纹理；尺寸事件到达后，在原渲染队列立即检查尺寸并绘制，覆盖首帧、暂停和尺寸变化，不再向 mpv 核心同步查询。此前的纹理注销和渲染上下文释放顺序继续生效。

实现见 [尺寸方法](../../windows/patches/media_kit_video/video_output_dimensions.inc) 和 [CMake 补丁入口](../../windows/patches/media_kit_video/apply.cmake)。源代码仍只复制到构建目录，保留五个锁定上游文件的 SHA-256 校验与 MIT 许可；不修改共享 Pub 缓存。主应用及 `PlayerEngine` 契约无需变化。

## 方案选择

采用保留 GPU、修正渲染线程调用的方案。软件渲染绕开共享 GPU 队列需要额外线程，还增加 CPU 解码、像素转换与上传成本；使用同样的同步尺寸查询时仍会触发 mpv 的等待。直接移除该查询能修复原因，也保持现有 GPU、解码设置和预览生命周期。

## 可复现的 Profile 对照

运行 `pwsh -File tool/test-video-preview-contention.ps1 -Label current`。脚本生成 720P/60fps 带音轨主视频和 480P/30fps 无音轨预览，启动真实 Flutter binding，连续打开并释放四次预览。素材仅使用本地文件，无账号、API 或公网请求。

`BILISAIL_VIDEO_RENDER_TRACE=1` 只在这个构建中加入原生操作耗时与出帧间隔计数，前四次渲染通知不计入间隔峰值，以排除主视频自身的启动过程。原生计数衡量渲染调用间隔，并非显示器最终呈现时间或视频 dropped-frame 计数。脚本结束后恢复环境并重新配置 CMake，普通构建不包含逐帧诊断代码。

| Windows Profile 本地对照 | 修复前 | 保留 GPU 的修复后 |
| --- | --- | --- |
| 主视频最大渲染调用间隔 | 226 ms | 52–55 ms |
| 预览尺寸检查的重复长等待 | 200–201 ms | 无超过 40 ms 的记录 |
| 主视频正常播放、未缓冲、音轨已解码 | 4/4 | 4/4 |
| 预览首帧就绪、无解码音轨 | 4/4 | 4/4 |

对照日志和 JSON 位于 `build/validation/video-preview-contention-gpu-diagnosis.*`、`video-preview-contention-gpu-fixed.*` 与 `video-preview-contention-gpu-final.*`。首次修复后最大间隔为 55 ms，最终探针为 52 ms、预览打开耗时 103–120 ms，五个输出均确认使用硬件渲染。仍有 GPU 上下文创建开销，不能承诺所有显卡和负载下完全没有出帧波动。

## 检查与边界

- `tool/test-windows-video-dispose.ps1` 的 5 项原生测试通过；包括旧纹理回调、队列排空、软件输出、缺失输出和尺寸事件。尺寸测试直接编译生产方法体，且不提供 `mpv_get_property` 声明，防止重新引入同步核心查询。
- `tool/check.ps1 -SkipPub` 完成：根应用及三个包格式／分析通过，根应用 1378、API 325、播放器 32、弹幕 65，共 1800 项测试通过。日志 `build/preview-contention-check.log`。这是当时工作区快照的检查结果，提交仅包含本次修复文件。
- Windows 原生回归通过：5 秒预览滚动缓冲 1 项，DASH 分轨（headers／redirect／Range／seek／生命周期）与多播放器并发 2 项，HTTP 403 脱敏诊断 1 项。日志分别为 `build/preview-contention-native-preview.log`、`preview-contention-native-playback.log`、`preview-contention-native-diagnostics.log`。
- 正常入口 `flutter build windows --release --no-pub` 已通过，日志 `build/preview-contention-release.log`；生成副本确认不包含 Profile 逐帧诊断代码。
- 对照为本机 Windows Profile 及本地素材，不代表真实推荐 API/CDN、其他显卡、MSIX 安装、Android/macOS 或长时间播放验收。
