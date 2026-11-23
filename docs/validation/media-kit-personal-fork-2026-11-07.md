# 官方基线与个人媒体 fork 统一维护

本页保留 2026-11-07 至 2026-11-23 使用个人 fork 期间的来源和实测。现行依赖、仍需移植的修复及验证见 [Predidit 播放链路](predidit-playback-2026-11-23.md)。

2026-11-23 修复 Windows Release 关闭主窗口时的访问冲突。Flutter 3.50.1 在销毁插件前先断开引擎与 messenger 的关联；视频插件随后调用 `SetMethodCallHandler(nullptr)`，即使未打开视频也会在 `FlutterDesktopMessengerSetCallback` 中崩溃。新的固定提交让 Flutter 的插件注册器随引擎释放处理器，视频插件继续等待管理和渲染任务结束、处理已排队的回调并销毁消息窗口。八个媒体包均使用该提交。[个人 fork 修复](https://github.com/CKopoer/media-kit/commit/8e16eba1b01be05927b4fa098323ed496fea380d) · [Windows 关闭实测](main-window-close.md#windows-release-关闭时的插件访问冲突2026-11-23)

2026-11-23 修复 Windows D3D11 视频纹理重建与插件退出时的资源释放。根应用和 `bili_player` 的八个媒体包统一固定到 [3bd90a7d](https://github.com/CKopoer/media-kit/commit/3bd90a7d84a605d75da2de6196b3cea57ec92815)，父提交为 `aaa85281`。申请新纹理、取得共享句柄并验证 EGL 绑定后才替换旧表面。失败时继续使用原尺寸与上一帧，相同尺寸可重试；纹理由 `ComPtr` 单独持有。插件在销毁消息窗口前按顺序完成已接收的管理操作、渲染释放和平台回调。

fork 的受控 C++ 回归覆盖五个重建失败点、绘制异常后继续调度、插件退出时仍在执行的创建和渲染，以及已排队的释放与平台回复。Windows x64 上，真实 D3D11/ANGLE 的 100 帧像素和快照生命周期检查、纹理描述符检查及 9 项原生生命周期测试通过。Flutter 3.50.1 Debug 真实窗口播放本地 H.264 视频与独立音轨，在暂停和播放时反复缩放并切换信息栏，输出宽度在 320 和 228 之间变化，纹理 ID 稳定，最终释放成功。这次窗口测试保留 `toImage`，未执行逐帧 CPU 像素读回。改用远端提交后再次通过上述真实窗口和原生测试，普通应用入口的 Windows x64 Debug 构建成功。`tool/check.ps1 -EnforceLockfile` 通过，已配置 `bili_mux` 原生库和 ffprobe 9.0.2。反馈者设备上 NVIDIA 驱动异常与这三处实现缺陷的因果关系仍待现场复测。

2026-11-21 修复 [Linux 软件视频输出关闭时闪退（#152）](https://github.com/CKopoer/BiliSail/issues/152)。根应用和 `bili_player` 的八个媒体包统一固定到 [aaa85281](https://github.com/CKopoer/media-kit/commit/aaa85281530b1ad80fa9e7d7808fcfdd7b5d30bd)，直接父提交为原锁定版本 `302d60ee`。每个软件输出持有一个可取消的 GTK 渲染源，关闭时断开 mpv 回调、销毁渲染源，并等待正在复制图像的 raster 回调脱离输出，再释放资源。传给 libmpv 的软件行跨度按接口使用 `size_t`。

Ubuntu 24.04 x64 下使用 Flutter 3.50.0 Linux engine 和固定的 libmpv 完成原生编译与 CTest。回归用例检查真实软件帧首尾像素、首帧前关闭、复制期间关闭和关闭后读取保留的纹理，ASan／UBSan 检查通过。WSL2 的 Xvfb 桌面上，BiliSail Linux Debug 普通入口构建成功；独立验证入口通过实际 Flutter 纹理完成 10 次显示 64×36 本地视频帧后关闭、10 次打开期间关闭。本地 Debug 链接阶段在临时构建目录为已固定的 libmpv 补建了链接名，运行时与 AppImage 一致，优先加载 bundle 内的 libmpv。普通主窗口的 Alt+F4 退出检查超时；上述 20 次检查的对象为视频播放器。报告者的原设备和发布 AppImage 尚未复测。

2026-11-13 Apple 生命周期后续：媒体包统一固定到 `302d60eedc55ca677e911e529569b1e14d8c2e7e`，修复销毁响应早于渲染结束、Flutter 保留纹理时的原生上下文释放、无界通知积压及软件输出初始化/关闭竞态。21 项受控 Swift 检查和 Windows 9 项原生回归通过，Apple SDK 编译和实机边界见[iOS 专项](ios-video-playback-crash-2026-11-13.md)。

2026-11-13 iOS 后续：媒体包统一固定到 `ba953612ebfa83a4590f374c78a1ba479e1ea1df`，修复每帧输出分配/纹理导入失败的强制解包、无效 FBO 后退出进程、CoreVideo 纹理释放和 mpv 参数指针作用域。原 SDK 资产不变；受控 Swift 回归通过，iOS SDK 编译与真机闪退接受度未验证，见[iOS 专项](ios-video-playback-crash-2026-11-13.md)。下文固定引用按各次验证的历史状态保留。

2026-11-09 后续：现行媒体依赖统一固定到 `9858a8db83faf8bcfa39a8bfbc02dde9a2e92572`，替换 Windows ARM64 中禁用 OpenGL 的 SDK，修复渲染降级与初始化错误传播；其他平台资产保持原内容。来源、自动检查和未构建／实机边界见 [ARM64 闪退修复](windows-arm64-preview-crash-2026-11-09.md)。

2026-11-08 Apple／Linux 后续：当时源码统一固定到 `b1c7e4336140d8c4550c1e963365da8edfe56d0a`，修复 Apple 完成帧发布与旧缓冲重用、Linux GPU 跨 context 同步和软件帧交付；Windows 修复及全部 SDK 资产继续沿用。实现与未测项见[跨平台纹理交接](apple-linux-texture-handoff-2026-11-08.md)。以下各条保留对应专项当时的固定引用。

2026-11-08 后续：现行媒体依赖统一固定到 `ba68fe1c56d46ed5d0e651da8d15e803e45038cb`，Windows 两后端共用已完成、不可变的 GPU 快照；原 SDK／ANGLE／MDK 资产未改变。修复、旧帧延后消费与慢 GPU 回归及跨平台边界见[纹理交接记录](windows-texture-handoff-2026-11-08.md)。以下保留迁移当时的来源与验证快照。

日期：2026-11-07（Asia/Shanghai）。本轮将播放器核心、视频插件、平台库插件与 libmpv 的维护入口统一到个人 fork；保持当前 Flutter Texture 合成、弹幕调度和产品容量设置。依赖迁移不作为新的性能提升结论。

Windows x64 后续更新：个人 mpv 已修复有填充的 D3D11 解码表面经 EGL／ANGLE 产生的边缘绿线，使用重建 SDK 与补充原始许可后的固定资产；[专项记录](windows-amd-hwdec-edges-2026-11-07.md)列出像素对照、构建与未测边界。以下首批镜像与旧产物数据保留为迁移当时的历史记录，当前 x64 不再使用首批镜像 DLL。Windows ARM64、Android、Apple、Linux 的原生内容未因本次修复改变。

## 固定来源

| 层次 | 现行来源 |
| --- | --- |
| 官方基线 | media-kit/media-kit `c533e446755f51cf53c7e57aea873f2aa5355f81` |
| 核心、视频、aggregate 及 Android/Windows/macOS/iOS/Linux 库插件 | [CKopoer/media-kit](https://github.com/CKopoer/media-kit/tree/f57d7c5ffd564d7a91c45769943831d468caeb2f)，统一固定 `f57d7c5ffd564d7a91c45769943831d468caeb2f` |
| mpv 源码 | [CKopoer/mpv](https://github.com/CKopoer/mpv)；Windows x64 `afd6da8843a07f463ba4c736a2ea636b1a92e23e`、ARM64 `88eb9f2e73945d8bc9c133a2f67babaa9af34680`，Android `9fda3e12a57a7b3ebd627a3c1b37561709d4ffee`，Apple 官方基线 `f4210f84906c3b00a65fba198c8127b6757b9350`，Linux `41f6a645068483470267271e1d09966ca3b9f413` |
| 资产与构建材料 | [Windows x64 修复 SDK](https://github.com/CKopoer/media-kit/releases/tag/native-windows-hwdec-edges-2026-11-07)、[其余平台固定资产](https://github.com/CKopoer/media-kit/releases/tag/native-2026-11-07)、[资产摘要](https://github.com/CKopoer/media-kit/blob/f57d7c5ffd564d7a91c45769943831d468caeb2f/native/assets.lock.json)、[构建分支提交](https://github.com/CKopoer/media-kit/blob/f57d7c5ffd564d7a91c45769943831d468caeb2f/native/builds.lock.json) |

根应用和 `bili_player` 保留必要的 overrides，八个媒体包统一来自同一完整 Git 提交。最终无 path override、相邻仓库依赖或 Pub 缓存修改。canvas_danmaku 的现行提交不变。

Windows、Android 和 Apple 首批资产是保留原 SHA-256 的上游二进制镜像，不宣称由个人仓库重编译。Windows 使用现有 LGPL x86_64 SDK 与 ANGLE；Android 使用 20260906 default jar；Apple 沿用官方基线 v0.7.2 的 CocoaPods/SPM 资产。来源和子依赖材料保留在锁定清单及各原发布中。

迁移前核心为 My-Responsitories `73771ec38176be2d984a3049c28177bce23b54a0`（1.1.11），视频为 bggRGjQaUbCoE `fd8421d21eade4d6d12de137fa7df902fec20292`（1.2.5），还依赖旧原生事件桥。本轮官方源码基线的核心为 1.2.6、视频为 2.0.1；个人 aggregate 为 1.0.8。官方更新提供事件路由、状态模型及平台修复，但版本号不能证明播放更快；原 fork 的 Android Surface 生命周期、应用已有 Windows 纹理／释放保护仍需保留。

“引用官方”通过在个人 fork 中同步官方提交实现：Dart 同名包只解析一份实现，不同时引入官方与个人两套核心。后续更新先同步官方基线，再审查小范围平台补丁、固定资产和回归记录，最后一次性更新根应用／bili_player 的完整 Git ref 与锁文件。Android 当前保留 SurfaceTexture 的兼容性路径；与官方 SurfaceProducer 的性能差异须用相同设备、视频、渲染后端和 Release/Profile 构建测量。

个人构建材料分别在 `CKopoer/mpv-winbuild`、`CKopoer/libmpv-android-video-build`、`CKopoer/libmpv-darwin-build` 的 `codex/bilisail-source` 分支；后续构建的 mpv 来源已改为个人源码 fork。Linux 库插件从个人 0.41.0 源码构建 libmpv；发行版 FFmpeg、图形和音频库仍为独立依赖。

## 实现与职责

- 核心保留官方跨平台 API、不可变状态、NativeCallable／受限环境和 debug isolate 路由、热重启及内存清理修复。`MPV_FORMAT_FLAG` 按 C int 读写；写入分配在 finally 释放。继续保留此前个人 fork 的 hooks、nativeOptions、逐播放器锁和 ABI 修复。
- 修复官方 Windows Debug 热重启引用缓存仅以 PID 命名的问题：按 PID 与 GetProcessTimes 创建时间共同定位，防止进程号复用后解引用上个进程的地址；同进程热重启仍保留原生清理能力。Win32 绑定从已安装 SDK 使用 ffigen 23 生成。
- 应用恢复官方 `Player`／`VideoController` API，创建等待、迟到资源清理、源代次和总 deadline 仍由适配器负责。Media 的 HTTP headers 回到官方模型，外部音轨、Range、重定向和音轨身份确认继续保留。
- 源 hook 内保留小型同步 FFI 端口，避免等待同一事件循环的异步回复。普通调用仍走既有异步端口。删除旧 FLAG 绕行专用方法及其失效测试，由真实 libmpv flag 往返与播放回归覆盖。
- 杜比视界启动等待当前源的原生输出矩阵／VO 确认；官方控制器提前公布尺寸时，不再把尚未完成的转换误判为不兼容。继续使用原总 deadline、格式不兼容错误和严格颜色阈值。
- Android 采用按源管理的 SurfaceTexture，保留无隐式 seek 的尺寸更新与 unload 后释放屏障。首帧使用公开 frame-consumed 回调；不接管 Flutter 内部帧监听。尺寸准备与帧消费分开等待。应用继续预设初始尺寸、隐藏未就绪纹理，并保留 Dolby Vision 的 gpu-next 选择。
- Windows 的 message-only HWND、释放完成确认、渲染通知合并、GPU 队列、视口上限、稳定 texture ID 和 descriptor COM 引用已进入个人 fork。官方的单全局插件实例／WndProc 接管由每实例转发替代，以适配独立播放窗口。
- Windows SDK 下载、解压、SDK 逐文件校验和安装时 DLL 复核移到库插件。ANGLE 解压文件也逐项校验。应用入口只核对依赖契约，不再替换 SDK 或执行视频源码变换。
- Linux 沿用官方 EGLImage 互操作及 `BLOCK_FOR_TARGET_TIME=0` 修复；新 libmpv 随 bundle 交付。打包入口使用 bundle 的库，拒绝替换成主机发行版 libmpv；来源、库摘要与 distro notices 分别保存。
- Linux 视频插件也链接同一构建的头文件和 libmpv，安装后用 `$ORIGIN` 查找同目录库，避免发行版 libmpv 提前加载形成双来源。整数尺寸默认值改为 0，纹理尺寸在转换为无符号类型前检查范围，保留严格编译检查。

硬解、GPU 资源交付和 Flutter 最终合成分别观测。同设备可直接交付，不同设备仍允许每个新视频帧一次的 GPU 复制；不宣称全链路零复制或独立系统视频 plane。Android 视口候选继续默认关闭，未改变弹幕 Ticker 或缓存预算。

## 验证记录

- 个人 fork：核心扩展／库选择／进程身份测试 13 项；视频生命周期／配置测试 22 项；核心、视频生产源码与相关测试静态分析通过。整仓示例 `media_kit_test` 仍有既有 file_picker API 分析错误，不将生产源码分析结果表述为整仓示例通过。
- Windows：9 项受控释放／渲染队列／尺寸检查通过；真实 ANGLE/D3D11 的 100 帧共享、复制回退、缩放、共享 display 生命周期及 descriptor 资源保留通过。
- Windows 媒体脚本已覆盖分轨、headers、续播、重播、首帧、后台意图、系统媒体控制、断流与静默停滞恢复。五分钟缓冲的初次运行行为断言通过，但测试结束仍保留 Video/Focus 子树，触发 semantics handle 检查；补充夹具卸载后复测通过，没有放宽播放器断言。
- Windows 媒体专项 34 项通过（另 1 项环境跳过），PGC／直播／音质专项 4 项通过，暂停／播放的纹理尺寸回归 1 项通过。杜比视界两种解码的颜色误差均为 9.8214，低于既有 12 阈值；无 Vulkan 的格式错误及恢复普通视频路径通过。普通视频恢复 `d3d11va`，转换时使用 `d3d11va-copy` 或软件解码，不能把转换路径视为直通硬解。
- Windows 独立普通 Flutter fixture 完成热重启与热重载：同进程正确找回并销毁旧引用，重新建立视频纹理；随后通过控制端口等待播放器释放并关闭测试进程，未操作用户已安装的应用。
- Linux：最终提交的 [Ubuntu 24.04 CI 42334273402](https://github.com/CKopoer/media-kit/actions/runs/42334273402) 完成个人源码构建、ldd 缺失依赖检查、client ABI 创建／销毁、实际库插件／视频插件的严格 C++ 编译。使用固定摘要的 Flutter 3.47.6 Linux engine SDK 编译插件；readelf 确认 `$ORIGIN`，ldd 确认加载 bundle/lib/libmpv.so.2。产物携带 LGPL 与 Copyright。此项不代表 Flutter 图形播放、VAAPI/NVDEC、Wayland/X11 或完整应用包验收。
- Linux 打包／APT 的 Windows 离线回归 19 项通过；随后使用 WSL Ubuntu 22.04 完成包含 POSIX 运行时脚本的 26 项离线回归。它不代表 Ubuntu 24.04 图形或完整应用包验收。

根应用与四个包的 `tool/check.ps1 -EnforceLockfile` 通过，离线测试共 5,569 项通过；根测试 13 项环境跳过，mux 原生测试 10 项因未配置 `BILI_MUX_LIBRARY` 跳过。随后仅增加 Linux CMake／C++ 修复并更新媒体 Git ref，重跑 Lint 与静态分析通过；最终 ref 的两处媒体锁文件均通过 `pub get --enforce-lockfile`，Linux 原生／插件 CI 通过。mux 组件构建与播放器原生回归分别记录，不能把配置跳过计为 mux 原生测试通过。

本机日志集中在忽略目录 `build/media-kit-port/`。Windows 的受控媒体、尺寸、杜比视界与普通热重载为 Debug 功能回归，原生 D3D11／ANGLE 用例为独立 C++ 回归。本轮未做官方／旧 fork／个人 fork 的同条件性能 A/B，不用 Debug 帧率或包版本推导性能收益。

## 本地产物

- Android arm64 开发 Release：`build/development/android-arm64/BiliSail-test-arm64-release.apk`，包名 `dev.bilisail.bilisail.test`，名称“BiliSail 测试版”，版本 `1.2.7+0`，实际 AOT／不可调试检查由开发构建脚本完成。APK SHA-256：`85dc2b60419c251f494be13569e4c672fe206cf59a3ea2b1ba1acd6c7f561430`；开发签名证书 SHA-256 仍为 `1a69fd8175656b4c091bea4dda3f30772901280f193a4c774c1412679ca30d1b`。仅构建与校验，没有安装或操作设备数据。
- Windows x64 普通入口 Release：`flutter build windows --release -t lib/main.dart` 通过，入口 `build/windows/x64/runner/Release/bilisail.exe`，版本 `1.2.7+0`。保留整个 Release 目录使用；安装后的 libmpv DLL 摘要为 `222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`，与固定 SDK 一致，来源与许可文件随目录交付。独立 mux 的 Windows 构建通过，仍不等于其跳过的原生测试已通过。

## 设备与平台边界

本轮开始时无 Android ADB 设备，开发 Release 仅构建，不安装、不卸载、不清数据或复制正式包凭据。Apple 本平台构建与设备不可用。Linux CI 为 native 构建／ABI 检查，完整应用构建、安装及图形播放待对应主机验证。mux 与播放器的 FFmpeg 保持独立。

## 2026-11-07：Windows ARM64 扩展

2026-11-09：下述初版 ARM64 SDK 经 #100 排查确认禁用了 OpenGL／ANGLE，已替换为具备相应能力的 LGPL SDK，并修复原生渲染降级和错误传播。当前来源、摘要与未构建／实机边界见 [Windows ARM64 闪退修复](windows-arm64-preview-crash-2026-11-09.md)；下列归档及 Vulkan loader 记录作为历史保留。

应用与 `bili_player` 的八个媒体包及两份锁文件统一更新到 `f57d7c5ffd564d7a91c45769943831d468caeb2f`。该次修改集中在 Windows 库插件、视频链接和验证工具；其他平台的媒体实现与原固定资产继续沿用。

- libmpv ARM64 使用同一 `88eb9f2e73945d8bc9c133a2f67babaa9af34680` 的 LGPL aarch64 SDK；归档摘要 `bdffd1f6c2ce4f083bea6fd8c0dec845065468ba7d0426c23cb9b09c8b540b86`，DLL 摘要 `6139b27ac410fc2535161e3e11969bbc8b27c2b6850a61e0550266f9a08c8c52`。
- ANGLE ARM64 固定 `a96fca8d5ee2ca61e8de419e38cd577579281c9e` 的 D3D11/OpenGL 构建，归档摘要 `f7f122533644ec0dd1f52f0117b9fa57ceb3f69dff3359579028ff4008f74f69`。上游包缺少动态导入库，fork 从已校验 DLL 的 115／1809 个具名导出记录生成 `.def`，使用目标 MSVC `lib /machine:arm64` 生成动态导入库，不链接附带的静态 ANGLE。
- mpv 的 `vulkan-1.dll` 是硬导入，不能仅靠无 Vulkan 的 ANGLE 包满足。另镜像 MSYS2 的 Khronos Vulkan Loader 1.4.357.0 ARM64 包，归档 SHA-256 为 `1a5e4c82fc568b83b2e2cbb1e9145d61bda15ed6e2d9f6fdfb96e674aaed49b9`；DLL 和 Apache-2.0 许可分别校验、随包保留，不依赖开发机系统安装的 loader。
- 三份归档逐字节镜像到 [ARM64 原生 Release](https://github.com/CKopoer/media-kit/releases/tag/native-windows-arm64-2026-11-07)，原始二进制未修改；新版本不是个人重新编译。原始 ANGLE LICENSE、源码／构建材料与导出定义随来源记录保留。
- 库插件按目标选择 SDK、头文件、导入库和运行时 DLL，归档及解压文件分别校验。ARM64 mpv 的 BCJ 过滤器使用 7-Zip 23.01+ 解压，不能由 CMake 内置 libarchive 代替。x64 原有 SDK 和 ANGLE 路径保持独立。

本机通过两种架构的 CMake 资产准备与逐文件校验，验证 ARM64 mpv／ANGLE 的 PE 头及动态导入库生成；可选 MDK 0.39.0 完整 Windows SDK 的 SHA-256 与 20 个 ARM64 EXE／DLL 的 PE 架构也已核对。原生 CI、应用打包及设备验收边界见 [CI/CD](ci-cd.md#windows-arm64-构建)，不从静态检查推导硬解性能或实际音画体验。

最终 [Windows 原生 CI 42366829360](https://github.com/CKopoer/media-kit/actions/runs/42366829360) 的 x64／ARM64 Flutter Release fixture 编译、插件链接、实际 DLL 加载、PE 架构和 mpv client ABI／创建销毁检查通过。ARM64 由固定 Flutter 自带引导器安装原生 Dart 3.13.5，生成 ARM64 应用；许可证按应用输出目标展开安装，避免 Flutter 的生成器表达式前缀被当成字面路径。此项不代表完整 BiliSail 安装包、真实安装 UI、视频纹理或硬解性能已经通过。
