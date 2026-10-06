# Web API 端点与首轮验证

密码／短信由内嵌官网登录页处理，应用只接入 Cookie 和账号 nav 校验；协议边界、平台依赖与验证见 [登录验证](password-sms-login.md)。

七类搜索的 Web 综合/分类端点、排序与游客查询“小约翰”结果见 [搜索分类与排序](search-categories.md)。下表 `searchVideos` 保留首轮仅视频搜索时的记录；当前搜索页面使用模块化 `SearchClient`。

播放侧栏新增的 UP 统计与关注／取消关注端点，以及合集播放量和时长映射，见 [简介侧栏端点与验证](video-sidebar.md)。

用户空间新增的资料、WBI 投稿、动态、收藏、关注/粉丝 GET 端点和本次结果登记于 [用户主页验证](user-profile.md)。

直播 SC 的 Web GET 快照端点、响应限制及游客空样本验证见 [影视侧栏与直播 SC](pgc-live-sidebar.md#sc-协议与状态)。

后续影视弹幕/发送、直播实时消息、SC 合并以及分区 Web 房间列表见 [影视与直播弹幕修复](pgc-live-danmaku.md)。

首页/空间动态继续使用既有 Web GET 端点；富文本表情、配图和转发引用的共用解析及测试边界见 [主页卡片与富动态](profile-dynamic-style.md)，未新增发送或互动端点。

日期：2026-10-05。环境：Windows x64、Dart 3.13.5、`bili_api` 0.1.0，`dio` 5.11.1、`crypto` 3.0.7。游客态经本机网络执行少量低频只读烟测；未使用账号 Cookie，也未访问媒体 CDN。测试入口为 `packages/bili_api/tool/live_smoke.dart`。在线接口会变化，以下结论只对应本次观测。

后续新增端点分别登记在 [首页子频道](home-subtabs.md) 与 [播放器评论/推荐](player-workspace.md#新视频端点)，直播推荐首页快照（`index/getList`，无分页）及新增互动、第三方空降接口登记于 [界面控件与设置](ui-controls.md)。下表保留首轮端点与当时结果。

| 能力 / 公开方法 | Host / 方法 / Path | Profile、鉴权与签名 | 响应、分页与重试 | 游客烟测 |
| --- | --- | --- | --- | --- |
| 热门 `getPopular` | `api.bilibili.com` GET `/x/web-interface/popular` | Web，Cookie 可选，无签名 | JSON；`pn`、`ps=20`；只读网络/超时/指定 5xx 最多 2 次额外尝试 | 成功，列表可解析 |
| 推荐 `getRecommended` | `api.bilibili.com` GET `/x/web-interface/index/top/feed/rcmd` | Web，Cookie 可选，WBI | JSON `data.item[]`；`ps=20`、`fresh_idx`/`fresh_idx_1h`、`fresh_type=4`、`feed_version=V8`、`y_num=5`；索引递增，非空视频页可继续读取；同上 | 本轮成功解析 20 条视频；未测登录推荐与连续分页 |
| 分区投稿 `getRegionalVideos` | `api.bilibili.com` GET `/x/web-interface/newlist` | Web，Cookie 可选，无签名 | JSON `data.archives[]`；`rid`、`pn`、`ps=20`；以 `data.page.count` 判断结束，缺省时按页大小判断；同上 | 本轮动画分区返回 20 条；未测所有分区与真实跨页读取 |
| 排行目录 `RankingClient.getRegions` | `api.bilibili.com` GET `/x/kv-frontend/namespace/data` | Web，Cookie 可选，无签名 | `appKey=333.1339`、`nscode=10`；JSON `data.data`；按 `channel_list.popular_page_sort` 引用各项的 name/tid，跳过 PGC；无分页；同上；[动态目录](ranking-regions.md) | 官网配置游客读取成功，当前 14 个 UGC 排行分区 |
| 排行榜 `getRanking` | `api.bilibili.com` GET `/x/web-interface/ranking/v2` | Web，Cookie 可选，WBI | JSON `data.list[]`；`rid`（0=全站，UGC 使用上述配置返回的 ID）、`type=all`；单份榜单无分页；同上；[目录修正](ranking-regions.md) | 完整应用烟测全站与动画 `1005` 各成功解析 100 条；其他时段游客遭遇 `-352`，按限流停止重试；未验证所有榜单日期；界面显示错误，不替换成热门 |
| 搜索 `searchVideos` | `api.bilibili.com` GET `/x/web-interface/wbi/search/type` | Web，Cookie 可选，WBI | JSON；`keyword`、`search_type=video`、`page`、`page_size=20`；同上 | 成功；视频搜索结果中出现空 bvid 的内嵌直播卡，已排除 |
| 详情/分 P `getVideoDetail` | `api.bilibili.com` GET `/x/web-interface/view` | Web，Cookie 可选，无签名 | JSON；`bvid`；同上 | 成功，aid/cid 以十进制字符串交付 |
| DASH `getPlayInfo` | `api.bilibili.com` GET `/x/player/wbi/playurl` | Web，Cookie 可选，WBI | JSON；`bvid`、`cid`、`qn`、`fnval=4048`、`fourk=1`；同上 | 成功取得 H.264 视频轨与 AAC 音轨元数据；未验证 CDN headers、Range 或实播 |
| 字幕索引 `getSubtitleTracks` | `api.bilibili.com` GET `/x/player/wbi/v2` | Web，Cookie 可选，WBI | JSON；`aid`、`cid`；同上 | 请求成功；样本字幕列表为空，未证明有字幕视频可用 |
| 字幕正文 `getSubtitleCues` | 响应中的 `.hdslb.com` / `.bilibili.com` HTTPS URL，GET | 不附带非匹配域 Cookie；不签名 | JSON `body[]`；同上 | 未测（样本无字幕） |
| 分段弹幕 `getDanmakuSegment` | `api.bilibili.com` GET `/x/v2/dm/web/seg.so` | Web，Cookie 可选，无签名 | HTTP Protobuf；`type=1`、`oid=cid`、`segment_index`；同上 | 成功解析第 1 段；只实现普通滚动/顶部/底部所需字段 |
| Web QR 创建 `generateQr` | `passport.bilibili.com` GET `/x/passport-login/web/qrcode/generate` | Web，无账号凭据，无签名 | JSON；不分页；只读有界重试 | 成功，key/URL 未打印或保存到 fixture |
| Web QR 轮询 `pollQr` | `passport.bilibili.com` GET `/x/passport-login/web/qrcode/poll` | Web，二维码 key，无 WBI | JSON；返回 waitingScan/waitingConfirm/expired/confirmed；Set-Cookie 进临时 jar；有界重试 | 未测真实扫码/确认/过期；仅 fake transport 测试 |
| 会话与 WBI `getNav` | `api.bilibili.com` GET `/x/web-interface/nav` | Web，Cookie 可选，无签名 | JSON；不分页；有界重试 | 游客返回业务码 `-101`，但 `data.isLogin=false` 和 `data.wbi_img` 有效；包按游客状态解析 |

上表首轮读取端点均为 GET。请求设置总 deadline，取消与 `sessionEpoch` 检查；旧会话响应被丢弃。网络/超时以及 HTTP 500/502/503/504 只读请求最多额外尝试 2 次，带短指数退避；429、风控/限流、认证/权限与协议错误停止重试。Dio 禁止自动跳转，防止 Cookie 随重定向发送至新目标。Cookie 仅按受限 Bilibili 域、路径、HTTPS、安全标志和绝对过期时间发送。二维码必须由主应用使用独立临时 client/jar；扫码确认后仍需 nav 校验与系统安全存储成功才可提升为主会话。包提供版本化 JSON 兼容快照供**安全存储**使用，不将其写入普通配置或日志。

WBI 密钥由 nav 的图片 URL 提取并单飞缓存；遇到 `-403` 仅刷新并重签一次。签名参数在最终 URI 构造前保持原始字符串，仅 transport 边界编码。普通弹幕解析器是按已公开字段编号独立编写的最小有界解码器，限制单段 2 MiB、最多保留 6000 项、单项 4096 字节、内容 1024 字节；超过条数预算时完整校验后均匀抽样，行为与登录首集验证见 [密集番剧弹幕](pgc-dense-danmaku.md)。未复制相邻参考仓库的 Protobuf schema、代码或 fixture。字段参考 [Bilibili API Collect 的弹幕说明](https://github.com/realysy/bili-apis/blob/master/docs/danmaku/danmaku_proto.md)，端点定位参考本项目 [API 方案](../api-design.md) 与 [参考映射](../references.md)。Dio/crypto 直接依赖版本来自各自维护方 [Dio](https://pub.dev/packages/dio) 与 [crypto](https://pub.dev/packages/crypto) 页面，包内精确固定版本。

超过 32 KiB 的分段弹幕通过 `TransferableTypedData` 交给独立 isolate 解码；包内最多同时运行 2 个解码任务、等待 4 个。等待时可取消或超时，解码前后再次检查取消、账号 epoch 和 deadline，旧结果不会回写。小段保留同步解码。包内测试覆盖真实 isolate 解码、排队上限路径及取消后的结果丢弃；未测目标设备上的解码性能。

本轮首页布局更新的在线入口是 `packages/bili_api/tool/feed_smoke.dart`：仅发起推荐、动画分区和全站排行榜各一次逻辑读取，输出数量、分页标记及脱敏错误类别/状态码。推荐和分区不再通过热门请求提供数据。推荐忽略 `goto` 明确为非普通视频的卡片；普通视频缺少关键字段仍返回协议错误。应用分区导航为一组固定 UGC 分区，并非实时的全站分区目录。排行榜参数参照相邻 UWP 的 `RankAPI.cs`（仅借鉴协议）；Web 推荐端点定位来自 `bili-kernel` 的 `BiliApis.Home.CuratedPlaylist`。请求与映射独立编写，未复制参考代码、资源或响应 fixture。新测试使用手写脱敏数据，覆盖独立端点、WBI、分页与排行榜风控不重放、不回退热门；分类/频道切换取消旧请求也有应用层测试。

目前未验证登录后的 Cookie 持久化、扫码完整流程、字幕正文、其他视频权限/地区/会员结果、CDN 媒体请求头与 Range、实际播放、macOS/Android 网络行为。没有自动发起账号写请求；本报告不代表 M0 三端播放验收。



## 播放页评论互动与合集协议（2026-10-05）

| 能力 / 公开方法 | Host / 方法 / Path | 鉴权、格式、分页与重试 |
| --- | --- | --- | --- |
| 热门/最新评论 `getVideoComments` | `api.bilibili.com` GET `/x/v2/reply` | Web Cookie 可选，无签名；JSON；`oid=aid`、`type=1`、`pn`、`ps=20`，`sort=1` 按点赞热度、`sort=0` 最新，`nohot=1` 避免额外热评混入；沿用有 deadline 的有界只读重试 |
| 二级评论 `getVideoReplies` | `api.bilibili.com` GET `/x/v2/reply/reply` | Web Cookie 可选，无签名；JSON；相同页码参数及字符串 `root`；沿用有界只读重试 |
| 评论点赞/取消 `likeVideoComment` | `api.bilibili.com` POST `/x/v2/reply/action` | Web Cookie 必需，body CSRF；`oid`、`rpid`、`type=1`、`action=1/0`；JSON；不自动重放 |
| 评论/回复发送 `addVideoComment` | `api.bilibili.com` POST `/x/v2/reply/add` | Web Cookie 必需，body CSRF；`oid`、`type=1`、原文 `message`、`root`、`parent`；JSON `data.reply`；不自动重放 |
| 评论表情面板 `getCommentEmotes` | `api.bilibili.com` GET `/x/emote/user/panel/web` | Web Cookie 可选，无签名/CSRF；`business=reply`；JSON `packages`，无分页；沿用共享 deadline、有界只读重试和会话隔离 |
| 视频合集 `getVideoDetail` | `api.bilibili.com` GET `/x/web-interface/view` | 可选 `ugc_season` 的 sections/episodes 映射为扁平合集；分 P 来自 episode/arc 的 pages，缺省为空，由应用按需加载详情 |

协议定位参考相邻 `biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/CommentApi.cs`（仅借鉴端点、字段和排序语义，未复制实现或资源）。本轮使用手写脱敏数据验证：长字符串 ID、热门/最新参数、置顶去重、点赞态与回复数、二级分页、嵌套预览最多一层/每条 20 项、顶层最多 100 项、合集最多 500 视频/每视频 100 分 P、合集视频去重、原文参数与 Cookie CSRF、写请求 503 不重放及游客拒绝写入。合集至多读取 50 个 section，各 section 至多 500 个 episode。未新增依赖。

新增写端点与合集完成离线单测，未在线验证评论点赞/发送、服务端风控结果或合集响应；未执行真实账号写操作。评论读写均使用现有取消、deadline 和 session epoch 管线。评论页 `totalCount` 为服务端 page.count（根评论条数），不使用 acount（包含二级评论的总数）。合集页缺少 pages 不代表视频没有分 P。

### 本轮游客只读补测

使用 `dart run tool/video_extras_smoke.dart`（可传 bvid，`--sort-only` 跳过合集候选探测）。2026-10-05 样本 `BV1cGbK6hEQK`：详情 1 个分 P，无合集；按点赞热度 sort=1 返回 3 条、根评论 total=635、hasMore=true，3 条均有头像 URL；选取有回复的根评论读取二级列表得到 18 条、total=18、hasMore=false。最新评论 sort=0 的游客响应为成功码 0，replies=null，page.num/size/count/acount 均为 0；control.input_disable=false、web_selection=false。一次不含 nohot 的对照请求结果相同。客户端明确接受该服务端空页（hasMore=false），不误报协议错误；它没有认证失败业务码，不能擅自断言需要登录。**本轮未验证游客或登录后非空最新评论排序可用**。这个空页也不能证明真实评论区没有评论。

已纠正原先的 sort=2 及相邻参考方法注释中的排序歧义：[API Collect 原协议说明](https://github.com/pskdje/bilibili-API-collect/blob/main/docs/comment/list.md) 将旧 `/x/v2/reply` 的 sort 定义为 0 时间、1 点赞、2 回复数；相邻源码的实际枚举 New=0/Hot=1 与此一致，其“1=最新，2=最热”注释不适用于该方法。应用发送最新=0、热门=1，并使用 nohot=1；尚未迁入另一个采用 mode/cursor 的 WBI main 端点，避免混淆两种分页契约。API Collect 同时区分 page.count 根评论数和 acount 总评论数，客户端分页使用前者。

热门公开列表仅取前 3 个视频详情，均为单 P 且无合集；没有扩大候选探测。合集与多 P 的在线响应本轮仍未验证，离线测试覆盖其映射。补测不使用账号 Cookie、不执行点赞/发送、未记录评论正文或媒体 URL。服务端只交付少量评论时，hasMore 只表示服务端计数尚有剩余，不能保证游客后续页能完整取得。

后续发布版界面只读复核使用应用已有登录会话，在另一公开视频 `BV1gQ9SBuED4` 实际显示非空最热／最新列表和带头像的二级回复（14 条），新旧日期顺序可见。这仅补充一个登录会话的读取证据，不改变上述独立游客样本的空页结论；没有执行账号写入。完整记录见 [播放页与评论交互](video-comments.md)。

最终补测以旧预览版已打开的 `BV1GLHE6hEFg` 为已知样本，通过同一 smoke 的 `--sort-only` 路径取得真实非空合集（视频本身 1 P）、推荐 40 条、热门 3 条（根评论数 347）、二级 1 条；游客最新仍为空页。这补充了前述候选未含合集的限制，未进行广泛探测或账号写入。

## 富评论与表情面板补测（2026-10-05）

`tool/comment_media_smoke.dart` 是显式开发只读入口，仅输出数量/失败分类，不输出评论正文、Cookie 或图片 URL。游客表情面板返回成功码 0，但 `packages=null`，因此显示空状态；不能记为游客可获取非空表情包。`BV1GLHE6hEFg` 的热门根评论及预览合计 10 条，10 条含等级、5 条含表情、1 条含图片，当前样本无粉丝勋章。

Windows 发布版随后使用应用已有登录会话，在 `BV146V86eEbB` 评论中实际显示等级、粉丝勋章和内联表情；表情面板成功显示非空“小黄脸”包，选择表情后原文 token 插入草稿。测试草稿已清空，没有执行发送或点赞；没有提取账号凭据。这是一个登录会话的界面读取证据，不改变游客空包响应的结论。

新增字段来自 `member.level_info`、`official_verify`、`vip`、`fans_detail` 和 `content.emote/pictures`，缺省独立降级，不使纯文本评论失效。内联表情最多 100 项，图片最多 9 张；面板最多 50 个包、每包最多 200 项，界面只懒加载所选包的可见项。图片统一为 HTTPS，不携带账号凭据；发送沿用原文 token、Web Cookie/CSRF 和单次 POST，没有自动重放或新增图片上传接口。
