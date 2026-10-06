# 推荐、视频动态与搜索的共享视频卡片

日期：2026-10-05。工具链为 Flutter 3.47.6 / Dart 3.13.5，在用户已有工程上增量修改。

2026-10-06 已将我的收藏和个人主页收藏夹内的视频接入同一公共卡片，补齐收藏资源统计并共用网格尺寸；最新页面范围及验证见 [收藏子标签与视频卡片](favorites-tabs.md)。下面的“三处”和测试数量保留前序验证快照。

2026-10-06 后续将“稍后再看”的“全部”和“未看完”接入同一 `HomeVideoCard → VideoCard` 与 `ResponsiveCardGrid`，显示封面、播放/弹幕数量、时长、两行标题、作者和发布时间；作者入口继续独立打开用户主页，视频点击沿用现有播放入口，缺少 bvid 的资源保留原有不可播放卡片。沿用已有端点与字段映射，没有新增依赖或修改原生播放。

上述卡片改动时点播仅采纳本地进度；后续已按用户要求接入 [云端进度上报与本地优先续播](cloud-playback-progress.md)。`toview` 的云端 `progress=-1` 仍仅用于“未看完”筛选，云端续播另从当前分 P 的播放器信息读取。

2026-10-06 修正稍后再看播放量映射：此前共用视频映射只读取 `play`，但 `toview` 使用 `stat.view`，使卡片把已有播放量显示为缺失的横杠。现在先读取 `view`，保留收藏资源 `cnt_info.play` 的兼容；真实 0 次与缺失字段仍分别显示 0 和横杠。协议回归覆盖“全部”和“未看完”的正常计数、0 次及缺失字段，并复查既有收藏计数和共用卡片布局测试。本轮使用脱敏 fixture，未读取真实账号稍后再看列表。

本次播放量修复在当前工作区运行 `tool/check.ps1 -SkipPub` 通过：根应用 693、API 包 227、播放器包 16、弹幕包 21 项，共 957 项；根应用与三个包格式检查、静态分析通过。新增两项稍后再看协议回归；日志为 `build/watch-later-count-check.log`。

稍后再看本轮验证：`tool/check.ps1 -SkipPub` 全量通过，根应用 647、API 包 207、播放器包 16、弹幕包 21 项测试通过，共 891 项；根应用与三个包格式检查、静态分析通过。扩展已有首页布局测试，覆盖两个稍后再看子标签在 320/800/1920 像素宽、两倍字体下使用公共卡片并保留统计、时长、作者和日期，定向 17 项通过。检查日志为 `build/watch-later-cards-check.log`。本轮未进行真实账号列表或 Windows/Android/macOS 实机界面验证；云端进度结论来自现有代码核查。

## 页面行为

三处使用 [VideoCard](../../lib/shared/ui/video_card.dart)，统一 16:9 圆角封面、封面底部播放/弹幕图标与时长、两行标题和作者/日期。保留封面失败占位、作者独立跳转、鼠标悬停、键盘激活及历史播放进度。搜索继续高亮关键词和显示 UP 图标；推荐隐藏 UP 图标，可显示浅橙色推荐理由；视频动态隐藏 UP 图标及“投稿视频”标签，不展示推荐理由。

2026-10-06 修正窄卡片元信息布局：原封面信息在可用宽度小于 210、作者信息小于 260 逻辑像素时直接拆行，导致内容明明能放下也出现两行。封面现按当前字体、文字缩放、实际统计/时长文本及图标间距测量，仅在确实不足时将时长移至下一行；统计能完整放下时不再等分宽度而提前省略。作者、推荐理由和日期保持同一行，UP 主名称使用扣除理由、日期及间距后的剩余宽度，最多一行并在放不下时省略；作者入口仍按实际名称宽度响应。标题明确占用卡片可用宽度，保持最多两行、超出显示省略号。

推荐理由从协议模型经过 FeedRepository 传到领域模型，不由页面请求或解析网络数据。只显示接口返回的非空文字，不根据本地账号状态猜测“已关注”，也不合成点赞理由。视频动态保留服务端的缩略计数和发布时间文字，避免将“2万”误当作精确播放数。

[ResponsiveCardGrid](../../lib/shared/ui/responsive_card_grid.dart) 以 300 逻辑像素常规卡宽、20 像素列距自动计算列数并均分可用宽度；大字体提高最小宽度。2026-10-06 调整手机宽度下的两列阈值：扣除页面内边距后的可用宽度达到 300 逻辑像素即可排两列，每张至少 140；不足时保留一列。三列及更宽布局继续按常规卡宽计算，默认三列起点仍为 940；两倍字体时，两列起点提高到 440。普通网格和懒加载网格共用该计算。搜索取消原 1680 像素宽度上限。在 1895 像素测试窗口下，视频区域为五列、每张约 352 像素，填满除两侧 28 像素内边距以外的区域。推荐及视频动态使用同一网格计算；富图文动态仍使用现有居中列表。

## 协议与来源

沿用推荐端点 `/x/web-interface/index/top/feed/rcmd`：`api.bilibili.com`、Web、GET、Cookie 可选、WBI、JSON，无 CSRF。分页与既有取消、账号 epoch、deadline 和有限读重试策略保持一致。新增可选 `rcmd_reason.content` 映射，并兼容纯文本 `rcmd_reason`；空值、空内容及非文本内容均不产生标签。

视觉参考本次用户提供的三张截图；只读查看相邻 kernel 的 [RecommendVideoResponse.cs](../../../bili-kernel/src/Services/Services.Media/Core/Models/RecommendVideoResponse.cs)、[CuratedPlaylistResponse.cs](../../../bili-kernel/src/Services/Services.Media/Core/Models/CuratedPlaylistResponse.cs)、[VideoAdapter.cs](../../../bili-kernel/src/Services/Services.Media/Core/Adapters/VideoAdapter.cs) 及 UWP 的 [RecommendItemModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Recommend/RecommendItemModel.cs)、[RecommendRcmdReasonStyleModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Recommend/RecommendRcmdReasonStyleModel.cs)，仅参考字段职责。自行编写 Dart/Flutter，不复制新代码、schema、图片或图标，不修改相邻仓库。已有 Bili 图标继续使用已登记资源。

游客只读烟测入口为 [recommendation_smoke.dart](../../packages/bili_api/tool/recommendation_smoke.dart)，不加载真实账号或输出凭据。此次返回 20 条推荐视频，非空推荐理由为 0；登录推荐理由的真实返回尚未验证。协议样本覆盖“已关注”“3万点赞”、嵌套/纯文本、缺失/空白/错误类型。

## 验证

2026-10-06 窄卡片元信息修正：共享卡片与网格定向 11 项测试通过。新增回归用实际 HarmonyOS Sans 字体验证 140/183/220 逻辑像素宽时截图样本的统计、时长、作者和日期无需拆行，并覆盖长标题、长作者、搜索高亮、推荐理由、UP 图标及双倍字体下的省略与动态宽度。已检查标准浅色、双倍字体深色的离线渲染预览，文件在 `build/video-card-layout-preview/`。`tool/check.ps1 -SkipPub` 全量通过：根应用 715、API 包 227、播放器包 16、弹幕包 21 项，共 979 项；四处格式检查和静态分析通过。日志为 `build/video-card-layout-check.log`。本轮未进行 Windows/Android/macOS 实机界面验证，没有修改原生播放。

2026-10-06 手机网格阈值调整：相关卡片、首页、搜索及个人主页定向 58 项测试通过，覆盖 360/375/393/412/430 逻辑像素手机宽度扣除留白后的两列、300/940 列数边界及两倍字体。`tool/check.ps1 -SkipPub` 全量通过：根应用 709、API 包 227、播放器包 16、弹幕包 21 项，共 973 项；根应用与三个包格式检查、静态分析通过。日志为 `build/mobile-grid-tests.log` 和 `build/mobile-grid-check.log`。本轮未进行 Android/macOS 实机界面验证。

- [共享卡片测试](../../test/shared/ui/video_card_variants_test.dart)：页面显示差异、关键词高亮、16:9、播放进度、220/300/360 像素宽、双倍字体与明暗主题。
- [网格测试](../../test/shared/ui/video_grid_test.dart)：1880 像素区域五列铺满、自动换行、窄窗口、键盘/鼠标反馈及封面失败。
- [首页布局](../../test/features/feed/home_layout_test.dart)、[推荐页面](../../test/features/feed/feed_screen_test.dart)：共享组件、动态移除标签、服务端缩略计数/日期保留、推荐理由仅在推荐频道出现。
- [搜索页面](../../test/features/search/search_screen_test.dart)：1895 像素五列铺满、各内容跳转、窄窗/字体缩放、排序筛选及滚动恢复。

截图使用离线样本并通过 widget 渲染检查。Android/macOS 和登录后的推荐/视频动态尚未实机验证；本次没有修改原生播放。

本次验证快照中，根应用 489、API 包 156、播放器包 16、弹幕包 10 项测试通过，共 671 项。本次修改的 16 个应用/测试文件定向静态分析通过；三个包静态分析通过，播放器/弹幕包格式检查通过。Windows Release 构建成功，产物为 `build/windows/x64/runner/Release/bili_lite.exe`。

已运行 `tool/check.ps1`；工程同时有账户/私信等文件继续修改，全量脚本复查先遇到这些文件的格式问题，随后遇到私信页类型错误，最新一次再次停在其他文件的格式检查。本次卡片文件没有报告问题；未修改或回退这些并行改动，不能将脚本整体记为通过。检查输出保存在 `build/shared-video-cards-check.log`，各项单独验证日志在同目录 `shared-video-cards-*.log`。
