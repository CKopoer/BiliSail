# 搜索分类与排序

日期：2026-10-05。增量修改用户已有工程，工具链为 Flutter 3.47.6 / Dart 3.13.5。视觉参考用户提供的官方 B 站搜索截图；相邻两仓库只用于端点、字段和职责参考，未复制新代码、schema 或资源，未修改相邻仓库。

## 页面与状态

- 七类为综合、视频、番剧、影视、直播、专栏、用户。计数只使用服务端返回值，未知不显示为 0，超过 99 显示 `99+`。
- 综合页显示匹配 UP 主的头像、等级、粉丝/投稿数、简介及响应附带的最多六条投稿预览。视频采用 16:9 封面、播放/弹幕数、时长、作者、日期及标题关键词高亮。
- 后续与推荐、视频动态统一共享视频卡片，扩大卡宽并取消结果区域固定宽度上限，当前布局及验证见 [共享视频卡片](shared-video-cards.md)。
- 综合/视频：综合排序、最多点击、最新发布、最多弹幕、最多收藏；时长为全部、10 分钟以下、10–30、30–60、60 分钟以上。
- 专栏：综合排序、最多阅读、最新发布、最多喜欢、最多评论。用户：综合排序、粉丝升降序、等级升降序；全部/UP 主/普通用户筛选。番剧、影视、直播只提供已确认的默认排序。
- 视频、PGC、直播、用户进入已有内置路由。专栏标记“在浏览器阅读”，仅由点击打开公开链接，不携带账号凭据，不新增账户写操作。
- 关键词/分类/排序/筛选变化取消旧请求，回到第 1 页和顶部；分类切换重置不适用的排序及筛选，刷新保留参数。工作区状态各自保留，账号变化沿用 app 的销毁/重载。
- 共用 `PagedScrollViewport` 首屏补页、接近底部加载和悬浮刷新/回顶部；隐藏标签不自动补页，失败只显式重试，稳定 ID 去重，重复/空页停止请求。
- 分类、排序和展开筛选可横向滚动，“更多筛选”常驻右侧，窄窗口及字体放大仍能操作。

## 协议登记

全部为 `api.bilibili.com`、GET、Web、Cookie 可选、WBI、JSON，只读请求，无 CSRF、App/TV token 或 gRPC。沿用传输层最多两次额外网络/超时/指定 5xx 重试，风控不重试；每次 Repository 操作共享账号 epoch、取消信号及 25 秒总 deadline。

| 能力 | 路径 | 参数/分页 |
| --- | --- | --- |
| 综合模块/计数 | `/x/web-interface/wbi/search/all/v2` | `keyword`、`page=1`、`page_size=20`、`highlight=1`；`result[].result_type/data`、`pageinfo` |
| 视频及综合页视频 | `/x/web-interface/wbi/search/type` | `search_type=video`，`order=totalrank/click/pubdate/dm/stow`，`duration=0..4`；`numResults/numPages` |
| 番剧/影视 | 同一分类路径 | `search_type=media_bangumi/media_ft`；使用 `season_id` 打开影视页，不能误用 `media_id` |
| 直播 | 同一分类路径 | `search_type=live`、`cover_type=user_cover`；`result.live_room`、`pageinfo.live_room` 独立计数/分页 |
| 专栏 | 同一分类路径 | `search_type=article`，`order=totalrank/click/pubdate/attention/scores` |
| 用户 | 同一分类路径 | `search_type=bili_user`；`order` 默认空/`fans`/`level`，`order_sort=0/1`，`user_type=0..2` |

实测综合接口接受 `order` 却未返回对应的视频顺序。综合首屏用一次综合请求读取模块/总数，加一次视频分类请求读取真正的排序/筛选结果；后续只分页视频，确保每页同一来源，不重复追加首屏用户等模块。共用 WBI 单飞、账号与 deadline，不以失败触发 App 降级或返回空成功。

协议模型不依赖 Flutter；ID 保留十进制文本，缺关键 ID/标题或异常结构形成协议失败。无 bvid 的已标识直播广告不混入视频，未知新增模块可忽略。图片 URL 校验 HTTP(S) 并转为 HTTPS；标题去标记后解码常见及数字 HTML 实体，不执行远端 HTML。

## 本轮验证

- 游客少量只读 `packages/bili_api/tool/search_smoke.dart`：七类均成功。“名侦探柯南”番剧返回 8 条，影视/直播/专栏/用户返回非空分类结果，空番剧结果正常结束。
- 按用户要求搜索 **“小约翰”**：综合和用户搜索第一位均为 **小约翰可汗，UID `23947287`**；综合响应附带 3 条投稿预览。此结论仅对应本次游客观测，服务端排名可能变化。
- 综合“最多点击”修正后，首三条视频播放数为 `76420235、47691183、47017131`，确认降序；专栏 `scores`、用户 `fans` 请求成功。其余参数映射由离线测试验证，不将请求成功等同于全部排序在线验收。
- 新增 10 项 API 测试覆盖六种结果、综合拼装、排序/筛选/WBI 编码、大 ID、HTML/URL、直播分页、空页、协议失败和取消。7 项控制器测试覆盖关键词/分类/排序/分页竞态、重复页、重试、计数和取消。
- 6 项 Widget 测试覆盖七类、排序/筛选、各类路由和专栏链接、排序后重置滚动位置，及 1440×900、360×640、320×568/2 倍字体。搜索列表在参数变化后不读取上一次的 PageStorage 偏移，同标签普通切换仍保留当前 ScrollController。运行 `flutter test test/features/search/search_screen_test.dart --dart-define=SEARCH_PREVIEW=true` 可生成 `build/search-preview/` 脱敏 fixture 布局图；已检查宽窄渲染预览。
- 最终 `tool/check.ps1 -SkipPub` 通过：根应用 461、`bili_api` 140、`bili_player` 16、`bili_danmaku` 10 项测试，共 627 项；格式与静态分析无问题。
- 最终 `flutter build windows --release --no-pub` 通过，产物为 `build/windows/x64/runner/Release/bili_lite.exe`。本轮没有原生播放器变更，没有将 fixture 布局图当作已安装客户端实机验收。

未验真实账号搜索、Android/macOS 实机、所有关键词/排序/会员/地区条件及真实系统浏览器启动；内置入口由 fake 路由/浏览器端口验证，不推导为三端 M0 完成。
