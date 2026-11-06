# 动态直播跳转与评论相对时间

日期：2026-11-06。仅实现与离线验证；本轮由用户自行构建和实机验收。

## 动态跳转直播间

首页动态和个人／UP 主空间动态中的直播卡片，点击后进入已有应用内直播播放页。转发中的原直播卡片共用同一回调；动态右上角“在浏览器打开动态”仍打开该动态原页面。

[动态解析器](../../packages/bili_api/lib/src/mappers/dynamic_post_parser.dart) 兼容三种 Web 内容结构：`major.live.id`、`major.live_rcmd.content` 内的 `live_play_info.room_id`，以及 `major.subscription_new.live_rcmd.content` 的同一房间字段。有效房间 ID 直接生成标准 HTTPS 直播链接；ID 保持十进制字符串，不经浮点数转换。直播标题缺失时显示“直播间”，直接直播结构的 `desc_first` 保留为副标题。无效 ID、异常 JSON 或超出既有容量限制的推荐内容继续使用动态原页面回退。

[直播链接识别](../../lib/features/dynamic/domain/dynamic_link.dart) 只接收标准 HTTPS、443 端口、无用户信息且只有一个有效十进制房间路径的 `live.bilibili.com` 链接；查询参数不进入房间身份。首页用既有 `/live/<房间 ID>` 路由，空间用原有 `onOpenLiveRoom` 端口。卡片和页面不发起新 API 请求，也不新增鉴权或账号写入行为。

## 评论时间

视频、动态及楼中楼共用的 [CommentAuthorHeader](../../lib/shared/ui/comment_rich_content.dart) 使用纯 Dart [commentTimeLabel](../../lib/features/comments/domain/comment_time.dart)：

| 条件 | 展示 |
| --- | --- |
| 未满一分钟 | 刚刚 |
| 一分钟至不足一小时 | `n分钟前` |
| 一小时至不足 24 小时 | `n小时前` |
| 已满 24 小时且为本地昨天 | `昨天 HH:mm` |
| 其余距本地日历日期 2–3 天 | `n天前` |
| 更早的同年日期 | `MM-dd` |
| 不同年日期 | `yyyy-MM-dd` |

先按实际经过时间判断 24 小时内的相对时间，再按本地年月日比较天数，避免夏令时的 23／25 小时自然日影响日历差。UTC 时间先转换为本地时间；未来日期显示绝对日期，不显示负数“前”。缺失、零或负 epoch 不显示时间占位。IP 属地的同一行位置和原文字样式保持。无逐秒 Timer 或全页刷新，随既有组件重建重新计算。

## 参考与许可

只读核对本地 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8`：

- `lib/utils/page_utils.dart`：`DYNAMIC_TYPE_LIVE`、`DYNAMIC_TYPE_LIVE_RCMD` 与 `DYNAMIC_TYPE_SUBSCRIPTION_NEW` 的房间字段和应用内导航职责。
- `lib/models/dynamics/result.dart` 与 `lib/pages/dynamics/widgets/forward_panel.dart`：直播内容结构及转发内原动态的相同跳转语义。
- `lib/utils/date_utils.dart` 的 `dateFormat` 与 `lib/pages/video/reply/widgets/reply_item_grpc.dart`：最近评论的分钟／小时、昨天、近期天数及较早日期展示。PiliPlus 的特定评论详情层级另有完整秒级绝对时间，本项目按本轮要求在共用作者头统一使用相对时间规则。

同时核对该仓库 `pubspec.yaml` 的 overrides 与 `pubspec.lock`：media-kit 核心、库插件和原生事件桥解析到 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，视频插件解析到 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`，弹幕解析到 `275046d8647a6a26cba1d0dadb9e28688cb3dbf1`。这些只用于确认参考快照，不代表本轮更新依赖。本轮未修改任何依赖、锁文件或相邻仓库。

PiliPlus 应用源码为 GPLv3；本轮仅借鉴协议字段和展示／跳转行为，独立编写本项目实现与脱敏 fixture，没有复制其源码、资源或 schema，也没有引入其运行时依赖。沿用[参考许可边界](../references.md#4-许可与来源记录)。

## 验证

- `packages/bili_api`：`dart test test/dynamic_post_test.dart`，28 项通过。覆盖首页／空间、三种直播结构、普通／转发、长整数房间 ID、异常 JSON 和无效房间 ID。
- 根应用：`flutter test --no-pub test/features/comments/comment_time_test.dart test/features/dynamic/dynamic_link_test.dart test/features/feed/dynamic_live_navigation_test.dart test/features/profile/profile_controller_test.dart test/features/video/comment_rich_content_test.dart`，75 项通过。覆盖首页／空间普通与转发直播卡片实际点击后进入路由／调用房间端口，且不调用浏览器；相对时间边界、跨午夜和跨年、未来值、UTC 转换及原评论布局／交互回归。
- 上述根应用变更的 10 个 Dart 文件 `flutter analyze --no-pub`、API 解析器与测试 `dart analyze` 均无问题；本轮 Dart 格式检查和 `git diff --check` 通过。

未做真实账号在线读取、构建、直播实际播放或 Android／iOS／Windows／macOS 实机测试。设备导航与时间观感由用户构建后验收；离线 fixture 通过不等同于端点当前在线可用。
