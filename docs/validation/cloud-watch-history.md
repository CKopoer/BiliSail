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

## 删除与清空（2026-10-26）

观看历史卡片沿用共享 `VideoCard` 的标题右侧三点菜单，提供“删除记录”。桌面悬停、键盘聚焦或菜单打开时显示，移动端常显；菜单点击不打开视频。历史项增加可空的 `deletionKey`，只由服务端根字段 `kid` 与 `history.business` 组成，不把 BVID、cid、episode ID 或详情 aid 当作删除标识。缺失或非法 kid 不影响读取，但删除时提示刷新；长十进制 ID 保留原字符串。

顶部工具行右侧增加低强调的红色“清空历史”按钮，按工具行可用宽度和实际 14px 字体缩放决定是否显示文字，极窄窗口或大字体时使用带 tooltip/语义标签的图标，触控区域至少 48×48 逻辑像素。独立历史页和“我的”内嵌历史均有入口。同日根据 402px 窄屏截图修正对齐：说明与按钮垂直居中，窄屏说明缩短为“云端观看记录”，普通窄屏仍显示“清空历史”文字；嵌入页顶部留白缩至 8、工具行与首张卡片间距为 8 逻辑像素。确认框可滚动，明确说明清空当前账号所有设备的全部云端历史，包括本页过滤掉的直播、专栏等记录，不可撤销。空的视频列表仍保留清空入口，因为账号可能存在其他类型历史。

| 操作 | Host / method / path | Profile / 鉴权 / 签名 / 格式 | 字段与重试 |
| --- | --- | --- | --- |
| 删除历史 | `api.bilibili.com` POST `/x/v2/history/delete` | Web Cookie + 当前作用域 `bili_jct`/CSRF，form-urlencoded，JSON，无 WBI | `kid={history.business}_{根 kid}`、`jsonp=jsonp`、`csrf`；单次显式提交，无分页，不自动重试 |
| 清空历史 | `api.bilibili.com` POST `/x/v2/history/clear` | 同上 | `jsonp=jsonp`、`csrf`；确认后单次提交，无分页，不自动重试 |

只读重新核对[官网历史页](https://www.bilibili.com/account/history) 当前引用的[官方脚本 app_d0026f29.js](https://s1.hdslb.com/bfs/static/history-record/app_d0026f29.js)：`deleteHistory` 取 `item.history.business` 与根 `item.kid` 拼接，`cleanHistory` 发送清空表单，均携带 Cookie/CSRF。只参考协议与操作语义，Dart/Flutter 和脱敏 fixture 独立实现，未复制官网代码或资源，未增加依赖。

控制器串行提交写操作，提交前取消在途分页并更新代次，写入期间阻止刷新/分页与重复写。只有确认成功才移除对应历史键的全部可见卡片或清空列表；删除后保留原分页游标，清空后重置分页。明确失败保留列表并允许用户重试；网络、超时、HTTP 或响应结构错误按结果不明处理，保留列表并提示手动刷新核对，刷新成功前禁用写操作与自动分页，不自动重放。关闭页面、账号 scope 或 session epoch 变化取消或丢弃旧写结果；确认框等待期间切账号也不能提交到新账号。提示仅在仍活动的页面显示。本地 SQLite 续播、数据库 schema 和历史上报均不变。

新增/扩展离线测试覆盖官网删除键、PGC/长 ID/缺失 kid、Cookie/CSRF、单次提交、失败/取消/deadline/账号隔离，控制器成功/失败/不明结果、迟到分页、共享历史键、单飞和游标续接，以及各平台菜单、320–1280 宽度、两倍字体、嵌入页入口、清空确认/取消、失败提示和写入中禁用。预览位于 `build/validation/history-actions/`，使用纯假仓储；不代表真实账号写入或移动设备验收。

本轮 `tool/check.ps1 -SkipPub` 全量通过：根应用 2945、API 478、播放器 83、弹幕 93、mux 5，共 3604 项；格式、静态分析和打包边界脚本通过。根应用 13 项符号链接测试因 Windows 权限不足跳过，mux 10 项原生测试因未设置 `BILI_MUX_LIBRARY` 跳过，不作为原生集成覆盖。日志为 `build/history-actions-check.log`。另用假仓储渲染并检查 360/1280 浅色与 800/320 深色页面及确认框（320 为两倍字体），Windows Debug 预览构建、启动、热重载成功，未检出运行时错误。首次调试构建与全量测试并行时遇到原生资产占用，结束测试后重试成功。关闭预览后，`flutter build windows --debug --no-pub` 普通 `lib/main.dart` 入口构建成功，恢复常规 Debug 产物；日志为 `build/validation/history-actions/windows-debug-build.log`。未读取或删除真实账号历史，未做 Windows Release、Android/iOS/macOS/Linux 设备构建或实机验收；预览入口仅位于忽略的 build 目录，不进入正式产品。

窄屏样式修正复验（同日）：新增 320/402/600/960 宽度与两倍字体的内嵌工具栏几何回归，确认说明与操作垂直居中、首排卡片间距为 8px、普通窄屏保留按钮文字；页面及虚拟化定向 21 项通过。重新渲染并检查 402px 内嵌页、360px 独立页和 320px 两倍字体预览。当前工作区重新执行 tool/check.ps1 -SkipPub 通过，根应用 2951、四包 478/83/93/5，共 3610 项；仍因符号链接权限和 BILI_MUX_LIBRARY 缺失跳过 13+10 项。日志为 build/history-toolbar-check.log。本次没有运行中的调试连接，未完成热重载或设备实测；未重新构建平台产物。

## 关键词搜索（2026-10-31）

独立历史页与“我的”内嵌历史共用搜索入口。输入后按回车、移动键盘搜索键或搜索按钮提交；不在每次输入时发请求。清除按钮恢复全部云端历史；空白关键词按未搜索处理。搜索请求由服务端执行，不受当前页面已经加载的记录范围限制；每次查询仍最多保留 500 条结果，连续三页没有新增视频时暂停自动扫描。刷新和错误重试保留已提交关键词，换词重新从第一页加载、取消旧请求并重置列表位置，迟到的旧查询/分页响应不能覆盖新查询。

| 用途 | Host / method / path | Profile / 鉴权 / 签名 / 格式 | 参数、分页与重试 |
| --- | --- | --- | --- |
| 搜索云端历史 | `api.bilibili.com` GET `/x/web-interface/history/search` | Web Cookie，JSON，无 WBI/CSRF | `keyword` 去首尾空白、仅编码一次，`pn` 从 1 递增，`business=all`；按原始 `list` 空数组/显式 null 终止，不能因过滤掉直播/专栏而提前结束。单页最多接收 100 条；沿用最多额外两次网络/5xx 重试及总 deadline |

普通列表继续使用三字段游标，搜索列表使用独立的页码游标。两条路径复用历史条目解析、视频统计补齐、账号 scope/session epoch 和取消检查，不请求 App token。结果卡片保留观看日期、进度、分 P/剧集跳转和删除菜单；搜索状态下的“清空历史”仍清空当前账号全部云端历史，确认文案明确此范围，不能解释成只清除搜索结果。写入过程中禁用搜索，成功删除/清空后保留关键词。

桌面足够宽时，320px 搜索框与说明、清空操作共用一行；窄屏和大字体下搜索框独占下一行，使用项目既有浅色/深色面板填充、12px 圆角和主题文字样式，搜索与清除图标触控区域至少 48×48。输入框自带透明 Material 容器，支持独立路由和嵌入页；文本控制器随组件销毁释放，输入不触发整个列表逐字重建。

协议只读参考相邻 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441` 的 [UserHttp.searchHistory](../../../PiliPlus/lib/http/user.dart)、[端点常量](../../../PiliPlus/lib/http/api.dart)、[历史搜索控制器](../../../PiliPlus/lib/pages/history_search/controller.dart)、[通用分页](../../../PiliPlus/lib/pages/common/common_list_controller.dart) 和 [历史响应模型](../../../PiliPlus/lib/models_new/history/data.dart)。仅借鉴端点、参数、字段与空页终止规则，Dart/Flutter 代码及脱敏样本独立编写；未复制 GPLv3 应用源码或资源，未新增依赖，未修改参考仓库。

离线回归覆盖中文/特殊字符单次编码、页码与空页、混合业务过滤、PGC/分 P/长 ID、非法响应、快速换词与旧分页、搜索失败及重试、写入互斥和关键词保留，以及移动/桌面提交、清除、空结果和清空确认。定向应用测试 87 项、API 历史协议测试 44 项通过；另外渲染并检查 320/360/402/800/1280px、浅深主题和两倍字体的假仓储预览，文件位于 `build/validation/history-search/`。这些预览不使用真实账号或读取凭据，不代表移动设备或在线接口验收。

最终执行 `tool/check.ps1 -SkipPub` 全量通过：根应用 3818、API 525、播放器 105、弹幕 145、mux 5，共 4598 项；格式、静态分析和打包边界脚本通过。根应用 13 项符号链接测试因 Windows 权限不足跳过，mux 10 项原生测试因未设置 `BILI_MUX_LIBRARY` 跳过，不作为原生集成覆盖；日志为 `build/history-search-check.log`。新增页面销毁前的初始化取消用例在控制器单独 25 项及最终全量中通过。前一轮全量曾出现不涉及本次修改的播放恢复时序断言失败，该项单独复验和最终全量均通过，未修改播放会话实现。

Windows Debug 假仓储预览构建、启动和热重载成功，未检出运行时错误；预览入口只放在忽略的 `build/validation/history-search/main.dart`，不进入产品。结束后关闭预览，并通过 `flutter build windows --debug --no-pub` 恢复普通 `lib/main.dart` 入口的 Debug 产物，构建日志为 `build/validation/history-search/windows-debug-build.log`。未使用真实账号验证搜索响应，未执行历史写入、Release 构建或 Android/iOS/macOS/Linux 设备验收。
