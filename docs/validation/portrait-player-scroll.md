# 方形、竖屏播放器与页面滚动

日期：2026-11-01。本轮按用户范围执行定向组件测试、格式及静态检查；统一测试由用户进行。

## 行为与实现

- 视频和影视页共用 [PlaybackPageLayout](../../lib/shared/ui/playback_page_layout.dart)。宽度小于 1000、信息区展开且未进入听视频时，依据 `PlaybackSnapshot.videoDimensions` 的有效显示尺寸识别竖屏及方形（高大于或等于宽）；该尺寸来自后端，并已处理像素比例及旋转。尺寸尚未就绪时沿用原高度，收到真实尺寸后只更新外层布局，不按标题、封面或分区猜测方向。
- 收起高度沿用各页现有的横屏计算：视频为同宽 16:9，影视另保留可用高度 55% 的上限。展开高度不超过视频自然比例高度、页面可用高度的 65%、可用高度减 240 三者的最小值，且不低于原收起高度。能够加高时，至少为简介／评论保留 240 逻辑像素及页面高度的 35%；高度不足时不额外展开。390×800 页面中的 9:16 视频初始为 520，高度下限为 219.375；480×660 页面初始为 420，下限为 270。
- 嵌套滚动先消耗展开与收起的高度差，再滚动活动信息列表；下滑先将列表滚回顶部，再恢复额外高度。短简介也可完成收起与展开。播放器处于固定的元素位置，列表之外的播放器手势沿用原处理；横向简介／评论分页不参与竖向高度计算。
- 简介控制器复用 [HeaderScrollController](../../lib/shared/ui/scroll_collapsing_header.dart) 的活动列表协调与桌面滚轮联动；评论列表在首轮实际仍使用独立控制器，原记录将其误记为 `PagedScrollViewport`，已在下方 2026-11-03 修复。分 P／影视选集的 [ScrollBoundaryHandoff](../../lib/shared/ui/scroll_boundary_handoff.dart) 同时识别嵌套页面和额外头部距离，保留内部列表到页面的边界拖动与惯性衔接。
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

## 评论列表内部滑动修复（2026-11-03）

- 根因：共享 [CommentsPanel](../../lib/shared/ui/comments_panel.dart) 的主评论与楼中楼一直使用独立 `ScrollController`，没有接入播放布局的 `NestedScrollView`。因此从评论内部拖动只会滚动评论，播放器高度不变；从顶部标签等外层区域拖动才会收起。此前测试从简介收起后才切换评论，没有验证展开播放器时直接拖动真实评论列表。
- 主评论与楼中楼改用 `HeaderScrollController`，只将当前可见、活动的列表接入同一协调器。上滑先连续收起播放器的额外高度，再滚动列表；即使评论已有非零偏移，也可直接收起。下滑先返回评论顶部，再展开播放器。视频和影视页共用修复，竖屏、方形及其他高大于宽的尺寸沿用原高度规则。
- `HeaderScrollController` 允许无持久偏移的临时列表显式接入头部协调，默认行为仍保持。楼中楼继续每次从顶部打开，使用仅限本次详情访问的 `PageStorageBucket`，避免框架创建的嵌套位置在页面存储中积累每条根评论的偏移。位置已经正确时不重复跳转，以免打开详情意外改变播放器高度；返回恢复主评论位置。简介／评论切换、隐藏页面隔离、唯一播放器及宽屏布局继续沿用既有机制。
- 新增 [真实播放页与评论滚动回归](../../test/shared/ui/playback_comments_scroll_test.dart) 10 项，覆盖视频／影视、9:16／1:1／1000:1100、拖动中的连续高度、收起下限、非零评论偏移、反向恢复、隐藏简介与评论的独立偏移、播放器元素保留、楼中楼访问重置及桌面滚轮。修复前 10 项均失败，修复后全部通过；包含既有播放页、评论、返回导航及嵌套滚动的九份定向测试共 195 项通过，日志为 `build/playback-comments-baseline.log`、`build/playback-comments-fixed.log` 和 `build/playback-comments-targeted.log`。
- 已运行 `tool/check.ps1 -SkipPub`：根应用与四包格式、全仓静态分析及打包边界检查通过；根测试 4,003 项通过，13 项符号链接用例因本机权限跳过，63 项设置／数据库用例因 `build/native_assets/windows/sqlite3.dll` 缺失失败。随后从当前 sqlite3 hook 的成功输出恢复生成副本并核对 SHA-256，补跑全部六份受影响测试，共 122 项通过，没有修改设置或数据库源码；不将首轮脚本记为一次完整通过。另运行 `tool/check.ps1 -SkipPub -Stage PackageTests`，四包分别通过 544／142／153／5 项，mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/playback-comments-check.log`、`build/playback-comments-sqlite-retry.log` 和 `build/playback-comments-package-check.log`。文档相对链接及本次差异检查通过。
- 未构建、安装、执行账号写操作、原生播放回归或性能测量；Windows／Android／macOS 实机视觉与手感尚未验收。DTD 未发现运行中的调试应用，热重载调用因无可连接应用未执行成功。
