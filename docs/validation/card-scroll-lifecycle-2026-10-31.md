# 视频卡片往返滚动：生命周期与测量复用

日期：2026-10-31。工具链：Flutter 3.47.6 / Dart 3.13.5。

## 定位

本轮针对推荐等长视频卡片页面持续下滚、上滚的卡顿，复查当前实现，而非重新实施已完成的列表虚拟化。旧优化与边界见[列表滚动记录](feed-scroll-performance.md)、[保留页面记录](retained-card-pages-2026-10-27.md)和[窄屏切页分析](narrow-video-card-navigation-analysis-2026-10-30.md)。

| 层级 / 组件 | 持有及创建 | 持续滚动、离屏及返回 |
| --- | --- | --- |
| 工作区、保留频道、FeedController | 工作区保留页面身份、频道数据和位置；领域列表可包含数百条摘要 | 隐藏页面停用输入、Ticker、分页和惯性滚动；并非关闭整个页面或清空列表 |
| ScrollHeaderLayout / PagedScrollViewport | 每个列表自己的 HeaderScrollController，只有活动列表接入顶部协调器 | 顶部在绘制层淡出，列表按真实距离滚动；回顶部按钮局部更新，翻页只在接近尾部时请求 |
| FeedVideoGrid / SliverResponsiveCardGrid | 数据变化更新委托；SliverList 按行懒创建视口及 cache extent 附近的卡片 | 仅滚动偏移变化复用行委托；远离缓存区的行被回收，不随已加载数量常驻全部卡片 |
| _FeedVideoCard / VideoCard | 挂载卡片局部订阅反馈；未变内容缓存主体，点击回调读取最新状态 | 卸载取消局部订阅并丢弃 State；滚回重新创建，保留页面不等于保留全部卡片 |
| ScrollAwareHoverRegion / VideoCardCover | 实际指针进入后才监听祖先滚动；只有启用悬停且命中卡片时创建预览 owner | 滚动抑制悬停、取消等待/请求并撤下预览；隐藏和卸载照常释放预览，未扩大原生播放器的存活范围 |
| AppNetworkImage / AppImageCache | 位置级共享监听和帧后可见性批次；按显示宽度选择封面及解码尺寸 | 160px 加载区域、嵌套视口裁剪、离屏取消与帧释放沿用原规则；隐藏保留页仅保留已就绪画面并停用流监听 |
| HighlightedText / 封面计数 | 之前仅在已挂载 State 内缓存溢出布尔值、三种字号的测量宽度 | 卡片回收即丢失这些结果，反复滚回时再次分配 TextPainter 和执行额外排版，是本轮消除的重复工作 |

图片解码缓存仍由 AppImageCache 管理，默认 256 项、64 MiB；它与领域摘要、行缓存、文字测量结果是不同的资源。没有证据支持把当前卡顿归因为所有历史卡片一直活跃，也没有将自然行高替换为固定高度。

Sliver 沿用框架的 AutomaticKeepAlive：InkWell 的焦点/按压高亮或未结束的水波纹可以保留所在行，交互结束再回收。上述组件测试使用普通未聚焦卡片，不把这类交互保留误计为泄漏。卡片的 AnimatedContainer / AnimatedScale 仅在状态过渡时运行，隐藏页由 TickerMode 停用；本轮新增的测量缓存没有 Ticker、Timer 或滚动订阅。

## 改动

- [TextMeasurementCacheScope](../../lib/shared/ui/text_measurement_cache.dart)由每个共享网格持有，分别用 LRU 保存最多 512 个宽度和 512 个溢出标记。只保留布局输入和值，不保留组件、Element、State、TextPainter、图片或播放器；网格销毁释放缓存和字体监听。
- [HighlightedText](../../lib/shared/ui/highlighted_text.dart)继续使用本地缓存避开悬停颜色变化带来的重复工作；卡片重新创建时，可按完整文本/高亮 span、实际样式、可用宽度、行数、缩放、方向、语言和高度行为复用网格结果。
- [VideoCard](../../lib/shared/ui/video_card.dart)继续保留单卡最多 9 项宽度缓存，首次测量优先读取网格结果。新字体通知同时清空网格和单卡缓存；宽度、字体、缩放等输入变化照常重新计算。实际渲染文字仍由 Flutter 正常排版，减少的是原来用于判断溢出/排列的额外测量。
- 普通 Wrap 和 Sliver 两种[共享响应式网格](../../lib/shared/ui/responsive_card_grid.dart)均接入，覆盖推荐、热门、搜索、历史、视频动态、收藏、稍后再看等使用这些组件的列表。其他独立卡片沿用原有局部缓存。
- 共享视频卡封面计数和时长去掉模糊文字阴影，保留既有底部黑色渐变、白字、尺寸和排列。密集行的三组标签无需反复绘制模糊字形；这一项是六列场景中收益更明显的绘制优化。

## 验证与性能边界

[新增组件回归](../../test/shared/ui/card_text_measurement_reuse_test.dart)覆盖窄屏两列和宽屏六列：滚出缓存区的原 Element 全部销毁；回到同一区域时挂载数量恢复，标题溢出及封面宽度额外测量均为 0。测试同时验证真实 RenderParagraph 的溢出结果、字号/窗口变化、字体加载失效、网格销毁后不共享旧缓存，以及 LRU 上限和近期访问保护。

[Windows Profile 探针](../../tool/validation/card_scroll_profile.dart)使用真实 FeedScreen、当前 ScrollHeaderLayout、500 条固定摘要、640×360 内存 PNG、仓库主题和字体；不使用真实账号、网络、磁盘缓存或原生悬停播放。先跳转预热遍历区域的封面，避免只测到快速滚动占位，再反复下滚 12,000px、上滚到 0，每段 4 秒。430px 与 1800px 窗口分别核对卡片横坐标，确认两列与六列；以引擎 FrameTiming 采集 UI/raster。

同进程保留基线 `d0e0f9b` 的页面、网格、卡片及分页视口副本，与优化版共用主题、图片、字体和顶部协调器；每种窗口按原版—优化版—优化版—原版执行，每次挂载预热后测两轮，各有 4 个样本。主机为 Ryzen 7 7700，Windows Impeller / OpenGLES，DPR 1；没有核实本次渲染选择的 GPU。完整数值见[数据](data/card-scroll-profile-2026-10-31.json)。

| 场景（4 个样本的中位数） | 原版 | 测量复用版（仍有阴影） |
| --- | ---: | ---: |
| 两列 UI P95 / P99 | 1.679 / 2.047 ms | 1.597 / 1.919 ms |
| 两列每轮累计 UI | 469.15 ms | 457.19 ms |
| 两列 raster P95 | 3.967 ms | 3.958 ms |
| 六列 UI P95 / P99 | 4.374 / 5.338 ms | 4.240 / 5.071 ms |
| 六列每轮累计 UI | 751.19 ms | 736.65 ms |
| 六列 raster P95 | 11.757 ms | 11.991 ms |
| 六列 UI 或 raster 超过 16.67 ms | 43 / 4154 帧 | 43 / 4109 帧 |

两列 UI P95 约下降 4.9%，六列约下降 3.1%；累计 UI 分别约下降 2.5%、1.9%。收益较小，不能将此表概括为深滚动卡顿已解决。六列 raster P95 没有改善，仍是主要余量不足处；高刷新率与新增行/纹理进入时的绘制工作需要继续关注。两列与六列在各检查点分别挂载 12–16、30–42 张卡片，优化版只多两个非渲染 Element，没有扩大保留卡片范围；解码缓存两版相同，分别为 126 项 / 15.57 MiB 和 256 项 / 56.25 MiB。

### 六列绘制热点：模糊文字阴影

进一步在同一进程比较“测量复用 + 原阴影”和“测量复用 + 无模糊阴影”，其他组件、布局、图片、预热、窗口与滚动距离完全一致。按有阴影—无阴影—无阴影—有阴影顺序，各两个样本；[原始结果](data/card-scroll-shadow-profile-2026-10-31.json)单独保存，不与前一进程的数值拼接成一组整体前后对照。

| 六列，2 个样本 | 有阴影 | 无模糊阴影（最终采用） |
| --- | ---: | ---: |
| raster P95 中位数 | 11.845 ms | 8.869 ms |
| raster P99 中位数 | 16.372 ms | 10.928 ms |
| 每轮累计 raster 中位数 | 6357.15 ms | 5703.42 ms |
| 最大 raster | 30.191 ms | 20.766 ms |
| UI 或 raster 超过 8.33 ms | 380 / 2098 帧 | 176 / 2229 帧 |
| UI 或 raster 超过 16.67 ms | 19 / 2098 帧 | 2 / 2229 帧 |

该受控场景 raster P95 约下降 25.1%，P99 约下降 33.3%，累计 raster 约下降 10.3%。确认模糊标签绘制是六列滚动的一个热点，最终删除这层阴影。没有将阴影移到整张封面或新增离屏层，原有黑色渐变继续提供文字对比度。仍有超过 16.67 ms 的帧，P95 也未完全进入 120Hz 的 8.33 ms 预算；两组小样本不能代替长期真实页面验收。

首轮非交替采样期间有同期 Android 构建和测试，前后负载不同，未用它计算收益。原始诊断入口/日志位于 Git 忽略目录 `artifacts/card-scroll-2026-10-31/` 和 `artifacts/card-scroll-*.log`。

### 自动检查与运行验证

- `tool/check.ps1 -SkipPub` 完整通过：根应用 3761、bili_api 499、bili_player 105、bili_danmaku 145、bili_mux 5，共 4515 项测试通过。根应用 13 项 Windows 符号链接权限相关用例、mux 10 项需要 `BILI_MUX_LIBRARY` 的原生用例跳过，没有计入原生通过。格式、静态分析和打包边界脚本通过，日志 `artifacts/card-scroll-check-final.log`。
- 五份锁文件的 `--enforce-lockfile` 解析、格式和静态分析另在独立验证工作区通过，日志 `artifacts/card-scroll-isolated-preflight.log`；该临时工作区已清理。
- 新增回收/字体/容量回归与既有标题、封面测量、网格绘制、预览取消、图片可见性、深滚动页面保留回归均纳入完整检查。
- Windows Debug 离线页面热重载成功，运行时异常查询为空，记录 `artifacts/card-scroll-runtime.log`；验证进程已退出。
- 验证后 `flutter build windows --profile --no-pub -t lib/main.dart` 与 `--debug` 均通过，已恢复普通入口。产物分别为 `build/windows/x64/runner/Profile/bilisail.exe` 和 `build/windows/x64/runner/Debug/bilisail.exe`，对应日志为 `artifacts/card-scroll-restore-profile.log`、`artifacts/card-scroll-restore-debug.log`。
- 文档 172 个本地链接、两份 JSON 数据和 `git diff --check` 通过。

组件工作次数不能换算为实际帧率收益；本探针也不等同于完整工作区、真实网络或 Android/macOS 实机验收。当前没有连接 Android 设备，本轮未开展 Android/macOS 实机、真实账号长时滚动和原生播放验收。
