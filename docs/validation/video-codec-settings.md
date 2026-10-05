# 视频编码与解码设置

日期：2026-10-05。入口：设置 → 播放 → 视频编解码。

## 可选项与生效范围

| 设置 | 选项 | 范围与默认值 |
| --- | --- | --- |
| 优先视频编码 | H.264 / AVC、H.265 / HEVC、AV1 | 视频与影视 DASH，默认 H.264；直播继续选择 H.264 线路 |
| 视频解码方式 | 自动（优先硬解）、软件解码 | 视频、影视与直播；默认沿用 SDK 的自动模式，硬解不可用时可软解 |

优先编码只是片源选择，本项目不进行视频编码或转码。先从 API 实际返回的 H.264/HEVC/AV1 轨道中选取不高于目标的最高清晰度，没有较低档时用最低可用档；再在该清晰度选择首选编码。缺少首选时按 H.264、HEVC、AV1 回退，避免仅因编码偏好降低清晰度；相同编码/清晰度选码率较高的轨道。可用清晰度包含上述三类编码，未知编码不进入选择。音频仍为 AAC 分轨，缺失音轨明确失败，不把只有画面视作成功。服务端权限限制继续适用。

设置在下次打开、换清晰度、换 P/集或重新加载时生效，不重启当前播放。`PlaybackSession` 在源 generation 开始时一起捕获编码和解码偏好，解析期间的设置变化不影响该次打开；重新加载保留位置、播放/暂停意图、倍速和音量。SQLite 设置快照版本从 6 增为 7，保留 `preferences.v1` 键，旧快照及未知字段值回退至 H.264/自动；表结构未变化，数据库 schema 仍为 2，不清除旧数据。

## 参考与 SDK 差异

只读参考 [UWP 播放设置](../../../biliuwp-lite/src/BiliLite.UWP/Controls/Settings/PlaySettingsControl.xaml) 的优先编码和播放器后端设置；自行实现 Dart 选轨和 Flutter 设置，没有复制 C#、XAML、图片或新增上游资源。

固定依赖为 `media_kit 1.2.6`、`media_kit_video 2.0.1`、`media_kit_libs_video 1.0.7`。核对本机固定版本 SDK 的 `VideoControllerConfiguration` 与 native/Android 实现：`hwdec: null` 保留平台默认（桌面 `auto`，Android `auto-safe`，模拟器可能禁用）；软件模式设置 `hwdec: no`。GPU 画面渲染保持 SDK 默认开启，与视频解码是否使用硬件分开。后端参考：[media_kit 源码](https://github.com/media-kit/media-kit/blob/main/media_kit_video/lib/src/video_controller/platform_video_controller.dart)、[mpv hwdec 文档](https://mpv.io/manual/stable/#options-hwdec)。在线源码/手册可能较固定原生二进制更新，行为以本项目锁定版本和实测为准。

UWP 的 Microsoft Store HEVC/AV1 扩展提示、Native/FFmpegInteropX/Web 后端切换、FFmpegInteropX 额外参数、Shaka/Mpegts 调试和同步阈值不适用于当前 media_kit/libmpv 后端，未加入设置。未提供强制硬解或 D3D11VA/VideoToolbox/MediaCodec 专用菜单，避免把某设备后端当成三端通用能力。

## 验证

- 行为测试覆盖旧设置加载/未知值回退/存储重载、窄屏设置点击保存、三种编码选轨、清晰度优先、缺少首选回退、HEVC/AV1 单编码源、未知编码和缺失音频。
- UGC/PGC 协议 fixture 检查 API 保留三种编码及非 H.264 单编码源；仍使用既有 `fnval=4048` 请求。
- 会话测试检查 UGC/PGC/直播参数传递、解析期间偏好快照和重新加载时的播放意图/进度/倍速/音量保留。
- `tool/check.ps1 -SkipPub` 通过根应用和三个包的格式、分析与测试：根应用 447、API 129、播放器 16、弹幕 10，共 602 项。日志：`artifacts/codec-check.log`。检查时也最小修正了既有直播气泡测试的重复导入和缺失花括号两条 lint。
- `tool/test-windows-codecs.ps1` 通过。使用系统 FFmpeg 生成 H.264、HEVC、AV1 的 256×144/24fps/4 秒无声视频，加既有独立 AAC fixture，在 Windows 对自动与软件模式共六组分别验证解码后视频/音频参数、进度前进、seek、释放，并读取脱敏的 `hwdec-current`。本机自动模式三种编码均返回 `d3d11va-copy`，软件模式均返回 `no`；六组均为 256×144 视频与单声道 AAC。日志：`artifacts/windows-codecs.log`。这只证明当前设备和锁定原生库对这些样片可用。
- `tool/test-windows-media.ps1` 通过既有 Windows 分轨请求头/Range/重定向、seek、生命周期、响应式控件/全屏、工作区标签与原生 HTTP 403 脱敏诊断回归；在线 UGC 用例在未设置 `-Online` 时跳过，不计为新增编码的 CDN 实播。日志：`artifacts/codec-native-regression.log`。
- `flutter build windows --debug` 通过，已用正常应用入口构建 `build/windows/x64/runner/Debug/bili_lite.exe`；日志：`artifacts/codec-windows-build.log`。

Android/macOS 原生构建与设备运行未验证；本轮样片不证明高分辨率、高帧率、HDR、杜比视界、量化音画同步或任意设备硬解能力。新增编码未进行真实 Bilibili CDN 在线实播；片源可用性仍依服务端返回。
