# 方形、竖屏播放器与页面滚动

日期：2026-11-01。本轮按用户范围执行定向组件测试、格式及静态检查；统一测试由用户进行。

## 行为与实现

- 视频和影视页共用 [PlaybackPageLayout](../../lib/shared/ui/playback_page_layout.dart)。宽度小于 1000、信息区展开且未进入听视频时，依据 `PlaybackSnapshot.videoDimensions` 的有效显示尺寸识别竖屏及方形（高大于或等于宽）；该尺寸来自后端，并已处理像素比例及旋转。尺寸尚未就绪时沿用原高度，收到真实尺寸后只更新外层布局，不按标题、封面或分区猜测方向。
- 收起高度沿用各页现有的横屏计算：视频为同宽 16:9，影视另保留可用高度 55% 的上限。展开高度不超过视频自然比例高度、页面可用高度的 65%、可用高度减 240 三者的最小值，且不低于原收起高度。能够加高时，至少为简介／评论保留 240 逻辑像素及页面高度的 35%；高度不足时不额外展开。390×800 页面中的 9:16 视频初始为 520，高度下限为 219.375；480×660 页面初始为 420，下限为 270。
- 嵌套滚动先消耗展开与收起的高度差，再滚动活动信息列表；下滑先将列表滚回顶部，再恢复额外高度。短简介也可完成收起与展开。播放器处于固定的元素位置，列表之外的播放器手势沿用原处理；横向简介／评论分页不参与竖向高度计算。
- 简介控制器和评论原有的 `PagedScrollViewport` 复用 [HeaderScrollController](../../lib/shared/ui/scroll_collapsing_header.dart) 的活动列表协调与桌面滚轮联动。分 P／影视选集的 [ScrollBoundaryHandoff](../../lib/shared/ui/scroll_boundary_handoff.dart) 同时识别嵌套页面和额外头部距离，保留内部列表到页面的边界拖动与惯性衔接。
- 普通横屏、宽屏左右布局、信息区显隐和听视频继续按原规则取高度；视频页在矮窗口中为信息区保留的 480 逻辑像素可滚动空间继续保留。全屏仍由原播放面板处理。布局与信息子页切换沿用同一播放器 State；同视频换 P、同作品换集保留信息状态，新视频／作品重置外层展开距离。
- [PlaybackVideoDimensions](../../lib/shared/ui/playback_layout_builder.dart) 只在显示尺寸改变时重建，不因播放进度更新重建页面，也不主动创建占位页面的播放会话。没有修改播放控制条、媒体引擎、倍速、音频或请求逻辑。

## 定向验证

以下命令通过，126 项组件测试全部通过；日志保存在 `build/portrait-player-targeted-tests.log`。

```powershell
flutter test --no-pub test/shared/ui/playback_page_layout_test.dart test/shared/ui/playback_layout_builder_test.dart test/features/pgc/pgc_screen_test.dart test/features/video/video_screen_test.dart test/shared/ui/scroll_boundary_handoff_test.dart test/shared/ui/scroll_collapsing_header_test.dart --reporter expanded
```

覆盖初始高度、简介留白、实际宽高比与非法／缺失尺寸、拖动中连续高度、收起下限、短列表、反向恢复、桌面滚轮、嵌套分 P 手势、晚到的显示尺寸、横屏／宽屏／听视频／信息显隐、简介／评论切换与播放器 State 保留。尺寸订阅另验证 100 次位置更新不重建，以及卸载后的监听释放。

本任务 11 个 Dart 文件的格式检查及 `flutter analyze --no-pub` 定向分析通过，文档链接与 `git diff --check` 通过。未执行整仓 `check.ps1`、构建、安装、在线账号操作、原生集成或性能测量；Windows／Android／macOS 实机视觉与手感仍待用户验收。DTD 未发现运行中的调试应用，因此没有执行热重载。


## 方形视频补充（2026-11-01）

- 用户提供的 `BV14Mne6tEvr` 公开详情元数据为 1080×1080、旋转 0。此前严格的“高大于宽”条件排除了方形，本次改为“高大于或等于宽”；不扩展到宽大于高的横屏内容。
- 方形复用原有自然比例、页面高度及简介留白限幅，沿用同一套滚动和播放状态保留逻辑。390×800 页面中的 1:1 视频展开高度为 390，上滑连续收至 219.375；480×660 页面展开高度上限为 420，保留 240 高度给信息区。视频／影视共用该修复。
- 修改前先运行 1080×1080 的共享布局与真实视频页回归，两项均在初始高度断言失败（实际 219.375，期望 390），确认测试能复现遗漏。修改后以下六份定向测试全部通过，共 129 项，日志 `build/square-player-targeted-tests.log`：

```powershell
flutter test --no-pub test/shared/ui/playback_page_layout_test.dart test/shared/ui/playback_layout_builder_test.dart test/features/pgc/pgc_screen_test.dart test/features/video/video_screen_test.dart test/shared/ui/scroll_boundary_handoff_test.dart test/shared/ui/scroll_collapsing_header_test.dart --reporter expanded
```

- 新增覆盖方形初始高度、信息留白、连续收起、下限及恢复、晚到的显示尺寸、简介／评论切换与播放器 State 保留、宽屏、空间不足、听视频和隐藏信息区，并确认 1081×1080 仍沿用横屏高度。三份改动 Dart 文件的格式、定向静态分析及差异检查通过，文档相对链接有效。
- 未构建、安装、实播该 BV、执行整仓检查或测量性能；实机视觉和手感仍由用户验收。DTD 未发现运行中的调试应用，未执行热重载。
