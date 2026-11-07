# 直播观看记录、关注分页与多类型历史

日期：2026-11-07。对应 [issue #87](https://github.com/CKopoer/BiliSail/issues/87)。本轮按用户范围只运行离线自动检查，不构建平台产物、不操作真实账号，在线与实机验收由用户后续完成。

## 行为与分层

- 登录用户进入并激活直播页、取得真实房间 ID 后，通过领域端口 `LiveHistoryRepository` 上报一次观看记录。游客、未激活页面和房间加载失败不提交。刷新房间、切换布局、后台恢复或保留页再次激活不重复上报；新页面或新账号 session epoch 可提交新记录。页面关闭或账号变化取消在途操作，旧结果不能覆盖当前状态。上报独立于播放和聊天，失败记录于请求诊断与控制器状态，不中断房间加载，不自动重放结果不明的写请求。
- 直播“我的关注”改用支持分页的 `user/following`。首屏保留本次响应中 `live_status=1` 的主播，使用 `room_cover` 封面；后续由既有“加载更多”按钮显式请求，关闭该分支的滚动／首屏补满自动翻页。按原始响应 `totalPage` 判断结束，不能用过滤后的条数、固定 30 条或主播总数提前截断。空在播页仍允许继续，既有控制器保留去重、失败后原页重试、账号隔离与连续空页暂停机制。
- “我的－历史记录”和独立历史页共用 `HistoryScreen`。视频、影视保留原卡片、观看日期、分 P／剧集跳转和进度；增加直播、专栏、文集及课程。非视频条目不伪装成 `VideoSummary`，不请求视频详情补齐或显示点播进度。
- 直播历史使用 `history.oid` 打开应用内房间，按快照 `live_status` 显示“直播中／未开播”；未开播房间沿用既有页面行为。专栏使用 `oid`、文集使用 `cid` 打开对应官网页面；课程使用 `epid`，缺失时从 `uri` 提取 `ep`／`ss` 数字身份，重建固定官网地址，不保留原链接查询参数。项目尚无专栏、文集和课程阅读／播放页，因此使用现有外链端口打开。
- 非视频卡片沿用共享响应式懒加载网格、16:9 封面、主题颜色、圆角和文字样式，展示类型／直播状态、作者、观看日期与删除菜单。搜索继续查询全类型记录；删除使用原始 business 与根 `kid`，清空仍作用于当前账号全部云端历史。按类型、内容 ID 与分 P／课程目标种类去重，避免数字 ID 相同的直播和专栏相互覆盖，仍最多保留 500 条。

## 协议

| 用途 | Host / method / path | 鉴权、请求与分页 |
| --- | --- | --- |
| 直播进房上报 | `api.live.bilibili.com` POST `/xlive/web-room/v1/index/roomEntryAction` | Web Cookie，查询参数 `csrf`，JSON 请求体 `room_id`／`platform=pc`，JSON 响应；直播域 Cookie、Origin、Referer 沿用统一写管线；无 WBI、无分页，单次提交、总 deadline、取消与 epoch 检查 |
| 关注直播列表 | `api.live.bilibili.com` GET `/xlive/web-ucenter/user/following` | Web Cookie，JSON，无 WBI／CSRF；`page` 从 1 开始、`page_size=20`、`ignoreRecord=1`、`hit_ab=true`；读取 `list`／`totalPage`，沿用有界只读重试和总 deadline |
| 全类型历史／搜索 | `api.bilibili.com` GET `/x/web-interface/history/cursor`、`/x/web-interface/history/search` | 沿用 Web Cookie、三字段服务端游标／搜索页码；识别 `archive`、`pgc`、`live`、`article`、`article-list`、`cheese`；未知业务跳过但保留原始分页，游标允许文集的连字符 |
| 删除／清空 | `api.bilibili.com` POST `/x/v2/history/delete`、`/x/v2/history/clear` | 沿用 Cookie／CSRF 表单和单次写入；删除键扩展到上述六种 business，仍只使用根 `kid`；写入互斥和结果不明时刷新核对规则保持 |

本记录更新了[历史列表早期记录](cloud-watch-history.md)中“只显示点播、过滤直播专栏”的范围，不改变 SQLite 续播、数据库 schema 或本地进度上报策略。

## 来源与许可

只读参考相邻 PiliPlus 提交 `265f879fa85973b4bf885bde2562f1007f1013b8`：`lib/pages/live_room/controller.dart`、`lib/http/video.dart` 的 `roomEntryAction`，`lib/http/api.dart`、`lib/http/live.dart` 的关注端点，`lib/pages/live_follow/controller.dart` 与 `lib/models_new/live/live_follow/{data,item}.dart`，以及 `lib/models_new/history/{history,list}.dart`、`lib/pages/history/widgets/item.dart`、`lib/utils/page_utils.dart` 的不同历史身份和目标解析。

仅采用协议字段及交互职责，按本项目 Riverpod、领域端口和共享 UI 独立实现；未复制 GPLv3 应用源码、schema 或资源，未修改相邻仓库、增加依赖或变更锁文件。

## 验证与未测项

离线回归覆盖进房 JSON／Cookie／CSRF 与单次超时、真实房间 ID、登录／可见性、刷新和重激活去重、账号 epoch 取消／迟到结果；关注列表的在线过滤、长 ID、跨空页继续与显式按钮分页；混合历史的 ID、封面、时间、删除键、课程单集／整季地址、搜索和分页；Repository 不为非视频请求详情、跨类型去重／删除，以及 320px 两倍字体和 1280px 历史卡片跳转与菜单。

`tool/check.ps1 -SkipPub -Stage RootTests` 通过：根应用 4615 项；`-Stage PackageTests` 通过：API／播放器／弹幕／mux 分别为 696／245／161／5 项，共 5722 项。根应用另因符号链接权限跳过 13 项；mux 因未设置 `BILI_MUX_LIBRARY` 跳过 10 项原生用例。日志为 `build/issue-87-root-tests.log` 和 `build/issue-87-package-tests.log`。收尾样式修改后，历史／直播／关注定向测试及假数据渲染共 91 项通过，日志为 `build/issue-87-final-targeted.log`。

本任务涉及的 15 组文件／目录通过定向 `flutter analyze --no-pub`；收尾后 `dart analyze lib/features/library` 通过。文档链接和任务差异检查通过。假仓储渲染并检查了 390px 浅色、1280px 浅色和 320px 深色两倍字体，预览位于忽略目录 `build/validation/issue-87/`，不属于平台构建或实机验证。

完整 `tool/check.ps1 -SkipPub` 的打包边界脚本通过；首次格式阶段曾被同期播放器文件拦住。本任务没有修改这些文件。收尾复查时，覆盖根应用、四包和 Linux 适配器的格式检查通过（1030 个文件、0 改动），全量 `flutter analyze --no-pub` 通过；日志为 `build/issue-87-final-format.log` 和 `build/issue-87-full-analyze-final.log`。测试按根脚本的 RootTests／PackageTests 阶段分别通过，不将首次中止的 All 日志表述成一次完整通过。

未读取真实账号历史、提交真实上报或执行删除／清空。没有 Windows／Android／macOS 等平台构建、热重载或实机验收；当前无可连接的 DTD 调试应用。接口在线响应、真实账号跨端同步、关注超过 30 个直播间及设备样式仍需用户实测。mux 原生用例的跳过不计为原生通过。
