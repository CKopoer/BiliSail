# 影视侧栏与直播 SC

日期：2026-10-05。在现有未提交工程上增量修改，保留既有改动，不修改相邻参考仓库。

本文件保留侧栏初次接入时的历史快照边界；后续实时 WebSocket、画面弹幕、影视发送和 SC 新样式见 [影视与直播弹幕修复](pgc-live-danmaku.md)。下列“未实现实时”描述属于该前序阶段。

## 视觉来源与范围

番剧、国创、放映厅的播放页面参考 **官方桌面“哔哩哔哩”**，不是哔哩哔哩 UWP。已实际查看本机官方客户端“名侦探柯南（中配）”播放窗口；用户第一张截图提供相同的简介／评论、作品信息、选集卡片和系列作品层次。直播的聊天气泡、SC 金额入口与完整卡片参考用户第二、第三张截图。

相邻 `biliuwp-lite` 只用于只读查阅 SC 端点与字段：`LiveRoomAPI.RoomSuperChat`、`LiveRoomViewModel.LoadSuperChat`、`LiveRoomSuperChatModel`。Dart/Flutter 实现独立编写，本轮不复制参考代码、图片或其他资源，不增加运行时依赖。

## 页面行为

- 番剧、国创、电影、电视剧、纪录片和综艺沿用同一个 `PgcScreen`；信息区只有简介／评论两个主标签，选集放在简介内的有界卡片中，保留正片及附加章节、当前集和权限提示。
- 作品统计按现有服务端数据展示，简介支持展开；选集支持列表／网格及正序／倒序，系列条目通过 app 组合根导航至对应作品。分享复制当前集的官方 HTTPS 链接。
- 直播信息区包含聊天／SC 两个子标签。聊天顶部金额气泡与 SC 列表消费同一份领域状态；点击气泡展开完整留言，可关闭或改选其他留言。聊天室仍明确标注历史消息定时刷新。
- 宽窄布局、子标签切换与收起信息不重建播放器；页面可见性继续通过 `WorkspaceActivity` 控制消息读取，播放所有权仍属于唯一的 `PlaybackSession`。

## SC 协议与状态

Web profile，HTTPS GET `api.live.bilibili.com/av/v1/SuperChat/getMessageList`，参数 `room_id` 使用 canonical 房间 ID 字符串，JSON 响应读取 `data.list`；Cookie 可选，无 App token、App 签名或 CSRF。无分页，沿用 `ApiRequests` 的取消、25 秒总 deadline 和有界只读重试。

SC 与历史聊天分别加载和显示错误，一个读取失败不清空另一个。请求携带账号 scope、session epoch 和读取代次，隐藏页面取消请求与计时器，旧响应不写回；SC 最多保留 100 条，昵称／正文分别最多 100／2000 字符，按服务端起止时间清理过期项。20 秒定时刷新不能等同于实时 WebSocket；直播画面弹幕、发送和礼物仍未实现。

游客只读探测：房间 `7734200` 返回 HTTP 200、业务 `code=0`、`data.list=null`；房间 `6` 返回业务错误。成功空样本只证明端点可以读取，非空 SC 的字段、气泡和卡片展示需要脱敏 fixture 验证，不能宣称已用真实 SC 完成在线验收。探测未使用真实账户或 App 签名，没有输出 token、Cookie 或留言正文。

最终协议实现另通过 `dart run tool/live_super_chat_smoke.dart`（在 `packages/bili_api` 执行）游客读取成功，输出 `messages=0`；该工具只输出状态和数量，不输出留言正文、昵称、身份或凭据。

## 验证

- `tool/check.ps1 -SkipPub` 完整通过：根应用 368、bili_api 86、bili_player 16、bili_danmaku 5，共 475 项测试；四部分格式与静态分析通过。
- 新增行为覆盖影视双标签与系列路由、1275 集当前定位、分组／排序／网格、320px 双倍字号、信息收起及窗口切换保留 State，相关作品长 ID／空封面／不可变列表，以及 SC 解析容量、独立失败、隐藏取消、账号 epoch、晚响应与本地过期清理。聊天向下滚动后点击 SC 气泡，会定位至可见完整卡片；收起侧栏保留聊天位置。
- 真实 Flutter 组件的明暗主题预览保存于 `artifacts/content-sidebar/`：影视简介、直播聊天、SC 展开与 SC 列表。资料为人工编写的脱敏演示，头像／封面和播放器为占位，不是真实账号或原生播放截图。

- `tool/test-windows-content.ps1 -Online` 两项 Windows 原生回归通过：受控 HLS／HTTP-FLV，以及游客影视 DASH／直播 CDN 均解码音视频；同时验证共享播放会话、原生请求头和暂停等既有行为。页面切换与侧栏状态保留由组件测试覆盖，本轮未用原生窗口完成所有新版页面交互验收。
- `flutter build windows --debug --no-pub` 通过，产物 `build/windows/x64/runner/Debug/bili_lite.exe`。
- `flutter build apk --release --target-platform android-arm64` 通过，产物 `build/app/outputs/flutter-apk/app-release.apk`。首次使用 `--no-pub` 构建时，原生测试留下的生成注册文件仍引用 `integration_test`，导致 Java 编译失败；刷新依赖并由正常构建重新生成后通过，未手改生成物。APK 沿用工程现有调试签名，供测试安装。

Android 实机运行、macOS 构建与运行、真实非空 SC、会员与地区权益及实时消息均不在当前已验结论中。SC 仍为 20 秒快照刷新，未接入实时 WebSocket。
