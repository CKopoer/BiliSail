# Windows 硬解边缘绿线：定位与原生修复

日期：2026-11-07～2026-11-08（Asia/Shanghai）。先用原生探针复现并定位，再在个人 mpv／media-kit fork 修复和构建固定 Windows x64 SDK；应用只更新统一依赖，不安装诊断 shader。未操作账号、用户设置或其他功能的同期修改。

## 结论与范围

在本机 AMD Radeon(TM) Graphics 上复现了用户所述的方向：AV1 横屏画面底部细绿线、竖屏画面右缘绿线。8-bit NV12 和 10-bit P010 都会出现。保持素材、原生 SDK、GPU 和输出尺寸相同，`d3d11va-copy` 与软件解码正常；直接硬解配合有效平面边界修正也正常。

这些证据将本轮复现定位到 **D3D11 解码表面经 EGL／ANGLE 映射后的边缘采样**：有效图像与纹理分配范围不一致，插值混入填充区。它不是 Flutter 控件、弹幕或页面布局产生的线，也不是必须关闭硬解才能解决的问题。填充区的具体内容及驱动行为仍未直接读回，不据此单独归责 AMD 驱动。

本机合成 HEVC 8／10-bit、横／竖屏素材没有复现；不能把 AV1 结论直接当成用户全部 HEVC 样本的根因。用户原始问题文件、其他 AMD 型号／驱动尚未验证。额外 NVIDIA 对照中，横屏正常、竖屏右缘也能复现，因此该类问题并非 AMD 独有。

## 环境和隔离

- AMD：PCI `1002:164e`，驱动 `32.0.21042.62`。探针通过 DXGI LUID 指定 ANGLE 适配器，再从实际 EGL D3D11 device 读取 LUID 复核；禁止静默跑到本机 NVIDIA。
- NVIDIA 对照：RTX 4070 Ti SUPER，驱动 `32.0.16.1742`，同样读取实际 ANGLE 设备。
- libmpv：`v0.41.0-1150-g88eb9f2e7`，FFmpeg `N-127388-g615b07170`。DLL SHA-256：`222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`。
- 使用当前 Windows CMake cache 所选的固定 libmpv／ANGLE SDK。`libEGL.dll` SHA-256：`b2590bd0692f0381fc45c20bf1c7f7f713c9ea19c7ea6bab62efdd1fadc4eaac`；`libGLESv2.dll`：`620bb6e38d7ed6c760a0cf4a8eb6a8f64b259b96ff286551cd32cefc6c35ca39`。
- 输出采用与插件相同的 GLES 2 context、BGRA D3D11 shared texture、EGL pbuffer 和 libmpv OpenGL render API，直接抓取渲染结果。未经过 Flutter 合成，所以可以把故障边界缩小到它之前的原生链路。探针不等于完整 Flutter 应用验收。
- 本地 FFmpeg 只用于生成无账号、无网络的合成素材；播放器仍加载上述固定 libmpv。它与 `bili_mux` 的封装运行库没有互用。

## 对照设计与观测

[原生探针](../../tool/native_tests/hwdec_edge_probe.cpp)接受本地素材、解码方式、输出尺寸与显卡 vendor。每次以新进程打开素材，确认播放时间推进到至少 0.25 秒，暂停并抓取 RGBA；实读 `hwdec-current` 必须与请求相同，软件回退不算硬解通过。

[执行脚本](../../tool/test-windows-hwdec-edges.ps1)生成并用 ffprobe 核对 12 个素材：HEVC／AV1 各 8／10-bit 横竖屏、H.264 8-bit 横竖屏，以及两种 128 对齐的 AV1 控制素材。每个素材使用原尺寸和半尺寸，分别运行直接硬解、copy-back、软件解码与平面边界修正，共 96 次抓图。

灰色素材便于测量边缘：取外侧一行／列（排除角落）和中心区域，记录 RGB 均值及 `G-max(R,B)`。修正和 copy-back 都要与软件参考逐区域、逐通道比较，均值误差不得超过 2/255；不能只用“绿线肉眼不见了”判定成功。

最终 96 次抓图通过：copy-back 与平面边界修正相对软件参考的最大区域 RGB 均值误差为 **0.188/255**。另以保留红／蓝／黄边缘的静态 10-bit AV1 素材补跑横竖屏、原尺寸／半尺寸和四种路径，共 16 次抓图，最大参考误差 **0.157/255**；没有通过裁去边缘色条获得正常结果。[机器可读摘要](data/windows-amd-hwdec-edges-2026-11-07.json)保留各组实际解码器、像素均值及素材／SDK 摘要。

AMD 的关键观测如下；8／10-bit 的异常幅度一致。

| 素材／输出 | `d3d11va` | `d3d11va-copy`／软件 | GPU 平面边界修正 |
| --- | --- | --- | --- |
| AV1 1920×1080，原尺寸 | 底部绿线，最大绿色超额 69/255 | ≤1/255 | ≤1/255 |
| AV1 1080×1920，原尺寸 | 右缘绿线，最大绿色超额 163/255 | ≤1/255 | ≤1/255 |
| AV1 横屏半尺寸 960×540 | 边缘仍异常，最大绿色超额 8/255 | ≤1/255 | ≤1/255 |
| AV1 竖屏半尺寸 540×960 | 右缘仍异常，最大绿色超额 49/255 | ≤1/255 | ≤1/255 |
| AV1 1920×1152／1152×1920 对齐控制 | 正常 | 正常 | 正常 |
| 合成 HEVC、H.264 横竖屏 | 未复现 | 正常 | 正常 |

例如竖屏右缘，直接路径 RGB 均值约 `(13.16, 175.83, 0)`，copy-back 约 `(127.78, 128.05, 127.78)`，中心两者均接近中性灰。横屏底缘直接路径约 `(79.76, 148.14, 71.09)`，copy-back 约 `(127.76, 128.13, 127.76)`。

OpenGL 抓图的 `gl_top` 对应此插件显示方向的画面底边；像素判断始终检查四侧，未用翻转截图掩盖异常。

## 诊断原型与正式修复

[诊断 shader](../../tool/validation/hwdec_plane_bounds.glsl)在插值前分别处理 LUMA 和 CHROMA：根据可见输入尺寸，把采样坐标限制在最后一个有效 texel 中心以内，并在 GPU 中物化为正常纹理。输出尺寸保持原值，没有裁掉视频边缘、覆盖黑线或把硬解改成软件解码；实读仍为 `d3d11va`。原型增加 GPU pass，并不宣称全链路零复制。

初版只修色度平面，虽然消除了绿线，但 AV1 10-bit 半尺寸仍留下约 4/255 的灰度暗边，像素回归拒绝该版本。修正亮度平面后才进入最终矩阵。因此正式修复应保护整个有效采样范围，而不是只消除绿色。

正式修复位于 [个人 mpv 的 D3D11/EGL mapper](https://github.com/CKopoer/mpv/blob/afd6da8843a07f463ba4c736a2ea636b1a92e23e/video/out/opengl/hwdec_d3d11egl.c)，由 media-kit 库插件分发：

1. 对比实际解码纹理分配尺寸与 `src_params` 可见尺寸。只有存在填充时，才用同一 D3D11 device/context 将有效区域复制到可见尺寸的 NV12／P010 纹理，再导入 EGL。两平面的物理边界随之正确，现有 `GL_CLAMP_TO_EDGE` 能扩展最后一个有效 texel。
2. 纹理在 mapper 生命周期内复用，尺寸／格式改变时重建，释放时归还纹理及 context；只有成功 acquire 的 EGL stream 才 release。映射失败按原生错误路径处理。
3. 解码仍是 `d3d11va`，不改变用户解码偏好，不下载到 CPU、不改整幅色度滤波、不裁去显示边缘；有填充时增加一次 GPU 内复制，未填充时保留原映射。未称为完整链路零复制，也未据此宣称性能提升。
4. 固定 [Windows x64 构建记录](https://github.com/CKopoer/mpv/actions/runs/42387266918) 保留工作流、容器摘要及各源提交。FFmpeg 保持原版本源码，容器提供的其他静态依赖和编译器与旧 SDK 不完全相同，因此另构建同工具链、同依赖、仅还原旧 EGL mapper 的控制 DLL，区分映射修复与依赖更新。

该实现作用于当前 mapper 已支持的 NV12／P010；4:2:0 表面尺寸向偶数取整。奇数可见尺寸、其他色度采样及原始 HEVC 问题文件仍不在已验证范围。Windows ARM64 保留旧资产，未声称包含此次修复。

本轮 shader 只验证未旋转、未裁剪的 4:2:0 输入，**未安装到正式播放器**；其 `input_size` 不能直接视作任意旋转／裁剪条件下的底层纹理有效范围。没有为修复原型引入应用层原生源码变换或修改 Pub 缓存。

额外排除：`d3d11va-zero-copy=no` 在当前 ANGLE 路径仍有绿线；`gpu-dumb-mode=yes` 也不能消除。`cscale=nearest` 可消除本次绿线，但会改变整幅画面的色度重建，不能当作无画质代价的正式修复。

## 正式 SDK 的像素回归

AMD 新 mapper **200 次抓图通过**：在首轮 96 次矩阵上增加 90／180／270 度旋转、保持右下边缘的裁剪、Lanczos／Spline36 色度缩放、10-bit 彩色边条和横竖屏 4K AV1。直接硬解相对软件参考的最大区域 RGB 均值误差为 **0.151/255**；包含 copy-back／原型路径的最大误差为 0.188/255，全部低于 2/255 阈值。所有直接路径实读为 `d3d11va`，输出参数保持 D3D11 NV12／P010。

NVIDIA 新 mapper 的 **96 次抓图通过**，直接路径和软件参考的区域 RGB 均值相同，包含其他路径的最大误差为 0.094/255。同工具链、同依赖、仅还原旧 mapper 的 AMD **96 次控制抓图**再次出现 AV1 底部／右缘绿线，copy-back 和诊断 shader 仍正常；它们是故障控制，未把异常 direct 当作修复通过。新旧 mapper 共 392 次抓图的[固定摘要](data/windows-amd-hwdec-fix-2026-11-07.json)记录每组实际解码器、格式、素材／DLL／源码摘要及像素误差。

最终 SDK 由个人 media-kit `f57d7c5ffd564d7a91c45769943831d468caeb2f` 分发：[原生 Release](https://github.com/CKopoer/media-kit/releases/tag/native-windows-hwdec-edges-2026-11-07)。归档 SHA-256 为 `6739acd7529400cc877ea84e417714bf043769ef088cd1b248d3de2467417ced`，DLL 为 `8fa6af29a94623d7d1e16bc6db48668f321e3fc9f1eaa86a8df8d61ec57f00e3`，发布端返回的摘要与本地一致。补充许可的打包脚本验证 DLL、import library、头文件及 JAR 与 CI 原始产物逐字节一致。插件负责下载、解压及 51 个文件的校验，应用不变换 SDK／视频源码或修改 Pub 缓存。

此前未启用 ANGLE mapper 的中间构建被实际硬解检查拒绝，未发布或接入应用；最终构建日志明确编译 `hwdec_d3d11egl.c` 并断言相应功能启用。探针也修正了最后一个 ANGLE display 终止前释放外部 D3D11 纹理引用的顺序，避免错误路径在模块卸载后释放 COM 对象。

## 重复执行和材料

先正常构建 Windows，使 CMake cache 指向项目固定 SDK，然后执行：

```powershell
./tool/test-windows-hwdec-edges.ps1 -RequireCleanDirect -IncludeTransforms
# 在一个新的输出目录记录 NVIDIA 同条件对照：
./tool/test-windows-hwdec-edges.ps1 -RequireCleanDirect -VendorHex 10de -OutputDirectory build/validation/nvidia-hwdec-edges-new
```

脚本要求 Visual Studio C++、ffmpeg 和 ffprobe；它不构建／覆盖普通应用、不改变 Windows 图形偏好，也不终止现有播放器。全部测试 DLL、原始 RGBA、素材、日志、编译命令和完整 JSON 留在忽略的 `build/validation/` 下。

本轮主要材料：`build/validation/amd-hwdec-edges-verified/`；初版色度原型失败记录保留在 `build/validation/amd-hwdec-edges-final/`，排除参数和 NVIDIA 单项对照保留在 `build/validation/amd-hwdec-edges/`。灰色横屏的边缘放大对照为后者的 `av1-bottom-comparison.png`（左直接硬解，右 copy-back）。

原生探针使用 MSVC C++17 `/W4 /WX` 编译通过；最终源码经 clang-format，PowerShell 语法与文档相对链接检查通过，`git diff --check` 通过。探针的未知实验参数在创建原生状态前明确拒绝。

`tool/check.ps1 -SkipPub` 完成打包边界脚本、根应用／四包格式检查、`flutter analyze --no-pub` 和 Linux 本地插件分析。根测试运行到 `+723`、最后显示 `workspace_router_test.dart` 的账号切换用例后超过 5 分钟没有新输出；停止了本次检查拥有的测试进程，保留日志和停止记录，**完整根测试未完成**，没有为通过它修改导航／账号代码。

随后独立执行 `tool/check.ps1 -SkipPub -Stage PackageTests` 通过：bili_api 696、bili_player 256、bili_danmaku 161、bili_mux 5，共 1118 项；mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。检查日志为 `build/validation/amd-hwdec-edges-{check,package-check}.log`，停滞记录为 `build/validation/amd-hwdec-edges-check-stall.txt`。工作区同时存在其他开发改动，上述离线检查仅表示当时观测，不归因于本轮新增探针。

未进行性能、能耗、真实账号、HDR／杜比视界或长期播放验收。

## 上游依据

- [mpv AMD 底部一像素绿线报告 #10963](https://github.com/mpv-player/mpv/issues/10963)：已知直接采样／填充区问题的先例，不作为当前复现的替代证据。
- [mpv 参数手册](https://mpv.io/manual/master/#options-d3d11va-zero-copy)：该开关仅适用原生 D3D11 GPU 输出，不能套用到当前 OpenGL／ANGLE 输出。
- [固定 mpv 的 D3D11／EGL 映射实现](https://github.com/CKopoer/mpv/blob/88eb9f2e73945d8bc9c133a2f67babaa9af34680/video/out/opengl/hwdec_d3d11egl.c)：导入分配纹理，包装各平面的实际纹理宽高。
- [FFmpeg 的表面对齐逻辑](https://github.com/FFmpeg/FFmpeg/blob/n8.0.1/libavcodec/dxva2.c#L593)：说明可见尺寸与表面分配尺寸为何可能不同；当前播放器的精确 FFmpeg 版本另见上述实读记录。

## 后续应用验收（2026-11-08）

为隔离同期其他播放后端开发，应用验收工作区位于 `build/validation/amd-hwdec-app-check/`，从已提交应用 `d081154` 出发，只叠加本次统一媒体 ref／锁文件和 SDK 校验脚本。更新前完整 `tool/check.ps1 -EnforceLockfile` 通过：根测试 4635、API 696、player 255、danmaku 161、mux 5，共 5752 项，环境跳过 13、mux 原生跳过 10；媒体 fork 此次没有 Dart／pubspec 内容变更。最终 ref 的锁定解析、静态检查与原生／应用验证另按实际完成结果记录。

新 SDK 的 7 项下载／解压完整性回归、9 项原生释放／队列回归通过；真实 GPU 队列和稳定纹理 ID／descriptor 生命周期／resize 回归通过。中间的应用构建因独立目录缺少 MDK 缓存、NuGet 路径和尚未生成 Flutter 头文件而重试；复用按现有清单核对 SHA-256 的 MDK 缓存、为该进程补充既有 NuGet 路径并由 Flutter 生成头文件，没有改动这些依赖或业务代码。

最终固定 ref 的 Lint／锁文件复验通过。当前主工作区另执行完整 `tool/check.ps1 -EnforceLockfile` 通过：根测试 4635、API 696、player 278、danmaku 161、mux 5，共 **5775 项**；13 项环境跳过、10 项 mux 原生跳过，未把后者计作原生通过。主工作区包含同期后端开发，本次提交只收纳绿线修复相关文件和文档段落。

Windows x64 普通入口 Release 构建通过，产物位于独立验收目录 `build/validation/amd-hwdec-app-check/build/windows/x64/runner/Release/bilisail.exe`。bundle 中 libmpv DLL 的 SHA-256 与测试 SDK 一致（`8fa6af29…c57f00e3`），并核对了固定 mpv 源提交和 44 份 provenance 文件随包存在。Release 为实际普通入口；后续集成测试使用 Debug 作功能回归，不据其帧率评价性能。

`tool/test-windows-codecs.ps1` 通过：H.264／HEVC／AV1 与独立 AAC 音轨，自动／软件共六组；自动模式均实读 `d3d11va`，软件模式为 `no`，视频尺寸和音频声道正确。普通应用路径实际加载了更新后的原生库。

完整 `tool/test-windows-media.ps1` 通过：15 组、66 项（含其附带的 fvp 兼容、音轨恢复、连续 seek 和两分钟前向缓冲回归），1 项交互桌面用例按环境跳过；加上 codecs 的 1 项共 **67 项 Windows 应用集成测试通过**。前向缓冲的实际采样仍约 120 秒；该兼容回归不作为绿线修复的性能结论。日志分别为 `build/validation/amd-hwdec-app-{codecs,media}.log`，Release 与 SDK／队列检查分别留在 `amd-hwdec-windows-release-ready.log`、`amd-hwdec-media-assets.log`、`amd-hwdec-video-dispose.log`、`amd-hwdec-gpu-queue-ready.log`；全量检查为 `amd-hwdec-current-workspace-check.log`。

最终仍未验证用户原始 HEVC 问题文件、奇数可见尺寸、其他色度采样、HDR／杜比视界、Windows ARM64、Android／Apple、长期稳定性和性能／能耗。没有将此前其他任务的设备或性能记录视为本次通过。
