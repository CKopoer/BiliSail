# Apple／Linux 纹理交接修复与 Android 检查

日期：2026-11-08，承接 [Windows 专项](windows-texture-handoff-2026-11-08.md)。按用户要求继续修复 Apple／Linux 已发现的风险，并检查 Android；本轮不构建 Flutter 应用、不安装或操作设备。

## Apple

### media_kit：macOS／iOS 的 GPU 与软件输出

原 `SwappableObjectManager` 在生产者发布新帧时，就把旧 current 放回可写池；三个缓冲只能推迟重用，不能证明 Flutter 的 Metal 队列已读完。GPU 输出还仅调用 `glFlush` 就发布跨 API 使用的 CoreVideo 图像。

个人 [media-kit b1c7e433](https://github.com/CKopoer/media-kit/commit/b1c7e4336140d8c4550c1e963365da8edfe56d0a)改为：

- 每次实际 render 创建新的 CoreVideo 帧，发布后不再作为生产者目标写入；取消旧帧回收池。硬件输出在 OpenGL／OpenGL ES `glFinish` 之后发布，软件输出在原生渲染完成并解锁像素之后发布。
- `CompletedFrameStore` 只保存一张最新完整图像，raster 线程在同一把锁内取得 retained 引用。缩放期间保留旧完整图像，释放播放器后消费者已取得的图像仍有独立所有权。
- GL 帧包装只在串行 render 期间存在；退出该作用域后，在对应 GL context 中清理未使用的 CoreVideo texture cache 项，避免每帧分配后缓存不断增长。

[Flutter 3.47.6 的 CoreVideo／Metal 导入代码](https://github.com/flutter/flutter/blob/3.47.6/engine/src/flutter/shell/platform/darwin/graphics/FlutterDarwinExternalTextureMetal.mm)会保留 last pixel buffer 并包装 Metal 图像，但这不是生产者可重写旧 IOSurface 的完成回执。本次不会按 CF 引用计数或固定轮转次数推断消费者 GPU 已结束使用。

### fvp：macOS／iOS 的 Metal 输出

原 `MetalTexture` 在同一张 CVPixelBuffer 上反复 blit，`commit` 后立即返回；CPU mutex 没有覆盖消费者 GPU 读取。

[替换实现](../../native/fvp/apple/metal_texture.inc)保持 MDK 的私有渲染目标及同一 Metal command queue：

1. Flutter 请求新版本时，分配独立 IOSurface 并在 MDK 同一队列中提交 blit。后续 MDK 绘制排在该复制之后，不能抢先覆盖复制源。
2. 最多保留一个 pending command；仅在 `MTLCommandBufferStatusCompleted` 后发布对应图像。等待期间返回旧完整图像，首次尚无完整帧时返回空；不阻塞 raster 等待 GPU。
3. 完成回调通过 weak 引用在主线程请求后续 Flutter 帧；若暂停期间出现更新版本，旧复制完成后仍会继续复制最新版本。销毁先停用回调并 invalidate，迟到完成不得再通知已关闭的纹理。
4. 失败的 command 不发布其图像，同一失败版本不会反复创建命令；新原生版本可重新尝试。关闭时独立释放当前／pending CoreVideo 引用。

[CocoaPods 准备脚本](../../tool/prepare-fvp-apple.py)校验官方 `e81637411c58a9ae28de246ee73ad06e3418f10e` 的 Apple 源码 SHA-256，把插件复制到 `build/apple-plugins/<platform>/fvp/` 后替换渲染类。两份 Podfile 在 Flutter 创建插件链接后调用该步骤；重复安装仍从原始固定源码开始，拒绝源漂移与不安全目标链接。源文件、许可证和 SDK 不在 Pub 缓存中改写。当前工程使用 CocoaPods，SwiftPM 仍明确关闭。

## Linux

### media_kit：跨 EGL context 的 GPU 输出

Flutter 与 mpv 在不同 context 中访问同一 EGLImage。原先生产者的 `glFlush` 只提交，且下一次生产者写入前没有等待前一帧消费者读完。

本次在 Flutter 当前 raster context 进入 populate 时，先完成其已提交的读取，再切换至 mpv context；分配和绘制完成后，以 `glFinish` 确认生产者 GPU 工作完成，再恢复 Flutter context。读侧与写侧两个方向都覆盖，尺寸变化也遵守相同顺序。Flutter 的 [Skia external-texture 路径](https://github.com/flutter/flutter/blob/3.47.6/engine/src/flutter/shell/platform/embedder/embedder_external_texture_gl.cc)在调用插件前提交此前图形工作；本次完成屏障不把未提交的 Skia 操作当成已结束。

### media_kit：软件输出

原像素回调直接返回会被后续原生 render 改写的内存。本次在生产者 mutex 内复制已完成像素及其真实渲染尺寸，交给 raster 回调独立持有。原生尺寸提前变化不能与旧像素混配；分配失败沿用旧完整图像，尚无首帧时不发布初始化内容。原生软件写入还检查既有缓冲上限。

### fvp

固定源码的 render callback 只通知 Flutter；实际 `renderVideo` 位于 `player_texture_populate`，在 Flutter 当前 GL context 执行，之后才由 Flutter 采样，同一命令流具有读写顺序。它没有 media_kit 的独立生产者 context／共享 EGLImage 写入路径，因此本次未增加跨 context 等待；保留现有 scissor 保存／恢复。

## Android 检查结论

未发现本次桌面／Apple 所定位的应用层可变交付纹理缺陷：

- media_kit 的 `VideoOutput.java` 创建 `SurfaceTextureEntry` 和 `Surface`，mpv 的 VO 在源 load／unload 屏障之间持有该 Surface；应用不直接反复写入 Flutter 正在读的共享 D3D／IOSurface 图像。
- 当前应用的 fvp Android 走 `FvpProcessHandler`／`FvpPlaybackService`：主进程创建 `SurfaceTextureEntry`，将 Surface 交给 worker。兼容模式通过 MDK `updateNativeSurface` 渲染；直出模式由 MediaCodec 向同一 Surface 队列提交，不把可写输出纹理直接借给 Flutter。
- 两条路径交给 [Android BufferQueue 与同步框架](https://source.android.com/docs/core/graphics/arch-bq-gralloc)管理 producer／consumer 缓冲与 acquire／release fence；首帧消费通知只用于就绪判断，没有被用作应用自行覆盖旧图像的许可。

因此本轮不在 Android 加额外复制或 `glFinish`。这表示静态审查未发现同类缺陷，不表示 Android 设备的所有视觉异常已排除；本轮没有连接设备播放或测量。

## 验证与边界

- [Apple 准备流程回归](../../tool/test_apple_texture_handoff.py)：6 项，覆盖 iOS／macOS 重复 staging、原缓存不变、源漂移拒绝、目标链接保护、Podfile 顺序、Python 3.9 接口兼容及发布先后关系。
- [独立原生受控回归](../../tool/test_native_texture_handoff.py)：4 项。编译实际 Linux populate／copy 方法，模拟两个 GPU 命令队列的延后读写，覆盖 100 帧、缩放、软件副本、尺寸身份与失败回退；分别移除读侧／写侧完成屏障的负向对照均触发断言。另以受控 API 声明对真实 Metal 替换类做 Objective-C++／ARC 严格语法检查。
- 上述原生回归使用替身图形 API，不计作真实 EGL／Metal GPU 运行或完整平台插件编译；Apple 源码发布顺序检查也不等于 Swift／Apple SDK 编译验收。
- `tool/check.ps1 -EnforceLockfile` 首轮全量通过：根应用 4,726、bili_api 719、bili_player 325、bili_danmaku 161、bili_mux 5，共 5,936 项离线测试通过；根应用 13 项按环境条件跳过，mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生通过。该轮固定引用为 `12acf0df`；最终引用仅补两条 Foundation 显式导入，Dart 源码未因本任务改变。
- 最终固定引用的锁文件强制解析通过，6 项 Apple 准备回归及 4 项受控原生／语法检查通过；Windows 前轮纹理、慢 GPU 和尺寸回归通过，fork 的 Windows 实现本轮未改变。
- 最后一次主工作区 Lint 被同期新增的 `mp4_buffer_index.dart` 格式阻塞；单独静态分析报告同期 `dash_track_buffer.dart:353`、`mp4_buffer_index.dart:85,142` 的三条 `curly_braces_in_flow_control_structures`。这些文件及相关 Dart 播放器改动属于其他工作，未修改或纳入本次提交。最终在 `69e594e2` 加本任务变更的隔离检出执行 `tool/check.ps1 -EnforceLockfile -Stage Lint`，五份锁文件强制解析、全部格式／静态分析、构建边界及 Apple 准备流程检查均通过。

日志保留在忽略目录 `build/apple-linux-handoff/`。独立受控原生检查入口为 `python -m unittest discover -s tool -p test_native_texture_handoff.py`；它需要 C++ 编译器，Metal ARC 语法项需要 Clang。

原生资产、解码器和 SDK 二进制未升级。应用与 `bili_player` 的八个媒体包及两份锁文件统一固定到上述完整源码提交；Windows 的前轮修复继续包含在该提交中。

本轮无 Flutter 应用构建、无 Apple／Linux／Android 实机验收。每帧独立分配与 Linux 完成等待的开销未做 Profile／Release 测量；需要在对应主机确认原片源、长播放、缩放、普通／全屏、暂停／seek、4K／高倍速、显存占用及退出。macOS／iOS 的 SDK 编译、真实 Metal／CoreVideo 和 Linux 的实际 GTK／EGL／驱动行为仍待对应平台验证。
