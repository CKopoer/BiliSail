# Windows 视频信息切换与窗口缩放闪黑

日期：2026-10-30。

## 原因与修复

视频信息区显隐和窗口缩放会更新 `VideoSurface` 的物理视口上限。Windows 原生输出按上限调整纹理尺寸；媒体源和 engine 并不需要重开。固定的 Predidit media-kit `83b7ca63772856e1ea0158916177e136f7b7b0be` 的 `VideoOutput::Resize` 会先注销原 Flutter 纹理再创建新纹理，导致 Flutter 仍引用旧 ID 的短暂空窗。

同时，mailbox 重分配将 completed 槽重置到尚未绘制的纹理，第一次 `ProducerCommit` 只提交 pending 槽，要下一次提交才检查 fence。暂停视频的缩放通常只有一次重绘，可能一直显示空白；播放时则表现为短暂闪黑。

修复仍通过本地[构建补丁](../../windows/patches/media_kit_video/apply.cmake)作用于已校验的构建副本，不修改依赖、Pub 缓存或相邻 fork：

- 尺寸改变保留同一个 Flutter 纹理 ID，更新输出尺寸并重绘。
- 重分配、绘制和消费者获取帧快照共用互斥锁。每个 GPU descriptor 持有实际交付纹理的 COM 引用，直到 Flutter 调用 release callback；descriptor 尺寸取自该纹理，防止旧句柄失效或尺寸错配。
- 对照当前 Flutter 3.47.6 的 `engine/src/flutter/shell/platform/windows/external_texture_d3d.cc`：`PopulateTexture` 在 `CreateOrUpdateTexture` 执行 release callback 后仍读取 descriptor 的可见尺寸。因此 callback 只释放 COM 引用，descriptor 保留至纹理注销；软件输出也保留独立的回调元数据快照。
- 每次新分配只在首帧等待 GPU fence，最多 100 ms，完成后直接发布这张帧。超时保留上次完成的纹理，后续提交可继续恢复；正常播放帧保留原有非阻塞路径。
- 视频、PGC、直播、离线和悬停预览共用这段 Windows 输出。没有修改播放会话、源 generation、弹幕时钟、视口像素上限或缩小防抖。

## 验证

- `tool/test-windows-gpu-queue.ps1`：新增缩放后只提交一张绿色帧、立即回读 GPU 像素，以及旧帧跨缩放存活的回归。修复前报 `consumer did not receive the completed producer frame`，修复后 8 轮创建／绘制／读取／连续缩放／释放通过。
- 同一脚本新增真实 D3D11／受控 Flutter registrar 回归，直接执行生产 `Resize` 和 descriptor callback：覆盖硬件／软件纹理 ID 不变、资源 release 后元数据存活、生产者缩放不破坏已返回的描述信息、未完成新帧时保留上一帧。
- `tool/test-windows-video-dispose.ps1`：9 项生命周期、渲染队列与尺寸测试通过。
- `integration_test/windows_video_resize_test.dart`：本地 DASH 音视频分轨，暂停／播放期间切换信息区并实际调整原生窗口尺寸，检查同一个 surface、纹理 ID、媒体 generation、音频解码和播放意图，要求输出经历多个真实尺寸；逐帧与稳定后截图均检查非黑色视频像素。可选 `--dart-define=BILI_RESIZE_INSPECT=true` 在第一次暂停缩放后保留窗口供人工查看。Windows 调试构建和真实窗口检查确认色彩测试图可见。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、打包边界检查和根应用 3496、API 496、播放器 96、弹幕 118、封装 5 项测试通过。根测试另有 13 项条件跳过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不作为原生封装验收。
- `tool/test-windows-media.ps1` 的首个文件有一项小窗控件断言失败：`windows_playback_test.dart:726` 在 640 宽度查找 `player-collapsed-progress`，但当前小窗实现保留常驻精简控件、不提供这条进度条。该测试夹具未随 `264c16a` 的控件行为同步，本次未改动此断言或播放控件生产代码；不将综合脚本记为全部通过。
- 随后单独顺序执行新增缩放测试、诊断、启动取消／回退、原生视频就绪、听视频切换、分轨中断恢复、悬停预览缓冲、视频／PGC 音量均衡和普通五分钟缓冲回归，共 19 项通过，未开启公网分支。
- 使用无账号的本地分轨调试探针重新构建 Windows，通过 DTD 热重载成功，未发现运行时错误；原生补丁的验证依据是重建后的二进制和上述原生回归，不由 Dart 热重载代替。

本轮仅修改 Windows 原生输出；Android、macOS、Linux 和 iOS 未构建或实机验证。没有进行性能测量、真实账号或公网媒体测试。
