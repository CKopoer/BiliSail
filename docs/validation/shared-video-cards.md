# 推荐、视频动态与搜索的共享视频卡片

日期：2026-10-05。工具链为 Flutter 3.47.6 / Dart 3.13.5，在用户已有工程上增量修改。

## 页面行为

三处使用 [VideoCard](../../lib/shared/ui/video_card.dart)，统一 16:9 圆角封面、封面底部播放/弹幕图标与时长、两行标题和作者/日期。保留封面失败占位、作者独立跳转、鼠标悬停、键盘激活及历史播放进度。搜索继续高亮关键词和显示 UP 图标；推荐隐藏 UP 图标，可显示浅橙色推荐理由；视频动态隐藏 UP 图标及“投稿视频”标签，不展示推荐理由。

推荐理由从协议模型经过 FeedRepository 传到领域模型，不由页面请求或解析网络数据。只显示接口返回的非空文字，不根据本地账号状态猜测“已关注”，也不合成点赞理由。视频动态保留服务端的缩略计数和发布时间文字，避免将“2万”误当作精确播放数。

[ResponsiveCardGrid](../../lib/shared/ui/responsive_card_grid.dart) 以 300 逻辑像素最小卡宽、20 像素列距自动计算列数并均分可用宽度；大字体提高最小宽度。搜索取消原 1680 像素宽度上限。在 1895 像素测试窗口下，视频区域为五列、每张约 352 像素，填满除两侧 28 像素内边距以外的区域。推荐及视频动态使用同一网格计算；富图文动态仍使用现有居中列表。

## 协议与来源

沿用推荐端点 `/x/web-interface/index/top/feed/rcmd`：`api.bilibili.com`、Web、GET、Cookie 可选、WBI、JSON，无 CSRF。分页与既有取消、账号 epoch、deadline 和有限读重试策略保持一致。新增可选 `rcmd_reason.content` 映射，并兼容纯文本 `rcmd_reason`；空值、空内容及非文本内容均不产生标签。

视觉参考本次用户提供的三张截图；只读查看相邻 kernel 的 [RecommendVideoResponse.cs](../../../bili-kernel/src/Services/Services.Media/Core/Models/RecommendVideoResponse.cs)、[CuratedPlaylistResponse.cs](../../../bili-kernel/src/Services/Services.Media/Core/Models/CuratedPlaylistResponse.cs)、[VideoAdapter.cs](../../../bili-kernel/src/Services/Services.Media/Core/Adapters/VideoAdapter.cs) 及 UWP 的 [RecommendItemModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Recommend/RecommendItemModel.cs)、[RecommendRcmdReasonStyleModel.cs](../../../biliuwp-lite/src/BiliLite.UWP/Models/Common/Recommend/RecommendRcmdReasonStyleModel.cs)，仅参考字段职责。自行编写 Dart/Flutter，不复制新代码、schema、图片或图标，不修改相邻仓库。已有 Bili 图标继续使用已登记资源。

游客只读烟测入口为 [recommendation_smoke.dart](../../packages/bili_api/tool/recommendation_smoke.dart)，不加载真实账号或输出凭据。此次返回 20 条推荐视频，非空推荐理由为 0；登录推荐理由的真实返回尚未验证。协议样本覆盖“已关注”“3万点赞”、嵌套/纯文本、缺失/空白/错误类型。

## 验证

- [共享卡片测试](../../test/shared/ui/video_card_variants_test.dart)：页面显示差异、关键词高亮、16:9、播放进度、220/300/360 像素宽、双倍字体与明暗主题。
- [网格测试](../../test/shared/ui/video_grid_test.dart)：1880 像素区域五列铺满、自动换行、窄窗口、键盘/鼠标反馈及封面失败。
- [首页布局](../../test/features/feed/home_layout_test.dart)、[推荐页面](../../test/features/feed/feed_screen_test.dart)：共享组件、动态移除标签、服务端缩略计数/日期保留、推荐理由仅在推荐频道出现。
- [搜索页面](../../test/features/search/search_screen_test.dart)：1895 像素五列铺满、各内容跳转、窄窗/字体缩放、排序筛选及滚动恢复。

截图使用离线样本并通过 widget 渲染检查。Android/macOS 和登录后的推荐/视频动态尚未实机验证；本次没有修改原生播放。

本次验证快照中，根应用 489、API 包 156、播放器包 16、弹幕包 10 项测试通过，共 671 项。本次修改的 16 个应用/测试文件定向静态分析通过；三个包静态分析通过，播放器/弹幕包格式检查通过。Windows Release 构建成功，产物为 `build/windows/x64/runner/Release/bili_lite.exe`。

已运行 `tool/check.ps1`；工程同时有账户/私信等文件继续修改，全量脚本复查先遇到这些文件的格式问题，随后遇到私信页类型错误，最新一次再次停在其他文件的格式检查。本次卡片文件没有报告问题；未修改或回退这些并行改动，不能将脚本整体记为通过。检查输出保存在 `build/shared-video-cards-check.log`，各项单独验证日志在同目录 `shared-video-cards-*.log`。
