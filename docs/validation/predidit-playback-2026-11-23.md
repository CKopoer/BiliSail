# 播放器迁移到 Predidit/media-kit

本文保留 2026-11-23 迁移时的基线。后续 Windows 与 Android 增加了 10 位呈现路径。Windows 随后引入含 IEC 61937 封装器的 libmpv，Android 为 JOC 音轨增加 Media3 系统播放路径。设备条件与实测见[原生 HDR 输出](windows-android-native-hdr.md)和[杜比全景声播放方案](../dolby-atmos-playback.md)。

根应用和 bili_player 的 media_kit、media_kit_video 固定在 Predidit 提交 `484639aca5ffc754a65876c22f01dbb070225732`。平台 libmpv 和事件库由 media_kit 的 Native Assets hook 提供。2026-11-23 核对的 Kazumi main 与此提交一致。参考的是 Kazumi 的源解析、播放实例所有权和输出配置，应用层沿用 BiliSail 的媒体会话。 [Kazumi 锁文件](https://github.com/Predidit/Kazumi/blob/635cd58d3ac7731085d0c64846ceefa52bc167bd/pubspec.lock#L1011-L1026) · [原生归档与 SHA-256](https://github.com/Predidit/media-kit/blob/484639aca5ffc754a65876c22f01dbb070225732/media_kit/hook/native_bundles.json)

Kazumi main 的播放器控制器在创建视频输出时显式选择 Android SurfaceTexture。BiliSail 采用相同的输出选择，标签的并发与独占播放、DASH 分轨、直播线路、离线媒体、字幕和弹幕仍由各自的会话负责。[Kazumi 播放控制器](https://github.com/Predidit/Kazumi/blob/635cd58d3ac7731085d0c64846ceefa52bc167bd/lib/pages/player/controller/player_playback_controller.dart#L411-L417)

## 从内容到画面

播放标签持有 PlaybackSession。会话按内容解析和选择源，点播将音视频轨组成 mpv EDL，听视频选音轨，直播按线路选择 HLS 或直链，离线沿用本地媒体描述。组合根直接创建 MediaKitEngine。引擎负责播放意图、代次、确认时间线和输出切换。mpv 的每文件参数随加载钩子设置，弱客户端独立读取当前播放条目、跳转和重启事件。页面、弹幕、字幕和历史记录都消费会话确认后的状态。

## 旧分支修复的去向

| 范围 | 当前实现 |
| --- | --- |
| mpv FLAG ABI、事件循环与热重启清理 | Predidit 已按 C int 读写 FLAG；原生事件桥由播放器持有并通过 finalizer 释放。Windows、Linux 与 Apple 的视频输出另外持有一个 mpv 弱客户端，收到 shutdown 后先释放纹理和渲染上下文，再释放客户端，防止调试热重启时核心提前销毁。旧分支按 Windows 进程号和创建时间维护指针缓存的补丁随旧缓存退出。 |
| DASH 请求头、缓存、开始位置与连续 seek | 应用适配层负责每源配置。START_FILE / END_FILE 的条目标识和 PLAYBACK_RESTART 用于确认当前加载及跳转。 |
| Android 首帧、解码与杜比视界 | 采用 Kazumi main 的 SurfaceTexture / Skia 组合。每次绑定向原生输出登记源代次，在栅格线程消费有效尺寸缓冲后解除首帧遮罩。纹理预先调整到解码尺寸时，SDK 会跳过尺寸变化通知，因此播放器用消费事件确认画面。保留 MediaCodec 直出、软件解码与 Profile 5 的 gpu-next 转换。 |
| Windows | 使用 Predidit 的 D3D11 / gpu-next 四槽 mailbox。构建副本补入消息窗口、串行管理队列、跨 resize 的纹理所有权及首帧和暂停 seek 的 GPU 完成通知。视口按原始宽高比调用 setSize。 |
| Linux | 保留上游 EGL 渲染线程。Windows 和 Linux 首选 gpu-next，并按实际创建的渲染上下文决定是否可以映射杜比视界。Wayland 合成器公开 DRM 接口时才把显示连接交给 VA-API 探测。软件输出使用原生 size_t stride，合并待运行的主线程回调并在释放前取消。 |
| macOS、iOS | CocoaPods 从固定插件生成本地副本，保留动态 mpv 符号绑定。渲染完成后发布帧，关闭时等待任务退出。iOS 的缓冲或纹理分配失败丢弃该帧。 |

构建只修改应用构建目录中的原生源文件。差异位于 [平台补丁](../../tool/media-kit-patches)，源自 MIT 许可的 [Predidit 基线](https://github.com/Predidit/media-kit/tree/484639aca5ffc754a65876c22f01dbb070225732) 和 [BiliSail 原维护分支](https://github.com/CKopoer/media-kit/tree/8e16eba1b01be05927b4fa098323ed496fea380d)。升级时应执行当前平台的媒体、缩放和释放测试，并逐项复核新归档的许可与对应源码。

旧的六个库插件、Windows ANGLE SDK、EGL 解码面边缘补丁和旧 Apple framework 下载脚本已退出构建。各平台 libmpv 归档由同一清单按架构选择并验证 SHA-256。Windows 改走 D3D11 渲染，旧显卡上 EGL 路径的验证记录单独保留。SDK 的命令分发仍有共享锁，BiliSail 各标签独立持有播放器，原生回归覆盖两个标签同时解码和切回独占播放。

Apple 的 Predidit 0.6.8 配方关闭了 mpv 的 libplacebo 和 Vulkan，FFmpeg 默认构建也未链接 libplacebo。当前项目原先固定的 Apple 配方同样关闭了这两项。在线 Profile 5 沿用会话的兼容清晰度回退，本地仅有 Profile 5 视频时返回色彩不支持。Windows 和 Linux 采用上表的 gpu-next，Android 对 Profile 5 使用软件 HEVC 解码以保留 RPU。[Predidit mpv 配方](https://github.com/Predidit/libmpv-darwin-build/blob/0.6.8/nix/packages/mk-pkg-mpv/default.nix) · [Predidit FFmpeg 配方](https://github.com/Predidit/libmpv-darwin-build/blob/0.6.8/nix/packages/mk-pkg-ffmpeg/default.nix) · [原维护配方](https://github.com/CKopoer/libmpv-darwin-build/blob/d4d9d65f8875f873b478ac4e76e9647d0dd2f3f4/nix/packages/mk-pkg-mpv/default.nix)

## 本次验证

| 环境 | 实际覆盖 |
| --- | --- |
| Windows x64 | 使用本地音视频和受控 HTTP/TLS 服务验证 DASH 分轨、PGC、HLS/FLV、纯音频、双标签并发与独占、断流恢复及缓冲。暂停和连续 seek 的 9 个用例通过。原生纹理在 resize 前后保留同一 ID，画面像素与释放回归通过。播放 DASH 分轨时连续热重启均能重新出画。 |
| Windows 杜比视界 | Profile 5 样片按参考 SDR 图逐像素比较，自动解码实际使用 d3d11va，软件模式使用软件解码。两者 RGB 平均绝对误差约 8.94，低于阈值 12，随后切换普通 SDR 也通过。禁用 Vulkan ICD 后重复通过。 |
| Linux x64 | Ubuntu 24.04 / WSLg 完成 Debug 构建，X11（Xvfb）及 Wayland 的启播、暂停 seek、重播、音频输出和增益用例通过。先前缺少 DRM 接口的 Wayland 合成器会触发 libva 崩溃，同一环境复测通过，播放中的热重启也能重新出画。Profile 5 参考图比较在两种解码设置下实际均使用软件解码，RGB 平均绝对误差分别约 10.57 和 10.21。 |
| Android arm64 | 小米 13 受控实机验证了 SurfaceTexture、DASH 独立音轨、播放、暂停和 seek。Profile 5 在自动／软件偏好下均使用软件 HEVC 解码，两次 RGB 平均绝对误差均为 9.33。换回 SDR 后，自动模式使用 MediaCodec，软件模式使用软件解码。两种解码模式分别测试暂停启播和自动播放，四组首帧采样均未出现闪帧，准备中取消也通过。测试后覆盖恢复普通入口的开发 Release，设备安装包和本地产物的 SHA-256 一致。 |
| macOS、iOS | Swift 生命周期与 iOS 输出回归通过，包括渲染进行中 Dart 所有者退出的受控用例。测试使用本地 Swift 工具链和测试替身，Apple SDK 构建、真机画面及释放仍待验证。 |

Android 在 `renderedTexture` 和 `directTexture` 两种输出模式下各运行 9 个延迟读取及连续 seek 场景。截取画面时按样片宽高比排除竖屏窗口黑边。连续改目标场景曾采到一次 158.8 ms 的音画差，超出 150 ms 断言；保留原阈值复测，两种输出共 18 个场景全部通过，同场景分别为 1.5 ms 和 3.3 ms。

根应用和四个独立包通过 `tool/check.ps1 -EnforceLockfile`。Dart／Flutter 套件共 7,473 项通过，另有 21 项按测试条件跳过。此次检查已配置原生 mux 库及 ffprobe。

上述样片验证覆盖 SDR 映射。原生 HDR 显示、其他显卡／物理 Linux 设备、公开在线源及长时间播放性能均未在本次验证中测量。

## 2026-11-26：Intel Mac 视频起播失败

反馈为 Intel 版任意视频提示「音视频播放失败，请重新加载或切换线路」，无现场诊断日志。该文案由共享播放器统一生成，覆盖原生初始化、加载和等待画面等失败。正式版 `1.3.0+8` 和预览版 `1.3.0+9` 都包含这次播放器迁移。固定的 Predidit 源码在 CGL 像素格式、上下文或纹理缓存无法创建时会回退到软件渲染，但移入的应用补丁沿用旧 fork 的强制初始化路径，覆盖了该回退。OpenGL 初始化和提交帧也把 Swift 临时指针传出了有效作用域。初始化失败可阻断起播，帧提交失败可使画面一直不可用。旧 `1.3.0+6` 的插件同样存在这两处缺陷，因此版本差异无法单独证明用户现场触发了它们。[预览版 Intel 构建日志](https://github.com/CKopoer/BiliSail/actions/runs/45528827282/job/138919943132) · [Swift 临时指针生命周期](https://docs.swift.org/swift-book/ReferenceManual/Expressions.html#Implicit-Conversion-to-a-Pointer-Type)

恢复可失败的 macOS OpenGL 初始化。CGL 或 libmpv OpenGL 上下文建立失败时，用同一个 mpv 播放实例创建软件纹理。libmpv 调用在参数有效期间完成。macOS BGRA 缓冲明确要求 IOSurface、OpenGL 与 Metal 兼容，CoreVideo 保持对纹理的所有权，分配或绘制失败时保留上一个完成帧。发布构建增加对 `Mpv`、`media_kit_video` 和 `media_kit_event_loop` 的目标架构检查。[构建补丁](../../tool/media-kit-patches/macos.patch) · [Apple OpenGL 与 Metal 共享缓冲](https://developer.apple.com/documentation/metal/mixing-metal-and-opengl-rendering-in-a-view)

以 SHA-256 核对 Predidit 0.6.8 macOS 归档及 `1.3.0+9` Intel DMG。归档的 libmpv x86_64 切片导出渲染和弱客户端符号。DMG 中的 Native Assets 清单包含 `macos_x64` 的 19 个 media_kit 条目，主程序、播放器和相关 framework 共 35 个 Mach-O 均含 x86_64，`@rpath` 引用的 framework 均已打包。[预览版安装包](https://github.com/CKopoer/BiliSail/releases/tag/v1.3.0%2B9)

Apple 受控回归模拟硬件纹理初始化失败，验证软件纹理收到渲染任务、通知首帧并正常释放。对 macOS Swift 渲染器使用真实 mpv C 头文件做类型检查，并用图形 API 替身复验初始化失败后的资源释放及失败帧后的恢复。Windows 格式、静态分析、打包边界检查和四个独立包的 1,510 项测试通过，播放器另有 7 项按环境条件跳过。根应用共 6,013 项通过，评论页 `video_comments_controller_test.dart` 两项查找不到预期控件而失败，另有 14 项跳过。真实 Intel macOS 构建和播放仍待验证。可在 Intel Mac 运行[原生播放回归](../../integration_test/native_video_readiness_test.dart)，再用普通在线 DASH 验证 HTTPS、音频与画面。
