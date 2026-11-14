# 视频播放页侧栏重建与生命周期优化

日期：2026-11-14；源码基线 `1c4135f7`。覆盖 UGC 视频页的信息侧栏、简介正文、评论、合集与播放队列，并检查视频／PGC 共用的布局边界。接续[播放页简介侧栏](video-sidebar.md)和[评论区生命周期复查](comments-scroll-lifecycle-2026-11-14.md)。

## 定位与处理

| 路径 | 定位结果 | 处理 |
| --- | --- | --- |
| 整个视频信息区展开／收起 | `_infoVisible` 通过页面 `setState` 更新，每次开关重新创建播放器、简介和菜单配置，即使详情、分 P 与操作回调没有变化 | 使用页面持有的 `ValueNotifier<bool>`，只在 `PlaybackPageLayout` 外监听；复用本次页面构建产生的播放器与信息区 Widget，关闭页面释放 notifier |
| 简介／标签、合集与队列的局部操作 | 仍需要更新页面业务状态，但播放器构建入口也随之被调用；PGC／直播已有播放器内容复用，UGC 没有 | 按详情对象、分 P 对象与注入的 builder 缓存一份播放器内容；改变任一输入时更新，`Builder` 保留自身的 inherited 依赖，主题等变化仍能到达播放器 |
| 共享信息区隐藏 | `Offstage` 保留 State 并停止绘制和命中，但本身不会停用 Ticker，也不表达图片、预览和分页所需的活动状态；原有各子页面的局部处理没有覆盖整个侧栏 | 在共享布局内为整个 `NestedScrollView`／信息区统一组合 `WorkspaceActivity` 和 `TickerMode`，隐藏时两者停用；工作区返回预览仍保持可见但无输入所有权。视频页的队列内简介区域改为在布局边界下读取活动状态，避免覆盖外层隐藏状态 |

实现入口：[视频页](../../lib/features/video/presentation/video_screen.dart)、[共享布局](../../lib/shared/ui/playback_page_layout.dart)。PGC 复用共享隐藏边界；直播使用自己的布局，已有播放器缓存和聊天活动控制，本轮没有改变它的实现。

侧栏依然通过 `Offstage` 保留布局和组件，展开后继续使用原有评论详情、草稿、选中标签及滚动位置。隐藏态的 Provider 数据更新仍可到达订阅组件，本次没有引入全局 Widget 缓存或禁止必要数据更新，也没有增加侧栏开关动画。

## 组件所有权复核

| 组件／资源 | 生命周期与复核结论 |
| --- | --- |
| 主播放器／播放会话 | 开关侧栏只改变尺寸；播放器 State、source 与会话所有权保持。缓存仅含一份展示配置，不创建第二个 engine；选分 P、详情变化及 builder 替换均更新输入，主题变化通过播放器自己的依赖传播 |
| `PlaybackPageLayout` | 持有并释放外层滚动控制器；信息区保留，隐藏时隔离焦点、绘制和活动，整个滚动子树停止 Ticker；内容身份改变沿用原有滚动复位规则 |
| 简介／标签 | 简介动画控制器由对应 State 释放，正文收起结束卸载正文及标签组件；首次请求后的标签由页面订阅保留，避免反复收起取消／重发。换视频或页面卸载后 autoDispose 取消请求 |
| 简介／评论分页容器 | 已访问页按原机制保留，未访问评论仍懒加载；`RetainedTabView` 隐藏时中断未完成的标签运动，离开后不提交旧滑动选择；TabController、分页进度 notifier 和监听均有释放路径 |
| 主评论／楼中楼 | 共用现有 controller、两组滚动控制器和草稿；活动状态控制分页、链接请求与滚动协调，行内图片沿用共享图片组件的可见性释放；本次没有改变账号代次、写操作或数据容量 |
| 相关推荐／UP 信息 | 推荐读取与详情并行，数据监听不重建主播放器；推荐行仍按视口懒创建，图片需求及悬停预览随隐藏停止。UP 与推荐沿用各自 Provider 的读取和取消边界，侧栏开关不卸载它们或主动取消重发；Provider 释放时取消在途读取 |
| 合集／播放队列 | 有界列表及滚动控制器沿用原所有权和释放；共享隐藏边界现在也覆盖队列封面、加载指示与展开动画。队列 registry 的 retain／release 仍归视频页持有，不因隐藏释放连续播放数据 |

## 可复现证据与验证

新增测试先在优化前运行，两个目标回归均失败：侧栏仍为活动状态；三次完整收起／展开使播放器、操作区和菜单构建计数均从初始 1 增至 7。优化后相同场景三个计数均保持 1，主播放器只创建一次，最终页面卸载时只释放一次。

组件回归另外覆盖：简介／标签开关不重建播放器；缓存接收主题、分 P 和 builder 更新；隐藏后活动与可见性均为 false、动画计数不再增长；重新展开保留 State 并恢复 Ticker；返回预览可见但不活跃；工作区完全隐藏后停用，最终卸载释放资源。既有滚动／评论、宽窄布局、队列、预览取消及全屏命令回归继续执行。

- 定向回归：`flutter test --no-pub test/features/video/video_screen_test.dart test/shared/ui/playback_page_layout_test.dart test/shared/ui/playback_info_tabs_test.dart test/shared/ui/playback_comments_scroll_test.dart test/features/pgc/pgc_screen_test.dart`，144 项通过。日志：`build/playback-sidebar-targeted.log`；优化前日志：`build/playback-sidebar-baseline.log`。
- `tool/check.ps1 -SkipPub` 完整通过，退出码 0：五处格式、静态分析与构建／打包边界检查通过；根应用 5,332、`bili_api` 920、`bili_player` 238、`bili_danmaku` 161、`bili_mux` 5，共 6,656 项测试通过。日志：`build/playback-sidebar-check.log`。
- 根应用 13 项符号链接测试受 Windows 权限限制跳过；播放器 3 项原生 EDL／倍速测试未配置 `BILI_TEST_NATIVE_MPV`／`BILI_TEST_MEDIA_DIR`，mux 10 项原生测试未配置 `BILI_MUX_LIBRARY`，均跳过，不计作原生通过。
- 本文与文档索引共 274 个本地链接、源码路径及 `git diff --check` 检查通过。
- 已主动发现 DTD 并尝试热重载；本轮没有运行中的调试进程或 DTD，工具无法执行热重载。

本轮没有修改原生播放器、协议、设置或依赖，没有进行平台构建、实际视频设备验收或 Profile／Release 帧耗时采样。上述计数只证明减少了重复构建并停用隐藏工作，不能据此推导 FPS、内存、CPU／GPU 或功耗的具体收益。`Offstage` 仍允许布局；真实场景若仍有切换卡顿，应在实际播放的 Profile／Release 构建中区分视频尺寸变化、侧栏布局及 raster 成本后继续定位。
