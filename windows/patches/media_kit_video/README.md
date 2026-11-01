# PiliPlus media-kit Windows 构建副本适配

当前来源为 MIT 的 [bggRGjQaUbCoE/media-kit](https://github.com/bggRGjQaUbCoE/media-kit/tree/fd8421d21eade4d6d12de137fa7df902fec20292)，固定完整提交 `fd8421d21eade4d6d12de137fa7df902fec20292`，与 PiliPlus 的锁文件一致。版权与许可保留在 [LICENSE](LICENSE)。只校验和修改构建副本，不修改 Pub 缓存、相邻仓库或其他平台实现；依赖变化时必须重新审查八个源文件 SHA-256 及补丁锚点。

`plugin_main_thread.inc` 通过每个插件实例自己的 message-only HWND，将 Resize 通知和 Dispose 回复送回平台线程，兼容隐式 view 和独立播放窗。没有全局插件 owner，也不替换其他组件的 WndProc。

`video_output_dispose.inc` 停止通知、排空渲染队列、等待 Flutter 纹理注销回调，在原渲染线程及当前 GL 上下文释放 mpv，然后释放 ANGLE surface。方法通道仅在这些步骤完成后回复 Dispose。重复渲染通知合并，执行期间的新通知放回队尾，避免阻塞共用渲染线程。

尺寸通过 Dart 的解码显示尺寸／SetSize 和当前 VideoSurface 的独立视口上限传入，避免共用渲染线程同步查询 mpv。保留放大即时、缩小延迟 300ms、单调 revision 和新视口所有者解除旧上限的规则。

`angle_gpu_queue.inc` 在可用时借用 ANGLE 的 D3D11 immediate context；Flutter 位于同一设备时直接交付，其他设备保留复制回退。相同帧不重复复制；旧设备保留原同步路径。

`video_output_resize.inc` 保留 Flutter 纹理 ID，并以相同互斥锁串行化缩放、渲染和 descriptor 获取。每次交付通过 COM 引用保留对应 GPU 纹理；Flutter release 之后仍可读取 descriptor 的可见尺寸。新分配尚无帧时继续提供上一个已绘制纹理；实际暂停帧在缩放时主动重绘。软件输出继续保留独立 descriptor。

libmpv 与 ANGLE 来自固定库插件，不启用 `native/mpv.cmake` 的历史覆盖；当前摘要及分发范围见[原生来源](../../native/PILIPLUS_SOURCE.md)。`mailbox_first_frame.inc` 仅保留为旧 D3D11 记录，当前不编译。

验证入口：

- `tool/test-windows-video-dispose.ps1`：9 项受控生命周期／队列／尺寸回归。
- `tool/test-windows-gpu-queue.ps1`：真实 ANGLE/D3D11 的 100 帧共享、复制回退、缩放与共享 display 生命周期，以及生产 resize／descriptor 回调的资源保留。
- `integration_test/windows_video_resize_test.dart`：实际 Flutter 播放、暂停与信息区／窗口尺寸切换时保持同一 texture 并检查像素。
- `tool/test-windows-media.ps1`／`tool/test-windows-content.ps1`：本地音视频分轨、headers、续播、PGC／直播等回归。

本轮结果及未测项见[依赖切换](../../../docs/validation/piliplus-dependencies-2026-11-01.md)。历史 ANGLE／D3D11 性能记录只描述当时的完整配置，不能直接作为本次切换的性能结论。
