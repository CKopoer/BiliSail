# Windows ARM64 悬停预览闪退修复

日期：2026-11-09。关联 [issue #100](https://github.com/CKopoer/BiliSail/issues/100)。

2026-11-10：用户反馈新构建不再闪退，但仍黑屏，另有 fvp 的 MDK 过期二维码。后续保留 ARM64 GPU 默认路径、撤回统一降级及 SDK 更新见[专项记录](windows-arm64-black-video-2026-11-10.md)；本页初始化检查不能证明已完成实际画面验收。

## 原因与影响

用户报告 Surface Pro X / SQ1 / Windows 11 ARM64 使用 1.2.8+5 时，悬停视频卡片后卡死退出；切换 fvp 后正常。日志停在 media_kit 的 `openStarted`，不能单凭该事件确定原生崩溃指令。

此前固定的 ARM64 SDK 为 `mpv-dev-lgpl-aarch64-20261012-git-88eb9f2e73.7z`。实际 DLL 的 SHA-256 为 `6139b27ac410fc2535161e3e11969bbc8b27c2b6850a61e0550266f9a08c8c52`，与清单一致，但其内嵌参数包含 `-Dgl=disabled -Degl-angle=disabled`，功能列表也没有 `gl` 或 `egl-angle`。Windows 视频插件调用标准 OpenGL render API，因此该构建无法创建它要求的渲染上下文。这是 ARM64 依赖集成缺陷，不能只视为 SQ1 的硬解问题。

原视频插件在 OpenGL 初始化失败后保留 GPU surface／纹理，又进入软件渲染分支；后续可能混用 GPU 纹理与不存在的软件纹理记录。软件 stride 还将 32 位 `int*` 传给要求 `size_t*` 的 API。初始化任务使用 `future.wait()`，无法把任务异常经构造器返回，平台通道也提前报告创建成功。

## 修复

- 个人 media-kit fork 的 ARM64 SDK 改用 [Carapacik 20261031](https://github.com/Carapacik/libmpv-win32-video-cmake/releases/tag/20261031) 已发布的 LGPL 构建，归档逐字节镜像到个人媒体资产 Release。源码为 mpv `41f6a645068483470267271e1d09966ca3b9f413`；构建材料与补丁固定为 `6b921819019b11a84554e4c65c280d2676a15dd8`。没有在本轮编译新的 SDK。
- 新归档 SHA-256 为 `497841ee27697d816ff3aa14a0e1cce0ce639b593d28b53fb4e06e4410c37df6`，DLL 为 `c7b5ab1cd0b98285ce56c96662f1e27bfa08264915554c681c12b16d6de70c11`。实际参数包含 `-Dgl=enabled -Degl-angle=enabled -Dgpl=false`；FFmpeg 构建禁用 GPL／nonfree，并开启 version3。来源和 LGPL 文本随包保留。
- ARM64 直接声明六项配对的 SDK 文件名／摘要，避免继承 x64 的来源材料尾部。新 DLL 没有 Vulkan loader 硬导入，ARM64 不再附带该 loader。其他架构和平台的原生资产保持原固定内容。
- 选择成功的渲染器后才注册 Flutter 纹理；GPU 失败时先释放其上下文和 surface，再创建软件渲染器。软件 stride 使用 `size_t`。两个渲染器都失败时，原生创建任务经 `future.get()` 和平台通道返回错误，Dart 清理就绪监听，不再等待永远不会出现的纹理。
- 库插件解压校验和[应用校验入口](../../windows/native/media-assets.cmake)均检查实际 DLL 内嵌的 `gl`／`egl-angle` 功能。仅有正确摘要、ARM64 PE 头或导出函数不能代替渲染能力验证。
- 根应用与 `bili_player` 的八个媒体包／overrides 及两份锁文件固定到同一修复提交 `9858a8db83faf8bcfa39a8bfbc02dde9a2e92572`，继续使用个人 fork，不修改 Pub 缓存。

## 验证与边界

本轮只执行自动检查与不依赖应用构建的受控原生检查。

- [媒体资产回归](../../tool/test_windows_media_assets.py)覆盖两种 Windows 架构的摘要／文件配对、缺文件、损坏、缺少 OpenGL／ANGLE 能力、相似功能名误匹配，以及实际生产初始化逻辑的 fake mpv／ANGLE 回归。
- 实际新 ARM64 DLL 通过能力检查，旧固定 DLL 被明确拒绝。新归档及六项 SDK 文件摘要、ARM64 PE 头和导入表均已核对。
- 现有 x64 DLL 通过扩展的原生 smoke：加载、client ABI、`mpv_initialize`、软件 render context 创建／释放。此检查不启动 BiliSail，不执行媒体播放。
- 依赖视频包 22 项测试通过，改动 Dart 文件静态分析通过。生产初始化逻辑的独立 C++ 单元测试覆盖六种选择／失败情形；原生释放／渲染队列／尺寸回归九项通过。三个改动 C++ 翻译单元使用真实 mpv／ANGLE／Flutter 头文件通过 MSVC `/Zs /W4 /WX` 语法检查，没有生成应用二进制。
- `tool/check.ps1 -EnforceLockfile` 完整通过：五份锁文件严格解析、打包边界、格式、静态分析和根应用／四包测试均通过；Dart／Flutter 测试合计 6,093 项（根应用 4,819、API 748、播放器 360、弹幕 161、封装 5）。根测试 13 项因 Windows 符号链接权限跳过，mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。日志为 `build/diagnostics/issue-100/check.log`；专项日志同目录保留。

按用户要求未构建应用、未触发远端构建、未安装或操作设备。没有运行中的 Dart 调试进程可供热重载。Windows ARM64 的悬停、点播音画、硬解、全屏／小窗切换及真实崩溃指令仍由后续构建实机验证；自动检查不代表设备验收。
