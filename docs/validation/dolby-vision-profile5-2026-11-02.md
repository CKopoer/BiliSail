# Windows Dolby Vision Profile 5 偏色修复

日期：2026-11-02。问题：[BiliSail #54](https://github.com/CKopoer/BiliSail/issues/54)。本轮使用公开本地样片验证播放器，不使用没有大会员权限的测试账号请求杜比视界流。

## 根因与参考

Profile 5 的 IPTPQc2 基础层没有 HDR10 兼容回退层。解码出 HEVC 像素不等于完成 Dolby Vision 色彩映射；直接交给普通 YUV 色彩转换会产生绿／紫偏色。

只读对照本地 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8` 的 `lib/plugin/pl_player/controller.dart`：它通过 `VideoController.create` 使用 SDK 默认输出，没有独立的 Profile 5 转换。核对其锁文件及本项目的固定依赖：核心为 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频插件为 `bggRGjQaUbCoE/media-kit` 的 `fd8421d21eade4d6d12de137fa7df902fec20292`。后者桌面原生控制器默认 `vo=libmpv`，Android 默认 `vo=gpu`。

mpv 的 [GPU／GPU-next 对照](https://github.com/mpv-player/mpv/wiki/GPU-Next-vs-GPU)说明 `gpu-next` 不支持 libmpv render API。因而不能仅把 `vo` 改为 `gpu-next` 并继续使用现有 Flutter 纹理。Windows 当前固定 SDK 为 `mpv v0.41.0-1150-g88eb9f2e7`，包含 libplacebo `v7.375.0` 及 FFmpeg `libplacebo` 滤镜；通过实际原生属性和滤镜探针核对，没有替换 SDK、修改 Pub 缓存或相邻仓库。

仅参考 PiliPlus 的配置职责，没有复制其 GPLv3 应用源码或资源。使用已固定的 MIT media-kit 公共接口及其已有生成绑定；原生二进制来源、哈希及许可沿用[Windows ANGLE 记录](windows-angle-direct-hwdec-2026-11-01.md)。

## 实现边界

- Windows 为播放器的独立 weak client 注册 `on_preloaded` 钩子，在解复用完成、选轨／创建解码器之前检查容器 `dolby-vision-profile`。不依赖 API 的清晰度编号或 `dvh1` 字符串，因此同样覆盖没有 codec 提示的本地／离线源。
- 检测到 Profile 5 后，使用 `lavfi/libplacebo` 应用帧内 RPU、色彩重塑和色调映射，输出 BT.709 原色／sRGB 传递函数的 SDR 视频，再交给现有 libmpv／ANGLE／Flutter 纹理。滤镜参数见 [native_video_color.dart](../../packages/bili_player/lib/src/native_video_color.dart)，语义依据 [FFmpeg libplacebo 文档](https://ffmpeg.org/ffmpeg-filters.html#libplacebo)。这不是向屏幕透传 Dolby Vision／动态 HDR。
- Profile 5 自动解码改用 `auto-copy`，为 lavfi/Vulkan 转换提供软件帧；用户显式软件解码继续为 `no`。该路径有下载／上传及转换开销，不声称保留直通硬解性能。没有对整个播放器统一开启滤镜。
- SDR、HDR10、Profile 8 和纯音频不设置此转换；每次换源创建的播放器拥有自己的滤镜与解码配置。其他平台的原有输出保持；本轮不推导其他平台已经支持 Profile 5。
- 配置失败通过既有加载失败／deadline 路径报告；钩子在 `finally` 中继续，weak client 在播放器核心前销毁，保留取消、迟到事件隔离及原生释放顺序。转换所需的 Vulkan／滤镜不可用时不声称成功。

## 样片与复现

来源为 [Dolby 官方 Glass Blowing Profile 5 MP4](https://media.developer.dolby.com/DolbyVision_Atmos/mp4/iOS_P5_GlassBlowing2_1920x1080%4059.94fps_15200kbps.mp4)。[Chromium 样本说明](https://chromium.googlesource.com/chromium/src/+/main/media/test/data/README.md)也登记了此来源和 Profile 5、兼容标识 0。

脚本只下载原文件前 32 MiB，SHA-256 固定为 `2e1a62c39519ccef267353672aff6c2985b7ef145739fb60b56029fa91ec6fac`，再流复制截取第 10～16 秒附近的六秒场景。`ffprobe` 确认 `dvh1`、`dv_profile=5`、`dv_bl_signal_compatibility_id=0`；完整解码提取后的六秒视频无错误。样片、参考图与实测截图只保存在忽略的 `build/validation/dolby-vision/`，不提交或分发原媒体。

```powershell
# 首次显式下载；需要本机 FFmpeg 含 libplacebo 及可用 Vulkan。
./tool/test-windows-dolby-vision.ps1 -PrepareSample

# 后续复用本地样片，不下载。
./tool/test-windows-dolby-vision.ps1
```

原生集成测试通过实际 `VideoSurface`／Flutter 纹理截图，与 FFmpeg 的 Dolby-aware SDR 参考图比较。修复前临时关闭转换钩子，出现明显绿／紫偏色，640×360 RGB 平均绝对误差 **超过 40/255**；修复后自动／软件两种解码均为 **9.82/255**，低于 12 的回归阈值。阈值允许缩放和渲染器差异，不是显示器色准校准结果。自动模式实际为 `d3d11va-copy`，软件模式为 `no`；返回 SDR 实际恢复为 `d3d11va`。

集成测试另覆盖独立音轨解码、开始播放、seek、暂停意图及媒体时钟冻结、换源后恢复原解码路径。已有快照在 seek 中暂停时可能继续标记 buffering，测试按暂停意图与时钟行为验收，不改变该状态机语义。

## 验证结果与未测项

- `tool/check.ps1 -SkipPub` 全量通过：格式、静态分析、打包边界脚本及根应用／四包测试通过。根应用 4041、bili_api 544、bili_player 137、bili_danmaku 153、bili_mux 5，共 **4880 项通过**。根应用 13 项跳过，未配置 `BILI_MUX_LIBRARY` 的 mux 原生 10 项跳过；不计作原生封装覆盖。
- `tool/test-windows-dolby-vision.ps1 -PrepareSample` 通过，包含样片 SHA-256／Profile 检查、完整解码、参考图生成及 Windows 实际纹理集成测试。

- `tool/test-windows-media.ps1` 的 **33 项 Windows 原生媒体回归通过**，覆盖分轨／headers、播放交互、重播、诊断、加载取消／替换／释放／超时、首帧、纯音频、系统媒体控制、断流恢复、预览、音量均衡及五分钟前向缓冲。
- 独立 Debug 样片夹具完成热重载，随后运行时错误查询为空；没有启动普通账号流程或访问会员流。Debug 运行只验证功能，不用于性能结论。
- `tool/build-download-mux.ps1 -Target windows-x64` 准备原生构建资产通过。`flutter build windows --release -t lib/main.dart` 普通入口构建通过；最终 libmpv DLL 的 SHA-256 为 `222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`，与固定 SDK 一致，插件注册不含 integration_test。

没有用真实大会员账号复测 issue 的 `BV1EHsf68End`，没有在报告者 RTX 5070 Ti／驱动上验证，也没有做 HDR 显示器透传、其他 Profile 的原生色准比较、长期播放或性能测量。Android／macOS／iOS／Linux 的本平台构建与设备播放不在本轮修复验证范围内。
