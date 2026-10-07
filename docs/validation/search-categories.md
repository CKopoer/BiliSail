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

## 横向交互与 UP 主预览弹幕数修正（2026-10-07）

顶部“综合、视频”等分类、排序方式及展开的时长／用户类型筛选均允许鼠标按住拖动；桌面普通纵向滚轮在这些横向栏内映射为左右滚动。分类栏原有横向滚轮支持，但默认滚动行为未接受鼠标拖动；排序／筛选原有横向滚动容器同时缺少这两项桌面配置。现在三处局部复用 `SmoothScrollBehavior(horizontalMouseWheel: true)`，在原有拖动设备集合中加入鼠标，保留触摸／触控板和共享滚轮算法。

综合搜索附带的 UP 主稿件使用 `bili_user.data[].res[].dm` 表示弹幕数，普通视频搜索使用 `video_review`。旧解析只读取 `video_review`／`danmaku`，导致预览稿件的已有弹幕数丢失，经 Repository 传到共用 `VideoCard` 后显示缺失标记。现在补充 `dm` 字段映射，已有字段优先，合法的 `0` 保留，缺字段继续表示未知；页面不额外请求视频详情或虚构统计。

本次游客只读观测搜索“我是”，返回“我是郭杰瑞”（UID `176037767`）的三条预览：`BV1sS4y1t7ce`、`BV1yZ4y1a7Ck`、`BV1PY4y137at`，`dm` 分别为 `14010`、`11387`、`13506`，响应未提供 `video_review`／`danmaku`。修复后的 `packages/bili_api/tool/search_smoke.dart 我是 all` 确认三条均解析出这些弹幕数；数值和搜索排名仅对应当次观测。回归 fixture 保留真实字段形状并替换无关文本／图片。

- 75 项定向测试通过：根应用 64 项、搜索 API 11 项。日志 `artifacts/search-scroll-targeted.log`。
- 420px／普通字体和 320px／双倍字体下，验证三处横向栏的普通滚轮、鼠标拖动、滚到末尾并点击最后选项、反向回到开头，及横向栏之间／结果列表的滚动隔离。响应 → API 模型 → Repository → UP 主预览视频卡的整条链路覆盖弹幕 `14010`、`0`、缺字段；API 另外验证数字文本和原有字段优先级。
- `tool/check.ps1 -SkipPub` 通过：根应用 989、`bili_api` 283、`bili_player` 22、`bili_danmaku` 32，共 1326 项测试，四处格式与静态分析通过；日志 `artifacts/search-scroll-check.log`。本文本地链接及 `git diff --check` 通过。
- 本轮未验证实体鼠标／触控板操作手感、Android/macOS 实机交互，也未执行平台构建。

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

## 搜索专属顶部分类（2026-10-06）

搜索页现将综合、视频、番剧、影视、直播、专栏、用户放在工作区原首页频道栏的位置，不再显示推荐、热门等首页入口，结果区域只保留关键词说明、排序及筛选。分类沿用顶部导航的选中下划线和界面字体；计数继续使用当前关键词的服务端值，未知不显示，超过 99 显示 `99+`。宽度至少 760 时分类和搜索工具同排，较窄时分行；分类可横向拖动，并支持桌面普通鼠标滚轮。

shell 通过 `WorkspacePageHeader` 提供顶部布局，router 在搜索标签已有的 `ProviderScope` 内构建该布局；顶部分类与结果页读取同一 `searchControllerProvider`，没有额外搜索控制器或进程级状态。分类只更新当前标签的控制器，保留关键词、同关键词计数，取消旧请求并按既有规则重置排序／筛选和结果滚动位置；展开筛选随分类变化收起。切换搜索标签或单标签返回保留当前分类，关闭标签或账号变化沿用既有作用域销毁和取消逻辑。

- `flutter test test/features/search test/app/workspace_shell_test.dart test/app/workspace_router_test.dart --dart-define=SEARCH_PREVIEW=true`：72 项通过。新增真实 `createBiliRouter` 回归覆盖两种导航模式、顶部分类与结果作用域一致、关键词／计数／分类保留、旧请求取消、筛选重置与重复分类条消除。
- 布局回归覆盖 1440×900、1000×800、360×640、320×568／2 倍字体；验证宽屏同排、窄屏分行，以及 Windows 模拟鼠标滚轮访问末尾用户分类。预览位于 `build/search-preview/workspace-1440-1.png`、`workspace-1000-1.png`、`workspace-360-1.png`、`workspace-320-2.png`，均为脱敏 fixture，包含真实 shell 和 router。
- `flutter analyze lib/app/shell.dart lib/app/router.dart lib/features/search test/features/search test/app/workspace_shell_test.dart test/app/workspace_router_test.dart`：无问题；修改文件格式检查通过。

本项未修改搜索协议或原生播放；定向阶段没有执行在线搜索、新的原生构建或 Windows 物理滚轮及 Android/macOS 实机验收。后续当前共享工作区完整工程检查共 1157 项通过，Windows Release 构建成功，打包及验证边界见 [视频卡菜单最终集成检查](video-card-menus.md#最终集成检查2026-10-06)。上述 72 项仅为搜索专项定向检查。
