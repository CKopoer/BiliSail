# 播放器与弹幕包首版验证

日期：2026-10-05。实现包：`packages/bili_player`、`packages/bili_danmaku`。本记录只覆盖包内实现与本机静态/单元验证，不代表三端原生播放验收。

## 固定版本与来源

本机 SDK：Flutter 3.47.6、Dart 3.13.5。`bili_player/pubspec.yaml` 精确声明 `media_kit 1.2.6`、`media_kit_video 2.0.1`、`media_kit_libs_video 1.0.7`；`bili_danmaku` 只依赖 Flutter SDK。包内 `flutter pub get` 解析出 Android 原生包 `media_kit_libs_android_video 1.3.8`、Windows `media_kit_libs_windows_video 1.0.11`、macOS `media_kit_libs_macos_video 1.1.4`。根应用必须保留自己的 `pubspec.lock`，并在三端构建后核对最终解析版本。

[media_kit 官方包页](https://pub.dev/packages/media_kit)列出 Android、Windows、macOS 视频/音频、外部音轨和请求头能力；这是包声明，未证明这些能力的组合已在本项目通过。`media_kit`、`media_kit_video` 和 `media_kit_libs_video` 包页标 MIT；分发前仍要单独核查打包的 mpv、FFmpeg 与其他原生库许可。[macOS 原生构建仓库](https://github.com/media-kit/libmpv-darwin-build)列出默认构建与可选 GPL 构建的许可区别。

包缓存中当前插件的构建脚本指向以下原生资产；这是预定下载来源，不能代替构建产物的实际校验：

| 目标 | 插件构建脚本中的来源 | 校验值 |
| --- | --- | --- |
| Android arm64 | `media-kit/libmpv-android-video-build` 的 `v1.1.7/default-arm64-v8a.jar` | MD5 `83df25b61193af8fa815e373143ac9af` |
| Windows x64 | `media-kit/libmpv-win32-video-build` 的 `2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z` | MD5 `a832ef24b3a6ff97cd2560b5b9d04cd8` |
| Windows x64 ANGLE | `alexmercerind/flutter-windows-ANGLE-OpenGL-ES` 的 `v1.0.1/ANGLE.7z` | MD5 `e866f13e8d552348058afaafe869b1ed` |
| macOS universal | `media-kit/libmpv-darwin-build` 的 `v0.6.0/libmpv-xcframeworks_v0.6.0_macos-universal-video-default.tar.gz` | SHA-256 `84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6` |

## 已实现边界

`MediaKitEngine` 每次换源先释放旧 Player，整个会话最多一个 native Player。DASH 视频以 `Media(httpHeaders: ...)` 暂停打开，等待实际视频轨就绪后，在同一 Player 通过 `AudioTrack.uri` 加入音频，再等待外部音轨就绪，完成初始 seek、倍速与音量后按用户意图播放。查看固定版本源码时，`media_kit` 在 `on_load` 将 `Media` 的 headers 设置到该 mpv 实例的 `http-header-fields`，外部音频通过同实例 `audio-add`；外部音轨 API 没有独立 headers 参数。因此只接受音视频相同的 headers，若不同则在创建 native Player 前明确失败。只允许非凭据的 `User-Agent`、`Referer`、`Origin`、`Accept`；Cookie/Authorization 被拒绝，以免重定向时泄漏。Windows 受控服务器已验证音视频两路 Referer/UA、Range/206 和 302；其他平台仍待验证，详见 [M0 实测](m0-results.md)。

命令串行执行；换源/停止递增 generation，旧 Player 的订阅取消，延迟事件不写入新状态。`PlayerFailure` 只包含静态安全文本，不转发可能含签名 URL 或凭据的 native 错误字符串。现订阅 native error/log，仅将白名单模块、错误分类、HTTP 状态和播放状态写入有界本地诊断；原文不落盘。error 流含非终止性日志，不能直接作为播放失败：运行期间收到 error 后观察确认进度，恢复前进则解除观察；用户仍要求播放且连续 8 秒无进度才报告停滞。暂停/seek 不计入观察时间，切源/停止/销毁取消观察，准备阶段仍由原有 35 秒轨道就绪预算兜底。详情与限制见 [播放错误排查](native-playback-errors.md)。底层库自身的诊断输出仍须在三端检查。`VideoSurface` 只使用公共 `PlayerEngine` 与 surface 契约，UI 不需要直接导入 `media_kit`。

`MediaKitEngine.inspectDiagnostics()` 返回公开的 `PlayerDiagnostics`，只含 generation、确认 position、已解码视频尺寸、音频声道/采样率及经字符白名单过滤的 codec（若后端有报告）。`hasDecodedVideo` 和 `hasDecodedAudio` 分别由解码后参数判断；未取得参数时为 false，不能用 URL 已打开替代。诊断不暴露可能是签名 URL 的 track ID、headers、标题或 native log。`media_kit` 的公开 `PlayerState` 没有 dropped frames 字段，因此首版不伪造该指标。

`DanmakuController` 使用后端确认位置作锚，两个样本间最多插值 700 ms；暂停、缓冲、seek 冻结。确认 seek 后二分定位窗口，倒退可重播。每次最多保留 500 条待调度、120 条可见、256 组文本布局；描边的每组包含填充/轮廓两个 `TextPainter`，其他效果一个，超额丢弃。主应用每 15 秒按偏移后的弹幕位置提供前 16 秒至后 60 秒的滑动窗口，包保留仍位于新窗口的活动项。样式与过滤边界见 [弹幕配置验证](danmaku-style-settings.md)。Canvas painter 由独立 Ticker 的局部 `Listenable` 驱动，不让全页逐帧重建。密集弹幕的性能目标仍需 profile 实测。

## 本机检查

两个包分别完成 `flutter pub get`、`dart format lib test`、`flutter analyze` 和 `flutter test`。`bili_player` 8 个测试通过（安全诊断、缺失 DASH 音频、分轨头不一致、凭据头拒绝，以及 native 等待/竞态/取消/超时释放）；`bili_danmaku` 4 个测试通过（时钟冻结/倍速、seek 回放、容量上限、滑动窗口保留活动项）。测试不加载 native 视频库。根应用 `PlaybackSession` 另有 10 个 fake engine/repository/progress 行为测试通过，覆盖快速换源、旧进度写、清晰度切换、迟到弹幕/字幕、旧 stop 与重开、布局所有权转交、短视频分段、片尾重播及异常释放；目标文件 `flutter analyze` 无问题。

本记录后的 Windows 原生集成与真实游客 UGC 结果已补入 [M0 实测](m0-results.md)。仍未验证：量化音画偏移、Android/macOS 原生运行、后台/休眠生命周期、HLS/FLV、密集弹幕性能和完整原生二进制许可归档；未测项不能当作支持承诺。
