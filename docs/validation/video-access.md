# 充电专属与付费视频

日期：2026-10-10。使用游客公开只读接口和脱敏 fixture；没有购买、充电或其他账号写操作。

## 在线证据

[用户提供的视频](https://www.bilibili.com/video/BV1q6ad6NEVK) 在 `GET https://api.bilibili.com/x/web-interface/view` 返回 `is_upower_exclusive=true`、`is_upower_play=false`、`is_upower_preview=true`，但 `rights.pay/ugc_pay/arc_pay` 全为 0。它属于充电专属，不能仅检查传统付费字段。

现有 WBI `GET /x/player/wbi/playurl` 的主播放（`fnval=4048`）与悬停预览（浏览器 profile，`fnval=2000`）都未取得 DASH 轨道。原实现映射为 `unavailable`，显示“当前内容暂不可用”；修复后返回带 `chargingExclusive` 分类的 `permission`，详情仍可读取。

UP 投稿接口 `GET /x/space/wbi/arc/search` 对同视频返回 `is_charging_arc=true`。游客搜索 `GET /x/web-interface/wbi/search/type` 返回 `badgepay=false`、`is_pay=0`、`is_charge_video=0`，未提供可靠的专属分类。卡片仅显示明确的服务端标记，没有按标题猜测或为缺失标记的搜索结果逐卡请求详情。游客动态接口本次返回 `-352`，不能记为在线通过。

## 实现与协议边界

- `ApiVideoAccess` 与纯 Dart `VideoAccess` 区分内容分类和账号权限；普通／充电专属／付费是内容属性，列表未提供的 `canWatch=null` 不能当成禁止观看。
- 充电专属解析 `is_upower_exclusive`、`is_charging_arc`、归档明确的 `badge.text=充电专属`；付费解析 `rights.pay/ugc_pay/arc_pay`、`is_pay`、`is_chargeable_season`。`rights.elec` 仅表示支持充电，不产生专属标记。
- 已有推荐／热门／排行／相关推荐、搜索、投稿、动态、收藏和稍后再看映射保留这些属性；历史沿用已有详情补读。共享 `VideoCardCover` 左上角显示“充电专属”或“付费视频”，覆盖网格卡、横向投稿卡与相关推荐，并给稍后再看按钮留出空间。
- 详情页保留播放和简介／评论，增加权益说明及“前往哔哩哔哩”按钮。仅用户点击打开公开视频 URL，不附带客户端 Cookie、token 或查询参数。
- 成功返回完整 DASH 时正常播放且不增加请求。缺少轨道或返回权限／不可用业务错误时，额外读取一次详情操作核对权益。普通／明确已授权的视频保留原错误；认证、风控、删除、网络错误不触发此诊断。
- UGC 主播放收到 `is_preview` 不将试看交给完整播放、进度上报、自动队列或下载，提示在官网试看。悬停可消费合法的试看 DASH，保留 `isPreview`；本样例未提供此类 DASH。PGC 与原生播放后端未改动。

端点都是 Web GET / JSON、Cookie 可选；详情无签名，播放／搜索／投稿沿用 WBI、现有分页及有界只读重试。补读与播放共用当前 account/session epoch、取消与 `ApiRequests` 的 25 秒 deadline。没有写操作或无限重试。

仅只读参考 [bili-kernel 视频字段](../../../bili-kernel/src/Services/Services.Media/Core/Models/VideoPageResponse.cs) 与 [UWP 传统权益字段](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Video/Detail/VideoDetailRightsModel.cs)，并以真实 Web 响应核对。独立实现 Dart/Flutter，未复制源码/schema/资源，未修改相邻仓库或新增依赖。

## 验证

- [协议测试](../../packages/bili_api/test/video_access_test.dart)：详情／列表、投稿特殊字段、未知／已授权权限、普通支持充电、缺少轨道、业务错误、完整分轨请求数、试看与取消。
- [应用测试](../../test/features/video/video_access_test.dart)：Repository 错误映射、切换账号抑制旧结果、140 像素卡宽／双倍字体共用角标、明确点击官网入口。
- [视频页测试](../../test/features/video/video_screen_test.dart)：充电视频保留详情和播放器槽并显示权益说明。定向应用／视频页共 27 项通过。
- [在线只读探针](../../packages/bili_api/tool/video_access_smoke.dart)：在 API 包运行 `dart run tool/video_access_smoke.dart BV1q6ad6NEVK --lists`，只输出分类、布尔权限、轨道数量及脱敏错误字段。

`tool/check.ps1 -SkipPub` 已通过根应用与四个包的格式、静态分析及测试：根应用 1625、API 377、播放器 34、弹幕 72、封装包 2，共 2110 项；封装包 7 项既有原生集成测试因未设置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/video-access-check.log`。复核缺少单一轨道的响应后，API 全量 379 项与应用定向 27 项再通过，API 静态分析、相关格式检查通过；日志为 `build/video-access-api-tests.log` 与 `build/video-access-targeted-tests.log`。

最终 Windows Release 构建通过，产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `build/video-access-windows-build.log`。构建保留既有 WebView 插件 CMake CMP0175 开发警告，不影响本轮构建完成。

未验证已付费真实账号、购买后重载、Android/macOS 原生界面与实机播放。
