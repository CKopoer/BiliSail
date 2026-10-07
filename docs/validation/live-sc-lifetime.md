# 直播 SC 时长与倒计时

日期：2026-10-07。在已有直播改动上增量处理 SC，沿用唯一播放会话、聊天跟随、用户主页入口、气泡横向滚轮和底部拖动条。

## 协议与来源

SC 快照继续使用 Web GET `https://api.live.bilibili.com/av/v1/SuperChat/getMessageList?room_id=<canonical ID>`，Cookie 可选、无签名和 CSRF，读取 `data.list`、最多 100 条、20 秒刷新；实时消息仍来自 `SUPER_CHAT_MESSAGE`／`SUPER_CHAT_MESSAGE_DELETE`。不新增账户写操作或运行时依赖。

`start_time`／`end_time` 为 Unix 秒时间戳，结束时间优先决定到期。`time` 同样以秒为单位，但两种来源的含义不同：HTTP 快照样本中的 `time = end_time - ts`，实时事件样本中通常是总显示时长。快照样本依据 [BiliSC Web API 原始响应记录](https://github.com/dd-center/BiliSC-WebAPI-Doc/blob/master/README.md)，实时字段对照相邻 UWP 与用户指定参考项目的解析器。源码核对与脱敏 fixture 不等同于本轮取得真实非空 SC。

协议包用 [live_super_chat_timing.dart](../../packages/bili_api/lib/src/live/live_super_chat_timing.dart) 统一解析两条通道并明确来源：

- 优先保留服务端 `end_time`，总时长由有效起止区间计算。
- 缺少结束时间时，实时事件可用 `start_time + time`；HTTP 快照可用 `ts + time`，不能把快照的剩余时长加到原始开始时间。
- 只剩秒数时，应用控制器在首次接收处补算结束时间，并按 SC ID 保存最多 200 条计时记录；重复轮询／实时投递不重置计时，近期过期项不会被相同的无时间戳样本复活。记录随房间控制器销毁／账号 epoch 切换释放。
- 秒数字段有类型和 24 小时范围检查；快照非正剩余秒数视为已到期。时间信息全部缺失时不按价格猜测时长，也不显示虚构倒计时。

## 显示与生命周期

保留现有双色卡片、头像和金额层次，卡片右侧显示剩余秒数，金额气泡也显示倒计时；样式参考 [SlotSun/dart_simple_live 的 SC 卡片](https://github.com/SlotSun/dart_simple_live/blob/25e55686e90639c3f2b52bf20f5971538f2a781e/simple_live_app/lib/widgets/superchat_card.dart)。参考提交为 `25e55686e90639c3f2b52bf20f5971538f2a781e`，上游许可证为 GPL-3.0；本轮只参考界面层次、倒计时及协议职责，独立编写 Dart／Flutter，没有复制上游源码、schema 或资源。

每个可见气泡／卡片只在自身子树每秒更新文字，不通过全局 Provider 每秒重建整页。关闭侧栏、切换聊天／SC 子标签、隐藏工作区或进入后台时，通过 `TickerMode` 停止显示计时器；再次显示时从绝对结束时间恢复剩余秒数。

SC 移除由 `LiveController` 按最近的结束时间安排单次计时器，不等待下一次 HTTP 轮询，也不依赖后续弹幕到达。到期或收到撤回事件后，气泡、展开卡片和 SC 标签列表同步更新。选中项到期清除其选择；播放器实例保持，聊天继续遵循原有人工滚动／跟随意图。隐藏页面停止网络和到期计时器，恢复时立即清理过期项。

## 验证

- SC 协议／分包定向测试 15 项通过：起止时间、HTTP 剩余时间与实时总时长的区别、时间戳缺失降级、无效秒数、服务端结束时间优先。
- 直播页面／仓库／控制器／倒计时定向测试 49 项通过：重复投递和轮询、读取失败时到期、后台恢复、气泡与展开详情同步消失、原播放器保留、局部更新、隐藏停止计时、窄窗口大字体、头像主页和既有滚动交互。
- 完整 `tool/check.ps1 -SkipPub` 通过：根应用与三个包格式／静态分析通过，共 1625 项测试（根应用 1222、API 319、播放器 32、弹幕 52）。按用户要求不构建。
- 本轮没有原生播放改动；未用真实非空 SC 完成在线倒计时验收，未做 Android／macOS 设备操作或长期计时性能测量。
