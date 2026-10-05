# 我的收藏子标签与收藏视频卡片

日期：2026-10-06。工具链沿用 Flutter 3.47.6 / Dart 3.13.5。

本日后续已为“我的收藏与订阅”增加卡片菜单与取消前确认，写接口及竞态验证另见 [收藏与订阅取消操作](favorites-unsubscribe.md)。下文端点和测试数量保留五类收藏只读接入时的验证快照。

## 页面行为

“我的收藏”按用户提供的已安装哔哩哔哩截图分为“默认收藏夹”“我创建的收藏夹”“我的收藏与订阅”“我的追番”“我的追剧”。默认收藏夹直接显示内容；创建列表按服务端默认收藏夹 ID 排除它，不依赖名称或位置。“我的收藏与订阅”保留普通收藏夹与 UGC 合集的不同类型，封面显示叠层、内容数量和收藏夹/合集标识；播放数仅在该订阅列表且服务端提供时显示。

“我创建的收藏夹”按补充截图显示内容数量、公开/私密状态，私密收藏夹名称前加锁图标，下方显示本地日期 `创建于YYYY-MM-DD`，不显示播放量。`attr` 的 bit 1 标识私密，`ctime` 按秒解析；可选字段缺失时不猜测状态或日期。右侧菜单“编辑信息”可修改名称、简介和公开/私密状态。打开编辑框先读取完整信息和所属账号，关键字段缺失或账号非拥有者时不能保存；取消不会提交，成功后刷新创建列表。

我的收藏中的有效视频和个人主页收藏夹内的视频共用 [VideoCard](../../lib/shared/ui/video_card.dart)，统一 16:9 封面、播放/弹幕数量、时长、标题、作者和发布时间。收藏资源的 `upper`、`duration`、`cnt_info`、`pubtime` 在 API/Repository 边界映射；失效资源保留提示并禁止播放，不因一个失效视频使整页失败。个人主页投稿继续沿用现有投稿卡片。

[ResponsiveCardGrid](../../lib/shared/ui/responsive_card_grid.dart) 与新增 Sliver 版本共用列数、宽度和间距计算；个人主页按行懒加载，卡片自然高度适配大字体。工作区子标签分别保留列表与路径，普通收藏夹与合集的查询/滚动键分开。每个收藏查询最多保留 500 条内容，超限显示刷新提示；每个子标签沿用父列表与最近 19 个子查询的容量限制。账号 scope、请求取消、generation 和 session epoch 沿用现有管线。

## 端点登记

以下读端点为 `api.bilibili.com`、Web profile、HTTPS GET、JSON，使用已有 Web Cookie 和收藏夹权限，无 App token、签名或 CSRF。共享总 deadline 与读请求最多额外两次网络/5xx 重试；权限/风控/协议错误不切换备用接口。

| 能力 | Path | 参数、分页与解析 |
| --- | --- | --- |
| 默认收藏夹识别 | `/x/v3/fav/folder/space/v2` | `up_mid`；读取 `default_folder.folder_detail.id`（兼容 `info.id`）；刷新重新识别，后续页在查询游标内保留该 ID |
| 创建的收藏夹 | `/x/v3/fav/folder/created/list` | `up_mid`、`pn`、`ps=20`、`platform=web`；过滤默认 ID；`has_more`，缺省时按 `count` |
| 收藏与订阅 | `/x/v3/fav/folder/collected/list` | 同上；`type=21` 为 UGC 合集，其余保留普通收藏夹类型 |
| 收藏夹视频 | `/x/v3/fav/resource/list` | `media_id`、`pn`、`ps=20`、`platform=web`；`medias`、`has_more`/`info.media_count` |
| 订阅合集视频 | `/x/space/fav/season/list` | `season_id`、当前 `mid`、`pn`、`ps=20`、`platform=web`；`medias`、`info.media_count`；实测一次返回整合集，已达到总数时停止分页 |
| 追番/追剧 | `/x/space/bangumi/follow/list` | `vmid`、`type=1/2`、`pn`、`ps=20`；`list`、`total`；保留 season ID 和更新集数，进入现有影视页 |

个人主页收藏夹沿用原 `ProfileClient` 每页 30 条读取，补齐统计/发布时间映射及失效判断。缺失关键字段为协议错误；明确零总数下的 null 列表为空状态。

编辑元信息复用 `/x/v3/fav/resource/list` 的 `info`（`media_id`、`pn=1`、`ps=1`、`platform=web`），读取 `id`、`upper.mid`、`title`、`intro`、`attr`，与当前账号核对。写接口为 `api.bilibili.com`、HTTPS POST `/x/v3/fav/folder/edit`，Web Cookie/CSRF、JSON，表单 `media_id`、`title`、`intro`、`privacy=1/0`（私密/公开），`csrf` 从当前 Cookie 提取；无 WBI/App 签名。字符串只在传输层编码一次，写操作不自动重试。控制器绑定 scope、session epoch 和 generation，关闭/账号切换取消请求，提交中禁止重复提交。网络/超时/HTTP/协议异常使结果进入待核对状态；用户“重新读取”后，若服务器值与此次提交一致则视为已保存，否则展示服务端信息，允许用户再次明确保存。原草稿在失败时保留。

最后验证：2026-10-06，列表与 `info` 已用本机已有 Web 会话只读验证；POST 仅做脱敏 fake transport 验证，未对真实账号提交修改。服务端权限、认证和风控错误按类别反馈；仍未在线验证所有业务失败码及写入结果。

## 来源与采用范围

视觉依据为用户本轮截图。只读查看相邻 UWP 的 [FavoriteAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/FavoriteAPI.cs)、[FollowAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/FollowAPI.cs)、[FavoriteDetailViewModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/ViewModels/Favourites/FavoriteDetailViewModel.cs)，以及 kernel 的 [MyClient.cs](../../../bili-kernel/src/Services/Services.User/Core/MyClient.cs)、[VideoFavoriteGalleryResponse.cs](../../../bili-kernel/src/Services/Services.User/Core/Models/VideoFavoriteGalleryResponse.cs)、[FavoriteAdapter.cs](../../../bili-kernel/src/Services/Services.User/Core/Adapters/FavoriteAdapter.cs)。快照及许可边界见 [参考文档](../references.md)。仅借鉴协议、类型和交互职责，独立编写 Dart/Flutter；未复制新增源码/schema/资源，未修改相邻仓库。参考 App 追番/追剧方法未迁入，使用已有 Web 追番端点的两种类型。

## 验证与边界

补充编辑验证：协议测试覆盖大 ID、完整简介、私密 bit 与 `privacy` 参数、Cookie/CSRF、错误和取消后不重放；Repository/控制器测试覆盖所属账号、scope/epoch、重复提交、未知结果核对、关闭和账号切换；Widget 覆盖菜单与打开收藏夹的独立点击、完整预填、空名称、取消、保存刷新、360 像素与双倍字体。Windows 已有会话只读确认 7 个自建收藏夹均提供状态和日期，样本 `info` 可解析且拥有者正确，未提交真实修改。

编辑补充后的 `tool/check.ps1 -SkipPub` 通过根应用与三个包的格式、静态分析和测试：根应用 588、API 206、播放器 16、弹幕 19，共 829 项（同时包含工作区其他并行改动的当前快照）。Windows 只读集成测试与最终 `flutter build windows --release --no-pub` 通过。无新增依赖和原生播放改动。新增日志为 `build/folder-edit-check.log`、`build/folder-edit-windows-read.log` 和 `build/folder-edit-windows-build-final.log`；普通检查脚本仍不运行真实账号写操作。

界面补充渲染为 1735 像素五列和 360 像素双倍字体自建收藏夹列表，使用占位封面；视检状态标记、锁图标、日期和菜单。实际 Android/macOS 视觉操作和真实收藏夹修改仍未验收。

- 离线协议测试覆盖默认 ID/改名与创建列表过滤、跨页游标、同 ID 不同类型、合集整页响应、追番/追剧分类、视频元数据、失效资源、权限错误、取消后不继续链式请求与无账号拒绝。
- Widget 回归覆盖五个标签、合集进入/返回和切换保留、公共卡片、作者/视频点击、窄窗口/双倍字体、宽屏铺满与个人主页懒加载；收藏容量测试覆盖去重和停止分页。
- 显式 [Windows 只读集成入口](../../integration_test/windows_favorites_test.dart) 使用系统安全存储中的已有会话；凭据和私有内容只在内存中使用，日志只输出数量/分页状态/失败分类。实测默认收藏前两页各 20 条；创建列表 7 项，样本夹 9 个有效视频；收藏与订阅 12 项，样本合集一次返回 38 个有效视频且停止分页；追番 20 项、追剧 4 项；个人主页样本夹返回 30 个有效视频。
- Windows Debug 构建与上述只读集成测试通过。此次只读读取不代表所有账号、隐私设置和会员/地区权限已验证；未执行收藏/取消订阅等账户写操作。Android/macOS 和真实客户端窗口视觉操作未验收，未修改原生播放。

`tool/check.ps1 -SkipPub` 通过根应用和三个包的格式、静态分析与测试：根应用 537、API 包 183、播放器包 16、弹幕包 10 项，共 746 项（本次工作区快照）。未新增依赖，使用已有解析结果。另完成三个离线 Flutter 渲染快照：1735 像素默认夹/订阅列表与 360 像素双倍字体列表；封面为占位样本，视检五列布局、叠层、公共视频元数据和可横滚标签。子标签字体改为继承应用主题，避免显式字号覆盖配置字体。日志位于 `build/favorites-*.log`，快照位于 `build/favorites-preview/`。

字体修正后再次全应用静态分析通过、首页 84 项回归通过；`flutter build windows --release --no-pub` 成功，产物为 `build/windows/x64/runner/Release/bili_lite.exe` 及配套目录。未替换或关闭用户已有客户端进程。登录只读验证可显式执行 `flutter test integration_test/windows_favorites_test.dart -d windows --no-pub`，需要本机安全存储中已有会话；普通检查脚本不运行此集成入口。
