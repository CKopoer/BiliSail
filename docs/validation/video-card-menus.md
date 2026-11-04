# 视频卡标题菜单

日期：2026-10-06。沿用现有依赖，未修改相邻参考仓库。

## 范围与交互

共享 `VideoCard` 菜单默认关闭；推荐页、稍后再看两个子标签及观看历史接入标题右侧竖三点。推荐提供“不感兴趣”和“稍后再看”，稍后再看提供“删除”，观看历史提供“删除记录”（2026-10-26 新增，协议与验证见[云端观看历史](cloud-watch-history.md)）。其他视频页面保持原卡片；自建/订阅收藏夹已有自己的菜单，不属于本入口。

Windows/macOS 任意窗口宽度均在整卡悬停、键盘聚焦或菜单打开时显示按钮；Android/iOS 提供常显触摸入口。菜单打开后指针移出卡片不会销毁按钮；三点、菜单项和作者点击均不打开视频。封面悬停视频预览继续保留。2026-10-07 起，稍后再看两个子标签隐藏封面右上角添加入口，其他页面保留；列表播放行为见 [稍后再看队列播放](watch-later-queue.md)。菜单添加与封面添加共用 `VideoCardController` 的单飞、成功状态和不明结果保护。

2026-10-11 标题右侧“更多”按钮沿用封面统计文字的整卡宽度三档分界：小于 180 逻辑像素时按钮为 20、图标为 14；180 至小于 240 时为 24／17；240 及以上为 28／20。操作中的进度图标同步缩放，按钮占位保持不变。使用 `shrinkWrap` 点击区域和标准视觉密度，避免 Material 默认 48 逻辑像素点击边距继续挤占标题宽度；标题继续使用原有两行与溢出提示规则。

不感兴趣和删除只由用户选择触发。推荐反馈确认成功后保留当前卡片的位置、尺寸和相邻视频，在封面位置显示模糊暗色背景、表情、“内容不感兴趣 / 将减少此类内容推荐”和撤销按钮；隐藏该卡的普通操作与悬停预览。点击撤销仅提交一次取消反馈，确认成功后恢复原卡片；提交期间显示“撤销中”并禁用按钮。反馈状态在当前账号生命周期保留，切换频道或迟到分页不会取消遮罩；刷新仍以新列表为准，若再次返回同一视频则继续显示遮罩。撤销携带原成功反馈的上下文，不使用刷新后的新 track_id，也不会把已不在列表中的视频强行插回。

稍后再看删除确认成功后才移除卡片，全部/未看完共用删除状态，刷新或迟到分页不得重新添加；确认再次添加成功才解除删除标识，之后刷新可重新显示。删除和添加不能同时提交同一视频；成功删除清除封面的已添加状态，不明删除清除旧的确定成功标识并保留不明保护。缺 BVID 的失效视频若有合法 aid 仍能删除。

写入失败保留卡片，撤销失败保留反馈遮罩，明确失败允许用户再次点击。网络、超时、HTTP 或无法解析的回复按结果不明处理，当前生命周期阻止再次提交，不自动重放；撤销不明时禁用按钮并提示核对。取消和账号变化不弹通用失败。写入、读取使用独立取消信号及会话 epoch，关闭应用或切换账号取消请求。每类同时最多 8 次写，保留的成功/不明标识有 500 项预算；不以淘汰不明标识来恢复提交，达到反馈标识上限仍允许撤销已有成功反馈。旧频道的 pending 状态在恢复缓存时按当前实际写任务重算，失败不会让菜单永久禁用。错误提示仅在仍活动的页面显示，反馈及撤销成功通过卡片变化确认。

## 2026-11-03 触控长按与自适应展示

共享 `VideoCard` 的封面、标题和作者区域支持触控长按打开操作菜单；标题右侧三点与长按调用同一个展示入口。窗口宽度小于 600 逻辑像素时显示带拖动柄的底部抽屉，600 及以上沿用三点按钮下方的锚点菜单，不按卡宽或操作系统选择样式。桌面三点仍在悬停、聚焦或菜单打开时显示，移动平台常显，原按钮三档尺寸保留。

两种展示都消费页面已有的 `VideoCardMenu.actions`、`busy` 和回调。推荐仍只有“不感兴趣／稍后再看”，稍后再看仍为“删除”，历史仍为“删除记录”；搜索、收藏及其他未配置菜单的视频卡不会因此增加收藏、反馈等能力。打开或取消菜单不执行账户写操作，选择稍后再看继续经过既有共享操作端口。

抽屉沿用当前 Material 主题和文字缩放，使用 16px 顶部圆角、10px 行圆角和 12px 内容留白，底部保留系统安全区；内容可滚动以适应较短窗口和大字号。宽屏保留原菜单的颜色、边框、圆角、图标、宽度与阴影。标题全文提示继续支持鼠标悬停；有菜单的卡片将标题触控长按交给卡片，未配置菜单的标题保留原长按全文提示。

长按、拖动取消和忙碌按钮不会误触视频导航；已有作者点击、键盘导航、悬停预览和反馈撤销保持。菜单打开后若账号操作端口、视频身份、页面可见性或可用动作改变，迟到选择不再执行。反馈遮罩、忙碌状态与空动作集不打开菜单，抽屉选择防止快速重复点击影响后面的页面。

`test/shared/ui/video_card_menu_test.dart` 新增 13 项行为回归，与卡片样式、状态复用和悬停预览合计 53 项定向测试通过，覆盖 390／599／600／1000 宽度的长按和三点、锚点位置、抽屉安全区／深色主题／两倍字号、封面／长标题／作者命中、取消与拖动、不同动作集、单次回调、忙碌禁用和旧选择隔离。使用离线 fake 操作，不提交真实账号写入。

主工作区首轮 `tool/check.ps1 -SkipPub` 在格式阶段停止，涉及本任务最后一处测试格式及同期 macOS 测试文件；本任务文件随后完成格式化。为避开同期改动及共享 build，使用基线 `2697097` 加本任务四个文件建立隔离副本，复用本机已解析的相同依赖与 hook 缓存，再运行同一根脚本。格式、静态分析、打包边界及离线测试全部通过：根应用 4079、`bili_api` 544、`bili_player` 142、`bili_danmaku` 153、`bili_mux` 5，共 4923 项。根应用 13 项 Windows 符号链接测试和未配置 `BILI_MUX_LIBRARY` 的 10 项 mux 原生测试跳过，不计作原生通过。日志位于忽略目录 `build/validation/video-card-long-press/check.log`，未改依赖或锁文件。

已加载应用字体和图标，离线渲染并检查 390／1000 宽度的明暗主题菜单，抽屉、锚点位置和安全区未见溢出，四项预览捕获通过；图片位于 `build/validation/video-card-long-press/preview-*.png`，使用手写样本与空封面，不是设备截图。DTD 发现后连接返回拒绝，再次发现没有运行中的调试应用，热重载未能执行。本轮未修改原生播放，未构建安装包或进行 Android／iOS／Windows／macOS 实机触控、鼠标和视觉验收；widget 回归不代替原生设备验收。

## 2026-11-05 添加与取消稍后再看（#68）

桌面共用封面右上角在已添加时显示勾选和“取消稍后再看”，再次点击显式删除，成功后恢复添加按钮。推荐、搜索、收藏、历史等共享视频卡按同一状态提供“稍后再看／取消稍后再看”；稍后再看列表原有“删除”菜单统一改称“取消稍后再看”，仍兼容只有 aid 的失效视频。窄屏长按沿用小于 600 逻辑像素的底部抽屉，UP 主投稿及播放页横向相关推荐也复用该抽屉；宽屏共享网格沿用锚点菜单。

账号稍后再看成员在首次悬停／打开菜单时从现有完整列表接口读取，单飞并在内存保留 30 秒，成员预算 1000 项。读取失败不当成空列表，菜单提示重试；无需逐卡查询。显式添加仍直接使用 BVID，取消优先使用列表原始 aid，缺失时才读取详情获取 aid，保持字符串精度。读取与操作按账号取消信号隔离，读取期间发生写操作时丢弃旧快照；删除标识沿用原列表控制器，成功取消同步过滤全部／未看完列表及已有播放队列，重新添加成功才能解除删除标识。低频变化只通知对应视频卡与封面，不通过整页状态逐帧更新。

添加、取消及列表删除共用同一视频的互斥保护；操作中禁用重复入口。确认失败保留原状态并允许重试，结果不明清除旧确定状态并阻止当前账号生命周期内自动或重复提交。菜单选择期间切换账号、视频身份或隐藏页面时不执行旧选择。未新增协议、依赖或数据库迁移。

本次 93 项定向回归通过，覆盖已有成员、30 秒缓存／单飞、长 aid、取消后重加、重复提交、明确失败／不明结果、旧快照和账号取消、全部／未看完列表同步，以及窄屏共用菜单、横向投稿卡和桌面勾选按钮。日志为 `build/issue-68-final-targeted.log`。四个包通过 `tool/check.ps1 -SkipPub -Stage PackageTests`：API 586、播放器 148、弹幕 161、mux 5，共 900 项；未配置 `BILI_MUX_LIBRARY` 的 10 项原生测试跳过，日志为 `build/issue-68-packages.log`。

根脚本 `tool/check.ps1 -SkipPub` 的格式、静态分析和打包边界检查通过；根应用全量首轮为 4175 通过、13 跳过、2 失败。其中网格测试误将自定义通用“删除”菜单也按视频卡新文案匹配，现已按网格种类区分，修正后包含在上述 93 项通过记录内。另一项 `font_selection_test.dart` 的 `appearance saves bundled and installed fonts independently`（125 行，期望 `HarmonyOS Sans`、实际 null）在独立复核中仍失败，未修改该测试及其字体实现；全量检查仍受该项阻塞。全量和字体复核日志分别为 `build/issue-68-check.log`、`build/issue-68-font-recheck.log`；最终静态分析再次通过，日志为 `build/issue-68-final-analyze.log`。

均使用 fake repository、手写长 ID 和离线 widget，未使用真实账号执行添加／删除。本机未发现运行中的 Dart/Flutter 调试应用，热重载尝试未能执行；未构建安装包或进行 Android／iOS／Windows／macOS 实机鼠标、触控及账号写入验收。

## 协议与来源

四个端点均使用 Web profile、HTTPS POST、`application/x-www-form-urlencoded`、JSON 响应，当前 host/path 有效的 Cookie 与 `bili_jct`；共享提交管线附加 CSRF，保留系统 TLS。无 WBI/App 签名、无分页，单次显式提交，不重试；继承总 deadline 25 秒与单次最多 12 秒预算的较小值。

| 操作 | host / path | 字段 |
| --- | --- | --- |
| 添加稍后再看（既有） | api.bilibili.com `/x/v2/history/toview/add` | `bvid`、`csrf` |
| 删除稍后再看 | api.bilibili.com `/x/v2/history/toview/del` | 列表原始 `aid`、`csrf`；不把列表的 BVID 主键当 aid |
| 不感兴趣 | api.bilibili.com `/x/web-interface/feedback/dislike` | `app_id=100`、`platform=5`、`from_spmid=`、`spmid=333.1007.0.0`、`goto=av`、推荐原始 `id`/作者 `mid`/`track_id`、`feedback_page=1`、`reason_id=1`、`csrf` |
| 撤销不感兴趣 | api.bilibili.com `/x/web-interface/feedback/dislike/cancel` | 与原成功反馈一致的字段和当前会话 `csrf`；原 `id`/`goto`/作者 `mid`/`track_id`/`reason_id` 不变 |

只读核对官方首页 [index-12fc55c2.js](https://s1.hdslb.com/bfs/static/shanks/laputa-home/assets/index-12fc55c2.js)：Web 反馈函数 `xv` 的 POST 路径，视频映射 `Ww` 的 `id→aid`、`owner.mid`、`track_id`，以及 `内容不感兴趣` 对应 `reason:1`。官网将缺失 track_id 默认成空字符串；本轮游客使用当前推荐参数只读读取到 20 条视频，track_id 为空，因此按原样或官网空默认透传，不捏造跟踪值、不禁止所有游客样本。删除函数 `YK` 使用 `aid`。

同日撤销改动再次只读核对上述官方脚本：`Pv` 以 POST 发送 `/feedback/dislike/cancel`，反馈调用点 `V` 在反馈与撤销时共用同一字段对象，仅按动作选择 `xv` 或 `Pv`。仅据此确认协议结构，没有使用真实账号提交反馈或撤销。视觉参考本次用户截图；表情用 Flutter Canvas 独立绘制，未复制官方图标或新增依赖。

另核对本地 UWP [WatchLaterAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/User/WatchLaterAPI.cs) 的删除 aid 职责，kernel `BiliApis.cs` 的路径；UWP [RecommendAPI.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Requests/Api/Home/RecommendAPI.cs) 使用 App access_key 接口，不能直接沿用到当前 Web 会话。许可限制沿用 [参考文档](../references.md)。只参考协议/交互，独立编写 Dart/Flutter；未复制源码、schema、图片或图标。

## 验证与限制

2026-10-11 三档菜单尺寸：现有共享卡片、菜单和网格定向 25 项测试通过，覆盖标题省略/完整标题提示、文字缩放、明暗主题及鼠标/键盘/触摸操作。`tool/check.ps1 -SkipPub` 通过根应用及四个包的格式、静态分析和测试：根应用 1908、API 426、播放器 51、弹幕 86、合并包 2，共 2473 项；合并包 7 项原生测试因未设置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/video-card-menu-tiers-tests.log` 和 `build/video-card-menu-tiers-check.log`。本轮未进行 Windows／Android／macOS 实机界面验收，没有修改原生播放。

新增 API fake transport 测试覆盖长 ID、原样 track、空默认、Cookie/CSRF 作用域、单次写、取消/deadline/会话 epoch 和推荐元数据解析。仓储测试覆盖 aid 删除、不明结果及账号取消；应用测试覆盖单飞、成功移除、失败保留、旧分页/刷新、两个稍后再看子标签、确认重新添加、账号变化、隐藏推荐缓存失败恢复；卡片测试覆盖标题位置、窄桌面隐藏、悬停后菜单存活、键盘、触摸、卡/作者点击隔离、共享添加及菜单页面范围。

上述为最初菜单接入的测试范围；撤销改动将推荐成功移除回归替换为保留位置/遮罩，并新增撤销单飞、成功恢复、明确失败重试、不明结果保护、刷新后沿用原上下文、隐藏频道和账号 epoch 隔离。Widget 回归覆盖相邻卡片位置、普通卡片点击隔离、键盘撤销、预览取消，以及 324/140 宽度和两倍字体。离线预览输出至 `build/recommendation-feedback-preview/`，不能代替真实账号写入或设备交互验收。

定向验证均使用手写无隐私 fixture，不使用真实账号执行任何添加、删除或反馈。官网脚本和游客公开读取只确认接口结构，不能代替登录后真实写入验收。菜单截图由主代理离线渲染检查，Windows 构建/全量检查结果由主代理统一记录；Android/macOS 实机与真实账号写行为仍未验证。

### 最终集成检查（2026-10-06）

- 当前共享工作区 `tool/check.ps1 -SkipPub` 通过：根应用 843、API 包 266、播放器包 16、弹幕包 32，共 1157 项；根应用与三个包格式检查、静态分析均通过。日志为 `build/search-card-menus-check.log`。
- `flutter build windows --release --no-pub` 成功，产物为 `build/windows/x64/runner/Release/bilisail.exe`；既有 WebView 插件 CMake 开发警告不阻断构建。日志为 `build/search-card-menus-windows-build.log`。
- 完整运行目录打包为 `artifacts/bilisail-search-card-menus-windows-x64.zip`，已核对应用、Flutter DLL 和 assets 都在包内；SHA-256 为 `bc97e3ba2b58ab35aef51338c9636676c0dbb311ecb6755acaf35d90bacca447`。
- 已检查真实 shell/router 的 1440、1000、360 宽度和 320 宽度／两倍字体的搜索布局，以及两种菜单的离线渲染预览。预览在 `build/search-preview/` 与 `build/video-card-menus-preview/`；它们不是安装后实机或账号写入证据。本轮没有启动新构建、没有关闭用户运行中的旧程序，真实账号写操作和 Android/macOS 实机仍待验收。

### 原位反馈与撤销检查（2026-10-06）

- `tool/check.ps1 -SkipPub` 通过：根应用 864、API 包 269、播放器包 17、弹幕包 32，共 1182 项；格式检查和静态分析均通过。日志为 `build/recommendation-feedback-check.log`。
- `flutter build windows --release --no-pub` 成功，产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `build/recommendation-feedback-windows-build.log`。既有 WebView 插件 CMake 开发警告不阻断构建；没有启动或替换用户运行中的程序。
- 已检查 `build/recommendation-feedback-preview/` 的常规封面、140 宽窄卡片和两倍字体离线渲染，撤销按钮可点击且没有布局溢出。该预览使用本地手写样本，不代表真实账号推荐或反馈/撤销接口实测；Android/macOS 实机仍未验证。
