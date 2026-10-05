# 我的收藏子标签与收藏视频卡片

日期：2026-10-06。工具链沿用 Flutter 3.47.6 / Dart 3.13.5。

## 页面行为

“我的收藏”按用户提供的已安装哔哩哔哩截图分为“默认收藏夹”“我创建的收藏夹”“我的收藏与订阅”“我的追番”“我的追剧”。默认收藏夹直接显示内容；创建列表按服务端默认收藏夹 ID 排除它，不依赖名称或位置。“我的收藏与订阅”保留普通收藏夹与 UGC 合集的不同类型，封面显示叠层、内容数量和收藏夹/合集标识；播放数仅在服务端提供时显示。

我的收藏中的有效视频和个人主页收藏夹内的视频共用 [VideoCard](../../lib/shared/ui/video_card.dart)，统一 16:9 封面、播放/弹幕数量、时长、标题、作者和发布时间。收藏资源的 `upper`、`duration`、`cnt_info`、`pubtime` 在 API/Repository 边界映射；失效资源保留提示并禁止播放，不因一个失效视频使整页失败。个人主页投稿继续沿用现有投稿卡片。

[ResponsiveCardGrid](../../lib/shared/ui/responsive_card_grid.dart) 与新增 Sliver 版本共用列数、宽度和间距计算；个人主页按行懒加载，卡片自然高度适配大字体。工作区子标签分别保留列表与路径，普通收藏夹与合集的查询/滚动键分开。每个收藏查询最多保留 500 条内容，超限显示刷新提示；每个子标签沿用父列表与最近 19 个子查询的容量限制。账号 scope、请求取消、generation 和 session epoch 沿用现有管线。

## 端点登记

所有端点为 `api.bilibili.com`、Web profile、HTTPS GET、JSON，使用已有 Web Cookie 和收藏夹权限，无 App token、签名或 CSRF。共享总 deadline 与读请求最多额外两次网络/5xx 重试；权限/风控/协议错误不切换备用接口。没有新增账户写操作。

| 能力 | Path | 参数、分页与解析 |
| --- | --- | --- |
| 默认收藏夹识别 | `/x/v3/fav/folder/space/v2` | `up_mid`；读取 `default_folder.folder_detail.id`（兼容 `info.id`）；刷新重新识别，后续页在查询游标内保留该 ID |
| 创建的收藏夹 | `/x/v3/fav/folder/created/list` | `up_mid`、`pn`、`ps=20`、`platform=web`；过滤默认 ID；`has_more`，缺省时按 `count` |
| 收藏与订阅 | `/x/v3/fav/folder/collected/list` | 同上；`type=21` 为 UGC 合集，其余保留普通收藏夹类型 |
| 收藏夹视频 | `/x/v3/fav/resource/list` | `media_id`、`pn`、`ps=20`、`platform=web`；`medias`、`has_more`/`info.media_count` |
| 订阅合集视频 | `/x/space/fav/season/list` | `season_id`、当前 `mid`、`pn`、`ps=20`、`platform=web`；`medias`、`info.media_count`；实测一次返回整合集，已达到总数时停止分页 |
| 追番/追剧 | `/x/space/bangumi/follow/list` | `vmid`、`type=1/2`、`pn`、`ps=20`；`list`、`total`；保留 season ID 和更新集数，进入现有影视页 |

个人主页收藏夹沿用原 `ProfileClient` 每页 30 条读取，补齐统计/发布时间映射及失效判断。缺失关键字段为协议错误；明确零总数下的 null 列表为空状态。

## 来源与采用范围

视觉依据为用户本轮截图。只读查看相邻 UWP 的 [FavoriteAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/FavoriteAPI.cs)、[FollowAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/FollowAPI.cs)、[FavoriteDetailViewModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Favourites/FavoriteDetailViewModel.cs)，以及 kernel 的 [MyClient.cs](../../../bili-kernel/src/Services/Services.User/Core/MyClient.cs)、[VideoFavoriteGalleryResponse.cs](../../../bili-kernel/src/Services/Services.User/Core/Models/VideoFavoriteGalleryResponse.cs)、[FavoriteAdapter.cs](../../../bili-kernel/src/Services/Services.User/Core/Adapters/FavoriteAdapter.cs)。快照及许可边界见 [参考文档](../references.md)。仅借鉴协议、类型和交互职责，独立编写 Dart/Flutter；未复制新增源码/schema/资源，未修改相邻仓库。参考 App 追番/追剧方法未迁入，使用已有 Web 追番端点的两种类型。

## 验证与边界

- 离线协议测试覆盖默认 ID/改名与创建列表过滤、跨页游标、同 ID 不同类型、合集整页响应、追番/追剧分类、视频元数据、失效资源、权限错误、取消后不继续链式请求与无账号拒绝。
- Widget 回归覆盖五个标签、合集进入/返回和切换保留、公共卡片、作者/视频点击、窄窗口/双倍字体、宽屏铺满与个人主页懒加载；收藏容量测试覆盖去重和停止分页。
- 显式 [Windows 只读集成入口](../../integration_test/windows_favorites_test.dart) 使用系统安全存储中的已有会话；凭据和私有内容只在内存中使用，日志只输出数量/分页状态/失败分类。实测默认收藏前两页各 20 条；创建列表 7 项，样本夹 9 个有效视频；收藏与订阅 12 项，样本合集一次返回 38 个有效视频且停止分页；追番 20 项、追剧 4 项；个人主页样本夹返回 30 个有效视频。
- Windows Debug 构建与上述只读集成测试通过。此次只读读取不代表所有账号、隐私设置和会员/地区权限已验证；未执行收藏/取消订阅等账户写操作。Android/macOS 和真实客户端窗口视觉操作未验收，未修改原生播放。

`tool/check.ps1 -SkipPub` 通过根应用和三个包的格式、静态分析与测试：根应用 537、API 包 183、播放器包 16、弹幕包 10 项，共 746 项（本次工作区快照）。未新增依赖，使用已有解析结果。另完成三个离线 Flutter 渲染快照：1735 像素默认夹/订阅列表与 360 像素双倍字体列表；封面为占位样本，视检五列布局、叠层、公共视频元数据和可横滚标签。子标签字体改为继承应用主题，避免显式字号覆盖配置字体。日志位于 `build/favorites-*.log`，快照位于 `build/favorites-preview/`。

字体修正后再次全应用静态分析通过、首页 84 项回归通过；`flutter build windows --release --no-pub` 成功，产物为 `build/windows/x64/runner/Release/bili_lite.exe` 及配套目录。未替换或关闭用户已有客户端进程。登录只读验证可显式执行 `flutter test integration_test/windows_favorites_test.dart -d windows --no-pub`，需要本机安全存储中已有会话；普通检查脚本不运行此集成入口。
