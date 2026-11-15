# Android 解码直出 HDR 色彩修复

日期：2026-11-15。用户确认色彩异常出现在 Android 开启“解码直出纹理”时，要求修改后提交、不构建，后续自行构建和实机测试。

## 原因与参考

直出使用 `vo=mediacodec_embed`，MediaCodec 将解码帧直接交给 Android Surface，绕过 mpv GPU 色彩转换。项目输出仍由 Flutter 的 SDR 纹理合成，没有实现 HDR 色彩标记与显示器透传契约。因此不能把支持 HDR 解码等同于该直出路径可正确显示 HDR。GPU 输出允许 MediaCodec 硬解继续工作，并由 mpv 完成 HDR 到 SDR 的映射。

只读核对相邻 PiliPlus `217fb54f51f6764176319bbdedab2a7522d75401`：

- 应用入口 `lib/plugin/pl_player/controller.dart` 创建视频控制器时没有指定直出 VO；没有额外的 HDR 亮度、饱和度补偿。
- 实际 overrides／锁文件中，核心与库插件为 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`；视频为 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`。后者的 `media_kit_video/lib/src/video_controller/android_video_controller/real.dart` 默认使用 `gpu`。
- 只借鉴其使用 GPU 渲染并保留硬解的输出职责，独立实现本项目按媒体源选择输出的规则；没有复制 GPLv3 应用源码或 MIT 插件源码，没有修改相邻仓库、Pub 缓存或固定依赖。

原生契约依据：[mpv mediacodec_embed／GPU 输出](https://mpv.io/manual/stable/#video-output-drivers)、[目标色域与传递函数](https://mpv.io/manual/stable/#options-target-trc)。GPU 输出是 HDR 到 SDR 映射，不是 HDR／Dolby Vision 屏幕透传。尚无报告视频或设备日志，不将本次代码定位写成已完成设备色准复现。

## 实现

- 主应用根据实际解析结果的清晰度识别 HDR（125）、杜比视界（126）、HDR Vivid（129），并识别杜比编码提示。使用实际选中的媒体，不能因请求 HDR 但服务端回退 SDR 就错误禁用直出。
- 通用 `MediaTrack.isHdr` 只传递媒体色彩提示，不将 Bilibili 清晰度编号下沉到播放器包。普通视频、PGC、离线解析结果和预览沿用共享映射；Android 文档提供器的 `content://` 到文件描述符转换保留提示。
- `ValidatedSource` 在原生分配和复用判断前，将 HDR 源的 Android 输出规范化为兼容渲染。自动解码仍优先 `mediacodec,auto-safe`，显式软件解码仍为 `no`；不改变音视频配对、位置、播放意图、倍速、音量、增益和超时。
- 设置与调用方传入的偏好保持原值。HDR／SDR 切换后的有效输出不同，现有后端兼容性判断会先释放旧实例再建立匹配的输出；切回 SDR 可恢复直出。预览和直播原有缓冲／时间线规则继续生效，纯音频不受提示影响。
- 已有 Dolby Vision Profile 5 的软件 HEVC／gpu-next RPU 转换和兼容流回退继续保留。普通 HDR 不增加软件解码强制规则，也不人为修改饱和度或亮度。设置说明同步提示 HDR／杜比自动使用兼容渲染。

## 验证与边界

- 定向播放器测试 22 项通过：输出规范化、硬解／软件偏好、传输参数保留、SDR→HDR→SDR、预览／直播／纯音频、文档提供器提示保留，以及已有 Dolby Vision 和解码配置回归。
- 定向主应用 HDR 会话／预览测试 5 项通过：UGC／PGC／离线切源、实际解析降级和静音预览提示传递。
- 全量 `tool/check.ps1 -SkipPub` 通过：格式、静态分析和打包边界检查通过，根应用 5633、bili_api 997、bili_player 356、bili_danmaku 161、bili_mux 5，共 7152 项 Dart／Flutter 测试通过。根应用 13 项及播放器 3 项按条件跳过；未配置 `BILI_MUX_LIBRARY`，mux 原生 10 项跳过，不计作原生封装通过。日志保存在 `build/validation/hdr-direct-output/check-final-2026-11-15.log`。
- 文档新增相对链接和 `git diff --check` 通过。没有运行中的调试应用／DTD，未启动构建或执行热重载。

按用户要求未构建、未安装、未执行原生播放或设备操作，没有新增性能、截图像素或显示器色准结论。自动测试证明输出选择和状态边界，不证明手机上已恢复正确颜色。后续请重点验收：直出设置保持开启时分别播放 HDR 与 SDR，检查色彩、硬解、换清晰度、seek、普通／全屏和离线播放。

当前提示来自已知清晰度及杜比编码；未包含色彩提示的任意外部媒体、直播 HDR 元数据识别、HDR Vivid 动态元数据处理和 HDR 透传不属于本次新增能力。
