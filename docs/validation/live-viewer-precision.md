# 直播在看人数精度与四项修复验证

日期：2026-10-07。

## 调查结果

本轮低频游客只读检查房间短号 `7777`（真实房间号 `545068`）：WebSocket 的 `ONLINE_RANK_COUNT.online_count` 在约 1.9 万变化，`online_count_text` 为 `1万+`；HTTP `getOnlineGoldRank.onlineNum` 同样返回超过 9999 的整数，`queryContributionRank.count` 也返回约 1.9 万。因此目前公开读取链路可以提供大于 9999 的人数，不能把 9999 当作统一接口上限。本轮未在当前时间重新收到用户此前看到的固定 9999，原始案例没有完整网络记录。

原解析器优先展示 `online_count_text`，而仅接受不带 `+` 的数字／万／亿文案，再回落 `online_count`。这既会丢失服务端的下界标记，也会在展示文本是 `9999`、整数其实更大时优先采用较低的展示值；同时没有独立人数快照读取来补充退化的实时展示。

现在保留有效的千／万／亿和 `+` 文案；当展示是 `9999` 或带 `+`、同时具有大于 9999 且满足文案下界的有效整数时，采用整数。另接入独立的精确人数快照：初次激活已开播房间读取一次，其后与已有刷新周期一同每 20 秒读取，使用真实房间号和主播 UID。最近 40 秒内接受的精确值（HTTP／实时整数）能保护精度，但不能遮蔽高于它的新下界。新 HTTP 可以替换读取前已有的旧下界或精确 `9999`；读取期间到达的实时下界只阻止低于该界的迟到快照，新的精确实时消息则阻止此前发起的 HTTP 覆盖。

人数快照不使用房间 HTTP `online` 或 WebSocket 心跳 operation 3 的人气，也不使用 `WATCHED_CHANGE` 累计看过人数。`ONLINE_RANK_COUNT.count` 仍不是本项人数来源。

## 端点与生命周期

| 项目 | 契约 |
| --- | --- |
| Profile / host / method | Web；`api.live.bilibili.com`；GET |
| Path / 参数 | `/xlive/general-interface/v1/rank/getOnlineGoldRank`；`roomId`、`ruid`、`page=1`、`pageSize=1` |
| 鉴权／签名 | Cookie 可选，游客实测成功；不使用 WBI、CSRF 或 App token |
| 响应 | JSON `data.onlineNum` 非负整数或十进制整数文本；零有效，缺失／浮点／负数不当作成功 |
| 分页 | 只读取人数，不遍历榜单；固定第一页、最小一条榜单记录，榜单内容不进入领域或 UI |
| 重试／超时 | 共享 API 读请求最多 3 次尝试；`ApiRequests` 总 deadline 25 秒，不叠加 feature 重试循环 |
| 刷新 | 当前可见且已开播房间，20 秒周期，不重叠；限流／鉴权／权限／协议失败后暂停该项自动刷新，用户刷新房间可重新尝试 |

通过纯 Dart `LiveViewerRepository` 端口注入现有 `ApiLiveRepository`，页面仍只消费控制器状态。隐藏页面、关闭页面、刷新房间、账号代次变更和下播均取消在途读取；失败保留已有人数，不影响媒体播放或聊天，不伪造零值。旧 account scope／session epoch／请求代次结果不能进入新状态。

## 参考与采用范围

只读检查本地 [bili-kernel PlayerClient](../../../bili-kernel/src/Services/Services.Media/Core/PlayerClient.cs) 和 [房间响应模型](../../../bili-kernel/src/Services/Services.Media/Core/Models/LiveRoomDetailResponse.cs)，没有发现可直接补充精确当前人数的独立直播方法；其 HTTP `online` 命名不能改变人气语义。UWP 的 [LiveMessage](../../../biliuwp-lite/src/BiliLite.UWP/Modules/Live/LiveMessage.cs) 仅使用 `online_count_text`。

GitHub 只读参考 [qydysky/biliApi 的 GetOnlineGoldRank / QueryContributionRank](https://github.com/qydysky/biliApi/blob/main/main.go) 定位候选端点，再对本机游客响应核验。`queryContributionRank` 仅作调查对照，没有新增为运行时降级通道。本项独立编写 Dart，未复制上游源码、schema 或资源，未修改相邻仓库或添加依赖；采用限制沿用 [参考文档](../references.md#4-许可与来源记录)。

## 验证

- 协议定向 15 项测试通过，覆盖超过 9999 的整数、零、损坏字段、无效 ID、`9999+`、`1万+`、展示 9999／整数更大的组合及旧计数语义。
- 新增人数回归覆盖初次读取、20 秒刷新、并发去重、精确／粗略实时更新、迟到 HTTP、更高下界、精确人数下降后的保护重置、隐藏／刷新／下播取消、旧账号隔离、限流停止、零和快照过期；Repository 测试验证 session epoch 变更取消实际 transport。
- 新增游客只收不发工具 [live_viewer_count_smoke.dart](../../packages/bili_api/tool/live_viewer_count_smoke.dart)，只打印连接阶段和人数，不打印消息、用户身份、URL、设备标识或凭据。7777 的 HTTP 快照本次返回 `20486`；35 秒连接成功，收到 12 次人数更新，数值在 `20276–20608`。结果见 `build/live-viewer-smoke.log`。
- 四项修复对应记录：[直播卡计数](live-card-count.md)、[连接提示](live-chat-status.md)、[UP 空间直播入口](profile-live-entry.md)。整体验证使用 `tool/check.ps1 -SkipPub`，最终结果见本记录的补充段落与 `build/live-fixes-check.log`。

本轮没有修改原生播放实现；尚未进行 Windows 原生界面点击、Android／macOS 构建与设备交互验收，长期连接与性能未实测。工作区另有并发的原生播放／窗口及直播 SC 改动，本轮提交只包含这四项直播相关修复。

## 最终集成检查

在前三项提交 `3c14225`、`c728d31`、`05c681f` 的基础上，仅应用本项人数修改及新测试的隔离检出执行 `tool/check.ps1 -SkipPub` 完整通过：根应用 1202、`bili_api` 317、`bili_player` 22、`bili_danmaku` 52，共 1593 项测试；根应用与三个包格式检查、静态分析均通过。日志保存在主工作区 `build/live-fixes-final-check.log`。没有运行构建。

共享主工作区先前检查曾通过，但随后并发 SC 编辑出现短暂编译／测试失败；本次最终结果对应隔离检出的这四项修复，不代表其他会话后续未提交改动已验收。本轮提交采用变更片段隔离，保留其他会话修改；验证结束后清理测试 worktree。
