# 界面控件与设置验证

日期：2026-10-05。本文记录本轮实现与验证，不能据此推导 Android/macOS 原生支持或真实账号写操作已经通过。

## 实现范围

- 设置页按外观、播放、弹幕、字幕、空降助手分组，采用自有 Flutter 控件，参考 UWP 设置项职责与分组，不复制 XAML、图标或资源。
- 播放设置包含自动播放、本地续播、优先清晰度、默认倍速和音量。弹幕设置包含开关、不透明度、字号、区域、速度、每秒上限、滚动/顶部/底部模式和有界关键词屏蔽。字幕设置包含默认开启、字号、背景和底部距离。
- 播放器新增独立设置弹窗和空降入口；会话消费设置，并保持单一原生引擎。视频操作包括点赞、投币、收藏、稍后再看和发送弹幕，写操作由用户明确点击触发，应用组合根已接入，公共 transport 的 POST 分支单次执行。
- 视频动态此阶段采用独立信息卡片，增加作者头像、名称、发布时间、封面、时长及播放/弹幕数；后续已统一为 [共享视频卡片](shared-video-cards.md)。直播采用房间卡片，展示主播、分区、人气和封面；分区选择支持父分区、子分区、横向滚动及展开。直播房间入口仍需按现有浏览器打开路径理解，不能称为已实现直播播放器。

## 操作反馈提示调整（2026-10-05）

点赞、投币、收藏、稍后再看、复制链接和发送弹幕的结果，以及登录提醒、设置保存失败、浏览器打开失败和标签数量限制，统一使用 `lib/shared/ui/app_notice.dart` 的轻量提示。提示水平居中，位于可用页面中间偏下（约三分之二高度），宽度随文字收缩、最大 320 逻辑像素，并在 1.5 秒后自动消失。新消息替换当前提示并重新计时；提示不拦截页面点击，避开安全区和软键盘。根应用通过 `MaterialApp.builder` 挂载提示宿主，弹窗与全屏共用同一展示层。

新增组件验证覆盖自动消失、连续提示替换、点击穿透、定时器释放，以及 320/800/1920 宽度下双倍字号和软键盘避让；点赞反馈另有 fake repository 交互验证。没有执行真实账号写操作。

本次 `tool/check.ps1 -SkipPub` 完整通过：根应用 228 项、bili_api 76 项、bili_player 16 项、bili_danmaku 5 项，共 325 项；四处格式检查与静态分析均通过。本次未重新构建安装包或进行各平台真机界面验证。

## 设置快照升级

SQLite 的 `settings` 表和数据库版本仍为 1。本轮仅扩展 `preferences.v1` 中的 JSON，写入 `schemaVersion: 2`。旧的主题、弹幕开关、不透明度和字号保留；新增字段缺失时使用默认值，不清空数据。

主要默认值：自动播放和续播开启，清晰度 80，倍速 1，音量 100，弹幕区域 0.75、速度 1、每秒 20 条，字幕默认关闭。空降助手默认关闭，默认类别为 `sponsor`。

边界归一化：清晰度限于明确列表；倍速 0.25–3，音量 0–100，弹幕不透明度 0.2–1、字号 0.2–1.5（2026-10-08 下限由 0.7 调整为 0.2）、区域 0.25–1、速度 0.5–2、每秒 1–100 条；关键词去空白、去重，最多 200 项，每项 100 字；字幕字号 0.5–2、背景 0–1、底部距离 0–120。非有限数恢复默认值，未知类别被过滤。

全局设置与播放器弹窗共用字号缩放范围。点播和直播的文本布局允许缩放后小于 12 逻辑像素的字号，轨道高度继续按实际文字高度加设置行距计算；新下限可在原设置快照中直接保存与重载，无需升级 SQLite 表结构。

2026-10-08 字号下限调整验证：设置入口／归一化／重载和点播／直播／影视桥接共 125 项测试通过；三个独立包的格式、静态分析及 416 项测试通过，本次根应用文件的静态分析通过。`tool/check.ps1 -SkipPub` 因其他并行修改文件的静态分析问题中断，日志为 `artifacts/danmaku-font-scale-check.log`；本轮未构建安装包或进行实机界面验收。

控制器公开各字段更新和组合 `update`，串行写入并保留最新可见状态；最新保存失败回滚到最近已持久化快照，页面提示失败。设置页滑条在保存结束后清除编辑草稿，让回滚值重新显示。

## 端点与第三方边界

- 动态：`api.bilibili.com/x/polymer/web-dynamic/v1/feed/all`，沿用 Web 会话与 cursor 分页，增加现有响应中的展示字段，不添加账号写操作。
- 推荐直播（未选分区）：Web profile、游客可用的 HTTPS GET `api.live.bilibili.com/xlive/web-interface/v1/index/getList?platform=web`，无签名；合并 `recommend_room_list` 与 `room_list[].list`，按房间 ID 去重并排除明确广告/非房间卡；该端点没有分页游标，`hasMore=false`。沿用只读总 deadline 和最多 2 次额外网络/指定 5xx 重试；风控不重试、不自动改端点。
- 直播分区：`api.live.bilibili.com/room/v1/Area/getList`；分区房间列表：`api.live.bilibili.com/xlive/web-interface/v1/second/getList`，父/子分区分别传 `parent_area_id` / `area_id`，按页请求。选中父区/子区后仍使用该分页端点，不将推荐首页数据冒充筛选结果。
- 空降助手：独立只读第三方 `https://bsbsb.top/api/skipSegments`，按 BV、CID 和类别查询，8 秒超时；404 视为无片段。使用独立无账号传输，不附 Bilibili Cookie，不提交片段、不上报跳过次数。类别为 `sponsor/intro/outro/selfpromo/interaction/preview`。UI 明示第三方查询，提供关闭、手动提示和自动跳过。
- 空降响应限制 512 KiB / 512 段，验证 CID、动作、类别、时间范围与视频时长；异步结果需在当前源和取消令牌仍有效时应用。自动跳过通过播放位置驱动，手动回看已跳过片段不应循环跳转。已补 source generation、取消和微任务执行时的播放状态复核。

2026-10-05 发布版复查：原 `second/getList` 推荐路径存在 `-352` 风控，已有记录见 [首页子频道](home-subtabs.md)。只读参考 UWP `Models/Requests/Api/Home/LiveAPI.cs` 的 `LiveHomeItems` 定位独立 Web 首页端点；本机无凭据单次 GET `index/getList` 返回 `code=0`，核对 `recommend_room_list`（5 条）与 `room_list`（11 个模块）及房间/主播/分区字段。未读取真实账号或复制源码/响应资源，未执行写请求；分区分页端点的风控限制仍保留。推荐首页结构和房间去重用手写 fixture 验证。

## 设置针对性验证

已执行：

```text
dart format lib/features/settings test/features/settings
flutter test test/features/settings
flutter analyze lib/features/settings test/features/settings
```

结果：设置相关 10 项测试通过；针对性静态分析无问题。覆盖快速连续保存、前序保存失败不阻塞后续、最新保存失败回滚、公开组合更新与重新加载、旧快照兼容、全部字段保存/读取、非法值归一化、非法快照错误、窄宽大字号主题选择和页面失败反馈。测试使用 fake repository 与内存 SQLite，不使用真实账号。

## 全量与交互验证

最终运行 `tool/check.ps1 -SkipPub`：根应用125项、bili_api 43项、bili_player 8项、bili_danmaku 5项，共181项全部通过；根应用及三个包的格式、静态分析均通过。设置新增构造列表快照测试，确保调用者修改原列表不会改变公开设置对象；`AppSettings.defaults()` 保留常量默认值。

- 播放范围 37 项：字幕显式关闭在换清晰度后保持、空降暂停/seek/切源/换 owner/账号变化竞态，普通/全屏复用同一引擎，320/800 宽及大字号设置弹窗。
- 新互动控制器 8 项、API 10 项：写请求不重试、CSRF/域路径/epoch、表单仅编码一次、禁止重定向、取消释放忙碌状态、未知结果只读核对与晚响应隔离。
- 操作栏与弹幕输入 12 项：320/800/1920 宽、2 倍字号、游客登录入口、投币确认、收藏差集、发送去空白/防重复/成功清空/失败保留。大字号真实溢出已修复。
- 头像 API 1 项、组件 3 项：字段映射、HTTPS/无凭据请求及空值/加载失败回退。
- 空降 API 3 项、弹幕包 5 项：响应容量/字段验证、播放时钟冻结/seek重建、区域和速度设置生效。

Windows 已运行 `tool/test-windows-media.ps1`：4 项本地实测通过，另一个在线用例在未传 `-Online` 时提前返回，不能计为已完成在线验证。原生验证确认320×180视频和48kHz单声道音轨均解码、独立 Range/Referer/重定向、seek/倍速、全屏/Esc单播放源、标签切换恢复与隔离安全存储探针。

Windows 发布版已实机查看原有会话恢复后的用户头像、三列视频动态卡片和作者头像；用户截图同一视频已显示1080P画面/弹幕、UP信息、操作栏及播放/弹幕/空降配置弹窗。全局设置页也已查看。最终便携版直播推荐已显示真实房间封面、主播、人气与分区；1266宽三列、1920宽五列均实机查看。没有更改登录信息或启用空降服务。

空降API另外用独立游客客户端做一次只读烟测：公开视频首P详情成功，独立无凭据 SponsorBlockClient 查询成功、0条有效片段。服务访问已验证；没有真实非空样本，跳过行为和字段边界仍以fixture/fake测试为依据。

本记录不宣称真实账号写操作已完成在线验证；测试没有真实点赞、投币、收藏或发送弹幕。性能未测量。

## 新增 Web 互动端点

均为 api.bilibili.com、Web Cookie profile，无 App token/WBI 假设。POST 使用 application/x-www-form-urlencoded，csrf 从目标域/path有效的 bili_jct Cookie 获取，并要求 SESSDATA；字段在 transport 只编码一次。不跟随重定向，不打印请求正文或凭据。写请求总次数=1，deadline 与单次12秒上限取较小值；账号退出取消在途请求，晚回不提交页面状态。只读 GET 沿用总 deadline/最多2次额外网络或指定5xx重试，认证/风控/协议错误不重试。

| 能力 | 方法 / Path | 参数 / 响应 / 分页 |
| --- | --- | --- |
| 是否点赞 | GET /x/web-interface/archive/has/like | bvid；data=0/1；无分页 |
| 已投币数 | GET /x/web-interface/archive/coins | bvid；data.multiply；无分页 |
| 收藏状态 | GET /x/v2/fav/video/favoured | aid；data.favoured；无分页 |
| 收藏夹选择 | GET /x/v3/fav/folder/created/list-all | up_mid、rid=aid、type=2；data.list[].id/title/fav_state；无分页，最多1000个 |
| 点赞/取消点赞 | POST /x/web-interface/archive/like | bvid、like=1/2、csrf；JSON code=0 确认成功 |
| 投币 | POST /x/web-interface/coin/add | bvid、multiply=1/2、select_like=0、csrf；用户选择后提交 |
| 收藏夹变更 | POST /x/v3/fav/resource/deal | rid=aid、type=2、add_media_ids/del_media_ids、csrf；只发差集 |
| 稍后再看 | POST /x/v2/history/toview/add | bvid、csrf；成功后按钮标记已加入 |
| 发送弹幕 | POST /x/v2/dm/post | bvid、oid=cid、type=1、msg、progress毫秒、mode=1/4/5、color、fontsize=25、pool=0、plat=1、rnd秒、csrf；最多100字符 |

协议定位参考相邻 UWP 的 PlayerAPI.cs、User/WatchLaterAPI.cs、User/FavoriteAPI.cs 和 VideoAPI.cs 中的读取接口；其中 App 写入不能直接用于 Web 会话，本次 Web 参数独立实现并以 fixture 验证。补充核对 [Web like/favorite 源码](https://github.com/SmallPeaches/BiliCheater/blob/main/videoapi.py)、[Web coin 调用源码](https://github.com/Dawnnnnnn/bilibili-tools/blob/master/main.py)，没有复制其实现或重试策略。空降字段依据 [BilibiliSponsorBlock API](https://github.com/hanydd/BilibiliSponsorBlock/wiki/API)，无源码复制。

账号头像来自 nav.face，UP头像来自 view.owner.face / 动态作者字段，保留在类型化模型直至 NetworkAvatar；图片加载失败显示姓名首个完整字素。可选头像字段兼容旧安全会话快照。账号识别在页面作用域加入 mid，避免同名账号之间混用状态。

## 本地产物与平台范围

- `flutter build windows --release --no-pub` 成功；便携目录 `artifacts/Bili-Lite-0.1.0-windows-x64` 与对应ZIP已更新并验证ZIP完整性。
- `flutter build apk --debug --target-platform android-arm64 --no-pub` 成功；调试APK已复制到 `artifacts/Bili-Lite-0.1.0-android-arm64-debug.apk`。
- 两个归档的SHA-256已写入 `artifacts/SHA256SUMS.txt`；没有提交源码、发布或签名。
- Windows已做本机播放和界面检查；Android未连接设备，macOS不能在当前Windows主机构建/运行，均未宣称原生验收通过。
