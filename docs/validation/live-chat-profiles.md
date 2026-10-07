# 直播侧栏、表情弹幕与主页入口

日期：2026-10-05。基于现有未提交工程增量修改，相邻 `biliuwp-lite` 仅只读参考。

## 页面行为

- 删除直播页的简介展开按钮及正文，也删除独立的“查看主播主页”按钮。点击头像或主播名，通过 app 已有的 `/user/:mid` 工作区入口打开主播主页。
- 侧栏右上角分两行显示“当前 xxx 人在看”和“xxx 人看过”（界面数字两侧不加空格），各自随对应直播消息更新；未收到有效人数时分别显示“在看人数暂无数据”／“看过人数暂无数据”。人气独立展示进入房间时 HTTP 返回的快照，后续心跳不更新人气，也不用于任何一项人数。两项人数拆分于 2026-10-06 修正，人气快照策略于 2026-10-07 调整，见下文。
- 聊天支持文字中的行内表情和独立大表情，历史与实时消息共用 `LiveChatBubble`。未知表情保留原文；图片失败显示文字回退；使用已有公共图片缓存和无账号凭据的图片请求。图片按比例限制尺寸，大表情最长边 80 logical pixels，行内表情随字号在 24–48 logical pixels 之间缩放。
- 普通弹幕、大表情和完整 SC 卡片的用户名，取得有效 UID 时可点击打开对应主页。缺少或无效 UID 时只显示文字，不依据昵称猜测账号。SC 金额胶囊继续用于展开留言。
- 历史补充覆盖到相同实时消息时保留已取得的 UID 和图片元数据。换账号、换房间、隐藏页面与旧连接隔离沿用原有代次/epoch；人数更新不会重新创建播放器。

## 协议与参考来源

只参考职责、字段及交互，独立编写 Dart/Flutter；没有复制 C#、图片、字体或 schema，也不新增依赖。参考入口：

- [LiveDetailPage.xaml](../../../biliuwp-lite/src/BiliLite.UWP/Pages/LiveDetailPage.xaml) 和 [LiveDetailPage.xaml.cs](../../../biliuwp-lite/src/BiliLite.UWP/Pages/LiveDetailPage.xaml.cs)：头像主页入口和弹幕发送者 UID 导航。
- [LiveMessage.cs](../../../biliuwp-lite/src/BiliLite.UWP/Modules/Live/LiveMessage.cs)、[LiveRoomHistoryDanmu.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Live/LiveRoomHistoryDanmu.cs)、[StringExtensions.cs](../../../biliuwp-lite/src/BiliLite.UWP/Extensions/StringExtensions.cs)：大表情与行内 `emots` 的不同载荷。
- [LiveMessageHandleActionsMap.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Live/LiveMessageHandleActionsMap.cs)：`WATCHED_CHANGE` 更新“人看过”，`ONLINE_RANK_COUNT` 更新“人在看”；参考项目仍共用一个展示字段，本项目独立保存两项。

没有新增 HTTP 端点。历史沿用 Web GET `/xlive/web-room/v1/dM/gethistory`，实时沿用已登记的 Web WBI 发现与 WSS 通道，SC 沿用 `/av/v1/SuperChat/getMessageList`；鉴权、取消、有限重试与容量上限见 [现有协议记录](pgc-live-danmaku.md)。补充字段：

| 来源 | 采用字段与边界 |
| --- | --- |
| 历史聊天 | `user.uid`（兼容顶层 `uid`）、`emots`、`emoticon`；UID 保持十进制文本，不经浮点数 |
| 实时 `DANMU_MSG` | `info[0][15].user.uid`（回落 `info[2][0]`）、`info[0][15].extra.emots`、`info[0][13]` 大表情 |
| `WATCHED_CHANGE` | 优先有效的 `data.text_small`，回落非负整数 `num`；仅更新“人看过”，不推导同时在线人数 |
| `ONLINE_RANK_COUNT` | 优先有效的 `data.online_count_text`，回落非负整数 `online_count`；仅更新“人在看”，`count` 是榜单数量，不作为观看人数 |
| SC | 顶层 `uid`，同时支持 HTTP 快照和实时消息 |

额外 JSON 字符串至多 64 KiB；每条最多处理 50 个表情映射，token 至多 100 字符，仅保留正文使用的项；图片 URL 至多 2048 字符，尺寸 1–4096，URI 保持 HTTPS（仅将 hdslb 的 HTTP 资源升级为 HTTPS）。可选富文本字段损坏只回退该部分，不丢弃整条正常聊天。正文/昵称上限 300/100 字符，原有历史 100 条、UI 500 条上限不变。

## 验证与边界

游客只收不发的 `dart run tool/live_chat_smoke.dart --popular` 已在线通过：40 秒 `connected=true`，83 条聊天均保留 UID，其中 8 条包含行内表情，41 条包含大表情；收到 8 次人数更新及 2 次心跳，SC 0 条。当时工具将两类人数事件合计，该历史记录不证明两项来源各自收到更新。工具只输出阶段和计数，没有输出昵称、正文、UID、URL、Cookie、token 或设备标识。该结果验证实际协议元数据，不代表远端表情图片全部加载成功。

组件测试使用自行绘制的 PNG，验证实际解码和行内排列、图片失败文字回退、用户名入口、320px 大字号布局与播放器保留；协议测试覆盖 UID 精度、损坏可选字段、无效 URL、人数来源和快照合并。组件预览位于 `artifacts/live-chat/live-chat-preview.png`，展示真实 Flutter 聊天组件与人工表情图，属于脱敏预览。

`tool/check.ps1 -SkipPub` 在直播改动完成后的工作区快照上完整通过：根应用 448、`bili_api` 130、`bili_player` 16、`bili_danmaku` 10，共 604 项测试；根应用和三个包的格式检查及静态分析均通过，日志为 `artifacts/live-chat/check.log`。工作区同时更新了其他功能，早期检查捕获的编解码/搜索中间态分析提醒已在该次检查中消失；仅补齐了搜索中的一个条件分支括号，保持既有行为。

该次全量检查后，另一项搜索功能继续修改共享工作区。两次 `flutter build windows --debug --no-pub --target lib/main.dart` 尝试均失败：第一次为搜索仓储接口/控制器未同步，第二次为 `search_screen.dart` 将新的 `List<SearchEntry>` 传给旧的 `List<VideoSummary>` 控件。没有为完成本任务回退或重写这些并发搜索改动，当前 Windows 构建不能记为通过，也不能将前面的 604 项检查视为这些后续搜索修改的验证。构建日志为 `artifacts/live-chat/windows-build.log`。

随后重新执行 `flutter test --no-pub test/features/live`，全部 47 项直播测试通过，日志为 `artifacts/live-chat/live-tests.log`。

原生播放实现没有调整；真实账号、真实非空 SC 跳转、Android/macOS 运行与长时间性能未在本轮实测。

## 在看／看过人数修正（2026-10-06）

原实现将 `WATCHED_CHANGE` 和 `ONLINE_RANK_COUNT` 都解码为 `ApiLiveViewerCountChanged`，再更新同一个 `viewerCountText` 并统一标注“当前 xxx 人在看”。两种消息交错到达时，平台报告的“人看过”覆盖了当前观众数，导致文案和数值语义不符。

当前新增独立的 `ApiLiveWatchedCountChanged` / `LiveWatchedCountChanged` / `watchedCountText`；现有 viewer 事件和状态只接收当前观众数。API 解码、Repository 映射、控制器状态与右上角文案全程分开，单项更新不覆盖另一项。零是有效计数；缺少、负数、浮点或损坏的计数不会从榜单数量或心跳人气补值。格式化文本损坏时允许回落对应的有效整数。账号 epoch、旧连接隔离和重新载入房间清空两项状态沿用现有生命周期。

本轮另外只读查看 [bili-kernel 的 PlayerClient.cs](../../../bili-kernel/src/Services/Services.Media/Core/PlayerClient.cs) 与 [LiveRoomDetailResponse.cs](../../../bili-kernel/src/Services/Services.Media/Core/Models/LiveRoomDetailResponse.cs)：心跳解析注释明确 operation 3 是人气；HTTP `online` 虽命名 `ViewerCount`，不能据此作为当前人数的备用值。采用范围仅为协议字段与职责理解，Dart/Flutter 独立编写；没有复制上游源码/schema/资源、新增依赖或修改相邻仓库。许可边界沿用 [来源记录](../references.md#4-许可与来源记录)。

回归覆盖交错更新、文本/数值回落、零值、无效数据、隐藏页面/旧账号隔离、重新载入清空、播放器实例保留，以及 320px／2 倍字号时同时展示两项人数。

`tool/check.ps1 -SkipPub` 完整通过：根应用 600、`bili_api` 207、`bili_player` 16、`bili_danmaku` 19，共 842 项测试；根应用与三个包的格式和静态分析全部通过，日志为 `artifacts/live-viewer-counts/check.log`。

游客只收不发的 WebSocket 烟测分别记录两类计数。第一间热门房 40 秒连接成功，仅收到 1 次在看更新、0 次看过更新；另外选取公开列表中的直播房后，40 秒连接成功，收到 12 次在看更新、8 次看过更新和 2 次心跳（聊天 22 条、SC 1 条），证明实际消息链路可分别接收两项来源；日志为 `artifacts/live-viewer-counts/live-smoke.log`。没有打印消息正文、用户身份或凭据，没有执行账号写操作。

本轮未调整原生播放，也未重新进行平台构建、Android/macOS 实机或长时间性能验证；上述结果仅覆盖协议、状态、Flutter 组件与本机游客消息链路。

## 人气保留入房快照（2026-10-07）

游客只读排查房间 7777（真实号 545068）和 1939021227 时，房间 HTTP `online` 分别返回 759985 和 1249362，但两间各两次 WebSocket operation 3 的原始消息体均为 `00 00 00 01`。原控制器将每次心跳数值覆盖到房间人气，导致页面持续显示 1；这是快照被心跳覆盖，不是数字格式化错误。

按用户指定策略，人气固定采用进入房间时 `/room/v1/Room/get_info` 返回的 `online`，观看期间不自动刷新、不被任何心跳值覆盖。零保持零，缺失保持不展示；重新进入或显式重新加载房间时采用该次房间响应。隐藏后返回、实时连接重连和开播状态消息继续保留当前快照。心跳解析、保活及超时判断仍由消息会话负责；“人在看”的 HTTP／实时更新、“人看过”的实时更新沿用独立字段。

回归覆盖正数、零和缺失快照，对心跳 1／0／其他正数的忽略，重新加载与重新激活，以及页面在收到心跳 1 后仍显示原人气、两项人数继续更新。定向 47 项测试通过；`tool/check.ps1 -SkipPub` 完整通过根应用 1223、`bili_api` 319、`bili_player` 32、`bili_danmaku` 52，共 1626 项测试，四处格式和静态分析均通过，日志为 `build/live-popularity-snapshot-check.log`。没有修改原生播放实现；本轮未进行平台构建或实机界面验收。

## 聊天列表自动跟随修正（2026-10-06）

直播播放页的聊天列表默认持续跟随最新消息；手动向上拖动、滚轮上滚或拖动滚动条离开底部后暂停跟随，手动回到底部后恢复。切换房间重置为跟随状态；聊天／SC 子标签切换、侧栏收起和窗口尺寸变化保留原有跟随意图，返回聊天时仅在原先跟随的情况下追到最新消息。打开完整 SC 卡片时暂时保留卡片阅读位置，收起后恢复此前的跟随意图。

旧实现按距底部 48 逻辑像素判断是否跟随，并在消息更新后只定位一次；变高的消息和懒加载列表重新估算滚动范围后，会留下空余滚动距离或中断后续跟随。现在由页面局部状态记录用户意图，列表尺寸变化后合并安排布局后的底部定位；自动定位不作为手动滚动，向上滚轮输入在平滑动画首帧前即可暂停跟随。没有修改播放器、网络协议、500 条消息上限或持久化设置。

组件回归覆盖不同消息高度、首屏／连续批次／达到消息上限后的跟随、触摸与鼠标滚动条拖动、平滑及减少动画模式的滚轮、只上滚 24 逻辑像素仍暂停、侧栏／子标签／窗口变化时的跟随与暂停保留、SC 阅读和切换房间。

`tool/check.ps1 -SkipPub` 完整通过：根应用 608、`bili_api` 207、`bili_player` 16、`bili_danmaku` 19，共 850 项测试；根应用和三个包的格式检查及静态分析均通过，日志为 `artifacts/live-chat-follow-check.log`。其中直播播放页面共 19 项组件测试，本轮新增 8 项滚动行为回归。

`flutter build windows --release --no-pub` 通过，产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `artifacts/live-chat-follow-windows-build.log`。真实直播窗口的拖动体验、Android/macOS 实机与长时间性能未在本轮实测。
