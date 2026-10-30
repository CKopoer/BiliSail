# Predidit media-kit Windows 渲染与释放补丁

来源：[Predidit/media-kit](https://github.com/Predidit/media-kit/tree/83b7ca63772856e1ea0158916177e136f7b7b0be)，当前固定提交 `83b7ca63772856e1ea0158916177e136f7b7b0be`。仅在构建目录复制其 Windows 源文件并修正 D3D11 mailbox、纹理交付和释放生命周期；不修改 Pub 缓存或 Android/macOS 实现。上游代码为 MIT，许可保存在 [LICENSE](LICENSE)，源文件版权头保留。libmpv 来自固定依赖的 Native Assets 钩子，见[原生资产来源](../../native/PREDIDIT_SOURCE.md)。

`apply.cmake` 在 Windows 插件目标创建后校验九个上游源文件的 SHA-256，将副本作为该目标的编译输入。依赖升级或源文件变化时配置失败，必须重新审查补丁，不能静默跳过。普通 `flutter build windows` 与 MSIX 打包共用此入口。

修正包括：方法通道等待原生 Dispose 完成；停止渲染通知并排空在途任务；等待纹理的注销回调；在渲染线程释放 mpv 渲染上下文，然后销毁 D3D11 输出。没有纹理时不等待不存在的回调。重复到达、尚未执行的渲染通知只排一个任务；执行期间的新通知会在队列尾部再排一次，避免长时间占住共用渲染线程。暂停、SetSize 与视口变化仍强制重绘。

尺寸方法改用 Dart 原生适配器通过 SetSize 发送的显示尺寸，避免在共用渲染线程同步调用 mpv 核心 API。另由当前挂载的 VideoSurface 按布局与设备像素比发送视口上限，原生端按源显示比例限制中间输出纹理，不改变源分辨率或解码设置。新视口所有者立即解除旧上限；放大立即更新，缩小延迟 300 ms，原生单调 revision 防止异步通道请求逆序覆盖。首帧／暂停时的尺寸更新立即触发检查和绘制，主视频与预览继续使用 GPU 渲染。纹理交付和同步采用下述 GPU 队列补丁。

`video_output_resize.inc` 在信息区切换和窗口缩放时保留 Flutter 纹理 ID，以同一把互斥锁串行化 mailbox 重分配、绘制和帧快照获取。每个交付给 Flutter 的 GPU descriptor 持有对应纹理的 COM 引用，由 Flutter 的 release callback 释放，避免缩放销毁尚在使用的共享句柄。descriptor 自身保留至纹理注销，兼容 Flutter 在资源 release 后继续读取可见尺寸；软件输出也保留纹理注册及独立 descriptor。

`mailbox_first_frame.inc` 只在新分配的首帧等待 fence（最多 100 ms）并直接发布已完成槽，确保暂停时的一次重绘可见；超时继续提供上一张已完成纹理。后续播放帧沿用上游非阻塞 fence 检查。

`.inc` 是编译到上游类中的替换方法，不是构建产物。生命周期/队列测试不依赖播放器、显卡或 Flutter 进程：`pwsh -File tool/test-windows-video-dispose.ps1`。真实 D3D11 纹理像素、单帧 resize 与旧帧资源保留由 `pwsh -File tool/test-windows-gpu-queue.ps1` 验证；此测试需要 Windows GPU，CPU 回读仅在测试 staging texture 中使用。Flutter 原生布局、纹理 ID 和播放意图由 `integration_test/windows_video_resize_test.dart` 验证。原因和当前验证边界见[缩放闪黑记录](../../../docs/validation/windows-video-resize-2026-10-30.md)。`angle_gpu_queue.inc` 及下列 ANGLE 性能文档属于迁移前历史，不是当前输出路径。

故障证据、设计及验收范围见 [验证记录](../../../docs/validation/windows-preview-dispose.md)。

悬停卡顿原因、保留 GPU 的方案与 Profile 对照见 [预览出帧争用](../../../docs/validation/video-preview-contention.md)。`BILISAIL_VIDEO_RENDER_TRACE=1` 仅供该探针构建记录耗时；常规构建不加入逐帧诊断代码。

本次视口尺寸和 Windows GPU Engine 的受控 Profile 对照见 [渲染性能验证](../../../docs/validation/windows-video-render-performance-2026-10-11.md)。性能结论以实际设备和素材为限，不能把输出像素面积下降直接等同于 GPU 忙碌率下降。

`pwsh -NoProfile -File tool/test-windows-video-render.ps1 -Label run-720 -Height 720 -GenerateFixture` 可在仓库根目录生成或复用同参数的 50 秒测试片并执行 Profile 探针；结果写入 `build/validation/windows-video-render-run-720.json`、同名日志、`.fixture.json` 素材 SHA-256 元数据与 `windows-gpu-engine-run-720.jsonl`。传入 `-MediaDir` 可复用指定素材，`-ExePath` 可运行已保存的旧版 Profile 可执行目录做交替对照。脚本在 Flutter 构建后还原普通 CMake 配置。独立分轨检查使用 `tool/validation/windows_dash_render_probe.dart`，不会混入单文件 A/B 指标。
