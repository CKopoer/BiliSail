# 直播侧栏、表情弹幕与主页入口

日期：2026-10-05。基于现有未提交工程增量修改，相邻 `biliuwp-lite` 仅只读参考。

## 页面行为

- 删除直播页的简介展开按钮及正文，也删除独立的“查看主播主页”按钮。点击头像或主播名，通过 app 已有的 `/user/:mid` 工作区入口打开主播主页。
- 侧栏右上角显示“当前 xxx 人在看”（界面数字两侧不加空格），随直播消息更新；未收到有效人数时显示“观看人数暂无数据”。心跳人气仍独立展示，不用人气伪造观看人数。
- 聊天支持文字中的行内表情和独立大表情，历史与实时消息共用 `LiveChatBubble`。未知表情保留原文；图片失败显示文字回退；使用已有公共图片缓存和无账号凭据的图片请求。图片按比例限制尺寸，大表情最长边 80 logical pixels，行内表情随字号在 24–48 logical pixels 之间缩放。
- 普通弹幕、大表情和完整 SC 卡片的用户名，取得有效 UID 时可点击打开对应主页。缺少或无效 UID 时只显示文字，不依据昵称猜测账号。SC 金额胶囊继续用于展开留言。
- 历史补充覆盖到相同实时消息时保留已取得的 UID 和图片元数据。换账号、换房间、隐藏页面与旧连接隔离沿用原有代次/epoch；人数更新不会重新创建播放器。

## 协议与参考来源

只参考职责、字段及交互，独立编写 Dart/Flutter；没有复制 C#、图片、字体或 schema，也不新增依赖。参考入口：

- [LiveDetailPage.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Pages/LiveDetailPage.xaml) 和 [LiveDetailPage.xaml.cs](../../../biliuwp-lite/src/BiliLite.UWP/Pages/LiveDetailPage.xaml.cs)：头像主页入口和弹幕发送者 UID 导航。
- [LiveMessage.cs](../../../biliuwp-lite/src/BiliLite.UWP/Modules/Live/LiveMessage.cs)、[LiveRoomHistoryDanmu.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Live/LiveRoomHistoryDanmu.cs)、[StringExtensions.cs](../../../biliuwp-lite/src/BiliLite.UWP/Extensions/StringExtensions.cs)：大表情与行内 `emots` 的不同载荷。
- [LiveMessageHandleActionsMap.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Live/LiveMessageHandleActionsMap.cs)：`WATCHED_CHANGE` / `ONLINE_RANK_COUNT` 更新观看人数。

没有新增 HTTP 端点。历史沿用 Web GET `/xlive/web-room/v1/dM/gethistory`，实时沿用已登记的 Web WBI 发现与 WSS 通道，SC 沿用 `/av/v1/SuperChat/getMessageList`；鉴权、取消、有限重试与容量上限见 [现有协议记录](pgc-live-danmaku.md)。补充字段：

| 来源 | 采用字段与边界 |
| --- | --- |
| 历史聊天 | `user.uid`（兼容顶层 `uid`）、`emots`、`emoticon`；UID 保持十进制文本，不经浮点数 |
| 实时 `DANMU_MSG` | `info[0][15].user.uid`（回落 `info[2][0]`）、`info[0][15].extra.emots`、`info[0][13]` 大表情 |
| `WATCHED_CHANGE` | `data.num` / `text_small`，平台报告的观看人数；不自行推导同时在线人数 |
| `ONLINE_RANK_COUNT` | `data.online_count_text` / `online_count`；`count` 是榜单数量，不作为观看人数 |
| SC | 顶层 `uid`，同时支持 HTTP 快照和实时消息 |

额外 JSON 字符串至多 64 KiB；每条最多处理 50 个表情映射，token 至多 100 字符，仅保留正文使用的项；图片 URL 至多 2048 字符，尺寸 1–4096，URI 保持 HTTPS（仅将 hdslb 的 HTTP 资源升级为 HTTPS）。可选富文本字段损坏只回退该部分，不丢弃整条正常聊天。正文/昵称上限 300/100 字符，原有历史 100 条、UI 500 条上限不变。

## 验证与边界

游客只收不发的 `dart run tool/live_chat_smoke.dart --popular` 已在线通过：40 秒 `connected=true`，83 条聊天均保留 UID，其中 8 条包含行内表情，41 条包含大表情；收到 8 次人数更新及 2 次心跳，SC 0 条。工具只输出阶段和计数，没有输出昵称、正文、UID、URL、Cookie、token 或设备标识。该结果验证实际协议元数据，不代表远端表情图片全部加载成功。

组件测试使用自行绘制的 PNG，验证实际解码和行内排列、图片失败文字回退、用户名入口、320px 大字号布局与播放器保留；协议测试覆盖 UID 精度、损坏可选字段、无效 URL、人数来源和快照合并。组件预览位于 `artifacts/live-chat/live-chat-preview.png`，展示真实 Flutter 聊天组件与人工表情图，属于脱敏预览。

`tool/check.ps1 -SkipPub` 在直播改动完成后的工作区快照上完整通过：根应用 448、`bili_api` 130、`bili_player` 16、`bili_danmaku` 10，共 604 项测试；根应用和三个包的格式检查及静态分析均通过，日志为 `artifacts/live-chat/check.log`。工作区同时更新了其他功能，早期检查捕获的编解码/搜索中间态分析提醒已在该次检查中消失；仅补齐了搜索中的一个条件分支括号，保持既有行为。

该次全量检查后，另一项搜索功能继续修改共享工作区。两次 `flutter build windows --debug --no-pub --target lib/main.dart` 尝试均失败：第一次为搜索仓储接口/控制器未同步，第二次为 `search_screen.dart` 将新的 `List<SearchEntry>` 传给旧的 `List<VideoSummary>` 控件。没有为完成本任务回退或重写这些并发搜索改动，当前 Windows 构建不能记为通过，也不能将前面的 604 项检查视为这些后续搜索修改的验证。构建日志为 `artifacts/live-chat/windows-build.log`。

随后重新执行 `flutter test --no-pub test/features/live`，全部 47 项直播测试通过，日志为 `artifacts/live-chat/live-tests.log`。

原生播放实现没有调整；真实账号、真实非空 SC 跳转、Android/macOS 运行与长时间性能未在本轮实测。
