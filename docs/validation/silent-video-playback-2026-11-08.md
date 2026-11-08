# 无音轨视频播放

日期：2026-11-08。针对 [BV1fTnZ6LEvr](https://www.bilibili.com/video/BV1fTnZ6LEvr)（《不到300KB的Dock栏工具》）在 Release 打开后显示“当前内容暂不可用”的反馈。

## 原因与在线证据

- 游客 `GET https://api.bilibili.com/x/web-interface/view?bvid=BV1fTnZ6LEvr` 成功，内容分类为普通视频，CID 为 `43074848375`，时长约 231 秒。
- 实际应用使用的 WBI `GET /x/player/wbi/playurl` 在 `qn=129` 和 `qn=32` 均返回 `code=0`、有效 DASH 视频轨道，同时明确返回 `audio=null`、`dolby={type:0,audio:null}`、`flac=null`。主播放重复读取三次仍为同一结果；悬停因本就允许省略音轨而可解析。
- 独立只读诊断使用 `GET https://api.bilibili.com/x/player/playurl` 的 `fnval=0` MP4，ffprobe 检查到唯一 H.264 视频流，时长 `230.583313` 秒，无音频流。该无签名诊断端点没有加入应用运行时。
- 原来 API 将所有缺少音频的完整播放响应判为 `unavailable`；选流与会话也无条件要求音轨，因此最终映射为该提示。底层播放器已经支持明确无音轨的 `DashPairSource`，本次补齐应用到此契约的传递。

## 修复与边界

- 运行时沿用 Web GET `api.bilibili.com/x/player/wbi/playurl`，Cookie 可选、WBI 签名、JSON、无分页。现有画质／编码／语音参数、三次共享请求预算、deadline、取消和账号 epoch 不变，没有新增依赖或设置。
- 保守识别本次在线确认的完整无音轨形态：必须有有效视频轨道，显式 `audio=null`、`flac=null`，并有 `dolby.type=0` 和显式 `dolby.audio=null`。字段缺失、空音频数组或声明有 Dolby 却缺音轨都不被当成静音成功，继续现有缺轨处理。合法 FLAC／Dolby 音轨仍优先解析为有声媒体。
- 无音轨响应仍通过同一操作内有界的详情读取核对权益；未授权充电／付费、试看不变为完整播放。完整有声 DASH 不增加详情读取。悬停主动省略音频不产生此标记。
- `ApiPlayInfo`、画质补取合并、`selectDashMedia`、`PlaybackMedia`、`PlaybackSession` 全程保留 `isIntentionallySilent`，最后使用既有 `DashPairSource(audio:null,isIntentionallySilent:true)`；不借用只能静音的悬停源。普通缺音轨仍失败。
- 无音轨视频保留普通播放、暂停、seek、清晰度选择及用户音量偏好；不提供依赖独立音轨的“听视频”。下载与封装仍要求完整音视频分轨，本次没有扩展无音轨下载。
- 未记录媒体 URL、查询参数或账号凭据。在线验证仅使用游客只读请求，不执行账号写操作。

## 验证

- [API 回归](../../packages/bili_api/test/playurl_retry_test.dart)：新增用例首先在旧实现复现 `unavailable`，修复后覆盖明确无音轨、普通缺轨恢复、FLAC／Dolby、权益／试看和预览隔离；与既有权益测试共 79 项通过，日志 `build/silent-video-api-test.log`。
- [选流](../../test/features/playback/dash_media_selection_test.dart)、[质量补取](../../test/features/playback/api_playback_quality_test.dart)、[会话](../../test/features/playback/playback_session_test.dart)覆盖标记传递、未确认缺轨仍失败、未知音频编码不作为无音轨、暂停／自动播放意图及 seek；选流与会话首轮 299 项通过。
- [原生回归](../../integration_test/silent_video_playback_test.dart)用本地无音轨视频和用户原视频，分别通过 Windows media_kit／fvp，4 项通过。确认视频解码、原生画面输出、无音频解码、进度推进、暂停、seek 及继续播放；在线部分显式使用 `--dart-define=BILI_ONLINE_SMOKE=true`，日志 `build/silent-video-native.log`。已接入 [Windows 媒体检查入口](../../tool/test-windows-media.ps1)。
- `flutter analyze --no-pub` 通过，日志 `build/silent-video-analyze.log`。已尝试热重载，DTD 未发现运行中的调试应用；实际原生回归另行构建并运行了测试应用。
- `tool/check.ps1 -SkipPub` 全量通过：根应用 4658、API 714、播放器 278、弹幕 161、封装 5，共 5816 项通过；格式、静态分析与打包边界脚本均通过，日志 `build/silent-video-check.log`。根应用 13 项既有条件跳过，mux 另有 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，不算作封装原生集成通过。
- `flutter build windows --release` 通过，普通入口产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志 `build/silent-video-release.log`。复用已有 Windows x64 mux 资产；CMake 沿用 WebView 插件 CMP0175 开发警告。可执行文件 SHA-256 为 `1059FFC42393B5D51057DA68FCF06CC1CF3DE5B25295DC4733369AEEE445CEDA`，运行／分发需保留整个 Release 目录。本轮未在普通 Release 界面手动操作，实播证据来自上述原生集成回归。
- 修改文档的 322 个本地链接、源码路径与 `git diff --check` 通过。

原生回归采用 Debug，仅验证功能，不作为性能结论。Android、macOS、iOS 的实机播放、本轮未涉及的完整原生媒体回归及长期稳定性未验证。
