# 影视与直播内置播放

日期：2026-10-05。首页番剧、国创、放映厅和直播卡片已进入应用内页面，现有只读列表、分页、分区与账号列表继续沿用各自端点。

后续影视侧栏改为官方桌面“哔哩哔哩”的简介／评论双标签、内嵌选集与系列作品；直播新增聊天／SC 双标签及同步 SC 气泡。当前界面、SC 端点和本轮结果见 [影视侧栏与直播 SC](pgc-live-sidebar.md)，下文保留内置播放初次接入记录。

## 页面与播放

- 三类页面：视频 `VideoScreen`、影视 `PgcScreen`、直播 `LiveScreen`。番剧/国创/电影/电视剧/纪录片/综艺共用影视页，桌面左播放器右侧栏，窄窗口上下排列。
- 影视侧栏提供选集、简介和评论；正片及附加内容按章节显示，保留当前集和服务端权限标记。评论由 app 注入已有组件，feature 不跨层引用视频 UI。会员/付费集可选择，最终权益由 Web playurl 裁决。
- 直播页显示 canonical 房间 ID、主播头像/名字、分区、人气、简介及开播状态。未开播不创建播放面板；清晰度来自服务端允许列表，优先 H.264 HLS，另支持 HTTP-FLV。
- 直播聊天室读取历史消息，每 20 秒刷新、最多保留 500 条并去重；隐藏页面取消计时器和在途读取。界面标示“历史消息 · 定时刷新”。实时 WebSocket、直播画面弹幕、发送和礼物尚未实现。
- app 只拥有一个 `PlaybackSession` 和原生 engine。影视按 episode、直播按 room ID 使用 `ContentPlaybackTarget`，不伪造 bvid。影视使用 DASH 分轨；原生媒体独立设置 UA/Referer、保留系统 TLS 验证，签名 URL 只在内存中使用。
- 跨类型切换复用 engine，取消/代次隔离旧响应。切到普通标签后原 owner 继续播放；同作品选集保留播放/暂停意图、倍速与音量。直播禁用 seek/倍速/点播续播/字幕/空降助手，重开使用当前直播源。三类页面调整布局不销毁播放器；关闭 owner 或账号变化停止播放。
- 路由：`/pgc/season/:id?ep=...`、`/pgc/episode/:id`、`/live/:roomId`。时间表卡片保留 episode；同作品选集深链接更新不卸载播放器。
- 本地历史保存影视 episode ID，点击历史卡片回到影视页。SQLite schema 从 1 升至 2，只添加可空列 `pgc_episode_id`；迁移保留已有设置、视频历史和进度，不清空数据库。直播不写入点播历史。

## 端点登记

均为 Web profile、HTTPS GET、JSON，无额外签名，Cookie 可选。取消、账号 epoch、25 秒总 deadline、只读最多额外 2 次网络/5xx 重试继承现有 `ApiRequests`/`BiliApiClient`。权限、风控、协议错误不自动重试，不使用 App token、第三方权限代理或账户写操作。

| 能力 | host / path | 参数与响应 |
| --- | --- | --- |
| 影视详情 | api.bilibili.com `/pgc/view/web/season` | season_id 或 ep_id；result，episodes/section、资料，单次有界读取 |
| 影视播放 | api.bilibili.com `/pgc/player/web/playurl` | ep_id、qn、fnver=0、fnval=4048、fourk=1、module=bangumi；result/data，H.264/AAC DASH；-10403/-10404 为权限错误 |
| 直播房间 | api.live.bilibili.com `/room/v1/Room/get_info` | room_id；data，canonical room_id、uid、live_status、标题、分区 |
| 主播资料 | api.live.bilibili.com `/live_user/v1/Master/info` | uid；data.info；与房间详情共享请求上下文 |
| 直播播放 | api.live.bilibili.com `/xlive/web-room/v2/index/getRoomPlayInfo` | room_id、qn、protocol=0,1、format=0,2、codec=0,1、platform=web；data，流/编码/线路、current_qn/accept_qn、g_qn_desc |
| 历史聊天 | api.live.bilibili.com `/xlive/web-room/v1/dM/gethistory` | roomid；data.room；每次最多解析 100 条 |

PGC 单作品的正片和附加内容合计最多 5000 集，附加章节最多 30 组、相关作品最多 100 项；正常超过 1000 集的长篇番剧保留新集数。直播协议/格式/编码/CDN 列表各有数量上限。这些上限限制异常响应，不代表分页接口。fixture、输出和日志不保存真实签名 URL、Cookie 或账户信息。

## 来源与验证

实际查看本机哔哩哔哩 UWP 的番剧首页和影视播放页：左播放器右侧栏、封面和剧名、分章节集数按钮及权限标记；直播首页展示分区和房间卡片。协议与职责另参考 [SeasonDetailPage.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Pages/SeasonDetailPage.xaml)、[SeasonAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/SeasonAPI.cs)、[LiveDetailPage.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Pages/LiveDetailPage.xaml)、[LiveRoomAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/Live/LiveRoomAPI.cs)。本轮自行编写 Dart/Flutter，未复制 C#、schema、图片、图标或新增原生依赖。

- 协议 fixture 覆盖详情/章节、缺字段、会员可选、权限错误、DASH 和直播线路/清晰度，以及 1275 集保留第 1001/1275 集和正片/附加内容合计 5000 集容量边界。游客 smoke 成功读取 PGC 详情、音视频分轨、直播房间和媒体流；聊天在线样本为空列表，内容展示由 fixture 验证。
- 界面/会话覆盖四频道卡片进入内置页、时间表 episode 路由、选集/简介/评论、同作品 episode 深链接、影视和直播宽窄布局保留 player State、隐藏页停止轮询、账号/旧响应隔离，以及三类播放共享 engine 与独立暂停意图。影视加载/失败/受限页刷新自己的详情，不重试其他播放标签；历史按记录打开，同 BVID 不同 CID/episode 的卡片保留各自路由和进度。
- Windows 受控原生：由现有 FFmpeg 信号素材生成 HLS/FLV，本地 HTTP 校验 UA/Referer；两种源均实际解码视频与音频并推进位置，暂停/隐藏返回不重开，live seek/倍速被阻止且不落盘点播进度。
- Windows 游客 CDN：通过 `ApiContentPlaybackRepository → PlaybackSession → MediaKitEngine` 实际播放公开影视 DASH 和直播 HLS，确认原生视频/音频解码及进度推进。未使用真实账号；不量化音画偏移、直播延迟、长时间稳定性或硬解性能。
- `tool/check.ps1` 通过：根应用 354、bili_api 84、bili_player 16、bili_danmaku 5，共 459 项测试；四处格式与静态分析通过。SQLite v1→v2 迁移测试保留旧设置、历史和续播进度。原有 Windows 点播原生回归 5 项及脱敏诊断 1 项通过。
- Windows x64 Profile 构建通过，实际应用内从番剧卡片进入影视页并播放/暂停。最终源码的主应用 Debug 构建和 Android arm64 Release 构建均通过；Android 沿用预览工程的 debug 签名配置。产物为 `build/windows/x64/runner/Debug/bili_lite.exe`（须保留整个 Debug 目录）和 `build/app/outputs/flutter-apk/app-release.apk`。Android/macOS 原生播放、会员权益、地区权限和真实评论读写未实机验收；当前 Windows 主机无法构建 macOS。

```powershell
./tool/check.ps1
./tool/test-windows-content.ps1         # 本地 HLS/FLV
./tool/test-windows-content.ps1 -Online # 另启用低频游客 CDN 烟测
flutter build windows --profile
flutter build windows --debug --no-pub
flutter build apk --release --target-platform android-arm64
# 根目录的低频游客协议烟测
dart run tool/content_smoke.dart
```

Flutter 的测试与平台构建必须顺序执行。本轮曾同时运行全量检查与 Android Release 构建，测试重写的 `GeneratedPluginRegistrant.java` 包含 `integration_test`，而 Release 排除开发依赖，导致 Java 编译失败；停止并行后由 `flutter build apk` 正常重新生成注册文件并构建成功，未手改生成物。
