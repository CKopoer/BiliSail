# 首页子频道只读接入

日期：2026-10-05。首页动态、视频动态、番剧、国创、直播、放映厅、稍后再看与收藏现有真实协议读取；不使用热门视频替代这些内容。不自动发起点赞、收藏、关注或观看上报。

本文件记录前序列表接入；其中 PGC/直播外部打开的边界已由 [影视与直播内置播放](content-playback.md) 更新。四个频道现在进入应用内影视/直播页，列表端点与分页策略继续沿用本记录。

收藏现已升级为五类子标签，默认收藏夹直接列视频，订阅合集与收藏夹分开读取，追番/追剧使用 Web 类型 1/2；本机已有会话的读取与当前分页边界见 [收藏子标签与视频卡片](favorites-tabs.md)。以下收藏两类子导航及“未真实登录验证”为前序记录。

直播分区列表后续固定改用已验证的 Web `/room/v3/Area/getRoomList`，按 `count` 分页；推荐首页仍使用 `index/getList`。当前端点与主/子分区在线证据见 [影视与直播弹幕修复](pgc-live-danmaku.md#分区接口)，下表保留首次接入结果。

## 2026-11-06：放映厅电影与电视剧类型修正

放映厅“电影”此前落入默认 `season_type=5`，而“电视剧”显式发送 `2`，导致两类内容互换。[HomeClient](../../packages/bili_api/lib/src/clients/home_client.dart) 现将电影显式映射为 `2`、电视剧映射为 `5`；推荐继续使用 `5`，纪录片 `3`、综艺 `7`，排序及分页参数保持原有行为。下表同步修正类型顺序。

[协议回归](../../packages/bili_api/test/home_client_test.dart) 新增五个分类的首屏及第二页检查，覆盖类型、排序、分页参数、影视条目解析及末页判定。修复前电影和电视剧两项均复现失败，修复后 HomeClient 28 项测试及 `bili_api` 静态分析通过。

`tool/check.ps1 -SkipPub` 通过，日志 `build/cinema-section-fix-check.log`：根应用 4502、bili_api 677、bili_player 170、bili_danmaku 161、bili_mux 5，共 5515 项通过；格式、静态分析及打包边界检查通过。另有 13 项 Windows 符号链接测试因权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。本文 17 个本地链接及 `git diff --check` 通过。未构建、在线验证或进行实机验收；未发现可连接的 Flutter 调试应用，热重载未执行。

## 端点登记

全部为 Web profile、HTTPS GET、JSON，签名为无（本轮不假定 App token）。公共端点允许游客，私有端点使用当前 Web Cookie。取消、session epoch、总 deadline、只读最多额外 2 次网络/5xx 重试继承 `BiliApiClient`/`ApiRequests`；风控/鉴权/权限/协议错误不自动重试。无备用降级端点。

| 入口 | host / path | 鉴权 | 参数与分页 | 在线验证 |
| --- | --- | --- | --- | --- |
| 动态全部/视频/图文；视频动态 | api.bilibili.com `/x/polymer/web-dynamic/v1/feed/all` | Cookie | type=all/video（图文使用 all 后按 DRAW/WORD/ARTICLE 类型筛选），page + offset；offset 原样传递，has_more；不变/缺失下一游标判协议错误 | 未真实登录验证，离线模型与游标测试 |
| 稍后再看全部/未看完 | api.bilibili.com `/x/v2/history/toview` | Cookie | 单次全部列表；未看完过滤 progress=-1 的已完成视频 | 未真实登录验证，离线筛选测试 |
| 自建收藏夹 | api.bilibili.com `/x/v3/fav/folder/created/list` | Cookie | up_mid，pn，ps=20，has_more | 未真实登录验证 |
| 订阅收藏夹 | api.bilibili.com `/x/v3/fav/folder/collected/list` | Cookie | up_mid，pn，ps=20，has_more | 未真实登录验证 |
| 收藏夹资源 | api.bilibili.com `/x/v3/fav/resource/list` | Cookie/收藏夹权限 | media_id，pn，ps=20，platform=web，has_more | 未真实登录验证，离线资源/失效卡测试 |
| 番剧/国创推荐与索引；电影/电视剧/纪录片/综艺 | api.bilibili.com `/pgc/season/index/result` | 游客 | season_type=1/4/2/5/3/7，page，pagesize=20，type=1，推荐 order=2 播放量排序，索引 order=0；has_next | 游客番剧索引 code=0，真实 season_id/title/cover 字段核对 |
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

## 启动推荐加载竞态修复

2026-10-07 使用延迟安全存储、真实 `SessionRepository` / `ApiRequests` 与工作区路由复现：恢复期间已开始的推荐读取，在旧登录失效并退出时被会话代次取消；恢复前后界面都显示游客，原工作区只按登录标记、MID 和名称隔离页面，没有重建列表。控制器忽略旧请求的取消结果后，首屏一直保留加载态。工作区页面作用域现在同时包含 session epoch，账号显示信息相同的会话变化也会释放旧控制器，并由新页面发起一次读取。

推荐首屏的 WBI key 单飞还有独立竞态：原共享 nav 请求使用第一个调用者的取消信号与 deadline，旧页面释放会让新页面或其他等待者同时得到取消结果；新 session 也可能加入旧 session 的在途请求。现在同 session 的 key 请求独立拥有取消信号和默认 12 秒总 deadline，调用者取消或超过自己的 deadline 只结束自己的等待。新 session 请求独立取 key 并取消旧在途请求；迟到响应不能写回缓存或清除新在途请求。关闭 API client 取消其共享取 key 任务。既有 key 缓存、签名失败一次重签与只读重试规则继续沿用，不增加推荐请求的无限自动重试。

回归使用脱敏手写响应和延迟 transport，不读取真实账号。[启动测试](../../test/app/home_startup_test.dart)覆盖旧登录失效、恢复登录成功、旧响应迟到丢弃与首屏退出加载态；[协议测试](../../packages/bili_api/test/wbi_request_lifecycle_test.dart)覆盖同 session 并发、首个等待者取消、等待取消及时结束、跨 session 新请求、旧请求收尾、调用者 deadline、失败后显式重试和 client 关闭。直播连接回归也确认旧房间取消后新房间继续共用同一次 nav，移除已不需要的取消重试补偿。

本轮根应用 1120、bili_api 298、bili_player 22、bili_danmaku 52 项测试分别通过，共 1492 项；三个包的格式与静态分析、本次根应用文件的静态分析均通过。`flutter build windows --release --no-pub` 成功，产物 `build/windows/x64/runner/Release/bilisail.exe`。执行 `tool/check.ps1 -SkipPub` 时，最后一次运行的根格式检查通过，整体静态分析仍被并行改动 `test/features/feed/dynamic_scroll_layout_test.dart` 的 `curly_braces_in_flow_control_structures` 提示阻塞，本轮未修改该文件。真实客户端冷启动、慢网和 Android/macOS 实机验收仍待验证。


## 2026-10-25：保留页面后的首页频道高亮

问题路径：打开设置并选择“缓存”，返回首页后依次切换热门、番剧等频道，内容已经切换，但顶部图标、文字和指示线仍可能停在旧频道。根因是设置页读取了外层 `TabPagingScope`，与首页分页争用同一个 `TabPagingProgress`；设置页保留在后台后仍能接管进度发布者，使首页的动画更新被忽略。双标签和多标签模式均可复现。

[设置页](../../lib/features/settings/presentation/settings_screen.dart)现在独立持有并释放分页进度，由设置分类条和分类内容分页共享；首页仍通过工作区进度驱动频道图标、文字和指示线。保留页面、分类选择和滚动状态的行为不变。

[工作区路由回归](../../test/app/workspace_router_test.dart)新增 4 项，覆盖双/多标签、390/1280 逻辑像素、访问设置后切换推荐/热门/番剧的图标与文字颜色，以及返回设置后分类高亮和分页实例保留。修复前 4 项均复现失败，修复后连同工作区、频道滑动和分页条定向测试共 83 项通过，日志 `build/home-channel-highlight-before.log`、`build/home-channel-highlight-tests.log`。

`tool/check.ps1 -SkipPub` 通过：根应用 2195、bili_api 446、bili_player 81、bili_danmaku 93、bili_mux 2，共 2817 项测试，五处格式、静态分析和打包边界检查通过，日志 `build/home-channel-highlight-check.log`。mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。

本轮未构建、启动客户端或执行实机验证；DTD 未发现运行中的调试应用，热重载因无活动连接未执行。

## 2026-10-25：首页、动态、我的滑动分组

问题路径：从推荐连续滑动，热门后进入动态，动态后进入直播，分区后进入稍后再看和收藏。顶部导航已经按一级入口分组，内容分页仍按旧 `HomeChannel.primaryValues` 枚举顺序遍历，导致显示顺序和手势范围不一致。

[工作区导航](../../lib/app/workspace_navigation.dart)现在统一提供频道顺序及同层分组，供[外壳标签栏](../../lib/app/shell.dart)和[根页面组合](../../lib/app/router.dart)共同使用：

同日按用户最新要求修订：频道分组只依据窗口宽度，不区分平台；Windows／macOS 窄窗口也采用首页内的直播子标签。

| 布局（所有平台） | 首页子标签，从左至右 | 直播归属 |
| --- | --- | --- |
| 窄屏（小于 600 逻辑像素） | 推荐、热门、直播、番剧、国创、放映厅、分区 | 属于首页；底栏为首页、动态、我的、设置四项 |
| 宽屏（600 逻辑像素及以上） | 推荐、热门、番剧、国创、放映厅、分区 | 独立一级入口 |

动态的同层子标签为“动态、视频动态”；我的仍使用独立分页，顺序为“历史记录、稍后再看、收藏、下载”。热门的综合热门／每周必看／入站必刷／排行榜、番剧分类以及直播的推荐直播／我的关注／观看记录属于再下一层，沿用原有内容分类选择，不加入首页频道序列。旧排行榜链接仍映射到热门。

[频道分页](../../lib/features/feed/presentation/home_channel_swipe.dart)为每个已访问一级入口保留独立的分页实例，只把同层子标签交给自己的 TabBarView；隐藏组保留页面和独立进度，当前组连接外壳标签栏的进度。触摸拖动、松手吸附、横向滚轮信号和触控板手势均使用真实分页边界，边界不循环、不滑入其他组。一级入口切换组，同组点击继续动画；隐藏、取消和外部选择使迟到的滑动提交失效。顶部指示线和内容使用同一组顺序，窗口宽度变化重新核对分组。[共享分页](../../lib/shared/ui/retained_tab_view.dart)补齐触控板输入与滚轮信号落定后的选择同步，保留内嵌列表优先响应规则。

[工作区回归](../../test/app/workspace_router_test.dart)覆盖 Windows／macOS／Android、390／1280 宽度、双／多标签共 12 组：按首页可见顺序双向滑动、边界拖动时位置不越界及快速甩动、横向滚轮／触控板同组切换与边界隔离、动态两端、我的四标签两端、桌面三个直播分类的双向隔离，以及返回首页后分页状态和 ProviderScope 保留。导航单元测试另行核对三端分组和完整顺序。

12 组滑动隔离回归通过，日志 `build/home-swipe-groups.log`；工作区、外壳、首页手势、播放信息分页、用户页及设置分页定向 210 项通过，日志 `build/home-swipe-focused-final.log`。`tool/check.ps1 -SkipPub` 通过：根应用 2319、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 2951 项测试；五处格式、静态分析及打包边界脚本通过，日志 `build/home-swipe-check.log`。mux 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。本文 15 个本地链接及 `git diff --check` 通过。

本轮未构建或操作真实客户端；未发现可连接的 Flutter 调试应用，热重载未执行。真实 Windows 触摸／触控板、macOS、Android 设备交互仍待用户验收。

## 2026-10-25：统一窄屏直播归属

按用户要求移除频道分组的平台分支。外壳和根页面组合均以 600 逻辑像素为界：所有平台窄屏的直播归首页，宽屏的直播独立；直播分类条随布局放入内容页或外壳。一级切换动效单独保留 Android/iOS 窄屏判断。

导航模型、外壳布局与真实路由三份定向测试共 106 项通过（`build/narrow-live-navigation-tests.log`）。布局回归覆盖全部 `TargetPlatform`，包含 599/600 边界双向切换、四项底栏、直播归属和选中状态，以及页面 Element 保留；真实路由回归覆盖 Windows/macOS/Android 双／多标签的同层滑动及移动动效隔离。工作区外壳原有五项底栏断言同步为四项，并从首页直播子标签验证分类选择记忆。

最终 `tool/check.ps1 -SkipPub` 通过：根应用 2599、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 3231 项测试；五处格式、静态分析及打包边界检查通过（`build/narrow-live-navigation-check-final.log`）。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。4 份改动文档的 102 个本地链接及 `git diff --check` 通过。

本轮未构建或启动客户端，未进行原生／设备与性能验收。已尝试连接 DTD 和热重载，发现的 DTD 入口拒绝连接，没有活动调试应用，热重载未执行。
