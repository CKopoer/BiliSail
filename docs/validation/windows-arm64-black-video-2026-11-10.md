# Windows ARM64 黑屏与 MDK 过期提示

日期：2026-11-10。基线 master `d66a8fc9`，关联 [issue #100](https://github.com/CKopoer/BiliSail/issues/100)。

## 证据与定位边界

Surface Pro X / SQ1 用户确认上一轮构建不再闪退，但 media_kit 播放黑屏；声音尚未确认。本轮用户暂时无法实机测试，没有新的解码器／GPU 日志，不能断言已经重现或确定具体失败的驱动调用。[上一轮修复](windows-arm64-preview-crash-2026-11-09.md)解决 SDK 缺少 OpenGL 能力和初始化失败后的资源混用，成功初始化不等于实际画面已送到 Flutter。

确定的配置缺口是：[video_decoder_configuration.dart](../../packages/bili_player/lib/src/video_decoder_configuration.dart) 的软件解码只设置 `hwdec=no`，`enableHardwareAcceleration` 仍为 true。锁定媒体依赖的 `VideoOutput::Initialize()` 只在 ANGLE／OpenGL **初始化失败**时转为软件渲染；成功创建上下文后，即使设备互操作／共享纹理呈现失败，也继续原路径。因此切换软件解码不能独立排除输出兼容问题。

fvp 是另一个问题：[用户扫码结果](https://github.com/CKopoer/BiliSail/issues/100#issuecomment-6745591641)明确为 `MDK SDK is outdated`。应用虽调用插件的 `registerWith` 安装原 bundled Flutter key，但 ARM64 仍固定旧 MDK v0.39.0 完整 SDK；SDK 自身的过期提示不会因 libmpv 修复而消失。

## 修复

- 使用 `Abi.current() == Abi.windowsArm64` 识别**当前原生进程**，在公共 media_kit 输出适配器中禁用硬件渲染，直接选择已有 libmpv CPU render API 和 Flutter PixelBuffer；悬停预览、点播和直播共用该配置。Windows ARM64 上运行的 x64 进程不会误判。
- 自动解码使用 `hwdec=auto-copy`，允许硬解后复制成 CPU 帧，避免非 copy 解码表面与 EGL 的直接互操作；显式软件解码继续为 `no`。不改用户保存的后端／解码设置，不自动切换到 fvp。
- 该兼容方案有性能代价：锁定原生插件的软件输出上限为 1920×1080，需要 CPU 色彩转换和纹理上传。它是缺少设备验证时的兼容修复，不能据此宣称 SQ1 的 4K、硬解效果或功耗已验收；恢复 GPU 默认值前需要实机像素与生命周期验证。
- ARM64 的 fvp SDK 单独更新到官方 [v0.40.1](https://github.com/wang-bin/mdk-sdk/releases/tag/v0.40.1) 的 `mdk-sdk-windows-vs2026.7z`。归档 SHA-256 为 `3ba57778bb9074dfb559027d1a4fd98a2df715cdbea84c54d51337178169d3b1`。完整包包含 `bin/arm64` 和 `lib/arm64`，无需 ARM64EC 或混用 x64 DLL。其他平台保留原固定资产。
- [资产解析](../../native/fvp/resolve.cmake)支持单平台 URL 覆盖；[构建配置](../../native/fvp/configure.cmake)仍以 SHA-256 校验归档，并按摘要分目录保存通用别名及部分下载，避免升级后复用旧包／旧续传数据。插件自身继续按摘要替换解压缓存。不修改 SDK、授权检查或 Pub 缓存源码。

SDK 原始归档已下载并重新计算摘要，21 个 ARM64 EXE／DLL 的 PE Machine 均为 `0xaa64`。对照现有桥接的三个公开 C 头文件，`Player.h`／`RenderAPI.h` 去除注释后的声明相同，`global.h` 仅版本宏从 0.39.0 变为 0.40.1。保留 0.39 的桥接头文件和绑定，不产生第二套 MDK。另核对新 ARM64 `mdk.dll` 导出了锁定 fvp Dart 绑定所需的全部 35 个 MDK 符号。新 ARM64 FFmpeg DLL 的七个库许可均报告 LGPL 2.1 or later，版本为 `git-2026-10-25-464fc8c-avbuild`，对应源码固定到 `464fc8c2ed53648b9ede81555921e3995d32bbe5`，已补入分发 notices。

## 验证与未测项

- 新增离线 SDK 回归 7 项通过：真实平台选择、两种 Windows 归档别名、正确缓存复用、损坏缓存替换、版本变更的部分下载隔离、错误下载摘要和非法锁摘要拒绝。已纳入 `tool/check.ps1`。
- 原 Android SDK 固定回归 8 项通过。
- 锁定 media-kit 的真实渲染初始化函数通过独立 C++ 回归，包括直接禁用硬件输出时不创建 ANGLE、软件 context 初始化和错误清理。
- 现有生产释放／渲染队列／尺寸 C++ 回归 9 项通过。
- 两种架构的媒体资产校验 10 项、Windows fvp 源码暂存 3 项和 Apple 纹理交接回归通过。
- Flutter 3.47.6 / Dart 3.13.5 下五份锁文件严格解析通过；全仓 1108 个 Dart 文件格式检查通过，根静态分析无问题。播放器包新增 ARM64 两种解码模式均禁用共享纹理的回归，368 项包测试通过。
- 根应用 5009、API 835、播放器 368、弹幕 161、封装 5 项通过，合计 6378 项 Dart／Flutter 测试通过。根应用 6 项按原条件跳过；mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。
- 完整 `tool/check.ps1 -EnforceLockfile` 在未修改的 `tool/test-macos-release-validation.ps1:318` 中断：Linux 上的模拟进程测试报告 `The independent parent failed to terminate a stalled worker and its child`。随后分别完成上述包测试、根应用阶段、格式、静态分析和受影响原生检查；不宣称完整检查脚本通过。

日志与 SDK 核对材料位于忽略目录 `build/issue-100/`，主要为 `check.log`、`root-tests.log`、`player-tests.log`、`windows-fvp-sdk.log`、`mdk-verification.json`。当前主机为 Linux，没有 Windows ARM64 SDK／设备运行环境。尚未构建 Windows 应用或完成 Surface Pro X 的悬停、视频音画、seek、全屏／小窗及 MDK 二维码消失验收；自动检查不作为这些项目的通过证明。MDK 的后续使用期限仍由上游 SDK 控制，固定版本需要持续维护，不能保证永久无过期提示。
