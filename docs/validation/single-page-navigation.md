# 单标签导航与顶部滚动

日期：2026-10-06。工具链：Flutter 3.47.6 / Dart 3.13.5。

## 行为

设置 → 外观 → 页面导航模式仅提供“单标签页、多标签页”。Windows 和 macOS 默认多标签页，Android 默认单标签页；用户手动选择优先，保存后跨启动保留。平台决定默认模式，调整窗口宽度或横竖屏不会改变模式。两种模式共用现有页面身份、ProviderScope 与 PageStorage，切换模式或调整窗口宽度不会重新挂载搜索、首页或播放页面。

- 顶部工作区横条按平台显示：Android/iOS 不显示标题横条、标签横条或返回／首页图标，也不保留对应高度；此规则适用于单／多标签两种导航模式。Windows/macOS 保留横条，单标签页显示返回、当前标题及首页入口，多标签页显示标签栏。窗口缩放不改变此规则，移动端使用系统返回，不增加浮动导航按钮。
- 单标签页新打开的页面进入访问历史，桌面返回按钮、系统返回和既有关闭标签快捷键（默认 Ctrl+W）逐页回退；没有历史时交还系统返回处理。Ctrl+T 与 Ctrl+Tab 在单页模式中不创建或切换隐藏标签。
- 多标签页继续支持新建、选择、循环、关闭标签；新增返回按钮与系统返回按访问顺序切回先前页面，保留标签。
- 频道、设置分类、分 P、选集等带当前 tab ID 的同页更新保留页面身份，不新增返回记录；深链打开的首个内容页可返回固定首页。弹窗打开时系统返回先关闭弹窗。
- 单页出栈释放已经不在更早历史中的非首页页面，取消该页请求、订阅并清理播放 owner。首页和仍可返回的页面保留已加载内容、滚动位置、输入草稿和播放状态。普通页面遮挡的播放行为沿用既有工作区规则；关闭／出栈当前播放页停止该 owner，只有一个 native engine 和一个可见 VideoSurface。
- 缓存最多 16 个页面，返回历史最多 64 次访问。单页模式在缓存满时释放最早创建的非首页、非当前页面并删除对应历史，继续新导航；多标签继续提示手动关闭。历史和页面缓存仅在本次运行中保存。

首页顶部频道、下一级子标签、设置分类及工作区标签都使用现有 [SmoothScrollBehavior](../../lib/shared/ui/smooth_scroll_behavior.dart) 的 `horizontalMouseWheel` 选项。桌面普通纵向滚轮在横向 delta 为 0 时映射为左右滚动，横向输入、Shift 轴切换、减少动画、边界仲裁和触摸拖动沿用共享实现。内容不足一屏时不会凭空滚动；溢出时可滚到末尾并点击最后一个子标签。没有新增依赖或修改滚轮过渡算法。

## 实现与持久化

2026-10-07 首页内容区增加触摸左右切换：向左进入顶部顺序中的下一个频道，向右返回前一个频道，覆盖推荐、热门、动态及其余首页频道，首尾不循环。后续按反馈改用 Flutter 原生 `TabBarView`：拖动时当前页和相邻页随手指一起移动，松手后按原生分页物理吸附，短滑回弹；点击频道也有 300ms 过渡，非相邻点击仅呈现原页与目标页，不依次穿过中间频道。系统减少动画时跳过点击过渡。

分页由 [HomeChannelSwipe](../../lib/features/feed/presentation/home_channel_swipe.dart) 承载触摸和手写笔输入。滑动吸附完成后才提交当前工作区 tab ID 的路由，顶部选中项同步并滚动到可见位置，不新增页面或返回历史。每个已访问频道保留真实页面、列表缓存、下一级子标签选择和滚动位置；未访问的相邻页先显示加载态，确认切换后才创建内容并读取数据。未选中页面停止自动分页、预览与焦点响应，账号清理仍沿用原有页面作用域。

上下滚动、下拉刷新及下一级横向子标签保留 Flutter 手势竞争规则；鼠标拖动／滚轮不触发内容区分页，内层列表保留应用原有滚轮、拖动及滚动条行为。短滑回到原页，指针取消、拖动期间外部切换频道和隐藏工作区会恢复／转到路由指定页面，不能提交旧手势。应用组合根注入频道切换回调，Feature 不依赖 app 导航实现；动画帧仅由原生分页控件处理，不逐帧刷新 FeedController。

2026-10-07 顶部工具与频道顺序统一调整为：头像、搜索框、观看历史、下载、设置，然后是当前页面的频道／分类子标签。首页、搜索页与设置页共用同一布局规则：可用宽度小于 760 时工具在第一行、子标签在第二行；宽度足够时按相同顺序排成一行。搜索框占工具行剩余宽度，子标签保留横向滚动；不按操作系统分别实现布局，桌面窄窗口同样拆行。此布局规则不改变单／多标签导航模式。

2026-10-07 按后续要求，顶部横条由导航模式判断改为平台判断。Android/iOS 不创建该横条，移除前一次添加的工具区／浮动返回和首页入口；Windows/macOS 恢复原有 42px 横条。Windows 的自定义窗口按钮和拖动区域仍在横条内，工具区恢复头像、搜索、历史、下载、设置的顺序。平台显示策略集中在 `workspaceHeaderVisibleForPlatform`，不改变已保存的导航模式、页面缓存与访问历史，也不新增 iOS 工程或宣称 iOS 平台已验收。

[WorkspaceTabs](../../lib/app/workspace_tabs.dart) 持有有界的页面访问 ID 栈；路由提交和回退不会重复添加访问。关闭／淘汰清除旧 ID，固定首页始终保留。[BiliAppShell](../../lib/app/shell.dart) 负责模式布局、PopScope、搜索草稿和页面生命周期。[路由组合根](../../lib/app/router.dart) 注入设置；其 feature 路由仅渲染空占位，工作区将 ShellRoute 内部 Navigator 以 Offstage 挂载，供 go_router 分发系统返回与弹窗关闭，不挂第二份内容页面或播放器。

平台默认值集中在 [app 适配函数](../../lib/app/platform_defaults.dart)，通过组合根注入设置 Repository。设置加载期间的路由外壳及无显式参数的外壳也使用同一规则，避免 Android 首次显示多标签页。领域模型和 Repository 不直接读取 Flutter 或平台 API。

设置沿用 SQLite `preferences.v1` 快照，初次添加 `navigationMode` 时 JSON schemaVersion 从 10 升为 11；移除自动选项后升为 12。缺失、旧版 `automatic` 或非法值按当前平台默认值补缺，已有 `singlePage`／`multipleTabs` 保留，其他设置保留。SQLite 数据库 schemaVersion 仍为 2，不修改表结构、不清理用户数据。

## 验证

- 2026-10-07 首页分页动画：52 项定向回归通过，日志 `build/home-channel-animation-targeted.log`。新增拖动中两页的实际位置、松手吸附／短滑回弹的中间帧、非相邻点击仅显示原页和目标页、连续点击与减少动画、内层桌面滚动条／鼠标拖动保留，以及取消预览不读取相邻频道；原有路由、频道与下一级子标签状态、滚动位置、隐藏／取消和分页隔离回归继续通过。`tool/check.ps1 -SkipPub` 全部通过：根应用 1299、API 319、播放器 32、弹幕 52 项，共 1702 项；格式与静态分析通过，日志 `build/home-channel-animation-check.log`。本轮按用户要求未构建，移动设备实机体验由用户后续验证。

- 2026-10-07 首页触摸切换：47 项定向回归通过，日志 `build/home-channel-swipe-targeted.log`。覆盖按顺序切换及首尾边界、短拖动／快速滑动／指针取消、鼠标输入隔离、隐藏工作区／外部频道更新、内层横向滚动、竖向滚动／下拉刷新、频道缓存／滚动位置恢复，以及 Android 单／多标签模式的路由、顶部选中项可见性与页面作用域保留。`tool/check.ps1 -SkipPub` 全部通过：根应用 1293、API 319、播放器 32、弹幕 52 项，共 1696 项；四处格式和静态分析通过，日志 `build/home-channel-swipe-check.log`。本次文档本地链接与 `git diff --check` 通过；未做移动设备实际触摸验收。

- 单／多标签初次接入的 77 项定向测试通过，日志 `artifacts/single-page-targeted.log`。覆盖回退顺序、重复访问、关闭后清除旧历史、缓存与历史上限、单页深链、系统返回／弹窗优先、页面状态／搜索请求保留、出栈取消、模式即时保存／切换、窗口尺寸切换和设置快照兼容；平台默认修正的验证见下文。
- 窄屏 420px 和宽屏 1000px 的首页频道滚轮测试验证到达末尾、点击“我的收藏”和反向滚动。400px 的收藏子标签测试验证普通滚轮到达末尾并点击“我的追剧”，加载对应内容，再以原生横向输入返回开头。
- `tool/check.ps1 -SkipPub` 通过：根应用 684、bili_api 225、bili_player 16、bili_danmaku 21，共 946 项测试；四处格式和静态分析均通过，日志 `artifacts/single-page-check.log`。变更文档的 115 条本地链接检查通过，`git diff --check` 通过。
- `tool/test-windows-media.ps1` 通过，日志 `artifacts/single-page-windows-media.log`。主播放测试显示 6 项通过，其中游客公网分支未开启；实际执行 5 项本地验证，另一个独立进程执行 1 项原生错误诊断。工作区新增单页原生断言：A 在 1700ms 暂停并设为 1.5x，B 播放并 seek 到 4000ms，顶部返回后 A 恢复约 1700ms、暂停和 1.5x；B 页面已释放，全程只有一个 VideoSurface；系统返回首页后没有 PlaybackPanel，播放器 idle。保留原有多标签播放／关闭、DASH 两轨、全屏、安全存储、云端 fake 进度和脱敏诊断验证。
- `flutter build windows --release --no-pub` 成功，输出 `build/windows/x64/runner/Release/bilisail.exe`，日志 `artifacts/single-page-windows-build.log`；`flutter build apk --debug --target-platform android-arm64 --no-pub` 成功，输出 `build/app/outputs/flutter-apk/app-debug.apk`，日志 `artifacts/single-page-android-build.log`。
- Windows 物理鼠标／触控板滚动手感、Android/macOS 实机返回手势与原生播放未在本轮验证；macOS 构建未在 Windows 主机执行。不从 Widget 测试或 APK 构建推导为三端实机验收。

## 平台默认修正验证

- 验证 Windows/macOS 默认多标签、Android 默认单标签，窗口 420px／1280px 往返时模式和页面状态不变；设置加载期间也按平台显示，加载后遵循保存的手动选择。
- 验证新用户／旧版缺字段／automatic／未知或类型错误值使用注入默认值；两种手动模式均能重载，不被平台默认覆盖，其他偏好保留。外观页只显示两种导航模式。
- 65 项定向测试通过，日志 `artifacts/platform-navigation-targeted.log`。`tool/check.ps1 -SkipPub` 通过：根应用 693、bili_api 227、bili_player 16、bili_danmaku 21，共 957 项测试，四处格式和静态分析均通过，日志 `artifacts/platform-navigation-check.log`。
- Windows release 与 Android arm64 debug 构建通过，输出分别为 `build/windows/x64/runner/Release/bilisail.exe`、`build/app/outputs/flutter-apk/app-debug.apk`，日志 `artifacts/platform-navigation-windows-build.log`、`artifacts/platform-navigation-android-build.log`。
- 变更文档的 116 条本地链接检查通过，`git diff --check` 通过。Android/macOS 平台默认值使用测试平台覆盖验证，不代表实机验证。

## 顶部顺序调整验证（2026-10-07）

`tool/check.ps1 -SkipPub` 通过：根应用 966、bili_api 282、bili_player 22、bili_danmaku 32，共 1302 项测试；四处格式与静态分析通过。现有搜索布局测试已改为检查分类位于搜索工具下方，继续覆盖 320px 双倍字体与宽屏布局。账号测试覆盖 320–1200px 往返调整、登录／账号菜单及单／多标签模式；400px 和 1200px 的离线渲染核对了工具顺序与双行／单行布局。本文 5 条本地链接和 `git diff --check` 通过。本轮未运行平台构建或 Android/macOS 实机交互验证。

## 单标签页横条移除验证（2026-10-07）

以下保留前一次按导航模式隐藏横条的验证记录，其布局规则已由后续平台规则替代。

- 77 项工作区／路由／布局／账号定向测试通过，日志 `artifacts/single-page-header-targeted.log`。覆盖单页无标题横条、多页标签栏保留、返回与系统返回、模式切换、页面状态保留、320px 双倍字体，以及 420px／1280px 首页、搜索、设置、历史、视频与用户页的窗口按钮位置和拖动事件。窄历史页的“页面导航”菜单可返回首页。
- `tool/check.ps1 -SkipPub` 通过：根应用 1158、bili_api 307、bili_player 22、bili_danmaku 52，共 1539 项测试；四处格式与静态分析通过，日志 `artifacts/single-page-header-check.log`。最终浮动按钮位置调整后重新运行上述 77 项定向测试通过。
- 400px／1200px 的离线 Widget 渲染确认单页从现有工具区开始、多页保留 42px 工作区横条，单页没有遗留空白高度。渲染使用空内容区，不代表真实页面数据或设备验收。README、架构决策与本文共 88 条本地链接、`git diff --check` 通过。
- 本轮未运行平台构建、Windows 原生窗口操作或 Android/macOS 实机交互；原生播放集成测试仅同步横条显隐断言，未执行。

## 按平台显示横条验证（2026-10-07）

- 87 项工作区／路由／布局／账号／平台定向测试通过，日志 `artifacts/platform-workspace-header-targeted.log`。Android/iOS 与 Windows/macOS 分别覆盖单／多标签两种模式、420px／1280px 调整、首页／搜索／设置／历史／视频／用户页；移动端无横条、返回或首页图标，桌面保留对应横条。系统返回仍能从用户页回到视频页，导航状态和保存的模式继续保留。
- 52 项播放面板测试及 4 项平台离线渲染通过，日志 `artifacts/platform-workspace-header-playback-render.log`。检查可见标签栏的桌面快捷键测试明确使用 Windows；渲染使用模拟视频内容区，移动端不增加覆盖按钮或占位，桌面单页保留 42px 标题栏，不代表原生视频或设备验收。
- `tool/check.ps1 -SkipPub` 通过：根应用 1167、bili_api 307、bili_player 22、bili_danmaku 52，共 1548 项测试；四处格式与静态分析通过，日志 `artifacts/platform-workspace-header-check.log`。README、架构决策与本文共 88 条本地链接、`git diff --check` 通过。
- 本轮未运行平台构建、Windows 原生窗口操作或 Android/iOS/macOS 实机交互。iOS 仅通过测试平台覆盖验证显示规则，未新增 iOS 工程或进行原生验收。
