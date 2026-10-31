# 长列表回到顶部：沿途行布局复用

日期：2026-10-31。工具链：Flutter 3.47.6 / Dart 3.13.5。

## 原因与范围

共享 [PagedScrollViewport](../../lib/shared/ui/paged_scroll_viewport.dart) 的回顶按钮使用 250ms、`Curves.easeOutCubic` 的真实滚动动画。页面继续持有已加载的摘要数据；[共享网格](../../lib/shared/ui/responsive_card_grid.dart)按行懒创建，远离视口及缓存区的卡片组件回收，返回时重新创建。回收卡片并不等于删除摘要或重新请求列表 API，封面是否重新下载还取决于图片缓存。

自然高度 `SliverList` 通过相邻行的布局尺寸推算位置，不能直接按固定高度计算索引。长距离向上动画的单帧位置跨度可能超过整个视口，框架会创建、布局一些最终没有进入这一帧绘制范围的中间行。回顶经过的可见内容必须照常构建和绘制，需要减少的是额外的定位工作。[Flutter 官方说明](https://api.flutter.dev/flutter/widgets/SliverList-class.html)解释了这种位置推算和离屏组件生命周期；本地复核入口为固定 SDK 的 `packages/flutter/lib/src/rendering/sliver_list.dart`。

本轮覆盖使用 `SliverResponsiveCardGrid` / `SliverVideoGrid` 的推荐、热门、搜索视频、历史、收藏等卡片列表；没有替换独立的动态、评论或播放侧栏列表。前序常规滚动和卡片生命周期验证见[卡片往返滚动](card-scroll-lifecycle-2026-10-31.md)，顶部协调见[连续滚动](continuous-scroll-headers-2026-10-31.md)。

## 实现与视觉约束

- 私有 `_RenderCardRows` 仍沿用 Flutter `RenderSliverList` 的自然高度布局、绘制、语义和 KeepAlive 管理；只在目标缓存区与当前行完全不重叠的反向滚动中优化起始行定位。
- 回收前按行索引保存最多 512 项实际测量高度，包含原有行间距。只保留整数和像素数值，不保存卡片、Element、State、RenderBox、图片或播放器。
- 从当前首行的真实偏移开始，按连续的已测量行高向前推算；跳过不可见中间行的创建，在相同索引与偏移处交还框架正常布局。缺失的测量不做估算，剩余区间照常逐行定位；数据、布局依赖或字体变化时清掉旧测量。分页更新行委托同样保守清理，刚追加内容后直接回顶的收益取决于随后重新测量的范围，不能将充分预热场景的收益推广到所有回顶。
- 普通相邻滚动保留原有 Element；没有改变缓存范围、自然行高、列数、卡片外观、图片预取与释放规则，按钮及 250ms 动画曲线沿用原实现。不是瞬移、截图过渡或占位替换。

## 自动验证

[组件对照](../../test/shared/ui/sliver_grid_scroll_to_top_test.dart)使用 2000 张不同高度的卡片，430px 两列和 1800px 六列，从 24,000px 点击真实回顶按钮，逐 16ms 检查偏移、可见卡片身份、位置和尺寸，与标准 `SliverList` 的原布局对比。检查卡片创建次数下降、原深处 Element 回收且最大挂载数不增加。

额外比较同条数数据替换、窗口变化、字号变化（包含只有离屏行高度受影响的情况）、子组件高度变化、系统字体通知、超过缓存上限的深滚动，以及 NestedScrollView 中被手势中断的回顶。失效场景按框架原有位置校正规则运行，不用旧高度强行定位。

`tool/check.ps1 -SkipPub` 完整通过：根应用 3,829、bili_api 525、bili_player 105、bili_danmaku 145、bili_mux 5，共 4,609 项通过；根应用 13 项 Windows 符号链接权限相关用例、mux 10 项需要 `BILI_MUX_LIBRARY` 的原生用例跳过，未计入原生通过。日志 `artifacts/scroll-to-top-check.log`。最终回顶、网格生命周期、测量复用 24 项回归通过，改动的源文件、测试和 Profile 入口静态分析无问题。

本机构建固定来源的 Windows mux 组件后，Profile 诊断构建与运行完成。另以 `TOP_SMOKE=true` 启动使用优化网格的 Debug 诊断入口，DTD 热重载成功，运行时异常查询为空，验证进程已正常关闭；该 Debug 结果不计作性能数据。随后 Debug / Profile 均已重新构建普通 `lib/main.dart` 入口，诊断界面未留在这两种构建产物中；日志 `artifacts/scroll-to-top-restore-debug.log`、`artifacts/scroll-to-top-restore-profile.log`。

## Windows Profile 对照

[离线探针](../../tool/validation/scroll_to_top_profile.dart)使用真实 VideoCard、仓库主题和字体、内存 PNG 与图片缓存，不访问真实账号、列表 API、CDN 或磁盘图片缓存，不创建原生悬停播放器。原版使用原有自然高度行、逐卡绘制边界和相同的文字测量缓存；仅回退本次行高复用，避免混入旧绘制优化的收益。

在同一进程分别以 430px 两列和 1800px 六列运行原版—优化版—优化版—原版；预热封面及遍历区域后，从 40,000px 按原 250ms 曲线回顶。每次挂载首轮仅用于预热，保留随后三轮。帧耗时来自引擎 FrameTiming，并按 buildStart 单调时间截取动画区间，排除批量迟到的预热跳转帧；不能用组件测试的创建次数换算实际帧率提升。首轮未过滤采样边界的诊断结果不用于下表。

主机为 Ryzen 7 7700，Windows Impeller / OpenGLESSDF，DPR 1；未确认本次选择的 GPU。430×900 / 1800×900 为窗口外框，实际内容区为 414×861 / 1784×861。两版均使用同一张预热的蓝色封面，分别只有一项解码缓存（129,600 / 230,400 字节），用于隔离卡片创建与布局开销，不代表不同真实封面的网络、解码和纹理上传负载。

每种布局每版 6 个有效样本，[原始数据](data/scroll-to-top-profile-2026-10-31.json)如下取中位数：

| 指标 | 两列原版 | 两列优化版 | 六列原版 | 六列优化版 |
| --- | ---: | ---: | ---: | ---: |
| 回顶创建卡片数 | 382 | 142 | 918 | 216 |
| 每次回顶累计 UI | 226.400 ms | 72.873 ms | 582.513 ms | 120.887 ms |
| 单次回顶最大 UI 帧 | 114.870 ms | 9.848 ms | 417.394 ms | 26.541 ms |
| raster P95 | 3.520 ms | 3.406 ms | 8.286 ms | 8.683 ms |
| 每次动画实际提交帧数 | 5 | 17 | 4 | 9 |

充分预热的这组场景中，卡片创建数约下降 62.8% / 76.5%，累计 UI 工作约下降 67.8% / 79.2%。优化并没有固定或减少动画帧数，原版大量时间花在单帧的中间行定位，优化后在同一条时间曲线上实际提交更多中间画面。

两列 UI 或 raster 超过 16.67ms 的帧为原版 18/29、优化版 0/103；六列为 17/24、28/53。六列优化后提交帧数增加，慢帧绝对数量也增加，raster P95 没有改善，最大 UI 帧中位数仍为 26.541ms；不能据此宣称六列已稳定 60Hz，或用原版少量提交帧的 P95 推导普遍帧率收益。真实卡片进入视口的布局与绘制仍是剩余工作。

运行命令：`flutter run -d windows --profile -t tool/validation/scroll_to_top_profile.dart`。诊断日志和临时输出位于 Git 忽略目录 `artifacts/scroll-to-top*`。

Android/macOS 实机和真实账号长列表手感仍需后续确认；Windows 离线探针不代表这些平台验收。
