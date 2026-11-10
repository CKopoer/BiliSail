# Windows ARM64 黑屏与 MDK 过期提示

日期：2026-11-10。基线 master `d66a8fc9`，关联 [issue #100](https://github.com/CKopoer/BiliSail/issues/100)。

## 证据与定位边界

Surface Pro X / SQ1 用户确认上一轮构建不再闪退，但 media_kit 播放黑屏；声音尚未确认。本轮用户暂时无法实机测试，没有新的解码器／GPU 日志，不能断言已经重现或确定具体失败的驱动调用。[上一轮修复](windows-arm64-preview-crash-2026-11-09.md)解决 SDK 缺少 OpenGL 能力和初始化失败后的资源混用，成功初始化不等于实际画面已送到 Flutter。

需要区分解码与渲染：[video_decoder_configuration.dart](../../packages/bili_player/lib/src/video_decoder_configuration.dart) 的软件解码设置 `hwdec=no`，同时保留 GPU 渲染，这是正常的职责划分，不能单凭这一点认定存在缺陷。锁定媒体依赖的 `VideoOutput::Initialize()` 在 ANGLE／OpenGL 初始化失败时转为软件渲染。黑屏可能出在解码、渲染或最终纹理呈现；目前没有证据证明是哪一环，也没有证据证明所有 Windows ARM64 设备都需要软件输出。

fvp 是另一个问题：[用户扫码结果](https://github.com/CKopoer/BiliSail/issues/100#issuecomment-6745591641)明确为 `MDK SDK is outdated`。应用虽调用插件的 `registerWith` 安装原 bundled Flutter key，但 ARM64 仍固定旧 MDK v0.39.0 完整 SDK；SDK 自身的过期提示不会因 libmpv 修复而消失。

## 当前变更

- 撤回 `ef181a40` 中新增的 `Abi.windowsArm64` 判断、`enableHardwareAcceleration=false` 和强制 `hwdec=auto-copy`，恢复与 x64 相同的 GPU 输出及 SDK 自动解码默认值；显式软件解码继续为 `no`。应用不再依据 ARM64 架构强制软件输出，也不再因此引入 1920×1080 的软件渲染上限。
- 原生初始化实际失败时，继续使用依赖已有的渲染降级和错误传播。此次没有新增按设备、驱动或失败证据触发的降级策略；#100 的黑屏仍待定位，不能标记为已修复。
- ARM64 的 fvp SDK 单独更新到官方 [v0.40.1](https://github.com/wang-bin/mdk-sdk/releases/tag/v0.40.1) 的 `mdk-sdk-windows-vs2026.7z`。归档 SHA-256 为 `3ba57778bb9074dfb559027d1a4fd98a2df715cdbea84c54d51337178169d3b1`。完整包包含 `bin/arm64` 和 `lib/arm64`，无需 ARM64EC 或混用 x64 DLL。其他平台保留原固定资产。
- [资产解析](../../native/fvp/resolve.cmake)支持单平台 URL 覆盖；[构建配置](../../native/fvp/configure.cmake)仍以 SHA-256 校验归档，并按摘要分目录保存通用别名及部分下载，避免升级后复用旧包／旧续传数据。插件自身继续按摘要替换解压缓存。不修改 SDK、授权检查或 Pub 缓存源码。

SDK 原始归档已下载并重新计算摘要，21 个 ARM64 EXE／DLL 的 PE Machine 均为 `0xaa64`。对照现有桥接的三个公开 C 头文件，`Player.h`／`RenderAPI.h` 去除注释后的声明相同，`global.h` 仅版本宏从 0.39.0 变为 0.40.1。保留 0.39 的桥接头文件和绑定，不产生第二套 MDK。另核对新 ARM64 `mdk.dll` 导出了锁定 fvp Dart 绑定所需的全部 35 个 MDK 符号。新 ARM64 FFmpeg DLL 的七个库许可均报告 LGPL 2.1 or later，版本为 `git-2026-10-25-464fc8c-avbuild`，对应源码固定到 `464fc8c2ed53648b9ede81555921e3995d32bbe5`，已补入分发 notices。

## 此前验证（对应 ef181a40）

- 新增离线 SDK 回归 7 项通过：真实平台选择、两种 Windows 归档别名、正确缓存复用、损坏缓存替换、版本变更的部分下载隔离、错误下载摘要和非法锁摘要拒绝。已纳入 `tool/check.ps1`。
- 原 Android SDK 固定回归 8 项通过。
- 锁定 media-kit 的真实渲染初始化函数通过独立 C++ 回归，包括直接禁用硬件输出时不创建 ANGLE、软件 context 初始化和错误清理。
- 现有生产释放／渲染队列／尺寸 C++ 回归 9 项通过。
- 两种架构的媒体资产校验 10 项、Windows fvp 源码暂存 3 项和 Apple 纹理交接回归通过。
- Flutter 3.47.6 / Dart 3.13.5 下五份锁文件严格解析通过；全仓 1108 个 Dart 文件格式检查通过，根静态分析无问题。播放器包新增 ARM64 两种解码模式均禁用共享纹理的回归，368 项包测试通过。
- 根应用 5009、API 835、播放器 368、弹幕 161、封装 5 项通过，合计 6378 项 Dart／Flutter 测试通过。根应用 6 项按原条件跳过；mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。
- 完整 `tool/check.ps1 -EnforceLockfile` 在未修改的 `tool/test-macos-release-validation.ps1:318` 中断：Linux 上的模拟进程测试报告 `The independent parent failed to terminate a stalled worker and its child`。随后分别完成上述包测试、根应用阶段、格式、静态分析和受影响原生检查；不宣称完整检查脚本通过。

日志与 SDK 核对材料位于忽略目录 `build/issue-100/`，主要为 `check.log`、`root-tests.log`、`player-tests.log`、`windows-fvp-sdk.log`、`mdk-verification.json`。当前主机为 Linux，没有 Windows ARM64 SDK／设备运行环境。尚未构建 Windows 应用或完成 Surface Pro X 的悬停、视频音画、seek、全屏／小窗及 MDK 二维码消失验收；自动检查不作为这些项目的通过证明。MDK 的后续使用期限仍由上游 SDK 控制，固定版本需要持续维护，不能保证永久无过期提示。

## 同日撤回统一降级

用户明确要求不能对 Windows ARM64 统一降级。上述 `ef181a40` 的软件渲染配置及相应测试已撤回，两个生产 Dart 文件恢复到原 master 基线；桌面自动解码的已有测试补充断言 GPU 输出保持开启。MDK 0.40.1 资产、缓存隔离、许可说明及相关回归保留。此前完整测试的结果作为历史记录，不替代撤回后的验证；本轮验证结果见交付说明及 `build/issue-100/revert-arm64-*` 日志。

撤回后验证：播放器包 367 项测试、MDK 资产 7 项回归、三个相关 Dart 文件的格式检查及根静态分析均通过；文档本地链接与 `git diff --check` 通过。通过与 `d66a8fc9` 比较，确认两个生产 Dart 文件与原 master 基线完全一致；MDK 相关源码／资产相对 `ef181a40` 无变更。没有重复运行其余应用／包的全量测试，前述完整检查脚本的 macOS 模拟进程阻塞及 Windows ARM64 实机未测项仍保留。

## PR #110 审查与补充

合入 `b78f7b80` 后保留索引中的 ARM64 与 macOS 冷启动两条记录。审查复现了 SDK 缓存的失败恢复问题：摘要不匹配时留下的 `.part` 会被后续配置继续使用，即使下载源已恢复也可能一直失败。现在校验失败先删除已拒绝的临时文件，再报告错误；正常中断的下载仍可续传，错误内容不会发布为缓存。

Windows 主机上的 8 项 SDK 离线回归通过，覆盖摘要拒绝后重新下载、同版本损坏临时文件清理及原有缓存／版本隔离。新增恢复断言在修复前失败、修复后通过；另核对上游 v0.40.1 Release 资产的公开摘要与锁文件一致。此次审查不改变 GPU／解码默认值，也不将 SDK 或构建验证作为 Surface Pro X 黑屏已经修复的证明。
