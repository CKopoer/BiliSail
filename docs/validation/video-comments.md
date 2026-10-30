# 播放页与评论交互

## 组件重建与生命周期（2026-10-30）

共用评论区已复用未变化行、将 busy/loading 更新限制到操作控件，并在关闭／刷新楼中楼时取消读取和释放详情数据。逐组件分析、结构计数前后对照及验证边界见[评论区性能记录](comments-performance-2026-10-30.md)。

## 桌面评论回车换行（2026-10-27）

共用评论输入框收起时使用 `maxLines=1`，未显式设置输入类型和动作，导致首次原生输入连接被配置为单行文本与 `TextInputAction.done`；回车因此可能结束编辑，失焦后评论框随之收起。现在 [CommentsPanel](../../lib/shared/ui/comments_panel.dart) 始终显式使用 `TextInputType.multiline` 和 `TextInputAction.newline`，显示行数仍按焦点展开／收起。视频、影视和动态共用该修复，评论和楼中楼回复均保留换行与焦点；发布继续由按钮显式触发。

[评论回归测试](../../test/features/video/video_comments_controller_test.dart) 新增 Windows／macOS／Linux 平台配置下的主评论和楼中楼回复共 6 项用例，检查首次连接的多行／换行配置、平台换行动作后的焦点和展开状态、不自动发送，以及收起再进入后的配置与草稿保留。修复前 6 项均因首次动作实际为 `done` 而失败，修复后评论定向测试共 40 项通过，日志为 `build/comment-enter-targeted.log`。

`tool/check.ps1 -SkipPub` 通过根应用与四个包的格式、静态分析和打包边界检查，首次启动根测试因其他 `flutter_tester` 进程占用 `build/native_assets/windows/sqlite3.dll` 而中止。保留该进程，待占用解除后分别通过 `-Stage RootTests` 和 `-Stage PackageTests`：根应用 2,998 项、API 478 项、player 83 项、danmaku 93 项、mux 5 项，共 3,657 项测试通过。根应用 13 项符号链接测试因 Windows 权限不足跳过，mux 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/comment-enter-check.log`、`build/comment-enter-root-check.log` 和 `build/comment-enter-package-check.log`；本次文档链接和 `git diff --check` 通过。检查基于包含同期修改的共同工作区。

当前无可连接的 Flutter 调试实例，热重载无法执行；本次未构建或完成 Windows／macOS／Linux 物理键盘及真实输入法验收，平台配置 Widget 测试不等于这些实机验证。

## 评论发送反馈与刷新可见性（2026-10-24）

用户反馈评论发布后本地可见，刷新后消失。经用户授权，使用现有 Release 的系统安全存储会话进行只读核验：在用户指定视频中，新版 `/x/v2/reply/wbi/main` 返回一条当前账号的评论，`state=17`、`invisible=false`；旧 `/x/v2/reply` 的最新列表前五页均未返回该条。游客读取该评论的楼中楼入口返回业务码 `12006`，同一视频正常公开评论的游客对照读取成功。这说明该评论已被服务端接收、当前未向游客公开；不把状态 17 进一步断言为永久删除、封禁或某种确定的审核结论。

此前发送代码丢弃 `reply.state`、`reply.invisible` 和 `success_toast`，把成功响应中的评论直接插入本地并固定提示“已发送”；刷新又使用不能返回上述本人条目的旧列表接口，造成前后表现不一致。本次调整：

- 视频（含使用视频评论身份的影视）主评论改用 Web Cookie 可选、WBI 签名的 GET `api.bilibili.com/x/v2/reply/wbi/main`。参数为 `oid`、`type=1`、`mode=3/2`（最热／最新）、`ps=20`、`plat=1`、`web_location=1315875` 和 `pagination_str={"offset":"…"}`，原样传递服务端 `cursor.pagination_reply.next_offset`，不从页码推算游标。沿用已有 WBI key 单飞、取消、deadline 与 session epoch；排序、刷新和账号变化重置游标。非视频身份和楼中楼保持已有端点。
- 首屏置顶与正文按评论 ID 去重，服务端总数取 `cursor.all_count`；读取不滤掉本人的非零状态评论。在线发现热门分页可以返回相同的 opaque offset 但提供不同条目，因此允许重复游标；若一页未增加任何新评论，则终止后续加载，继续保留 500 条上限。
- 协议模型保留原始状态、不可见标志和提交提示；Repository 映射为普通／受限／未知三种领域状态。非零状态或 `invisible=true` 显示“暂未公开”，发送反馈为“评论／回复已提交，暂未公开，请稍后查看”；普通状态优先显示服务端提交提示，缺少状态和提示时仅说明已提交、需要刷新确认。点赞和替换回复列表保留这些字段。
- 发送仍为单次 POST `/x/v2/reply/add`，正文、root/parent、Cookie/CSRF 和不确定写入保护保持既有规则。已被服务端接收的受限评论清空对应旧草稿，不自动重新发送；输入期间形成的新草稿继续保留。不通过本地持久缓存掩盖服务端后续删除或状态变化。

协议字段参考[评论分页调查](https://github.com/bilibili-plugins/bilibili-api-collect/blob/master/docs/comment/list.md)及本次实际 API 响应，独立实现 Dart 映射，没有复制第三方代码。新生产 API 的登录态只读复验中，最热和最新均返回该本人条目及状态 17，两种排序的第二页各返回 20 条、与首屏没有重复。未新增真实评论、点赞或删除操作，未输出或落盘凭据、账号身份及评论正文。

定向回归 42 项、`bili_api` 完整 434 项通过，覆盖 opaque 游标编码、置顶去重、空页／非法游标、重复游标下的有进展与无进展、刷新／排序重置、受限与未知发送反馈、单次写、草稿保护、刷新后的状态标签以及现有账号与详情导航隔离。其余包检查：`bili_player` 81、`bili_danmaku` 93、`bili_mux` 2 项通过；mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。

首次根检查遇到同期播放器任务未完成的格式／语法修改；本次不修改该任务文件。该任务更新后重新运行 `tool/check.ps1 -SkipPub`：打包边界、根格式与根静态分析通过，根测试 2024 项通过、1 项失败。失败为同期修改的 `test/features/playback/playback_session_test.dart:1255` 中 `pause failure after successful audio decode cannot consume a backup`，预期原生打开一次、实际两次；未为消除此失败改动播放器。四个包另行完成上述格式、分析及测试。日志在本机忽略目录 `artifacts/comment-send-check.log`、`comment-send-analyze.log`、`comment-send-root-tests.log`、`comment-send-final-check.log`，定向与 API 日志为 `comment-send-targeted-tests.log`、`comment-send-api-tests.log`。

未重新构建应用或完成 Windows／Android／macOS 实机发送交互验收；当前没有可连接的 Flutter 调试进程，无法热重载已安装的 Release。只读 API 和离线测试不等于公开发布验收。

后续简介侧栏已调整为 UP 统计与关注、一体合集卡片和常驻推荐；当前布局及本次验证以 [播放页简介侧栏](video-sidebar.md) 为准，下面保留前序记录。

日期：2026-10-05。Windows x64、Flutter 3.47.6 / Dart 3.13.5。工作区尚无初始提交，代码包含既有未提交功能；本轮不修改相邻参考仓库。

## 界面与功能

视觉参考为用户截图和本机已打开的官方“哔哩哔哩”桌面客户端，而非 UWP。实际查看了简介、合集内嵌分 P、评论列表及同侧栏楼中楼详情。仅参考信息层次与交互，自行实现 Flutter 控件，没有复制代码、图标、字体或图片。

- 播放信息区仅有简介／评论两页。桌面固定侧栏，窄屏纵向排列；评论、简介与侧栏收起切换保留同一播放器。
- 简介排列为 UP 头像、标题与统计、图标操作栏、可展开正文、可折叠选集／合集和推荐。单 P 视频省略重复选集，多 P 视频保留独立选集。操作图标保留 tooltip 和无障碍标签。
- 稍后再看、重新加载通过右上角三点菜单操作；错误恢复与全屏错误态也通过菜单恢复。重新加载复用 PlaybackSession.retry，保留确认进度、清晰度、倍速、音量和播放意图。
- 合集来自详情中的 `ugc_season`，按视频 ID 去重；条目分 P 不完整时按需请求该视频详情。选择分 P 携带具体 CID，合集展开状态与分 P 展开状态分别维护。
- 评论显示真实头像、用户名、时间、正文、点赞数和回复按钮，附楼中楼预览；详情显示原评论及分页回复，返回保留主列表位置。输入框显示回复对象，失败保留草稿，成功后更新列表。

## 协议与会话

评论端点及参数见 [API 端点验证](api-endpoints.md)。Web Cookie 和 CSRF 仅由协议包处理；图片加载不携带 Cookie。页面只消费应用控制器与领域模型。

列表与楼中楼有独立取消和代次，账号 scope 与 session epoch 隔离旧结果。同一控制器写入期间防止重复提交；POST 总次数为 1，超时、网络中断或无法解析成功结果时显示结果不确定，不在后台重放。评论列表和回复列表各限制 500 条；协议层限制预览深度、数量与合集大小。

## 评论详情布局与返回（2026-10-11）

视频和影视页打开二级评论后，评论详情占用整个信息区，隐藏简介／评论子标签栏及其右侧菜单，暂停该信息区的横向分页。顶部显示“返回评论”按钮、“评论详情”标题和“关闭评论详情”按钮；两种按钮都只退出二级评论。返回后恢复子标签栏、一级评论滚动位置和输入草稿，沿用原来的播放器与评论面板。宽屏侧栏与移动窄屏共用同一逻辑。

`PageBackScope` 为每个工作区标签持有可释放的页面内返回步骤。顶部工作区返回、移动系统返回，以及当前设置中的“关闭当前标签页”快捷键（包括绑定为此操作的鼠标侧键）优先消费活动评论详情；退出详情后，再次操作沿用单页历史返回或多页关闭标签的既有规则。输入框聚焦时继续遵守现有快捷键规则；普通弹窗阻止底层工作区快捷键，隐藏页面／隐藏信息区不拦截当前页返回。工作区标签本身的关闭图标仍为明确关闭该标签的操作。

关闭详情会取消回复读取并递增回复代次，迟到结果不能重新打开详情。已发起的账号写入仍由评论控制器管理，不因返回而重放。独立评论弹窗中的系统返回也先退出二级评论。

`test/app/comment_detail_navigation_test.dart` 使用真实视频／影视页面、评论控制器和工作区，注入离线仓储及播放器占位。覆盖 Android 390px、Windows 1200px 的两类页面、详情顶端覆盖子标签、禁止横向切页、六类返回入口、编辑焦点和草稿、连续返回、播放器元素保留、弹窗隔离、隐藏标签、读取取消及迟到响应。既有评论测试继续覆盖一级列表滚动恢复、账号代次和不确定写入。

验证结果：`tool/check.ps1 -SkipPub` 完整通过，根应用 1,750 项、`bili_api` 379 项、`bili_player` 35 项、`bili_danmaku` 85 项、`bili_mux` 2 项，共 2,251 项测试通过。`bili_mux` 的 7 项实际原生库测试因未设置 `BILI_MUX_LIBRARY` 跳过；各处格式与静态分析通过，日志为 `build/comment-detail-check.log`。本文本地链接和本次差异检查通过。

本次未执行平台构建、Windows 物理侧键或 Android／macOS 实机验收；Widget 注入事件不等于原生设备输入验证。

## 双标签独立播放窗口返回（2026-10-25）

双标签桌面播放窗口原先将“关闭当前标签页”命令直接交给窗口关闭回调，绕过工作区已有的 `PageBackScope`。因此绑定到该命令的鼠标侧键和 `Ctrl+W` 在评论详情中会直接关闭播放窗口；此前仅在单个视图内验证双／多标签返回的测试没有覆盖独立窗口输入宿主。

[WorkspacePlaybackWindow](../../lib/app/workspace_playback_window.dart) 现在将该命令交给工作区统一返回回调：优先退出当前评论详情，再消费双标签媒体历史，历史为空时关闭播放窗口。标题栏的显式关闭操作仍直接关闭播放窗口。

[评论详情导航回归](../../test/app/comment_detail_navigation_test.dart) 新增使用真实第二 Flutter 视图和独立播放窗口输入宿主的离线场景，覆盖视频／影视评论详情、鼠标侧键和键盘返回、弹窗隔离、草稿与播放器元素保留，以及详情 → 上一媒体 → 关闭窗口的连续返回顺序。

验证：`tool/check.ps1 -SkipPub` 完整检查快照通过，根应用 2,218 项、`bili_api` 446 项、`bili_player` 81 项、`bili_danmaku` 93 项、`bili_mux` 2 项，共 2,840 项测试通过，格式、静态分析和打包边界检查通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。随后同文件的同期侧键窗口交接改动落地后，补跑评论详情、独立窗口、窗口工作区及侧键交接定向回归 18 项和定向静态分析，均通过。日志为 `build/comment-detail-dual-targeted-2026-10-25.log` 和 `build/comment-detail-dual-check-2026-10-25.log`；本文本地链接和 `git diff --check` 通过。

本轮未重新构建或进行 Windows 物理侧键、Android／macOS 实机验收；未发现可连接的 Flutter 调试进程，无法热重载现有 Release。独立视图的 Widget 回归不等于原生窗口输入验证。

## 回复中被 @ 用户的主页入口（2026-10-08）

Web 评论正文中的被 @ 用户由 `content.at_name_to_mid_str`（用户名 → 十进制 UID 字符串）提供；缺少有效条目时依次使用 `at_name_to_mid` 和 `content.members[].uname/mid`。协议模型 `ApiVideoComment.mentionedUsers` 保留十进制文本，Repository 转换为 `CommentEntry.mentionedUsers` 的 `UserId`，单条评论最多保留 100 个引用。缺失、空白用户名、非法 UID、浮点 UID 或错误类型均忽略，不影响评论正文；点赞与更新回复列表保留映射。

共用 `CommentRichContent` 只把服务端映射中完整匹配的 `@用户名` 显示为可点击文字，通过现有 `onOpenUser` 跳转应用内用户主页。主评论、回复预览和完整二级回复共用此行为；点击预览内用户引用不会展开楼中楼。未知用户和无 UID 的历史评论保留普通文字，不按用户名搜索猜测身份；URL 中的 `@` 保持原链接语义，正文、表情、时间点及选择复制继续保留。

2026-10-08 游客只读请求验证：`BV117BkBsEWw`（aid `115790556692803`）的 `/x/v2/reply/reply` 返回 `回复 @沧濂白羽 :…`，对应 `at_name_to_mid_str.沧濂白羽 = "94184612"`，`members` 同时返回相同 `uname/mid`。另一条 `回复 @涂山16 :…` 返回 UID `2629662`。再通过实际 `BiliApiClient` 与共享正文解析器读取该楼中楼，17 条回复中有 6 条携带 UID，成功解析出 6 个用户引用，并确认上述用户名与 UID 匹配。公开视频 aid `170001` 的部分旧回复虽包含 `回复 @用户名`，但 `members` 为空且不含映射，因此该类评论不会产生主页入口。未使用登录凭据，未执行评论、点赞或其他账号写操作。

本轮定向根应用回归 52 项、协议包 `video_extras_test.dart` 18 项通过，覆盖字段优先级、成员回退、非法数据、UID 精度与容量限制、复制保留、用户名完整匹配、URL／表情／时间点共存、实际文字点击、控件复用后 UID／回调变化，以及主评论／预览／完整回复导航。修正 Repository 的 null-aware collection lint 后，`tool/check.ps1 -SkipPub` 完整通过：根应用 1429 项、`bili_api` 336 项、`bili_player` 32 项、`bili_danmaku` 65 项，共 1862 项，根应用与三个包格式／静态分析均通过。本文及来源文档相对链接与本次差异检查通过。三端真实应用点击验收与构建未执行。

## 验证记录

`tool/check.ps1 -SkipPub` 完整通过：根应用 140 项、bili_api 47 项、bili_player 8 项、bili_danmaku 5 项，共 200 项。根应用与三个包的格式、静态分析均通过。

新增回归覆盖排序／分页和去重、请求取消、同账号新 epoch 的旧响应、楼中楼 root/parent、未知写入结果、防重复点击、发送中修改草稿、320px 双倍字号、返回主列表滚动恢复，以及折叠／窗口宽窄变化保留信息面板和播放器。播放错误菜单重新加载验证了保留 12 秒位置和暂停意图。

`tool/test-windows-media.ps1` 通过：实际执行 4 项本地原生验证，包含 DASH 分轨、headers/重定向/Range、seek、倍速、全屏/Esc 单 surface、工作区双视频切换与进度保留，以及隔离安全存储探针。测试输出显示 5 项，其中公网媒体分支未启用，不能计入在线原生烟测。

`flutter build windows --release --no-pub` 成功。已启动发布版，在 1266px 窗口使用应用已有会话只读查看公开视频：新简介／评论侧栏、图标操作、视频画面和真实头像可见；最热及最新均返回非空列表；楼中楼 14 条回复加载成功，点击二级回复按钮可正确选中对象，返回恢复主列表。三点菜单包含稍后再看与重新加载。没有输入或提交评论，没有点击点赞／稍后再看。

独立游客烟测最热返回 3 条（均有头像）、二级列表 18 条；游客最新在另一视频返回服务端空页，不能据此认定视频没有评论。详情本身存在评论时 UI 显示当前会话未返回可展示评论。随后从旧预览版已打开视频取得公开视频 ID，`BV1GLHE6hEFg` 的游客详情成功解析到非空合集，相关推荐 40 条；便携版实际显示该合集并完成收起／展开复核，推荐独立保留。合集内多 P 条目导航仍以 fixture／widget 测试为证据。端点与边界详见 [API 端点验证](api-endpoints.md)。

`flutter build apk --debug --target-platform android-arm64 --no-pub` 成功，仅为构建检查，没有连接 Android 设备实测。Windows 便携目录和 ZIP、Android 调试 APK 已更新至 `artifacts/`，SHA-256 记录于 `artifacts/SHA256SUMS.txt`；便携 EXE 与 Release 构建哈希一致，ZIP 可打开且包含完整入口，更新后的便携版已重新启动。

未执行真实账号点赞、评论或回复发送。Android/macOS 运行、性能和长期播放仍需对应平台实测；公开游客读接口的成功不代表登录写接口已完成在线验收。

## 评论 IP 属地（2026-10-07）

属地取自评论响应的可选 `reply_control.location`，映射为 `ApiVideoComment.ipLocation` 和 `CommentEntry.ipLocation`。沿用服务端显示文本（例如 `IP属地：广东`），去除首尾空白，不重复添加前缀。缺失、空白或类型异常时省略属地，不影响日期、正文和其他评论信息。主评论及完整二级回复通过既有作者头部在日期后显示，复用当前元数据字体/灰色，间距 8px，宽度不足时换行；点赞和更新回复列表保留属地。

只读参考相邻 `biliuwp-lite` 的 `Models/Requests/Api/CommentApi.cs`、`Models/Common/Comment/CommentItem.cs` 和 `CommentReplyControlModel.cs`，借鉴响应字段语义，独立实现 Dart 映射与 Flutter 展示；未复制代码、样式或资源，不扩大许可采用范围。保持现有 `/x/v2/reply` 和 `/x/v2/reply/reply` 页码契约。

定向测试通过 43 项，覆盖主评论/预览/二级响应映射、Repository 转换、点赞/回复复制、属地缺省/异常降级、日期同行样式及 180/320px 双倍字号布局。游客只读样本 `BV1GLHE6hEFg` 的旧接口返回 3 条主评论、7 条预览及 1 条二级回复，均未携带属地；按参考实现签名请求 WBI main 返回 20 条主评论，同样未携带属地。此结果只说明该游客响应未提供字段，不能推断登录后的响应或其他视频行为。非空属地以脱敏 fixture/widget 测试验证，尚未完成真实登录响应及 Windows/Android/macOS 视觉验收。

`tool/check.ps1 -SkipPub` 完整通过：根应用 994 项、`bili_api` 285 项、`bili_player` 22 项、`bili_danmaku` 32 项，共 1333 项；根应用及三个包的格式、静态分析通过。文档相对文件链接和 `git diff --check` 通过。

## 评论日期年份（2026-10-16）

游客只读检查 `BV14P4y1g75A`（aid `894565084`）的 `/x/v2/reply`，主评论及楼中楼预览均返回完整的秒级 Unix 时间戳 `ctime`。例如主评论的 `1653457764` 对应北京时间 `2022-05-25 13:49:24`，年份没有在接口或模型映射中丢失；原显示组件固定输出月、日。

共用 `CommentAuthorHeader` 继续将 `publishedAt` 转为设备本地时间，再与当前本地年份比较：同年显示 `月-日`，非同年显示 `年-月-日`。视频、影视及动态评论的主评论和完整楼中楼回复共用此规则，缺失时间仍不显示日期。评论组件 14 项测试通过，覆盖同年、过去年份、未来年份，以及 UTC 时间转本地后的年初／年末边界。

`tool/check.ps1 -SkipPub` 完整通过：根应用 1940 项、`bili_api` 426 项、`bili_player` 69 项、`bili_danmaku` 90 项、`bili_mux` 2 项，共 2527 项；根应用及四个包的格式和静态分析通过。另有 10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 条件跳过。文档相对链接及 `git diff --check` 通过。未构建或进行三端实机视觉验收。

## 正文实体、链接与进度（2026-10-07）

评论正文通过共享评论模块的纯 Dart `lib/features/comments/domain/comment_text.dart` 分段。展示前仅解码一遍常用 HTML 实体（`amp/lt/gt/quot/apos/nbsp`）和合法 Unicode 十进制／十六进制字符引用，例如 `30tps -&gt; 50tps` 显示为 `30tps -> 50tps`。未知或非法实体保留原文，编码的标签显示为普通文字；原始 `CommentEntry.message`、编辑草稿和发送内容保持原样。视频原路径转为导出入口，定向测试经过该入口验证共享实现。

主评论、楼中楼预览和完整回复共用 `CommentRichContent`：HTTP/HTTPS 链接以及 `分:秒`、`时:分:秒` 均使用主题链接色和鼠标手形，正文继续支持选择复制、行内表情、换行及图片预览。2026-10-11 起，时间分隔符同时支持英文冒号 `:`、中文全角冒号 `：` 及两者混用，例如 `00：09`、`1：02：03`、`1：02:03`；只在计算进度时统一分隔符，展示和复制保留原时间文本。URL 先整体匹配，路径和查询中的 `00:09` 不会生成进度动作；中文标点、句尾标点和不配对的闭括号留在链接外。秒必须为 00–59，三段时间的分钟也必须为 00–59，非法时间不会部分匹配。

2026-10-11 中文冒号增补验证：55 项评论定向回归通过，覆盖两种冒号及混用、中文标签标点、原文保留、非法时间不部分匹配，以及主评论／预览／完整回复的实际文字点击与暂停状态下的 fake 播放器跳转。根应用完整测试 1848 项、API 390 项、player 41 项、danmaku 86 项、mux 2 项通过；mux 另有 7 项条件性原生测试跳过。本次文件及四个包静态分析、根应用及四个包格式检查通过。`tool/check.ps1 -SkipPub` 在全仓静态分析阶段被工作区已有的 `integration_test/windows_ime_shortcuts_test.dart:161` 的 `NativeCallable` 类型错误阻断，未改动该并行任务文件，其余测试单独执行。未构建或进行 Windows／Android／macOS 实机点击验收。

链接由显式点击触发。2026-10-08 起，共用评论入口优先识别 B 站视频：`b23.tv/BV…`、`bilibili.com/video/BV…`、`www.bilibili.com/video/BV…` 和移动版链接直接提取完整 BV 号；对应 AV 形式通过 `/x/web-interface/view?aid=…` 取得 BV 号。随机 b23.tv 短链读取 301/302/303/307/308 的 `Location` 后重复识别，整个解析限时 8 秒、最多 3 次重定向。域名精确匹配，要求 HTTP/HTTPS 默认端口、无 userInfo，并锚定完整视频路径；不会搜索任意网页的路径、查询或片段中的 BV 字符串。这里只定位视频，不解析链接中的分 P 或进度参数。

识别成功由 app 注入的导航动作进入既有 `/video/:bvid` 工作区，共用评论面板因此覆盖主评论、回复预览、完整楼中楼，以及动态/影视使用的评论入口；动态评论弹窗先关闭再导航。短链使用独立无 Cookie/Authorization 传输，关闭自动跳转、不下载 HTML，只请求 b23.tv；离站目标不会由短链解析器继续请求。AV 转 BV 使用既有 API 会话和取消边界。新点击、换评论目标、页面隐藏/销毁、账号切换会取消旧解析或阻止旧结果导航，其他弹窗遮挡期间也不导航。网络解析失败显示重试提示，不自动打开浏览器。

其他链接经 `core/platform/external_links.dart` 的 `webLinkOpenerProvider` 用系统外部应用打开 HTTP/HTTPS 地址（桌面使用默认浏览器），不添加账号凭据；短链成功解析为非视频时也沿用原地址的浏览器打开行为。非 Web scheme、缺失 host、带 userInfo 的地址不能打开；既有官方入口继续使用原 `externalLinkOpenerProvider` 的目标范围。打开失败显示可重试提示。

本轮只读参考 `biliuwp-lite` 的 [MessageCenter.HandelUrl](../../../biliuwp-lite/src/BiliLite.UWP/Services/MessageCenter.cs) 与 [BiliExtensions.GetShortLinkLocation](../../../biliuwp-lite/src/BiliLite.UWP/Extensions/BiliExtensions.cs)，借鉴先还原短链、再识别视频身份的职责；独立编写 Dart，没有复制 C# 或新增资源。在线无凭据 HEAD 验证用户示例 `https://b23.tv/BV117BkBsEWw` 返回 302，目标为 `https://www.bilibili.com/video/BV117BkBsEWw`。

验证：根应用完整测试快照 1377 项通过，之后新增的动态评论弹窗导航及视频评论回归共 36 项通过；三个包格式/分析和测试通过（API 325、player 32、danmaku 65）。本次涉及文件的定向静态分析通过。`tool/check.ps1 -SkipPub` 首轮通过签名/安装包边界和根格式检查，曾被并发任务的 `tool/validation/video_preview_contention_probe.dart:27` 缺少花括号告警阻断；该告警随后消除，最终单独执行 `flutter analyze --no-pub` 全仓通过，测试也已单独执行。首轮脚本及根测试日志为 `artifacts/comment-video-links-check.log`、`artifacts/comment-video-links-root-tests.log`。31 个文档相对链接和 `git diff --check` 通过。未构建，Windows/Android/macOS 实际点击、随机短链在线解析和 AV 在线转换尚未实机验收。

进度点击读取当前标签作用域内的 `PlaybackSession`，核对当前视频身份及已加载媒体后调用既有 `seek`，沿用弹幕重建与进度保存流程，保留播放／暂停意图。超过已知视频时长的时间点限制到视频末尾，播放器未就绪或视频身份不匹配时提示用户。点击回复预览中的链接／进度不会触发外层楼中楼展开。

定向测试 42 项通过，覆盖用户提供的箭头／URL／三个时间点、单次实体解码与非法字符、URL 查询／标点、时间合法性、表情保留、实际文字点击、相同链接样式、180px 双倍字号、控件复用时回调更新、主评论／预览／完整回复路由、暂停意图、播放会话复用和打开失败提示。检查使用 fake 播放器及链接打开端口，没有提交真实账号写操作；真实评论、默认浏览器打开和原生播放跳转的 Windows/Android/macOS 实机验收尚未完成。

Windows `flutter build windows --debug --no-pub` 构建成功。检查过程中共享评论模块迁移已保留本次解析、链接和 seek 交互；`CommentsPanel` 的 Provider getter 使用显式类型，避免评论排序枚举的扩展成员经动态调用导致列表构建失败，迁移后上述 42 项回归再次通过。

本轮检查快照中，根应用完整测试 1035 项、`bili_api` 291 项、`bili_player` 22 项、`bili_danmaku` 32 项分别通过。根应用和协议包格式复核通过，三个包静态分析通过。`tool/check.ps1 -SkipPub` 已运行，但工作区持续有并行动态功能及其测试改动：最后一次执行停在新建 `test/features/dynamic/interactive_dynamic_post_card_test.dart` 的未使用 import 和 if 大括号 lint，完整脚本尚未整体通过。该新增动态测试不属于上面的 1035 项根测试快照；保留并行改动，未将早期检查结果当作当前完整工作区验收。本文相对链接、源码路径和本次改动的 `git diff --check` 通过。
