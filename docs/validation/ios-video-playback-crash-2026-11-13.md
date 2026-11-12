# iOS 播放期间闪退：输出帧分配与失败处理

日期：2026-11-13（Asia/Shanghai）。反馈版本为当前 `1.2.9+5`，用户描述通常播放十几秒后退出、其他平台及 PiliPlus 未出现同类现象。[Issue #122](https://github.com/CKopoer/BiliSail/issues/122) 另有 iOS 16.6.1、巨魔安装、任意视频播放时随机退出而首页正常的报告；没有原生异常堆栈或 JetsamEvent。

本轮定位并修复了可通过故障注入复现的 iOS 原生进程退出路径。尚不能把这些受控结果等同于现场十几秒闪退已经复现，也不能断言现场是内存耗尽、解码器错误或哪一种系统异常。

## 实际依赖与 PiliPlus 对照

- 修改前根应用和 `bili_player` 的八个媒体包均固定到个人 media-kit `eaae0273a93fbd23b24e3c951b99efd9b73e702b`；本轮以该提交隔离检出修改，没有改相邻仓库或 Pub 缓存。
- iOS 真机默认走 `TextureHW` → `TextureGLESContext` → CoreVideo/OpenGL ES → Flutter Metal 外部纹理。模拟器走软件输出，不能用模拟器正常替代真机路径验收。
- 相邻 PiliPlus 的当前锁文件将视频插件固定到 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`，核心及 iOS 库插件为 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，不是本项目的媒体依赖组合。
- [PiliPlus 锁定视频源码](https://github.com/bggRGjQaUbCoE/media-kit/blob/85f0a69ea66b100882b27a3375c72e5155375343/media_kit_video/ios/Classes/plugin/TextureHW.swift) 在初始化或尺寸变化时建立三张输出缓冲并轮转。本项目此前为避免覆盖 Flutter GPU 尚在读取的旧帧，改为每次实际 render 分配独立输出图像，见[纹理交接记录](apple-linux-texture-handoff-2026-11-08.md)。因此两者触发分配、纹理创建和帧缓冲失败的频率不同；PiliPlus 无同类反馈不等于两套依赖的每条失败分支都安全。
- 本项目的原生点播包缓存已经设置前向 32 MiB、后向 32 MiB，直播前向 64 MiB、后向 0。本轮没有证据证明这些有界包缓存耗尽 iOS 内存，没有通过盲目调整缓存、关闭硬解或恢复旧纹理轮转掩盖问题。

## 已确认的缺陷

1. `OpenGLESHelpers.createPixelBuffer` / `createTexture` 仅 assert 返回码，再强制解包。在 Release 中 assert 不执行，CoreVideo 失败或返回空对象后仍会发生 Swift trap。
2. `TextureGLESContext` 遇到帧缓冲不完整会在同一帧内反复分配，四次失败后直接 `exit(1)`。受控注入 `GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT` 可使原实现退出码为 1；像素缓冲和纹理创建失败也可使原版测试进程异常结束。
3. 像素缓冲只声明 Metal 兼容，没有显式设置 OpenGL ES 兼容和 IOSurface 属性。[Apple QA1781](https://developer.apple.com/library/archive/qa/qa1781/_index.html) 说明非 IOSurface 支持的像素缓冲无法导入 OpenGL ES，并要求创建时设置 `kCVPixelBufferIOSurfacePropertiesKey`。Metal 兼容属性不能作为完整的跨 API 分配契约。
4. `TextureGLESContext.deinit` 对 CoreVideo 管理的 GL 纹理名调用 `glDeleteTextures`，但并没有释放 CoreVideo 包装对象。应该由 ARC 和纹理缓存管理该对象的生命周期；不能把手动删除 GL 名称当作 CoreVideo 缓存回收。[Apple 的纹理类型说明](https://developer.apple.com/documentation/corevideo/cvopenglestexture)明确其由 `CVOpenGLESTextureCache` 管理。
5. 初始化参数和每帧 FBO 参数的指针从 `withUnsafeMutableBytes` / `withUnsafeMutablePointer` 借用闭包中返回，之后才传给 mpv。借用作用域已结束，指针有效性没有保障；优化构建不能依赖当时栈布局恰好未改变。

其中 1、2 是已确认、可复现的进程退出缺陷。3、4、5 是需要修正的原生契约问题；没有设备证据证明它们各自造成了此次现场闪退。

## 修复与接入

个人 [media-kit 修复提交](https://github.com/CKopoer/media-kit/commit/ba953612ebfa83a4590f374c78a1ba479e1ea1df)：

- iOS 像素缓冲同时声明 IOSurface、OpenGL ES 和 Metal 兼容。
- 每帧分配和纹理导入改为可失败返回；帧缓冲创建失败返回空，不重试分配、不主动终止进程。当前 render 保留之前完整画面，后续正常 render 可继续发布新画面。
- CoreVideo 包装对象通过 ARC 释放；只删除本插件创建的 FBO。包装对象作用域结束后仍在对应 EAGL context 中 flush 缓存，失败路径也执行清理。
- 分配、绘制和清理处于对应 EAGL context；嵌套辅助方法和 render 恢复进入时的 context。拒绝无效、非有限、不能表示为 GLsizei 的尺寸。
- mpv 初始化和 render 调用放入指针借用闭包内；mpv render 返回失败时不发布未完成图像。
- 保留 `glFinish` 后发布、`CompletedFrameStore` 原子交接和消费者 retained 引用；不根据固定缓冲数量推断 Flutter GPU 已完成读取。

根应用及 `bili_player` 的核心、视频和所有平台库插件统一固定到该完整提交，两份锁文件由 Flutter Pub 重新生成。SDK 资产及解码器二进制没有更换，其他平台原生实现没有修改。

## 验证

- 新增 [回归入口](../../tool/test_ios_video_output.py) 和 [Swift 故障注入环境](../../tool/native_tests/ios_video_output_test.swift)。根检查既有的 `test_ios_*.py` 入口会执行源码契约检查；没有 `swiftc` 时明确跳过可执行用例。
- 在 WSL Ubuntu 22.04 / Swift 6.0.3 下，以 Swift 5 语言模式和 `-O` 编译真实生产 `TextureHW`、`TextureGLESContext`、`OpenGLESHelpers`、`CompletedFrameStore`。仅替换不可用的 Apple 图形 API 和 Flutter 协议，执行完整生产方法及 ARC 释放。
- 首轮原版 7 项检查全部失败，其中分配/纹理失败触发异常退出、无效 FBO 触发 `exit(1)`。修复后共 9 项通过：源码契约、连续 2,000 帧、像素缓冲分配失败、纹理导入失败、无效 FBO、非法尺寸、context 激活失败、mpv render 失败和真实 mpv C 参数类型检查。验证失败期间保留旧图像、故障解除后继续发布、旧图像不被覆写、FBO 与临时引用释放、context 恢复。
- C 参数检查使用 fork Makefile 指定的 mpv v0.36.0 头文件归档，先验证既有 SHA-256，再让真实生产 Swift 类型检查导入 C 声明，避免只用 Swift 替身函数签名掩盖 FFI 参数错误。该检查仍不包含 Apple SDK 类型。
- `tool/check.ps1 -EnforceLockfile` 完整通过：五份锁文件可复现解析、格式/静态分析、打包边界及 6,565 项离线测试（根应用 5,270、API 917、播放器 212、弹幕 161、mux 5）。根应用 13 项、播放器 1 项按环境跳过；mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。Windows 根检查没有 Swift 编译器，可执行 Swift 用例由上述 WSL 专项单独执行。
- fork 提供 `media_kit_video/test/ios_renderer_typecheck.sh`，使用 iPhoneOS SDK、固定 mpv C 头文件和最小 FlutterTexture 协议声明检查真实 Swift 文件。尝试通过隔离验证分支远端执行时，GitHub 返回 `422: Actions has been disabled for this repository`；没有产生成功的 SDK 验证结果，临时验证分支已移除。

检查日志位于忽略目录 `build/ios-playback-fix/check.log`，原版故障注入对照在同目录 `baseline.log`。交付前发现同期 `lib/features/pgc/presentation/pgc_screen.dart` 修改，已保留，未纳入本任务；以上全量结果对应此次检查运行期间的源码，不作为后续并行修改的验证结论。

这些替身 API 回归不验证 Apple 驱动、真实 CoreVideo/Metal 资源占用或系统内存终止，不能据此声称长期播放内存稳定。Windows 主机不能构建 iOS IPA，当前没有 iOS 设备；iOS SDK 编译、同版本真机长播放、原报告退出原因及修复接受度仍待验证。需要覆盖普通/全屏、暂停/seek、旋转/切清晰度、前后台、连续换视频，并核对崩溃记录或 JetsamEvent。
