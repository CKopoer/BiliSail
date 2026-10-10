# 影视页面性能分析与选集滚动衔接

日期：2026-10-11。性能部分只分析和采样，本轮实现改动只修复影视选集、普通视频分 P／合集与外层简介之间的滚动衔接。

## 性能热点与优先级

1. **系列作品列表全量构建，优先处理。** [PgcScreen](../../lib/features/pgc/presentation/pgc_screen.dart) 的简介使用 `SingleChildScrollView → Column`，系列条目通过 `for` 一次创建，数量最多 100。可见性加载能限制图片下载，却不能省掉所有卡片的构建、布局、图片状态与滚动检查。建议让简介与系列共用 `CustomScrollView`，系列使用懒创建的 Sliver 委托；保留选集的固定高度、懒加载和独立位置，不将数千集全部挂载。
2. **简介的局部操作引发整页重建。** 展开简介使用页面 `setState`，重新调用播放器 builder、选集 build 和所有系列卡片 builder。100 个系列条目的探针中，展开一次触发 100 次图片可见性检查；播放器 builder 多调用一次。它是 UI 子树重建，并不表示 native engine 重新创建。建议把简介展开状态下沉到局部组件，稳定系列列表委托和播放器子树。
3. **长季数据重复整理，次级热点。** [PgcEpisodePanel](../../lib/features/pgc/presentation/pgc_episode_panel.dart) 每次 build 都重建分组、拷贝当前组、按需倒序，并线性查找当前集；分组标签悬停、切换列表／网格和父级更新也会进入该路径。建议按不可变 episodes 列表缓存分组和 ID 索引，在资料更新时失效。本轮 5000 集排序操作的 UI P95 约 1.46–2.19 ms，未单独证明这段遍历造成卡顿，优先级低于系列全量构建。

[PGC 协议解析](../../packages/bili_api/lib/src/clients/pgc_client.dart)和[领域映射](../../lib/features/pgc/data/api_pgc_repository.dart)也在调用 isolate 同步处理最多 5000 集；真实详情响应的 JSON 解码、映射、网络等待及原生播放器／弹幕准备未包含在本次 UI 探针中，不能据此认定或排除这些路径。

## 当前页面结构证据

受控组件探针使用实际 `PgcScreen`、模拟 repository、注入的本地 PNG 图片加载器和空播放器。视口为 1200×800 和 390×800、DPR 1，无真实账号或网络请求。

| 集数／系列数 | 已挂载选集条目 | 已挂载系列封面 | 外层滚动时图片检查 | 展开简介时图片检查 |
| --- | ---: | ---: | ---: | ---: |
| 12／0，宽屏 | 6 | 0 | 0 | 0 |
| 1275／20，宽屏 | 6 | 20 | 20 | 20 |
| 5000／100，宽屏 | 6 | 100 | 100 | 100 |
| 5000／100，窄屏 | 6 | 100 | 101 | 100 |

条目数量取决于视口和缓存区，6 不是固定容量。外层滚动没有调用播放器 builder；展开简介调用一次。窄屏额外一次图片检查属于可见图片加载后续帧。

## Windows Profile 证据

使用生产 Flutter binding 和实际页面，模拟 repository 与 PNG 图片加载器，不创建 native player、不加载弹幕，不读取账号或图片磁盘缓存。分别请求 1200×840 和 390×840 窗口，每组独立创建页面三次；第三次打开后滚动往返，并切换排序六次。打开阶段只有 3–4 个样本帧，因此以下用每次打开的最慢 UI 帧，避免将少量帧的 P95 当作稳健统计。

下表来自将自动测试与 Profile 分开运行后的复采。初次混合负载采样曾出现约 25–30 ms 尖峰，不能作为页面独立运行的稳定性能结论。

| 请求窗口宽度 | 集数／系列数 | 三次打开最慢 UI 帧（ms） | 稳定滚动 UI／Raster P95（ms） |
| --- | --- | --- | --- |
| 1200 | 12／0 | 6.44、2.02、3.90 | 内容无滚动范围，未采样 |
| 1200 | 5000／0 | 2.12、2.02、2.14 | 内容无滚动范围，未采样 |
| 1200 | 12／100 | 8.55、9.73、5.78 | 0.70／0.92 |
| 1200 | 1275／20 | 3.13、2.83、2.98 | 0.43／1.03 |
| 1200 | 5000／100 | 9.04、11.27、5.75 | 1.08／1.22 |
| 390 | 5000／100 | 10.86、14.43、5.61 | 1.07／1.20 |

复采没有 UI 或 Raster 超过 16.67 ms 的帧。证据说明系列数量增加了打开时的 UI 工作，尚不能解释真实环境的全部卡顿；尤其不能把 Windows 窄窗口视作 Android 真机性能。图片可见性检查也只代表组件遍历，不等于发起了同等数量的 HTTP 请求。

本机探针和脱敏结果保存在忽略目录 `artifacts/pgc-page-investigation/`：`structural_probe_test.dart`、`structural-results.json`、`windows_profile_probe.dart`、`windows-profile-results.json` 和 `profile-final.log`。性能实现保持原样，后续优化应在相同数据、显示环境和负载下做前后配对采样。

## 滚动问题与修复

影视列表／网格、普通视频独立分 P 列表和合集列表均能复现：内层到顶后继续同一次触摸拖动，外层简介的 offset 不变。Flutter 普通嵌套视口各自接收手势，不会自动转交到达边界后的位移，参见 [NestedScrollView 说明](https://api.flutter.dev/flutter/widgets/NestedScrollView-class.html)。本页的选集是简介中的有界卡片，下方还有其他内容，保留当前页面结构与独立控制器。

两类组件共用 [ScrollBoundaryHandoff](../../lib/shared/ui/scroll_boundary_handoff.dart)：只观察自身垂直视口的边界通知，将触摸剩余位移传给最近的外层垂直视口；内层使用 clamping 边界让短列表和 bouncing 平台也能衔接。释放手指时或惯性滑动中途到达边界时，外层继承剩余速度；再次按下停止外层惯性。列表内部正常滚动、选集跳转及原有列表／网格、排序、正片／SP 分组与横向滚轮均保留。

## 验证与边界

- [32 项选集／分 P 回归](../../test/features/playback/episode_scroll_handoff_test.dart)覆盖四种视口的同一次拖动到顶／到底、短列表／长列表释放后的惯性，以及释放后才抵达边界的惯性；分别使用 Android、iOS 滚动物理。
- [两项共享回归](../../test/shared/ui/scroll_boundary_handoff_test.dart)覆盖桌面滚轮边界仲裁、程序跳转保持外层位置、新触摸停止外层惯性和惯性期间销毁。
- [影视页面](../../test/features/pgc/pgc_screen_test.dart)和[视频页面](../../test/features/video/video_screen_test.dart)在 390／1200 宽度验证从选集内部滚到实际简介顶部，原播放器 State 保留；既有选集、分组滚轮、播放状态保留和桌面平滑滚动回归通过。

专项组件测试共 112 项通过，结构探针四项通过。`tool/check.ps1 -SkipPub` 通过：根应用 1698、bili_api 379、bili_player 34、bili_danmaku 84、bili_mux 2，共 2197 项测试；各处格式和静态分析通过。bili_mux 的七项实际原生封装测试因未设置 `BILI_MUX_LIBRARY` 按既有规则跳过，本轮没有该模块改动。文档链接和 `git diff --check` 通过。

`flutter build windows --profile --no-pub -t lib/main.dart` 通过，已将常规 Profile 构建目录恢复为正常应用入口：`build/windows/x64/runner/Profile/bilisail.exe`。构建通过不等于真实播放或人工滚动验收。

本轮未进行真实账号／CDN 播放诊断、Android／macOS 构建或真机触摸验收。框架手势回归不代替实际设备手感，未修改播放协议、原生媒体或弹幕实现，也未提交或发布。
