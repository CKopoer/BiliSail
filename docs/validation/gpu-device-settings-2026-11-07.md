# 解码与输出设置

日期：2026-11-07。

## 2026-11-08：直出入口显示与 GPU 选择移除

此前整理解码设置时，将播放后端和 Android 视频输出都放在硬件解码条件内，导致软件解码时原有「解码直出纹理（实验）」入口不可见。

现在「设置 → 播放 → 视频编解码」始终显示播放后端；Android 始终显示兼容渲染／解码直出纹理。media_kit／fvp 硬件解码时可切换输出；软件解码下保留选中偏好、置灰并说明原因。恢复硬件解码后，可继续使用原有输出偏好。实际生效仍在下次打开或重新加载播放源，悬停预览继续使用兼容输出。

移除 GPU 设备选择的界面、设置字段、应用层目录和 Windows 原生枚举 channel；应用创建 fvp engine 时使用后端自动选卡。旧 `fvpGpuDeviceId` 读取时忽略，下次成功保存设置后移除；`preferences.v1` 快照版本由 43 升至 44，不修改 SQLite 表，也不重置后端、解码方式、输出或其他有效配置。原逐设备选择集成测试随入口移除。

新增回归覆盖软件解码下后端仍可切换、Android 输出置灰与偏好恢复、两后端切换，以及旧 GPU 字段移除时其他设置保留。

本轮定向测试 `test/features/settings/playback_backend_test.dart` 7 项通过，`flutter analyze --no-pub` 通过；Windows 内存设置页 fixture 的 Debug 构建、启动和热重载通过，运行时错误采样为空。根检查已通过打包边界脚本和根应用／四包格式门槛，随后按用户要求停止全量回归；未把未完成的检查计为通过。本轮未进行 Android 实机安装、播放或性能测量，也未执行 mux 原生回归。

以下为 2026-11-07 的历史实现与验证记录，其中手动 GPU 选择入口及其集成测试已于 2026-11-08 移除。

## 设置与生效范围

「设置 → 播放 → 视频编解码」按以下顺序显示：

1. 视频解码方式：软件解码／硬件解码（优先）。沿用已保存的 `software`／`automatic` 值；硬解不支持当前编码时仍允许软件回退。
2. 硬解下显示播放后端、GPU 设备；Android 继续显示兼容渲染／解码直出纹理。
3. 优先视频编码、优先音质在两种解码方式下均可调整。

软件解码使用已保存的后端，界面显示该后端名称；隐藏硬解选项时保留后端、GPU 和 Android 输出偏好。切回硬解恢复这些偏好。解码与设备设置在下次打开或重新加载播放源时生效，不替换正在播放的 engine。视频／影视／直播／离线／预览继续共用组合根的 `ConfigurablePlayerEngine`；视频编码与音质偏好的原有适用范围不变。

## 平台与后端能力

| 平台／后端 | GPU 设备选项 | 边界 |
| --- | --- | --- |
| Windows fvp／MDK | 自动、当前 DXGI 硬件适配器 | 选择视频解码设备，不改变 Flutter 界面渲染 GPU；跨 GPU 传输可能增加开销 |
| Windows media_kit | 自动 | 当前 ANGLE／libmpv 直通硬解复用渲染上下文的 D3D11 设备，不能独立指定；用户可通过 Windows 图形设置选择应用 GPU |
| Android 两后端 | 自动 | 系统 MediaCodec 选择解码器，不展示桌面 GPU 列表 |
| macOS／iOS 两后端 | 自动 | 系统 VideoToolbox 选择设备，当前接入未提供独立选择 |
| Linux 两后端 | 自动 | 当前未接入 DRM／CUDA 等各自设备枚举与选择，不复用 Windows 索引 |

Windows native channel 通过 DXGI `EnumAdapters1` 枚举，保留原始索引、排除 software／WARP 适配器；由设备目录端口注入设置应用层。界面只在 fvp 且目录支持时读取设备，可刷新重试；读取失败不清除偏好。

`preferences.v1` 快照增加 `fvpGpuDeviceId`，schemaVersion 由 42 升至 43，不改 SQLite 表。空字符串、旧快照缺失或非法类型表示自动。保存失败沿用设置控制器的回退；恢复默认清空该字段。标识采用 PCI vendor／device／subsystem／revision 加同型号出现序号，不落盘只在本次枚举有效的索引或重启后可能改变的 LUID。多个完全相同型号的设备仍依赖其出现顺序区分，这类机器尚未验证。

每次为已保存的 fvp 硬解偏好创建 engine 时，重新读取目录并解析当前 DXGI 索引。设备缺失时本次自动选择并保留偏好，设置显示不可用提示；枚举报错时中止该次打开，避免把过期索引传给其他 GPU。自动模式和软件解码不为播放初始化额外枚举 GPU。

显式设备选择使用 `MFT:d3d=11:adapter=N`，继而 `D3D11:hwdevice=N`，失败后可回退 `FFmpeg`／`dav1d`。不把 DXGI 编号传给独立枚举的 D3D9／DXVA 或 CUDA，也不回退到未指定设备的硬解器。自动选择保留原解码器顺序；软件模式始终只提供软件解码器。

## 依据与来源

- MDK 官方 [Decoders](https://github.com/wang-bin/mdk-sdk/wiki/Decoders)：MFT 的 `adapter` 与 D3D11 的 `hwdevice` 参数。现有固定 MDK 0.39.0／fvp 提交不变，见 [fvp 记录](fvp-backend-2026-11-07.md)。
- mpv 官方 [ANGLE D3D11 互操作实现](https://github.com/mpv-player/mpv/blob/master/video/out/opengl/hwdec_d3d11egl.c)：从 EGL 当前上下文取得 D3D11 设备；[手册](https://mpv.io/manual/stable/#options-d3d11-adapter)中的 D3D11 输出选项不能直接视作当前 libmpv／ANGLE 路径可独立选卡的保证。没有为选卡改变现有 media_kit 输出或强制使用 copy-back。
- Microsoft [EnumAdapters1](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgifactory1-enumadapters1)：DXGI 适配器枚举接口。新增代码为本项目实现，没有复制上游实现。

## 验证

定向测试覆盖配置迁移、保存／失败回退／重置、软硬解切换后偏好保留、后端能力隔离、设备重排／缺失／枚举失败，以及 MDK 参数映射和跨平台隔离。

原生回归入口 `integration_test/windows_gpu_device_selection_test.dart` 使用本地 DASH 视频和独立音轨，逐设备打开、观察解码器与音频／画面、暂停／seek／释放，再验证保留 GPU 偏好时软件模式仍使用 FFmpeg。此回归不以配置值推导物理 GPU 使用率或性能。

本轮执行结果：

- `tool/check.ps1 -SkipPub`：打包边界脚本通过，但根目录格式门槛被本轮未修改的 `test/core/platform/mini_player_window_service_test.dart` 阻塞；未顺带修改该文件。任务涉及的 15 个 Dart 文件格式检查通过，四包与 Linux 本地插件共 206 个文件的格式检查通过，`git diff --check` 通过。
- 独立运行检查阶段：根应用 4607 项通过、13 项按原条件跳过；bili_api 678、bili_player 235、bili_danmaku 161、bili_mux 5 项通过。未配置 `BILI_MUX_LIBRARY`，mux 的 10 项原生用例跳过，不计为原生通过。
- `flutter analyze --no-pub` 与 Linux 本地插件单独分析通过。
- Windows mux 原生资产重新构建通过；新增 GPU 原生回归 1 项通过。枚举得到 NVIDIA GeForce RTX 4070 Ti SUPER（DXGI 0、2）及 AMD Radeon(TM) Graphics（DXGI 1），逐项传入对应索引后，本地 H.264／AAC DASH 播放观察到 MFT 解码、音频、视频输出，暂停／seek／释放正常；软件模式观测到 `hardwareDecoder=no`。未测量各物理 GPU 实际负载，不从 MFT 名称推导资源使用或性能。
- `tool/test-windows-fvp.ps1` 通过：直播／音频／后端切换 3 项、精确跳转及暂停／取消／换源隔离 9 项。
- 使用无账号、内存设置仓储的 Windows 设置页 fixture 启动并热重载通过，运行时错误采样为空；fixture 位于忽略目录，未纳入交付或改写用户偏好。
- Windows x64 普通入口 Release 构建通过。标准输出目录中的 `bilisail.exe` 正在被占用，首次链接报 `LNK1104`；保留运行中的应用，临时把 CMake Release 输出与安装前缀指向 `build/validation/gpu-settings-release/` 后重新构建，核对 EXE、Flutter／mpv／MDK 动态库及 AOT／ICU 资产，并在 `finally` 恢复原 CMake 输出配置。交付或运行须保留该目录完整内容；未进行该 Release 构建的真实账号与长期播放验收。

Android／Apple／Linux 设备、同型号多 GPU 的重排、热拔插与性能／能耗仍需对应环境验收。
