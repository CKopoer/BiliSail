# 云端观看历史列表

日期：2026-10-07。工具链沿用 Flutter 3.47.6 / Dart 3.13.5。

## 数据与页面行为

此前 `/history` 的 `LibraryRepository` 注入 `SqliteLibraryRepository`，读取本机 `playback_progress`。该表只保存续播元信息，没有播放量、弹幕数或发布时间；页面也没有使用已保存的观看时间，因此公共卡片显示缺失统计和空日期。

现在 app 注入 [ApiLibraryRepository](../../lib/features/library/data/api_library_repository.dart)，观看历史只读取当前账号的云端记录。游客显示登录提示；网络或认证失败显示错误和重试，不回退成本地列表。本地 SQLite 的进度保存与“本地优先、云端补充”续播规则保持，数据库 schema 不变。

[WatchHistoryClient](../../packages/bili_api/lib/src/clients/watch_history_client.dart) 解析历史的 `history.bvid/cid/page/part/epid`、`view_at`、`duration` 和 `progress`。时间戳为秒，转成 UTC DateTime 后按设备本地时区显示；进度秒转 Duration，`-1` 为已看完、0 为未开始，超出时长截到末尾。普通视频按 BVID/cid 打开对应分 P，影视按 episode ID 打开现有影视播放页。没有 cid 时不传空 cid。直播和专栏条目不混入点播页，直播记录仍可在直播频道查看。

云历史不提供视频播放/弹幕统计。Repository 在每页内按有效 BVID 去重，通过现有视频详情补齐 `stat.view` 和 `stat.danmaku`，最多三个请求并发、共享本页取消与 25 秒 deadline。单条详情不存在或统计字段缺失时保留历史条目，对应统计为 null，公共卡片显示横杠；真实 0 显示 0。出现网络、认证、限流等错误后不继续启动本页剩余详情请求。没有有效 BVID 的影视历史仍按剧集打开，无法取得的统计保持缺失，不用全剧统计代替单集统计。

卡片日期采用云端观看日期：当年显示 `MM-DD`，跨年显示 `YYYY-MM-DD`；日期 tooltip 展示 `观看于 YYYY-MM-DD HH:mm`。不把观看日期映射为发布时间。统计、时长、作者跳转和进度继续复用公共 VideoCard；紧凑日期避免完整时间占用作者行造成异常截断。

## 端点与分页

| 用途 | Host / method / path | Profile / 鉴权 / 签名 / 格式 | 参数与重试 |
| --- | --- | --- | --- |
| 云端观看历史 | `api.bilibili.com` GET `/x/web-interface/history/cursor` | Web Cookie，JSON，无 WBI/CSRF | `ps=20`，`max`、`view_at`、`business` 为服务端游标；首屏 0/0/空。沿用最多额外两次网络/5xx 重试及总 deadline |
| 视频统计补齐 | `api.bilibili.com` GET `/x/web-interface/view` | 既有 Web 视频详情，Cookie 可选，JSON | `bvid`；只使用播放量和弹幕数，不替换历史时长、标题、观看时间或位置；沿用既有读重试 |

[HistoryController](../../lib/features/library/application/library_controller.dart) 独立管理刷新代次、取消、账号 scope 和 session epoch。刷新丢弃旧分页，重复游标显示可重试错误；重叠页面按 BVID/cid/episode 去重，保留不同分 P 和剧集。使用既有 PagedScrollViewport 自动补满首屏和滚动分页，隐藏工作区不自动翻页；最多保留最近 500 条，连续三页没有新增点播条目时暂停自动扫描，可显式继续。分页失败保留已显示记录，并沿原游标重试。

## 协议来源与采用范围

只读核对 [官网历史页](https://www.bilibili.com/account/history) 引用的 [官方脚本 app_d0026f29.js](https://s1.hdslb.com/bfs/static/history-record/app_d0026f29.js)：Web Cookie GET、`max/view_at/business` 游标以及空列表终止。交叉参考相邻 UWP [AccountApi.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/AccountApi.cs) 的 `HistoryWbi`、[UserHistoryItem.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/User/UserHistoryItem.cs)、[UserHistoryItemHistory.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/User/UserHistoryItemHistory.cs) 的历史字段，以及 [PiliPlus 自有历史读取](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/http/user.dart) 的每页 20 条请求。仅参考协议职责，Dart 实现和手写脱敏样本独立编写，不复制代码、schema 或资源，不增加依赖或修改参考仓库。

## 验证

协议回归覆盖秒时间戳、字符串 ID 与超过 2^53 的 ID、三字段游标、PGC 无 BVID/cid、混合业务过滤、完成/0/超时长进度、格式错误与停滞游标。Repository 回归覆盖云端读取、每页去重统计、真实 0/缺失计数、详情失败保留列表、游客不请求、三个并发上限、账号及同账号 epoch 变化。控制器回归覆盖分页去重、刷新竞态、错误重试、扫描/列表上限与旧账号响应。页面回归覆盖统计格式化、观看日期 tooltip、分 P／剧集导航和进度条。

`tool/check.ps1 -SkipPub` 全量通过：根应用 895、API 包 281、播放器包 22、弹幕包 32 项，共 1230 项；四处格式检查与静态分析通过。检查日志为 `build/cloud-history-check.log`。本轮新增 API 协议测试 12 项、Repository 测试 6 项、控制器测试 8 项，并扩展原有两项历史页面测试；SQLite 续播与工作区导航既有回归通过。文档相对链接和差异检查通过。

本轮没有读取真实账号历史，也没有提交历史上报。Windows/Android/macOS 实机界面与登录云端响应仍待验证；离线样本不能视作在线验收。没有修改原生播放或进行平台构建。
