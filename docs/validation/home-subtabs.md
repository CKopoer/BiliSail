# 首页子频道只读接入

日期：2026-10-05。首页动态、视频动态、番剧、国创、直播、放映厅、稍后再看与收藏现有真实协议读取；不使用热门视频替代这些内容。不自动发起点赞、收藏、关注或观看上报。

本文件记录前序列表接入；其中 PGC/直播外部打开的边界已由 [影视与直播内置播放](content-playback.md) 更新。四个频道现在进入应用内影视/直播页，列表端点与分页策略继续沿用本记录。

收藏现已升级为五类子标签，默认收藏夹直接列视频，订阅合集与收藏夹分开读取，追番/追剧使用 Web 类型 1/2；本机已有会话的读取与当前分页边界见 [收藏子标签与视频卡片](favorites-tabs.md)。以下收藏两类子导航及“未真实登录验证”为前序记录。

直播分区列表后续固定改用已验证的 Web `/room/v3/Area/getRoomList`，按 `count` 分页；推荐首页仍使用 `index/getList`。当前端点与主/子分区在线证据见 [影视与直播弹幕修复](pgc-live-danmaku.md#分区接口)，下表保留首次接入结果。

## 端点登记

全部为 Web profile、HTTPS GET、JSON，签名为无（本轮不假定 App token）。公共端点允许游客，私有端点使用当前 Web Cookie。取消、session epoch、总 deadline、只读最多额外 2 次网络/5xx 重试继承 `BiliApiClient`/`ApiRequests`；风控/鉴权/权限/协议错误不自动重试。无备用降级端点。

| 入口 | host / path | 鉴权 | 参数与分页 | 在线验证 |
| --- | --- | --- | --- | --- |
| 动态全部/视频/图文；视频动态 | api.bilibili.com `/x/polymer/web-dynamic/v1/feed/all` | Cookie | type=all/video（图文使用 all 后按 DRAW/WORD/ARTICLE 类型筛选），page + offset；offset 原样传递，has_more；不变/缺失下一游标判协议错误 | 未真实登录验证，离线模型与游标测试 |
| 稍后再看全部/未看完 | api.bilibili.com `/x/v2/history/toview` | Cookie | 单次全部列表；未看完过滤 progress=-1 的已完成视频 | 未真实登录验证，离线筛选测试 |
| 自建收藏夹 | api.bilibili.com `/x/v3/fav/folder/created/list` | Cookie | up_mid，pn，ps=20，has_more | 未真实登录验证 |
| 订阅收藏夹 | api.bilibili.com `/x/v3/fav/folder/collected/list` | Cookie | up_mid，pn，ps=20，has_more | 未真实登录验证 |
| 收藏夹资源 | api.bilibili.com `/x/v3/fav/resource/list` | Cookie/收藏夹权限 | media_id，pn，ps=20，platform=web，has_more | 未真实登录验证，离线资源/失效卡测试 |
| 番剧/国创推荐与索引；电影/电视剧/纪录片/综艺 | api.bilibili.com `/pgc/season/index/result` | 游客 | season_type=1/4/5/2/3/7，page，pagesize=20，type=1，推荐 order=2 播放量排序，索引 order=0；has_next | 游客番剧索引 code=0，真实 season_id/title/cover 字段核对 |
| 番剧/国创时间表 | api.bilibili.com `/pgc/web/timeline` | 游客 | types=1/4，before=6，after=6；单次日期列表展开真实 episodes | 游客番剧时间表 code=0；result 为数组，核对 season_id/episode_id/pub_time/pub_index |
| 我的追番 | api.bilibili.com `/x/space/bangumi/follow/list` | Cookie | vmid，type=1，pn，ps=20；total | 未真实登录验证；国创入口显示账号追番列表，不承诺服务器按国创过滤 |
| 推荐直播/分区直播 | api.live.bilibili.com `/xlive/web-interface/v1/second/getList` | 游客，可能风控 | parent_area_id，area_id=0，platform=web，sort_type=online，page；has_more | 本机游客返回 -352 风控；界面显示可重试错误，不伪装空成功 |
| 全部分区 | api.live.bilibili.com `/room/v1/Area/getList` | 游客 | 返回主分区，点击读取该 parent_area_id 的直播房间列表 | 游客 code=0；data 为数组 |
| 我的关注直播 | api.live.bilibili.com `/xlive/web-ucenter/v1/xfetter/GetWebList` | Cookie | page，page_size=20；count/rooms | 未真实登录验证 |
| 直播观看记录 | api.bilibili.com `/x/web-interface/history/cursor` | Cookie | type=live，ps=20；后续 max/view_at/business=live，不变游标停止分页 | 未真实登录验证 |

## 界面与边界

列表由纯 Dart 领域 Repository 和应用控制器管理，按频道/子频道/账号/收藏夹分别持有状态；已访问的频道子页面留在 `IndexedStack`，切换不销毁列表、滚动位置和收藏夹路径。工作区标签作用域由 router 隔离；账号切换销毁私有页面状态，旧响应经 generation/epoch 丢弃。分页失败保留列表，重试原页/游标，并按 kind/id 去重。每个子频道最多保留父列表和最近 19 个收藏夹/直播分区查询，超限淘汰后重新读取；关闭标签或账号作用域统一释放。

动态图文显示真实作者、正文和首张图片，不假装视频。已失效收藏资源保留失效卡，不让一个缺失 bvid 的资源破坏整页。UGC 卡片进入应用视频页；PGC、直播、图文卡片标记“外部打开”并由用户点击打开官方 HTTPS 页面；这里不承诺内置 PGC/直播播放。番剧和国创推荐目前是官方索引的播放量排序，未实现首页运营模块。时间表展平日期和更新集数；未提供额外筛选面板。

## 来源与验证

只读参考 UWP `Models/Requests/Api/User/DynamicAPI.cs`、`FavoriteAPI.cs`、`WatchLaterAPI.cs`、`Home/LiveAPI.cs`、`Live/LiveAreaAPI.cs`、`Live/LiveCenterAPI.cs` 与 kernel `BiliApis.cs` 的端点和分页职责。UWP 动漫首页使用第三方聚合服务，本实现改用官方 PGC Web 索引/时间表。没有复制 C# 代码、schema、图片或图标。

游客在线读取仅核对公开协议结构，不使用真实账号，不保存 Cookie、二维码 key 或签名媒体 URL。离线测试使用手写无隐私样本。登录列表和 Android/macOS 浏览器打开尚未实机验证。

定向验证：`flutter test test/features/feed` 11 个测试通过，覆盖旧响应隔离、游标分页失败重试/去重、子频道返回与收藏夹进入/返回状态保留；`dart test test/home_client_test.dart` 5 个协议测试通过。根应用 feed 与新增 API 文件静态分析通过。

可复现入口 `packages/bili_api/tool/home_smoke.dart` 已通过完整 HomeClient 请求/解析链：番剧推荐 20 条、番剧时间表 57 条、直播分区 12 条；推荐直播按 rateLimited 记录业务码 -352。仅输出数量与状态，不记录账号或内容。每个子频道最多保留 20 个查询（父列表与 19 个收藏夹/直播分区），超出后释放最早访问的子列表；关闭工作区标签或账号变化会释放全部。

## 推荐页滚动分页

本节记录前序只在推荐下滚时检查的实现。本轮已经扩展为首页频道及所有子标签的首屏/尺寸变化/恢复可见/下滚检查，并统一刷新与回顶部入口；当前行为、图片缓存及新增验证见 [首页刷新、自动分页与图片缓存](feed-scroll-image-cache.md)。以下测试数量是前序记录。

推荐页向下滚动至距底部不超过 600 逻辑像素时，自动请求下一页并追加到现有列表，保持滚动位置。只响应当前活动工作区的推荐列表；加载中、刷新中、没有更多内容或上一页加载失败时不自动请求。失败保留现有内容并等待点击“重试”，手动“加载更多”入口继续保留。刷新、切换频道和关闭页面沿用控制器的取消与 generation 隔离。

新增 [滚动分页测试](../../test/features/feed/feed_autoload_test.dart) 5 项，使用鼠标滚轮事件和延迟 Repository，覆盖提前加载、连续滚动单次请求、末页停止、位置保持、失败手动重试、刷新/频道切换旧响应隔离与非活动工作区。与原有推荐页测试共 13 项通过。本轮为离线 widget 验证，未进行真实客户端鼠标操作或 Android/macOS 实机验证。


