# 窄屏一级导航动效与切换开销

日期：2026-10-25。此记录针对 Android 底栏的首页、动态、我的、设置切换；此前首页频道分组和其他导航修改保留在当前工作区。

2026-10-28：[后续复查](primary-navigation-performance-2026-10-28.md)将不透明滑入按实际底栏布局启用，包含 Windows 窄窗口，并隔离分页器的活动通知与设置内容构建。下文仅限移动平台的动效条件是历史实现。

## 2026-11-01：底栏重复点击按目的页判定

- 原底栏只比较 `sectionForLocation` 的分区；`/history` 归入“我的”，因此历史页点击“我的”被当作重复选择吞掉。搜索页归入“首页”、旧稍后再看／收藏频道归入“我的”时也存在同类问题。
- [外壳](../../lib/app/shell.dart)保留分区高亮规则，重复点击的拦截同时检查当前是否位于该入口自身的页面：“我的”为 `/me`，“设置”为 `/settings`，首页／动态／直播为对应分区的 `/`。历史页仍是原有临时页面，不调整工作区根标签或返回历史。
- [组件回归](../../test/app/bottom_navigation_destination_test.dart)覆盖 Android／Windows、单／双／多标签、390 自动底栏、1280 手动底栏及 1280 自动侧栏，共 18 项。修复前 12 项底栏场景在历史页点击“我的”后仍停留 `/history`，6 项侧栏场景通过；修复后全部通过，并覆盖搜索／旧频道返回一级入口、真正重复点击时不发起导航及栏目、页面身份和草稿保留。日志为 `build/bottom-navigation-before.log`、`build/bottom-navigation-after.log`。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析和平台打包边界通过；根应用 3940 项、四包 829 项测试通过。13 项根测试因 Windows 符号链接权限跳过，10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。全量日志为 `build/bottom-navigation-check.log`；新增文档相对链接及 `git diff --check` 通过。
- 本轮只验证离线组件行为，未执行平台构建、实机触摸验收或性能测量。已尝试热重载，当前没有运行中的 DTD／Flutter 调试实例，未能执行。

## 2026-10-26：推荐与视频动态往返切换

继续处理窄屏底栏切换卡顿。检查当前源码并用真实 `FeedScreen`、390×844 逻辑像素视口复查。每边 fake 仓储返回 500 条，推荐保留 500 条，视频动态依照既有上限保留 200 条：列表仍按视口懒创建，预热后往返切换不增加仓储读取。没有证据将此问题归因为每次切换全量创建卡片。

本轮消除以下额外工作：

- [RetainedTabView](../../lib/shared/ui/retained_tab_view.dart)保持空闲分页器的滚动物理类型，通过外围 `IgnorePointer` 拦截失活页面输入。原来切换到 `NeverScrollableScrollPhysics` 会替换 `ScrollPosition`，连带更新下游滚动依赖。未结束的分页手势、动画仍按既有 generation 和控制器替换机制取消；显式关闭横滑仍保留原有处理。
- [FeedScreen](../../lib/features/feed/presentation/feed_screen.dart)在带频道分页器的首页路径按频道和实际显示配置复用页面 Widget，避免一级入口切换重新构建配置未变的频道。缓存至多覆盖固定频道枚举；登录、栏目回调转发给最新配置，登录入口增删、登录状态、路由初始栏目与布局配置变化照常更新。隐藏页面继续接收继承状态和 Provider 通知；“我的”页内嵌的单频道列表沿用原有配置更新路径。
- 动态等非推荐类频道不再挂载底下那份空的视频列表、滚动控制器和刷新按钮；实际 `HomeContent` 列表及其状态、分页和滚动位置保留。
- [共享视频封面](../../lib/shared/ui/video_card_cover.dart)移除未使用尺寸参数的 `LayoutBuilder`，避免可见性/悬停状态变化安排这层布局构建。
- [一级切换动效](../../lib/shared/ui/primary_navigation_transition.dart)保留 220ms、4% 位移和减少动画适配，移除包裹整个内容区的淡入层。图片密集页面切换期间保持不透明，消除这层透明度合成；下文 2026-10-25 的整页淡入描述属于此前实现。

受控结构探针位于忽略目录 `artifacts/primary-switch-20261026/`，`baseline-results.json` 与 `optimized-results.json` 记录同一视口预热后四次切换（两轮往返）。未请求真实账号/API/CDN，封面 URL 为空，不创建原生预览。

| 每次入口切换中的工作 | 修改前 | 修改后 |
| --- | ---: | ---: |
| 盒布局构建器参与布局次数 | 72 | 48 |
| 视口布局次数 | 6 | 3 |
| 频道页构建次数 | 3 | 1 |
| 整页透明度渲染对象参与布局次数 | 1 | 0 |
| 预热后的新增推荐／视频动态仓储读取 | 0／0 | 0／0 |

这是 debug 下的工作次数，不能换算成帧率或实际卡顿下降比例。隐藏分支仍使用 `Offstage`，未宣称隐藏页面零布局；图片恢复和首次进入仍需工作。本机 `adb devices` 未发现 Android 设备，DTD 未发现运行中的 Flutter 应用，热重载无可用连接；未进行 Android/iOS 真机 Profile/Release 帧耗时、真实图片解码或 GPU 合成对比，也未构建新安装包。

[新增页面回归](../../test/features/feed/feed_primary_switch_test.dart)覆盖大批量 fake 数据下的懒创建、滚动位置对象和偏移保留、重复进入零额外读取、最新登录动作、入口移除及隐藏期间退出登录；[分页回归](../../test/features/feed/home_channel_swipe_test.dart)补充空闲分组的 `ScrollPosition` 身份检查。[动效回归](../../test/shared/ui/primary_navigation_transition_test.dart)与[路由回归](../../test/app/workspace_router_test.dart)验证不透明滑入、详情取消、平台开关和减少动画。

最终 `tool/check.ps1 -SkipPub` 通过：根应用 2725、bili_api 460、bili_player 81、bili_danmaku 93、bili_mux 5，共 3364 项测试通过；10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。格式、静态分析和平台打包边界检查通过，日志为 `build/primary-switch-20261026-check-final.log`。文档 17 个相对链接和 `git diff --check` 通过。本轮按用户要求提交已有优化，不推送；保留已有及同期其他功能修改。

“我的”历史记录、稍后再看和收藏列表跨底栏切换的恢复开销，以及保留的滑入动效在目标设备上的成本，尚未完成专门对照验证。不能将推荐／视频动态的结构计数推广为这些页面的卡顿根因或修复结论；按用户要求留待后续继续定位。

## 实现

- [外壳](../../lib/app/shell.dart)将一级入口标题、工具栏和内容作为同一动效区域，底栏保持固定。[PrimaryNavigationTransition](../../lib/shared/ui/primary_navigation_transition.dart)在目标入口变化时执行 220ms easeOutCubic 动画：内容由相应方向的 4% 宽度偏移归位，透明度从 0.65 恢复至 1。390 逻辑像素宽度下，位移约 16px；根据入口顺序与文字方向确定左右方向。
- 一级动效独立判断平台与宽度，Android/iOS 小于 600 逻辑像素时启用；桌面和宽屏不增加此切换动效。频道分组则只按宽度判断：所有平台小于 600 时直播归首页，底栏均为四项。首次显示、搜索/播放/用户详情的进入和返回、同一入口中的频道/分类切换均不触发一级动效。页内横滑继续使用各自分页组件。
- 快速连点以最后目标为准，进入详情、切到宽屏或开启系统“减少动画”时立即停止并归位；底栏选中动画也遵守减少动画设置。位于底栏入口自身的目的页时，重复点击该项不再发起路由导航。
- 动效围绕同一保留树执行，不通过切换动画 key 重挂载页面，也不同时绘制两份业务页面。SlideTransition/FadeTransition 仅更新绘制和合成，内容增加 RepaintBoundary，逐帧不调用页面构建器。

## 性能逻辑检查与修改

[WorkspaceRootPage](../../lib/app/workspace_root_page.dart)此前每次构建都会为所有已访问分支创建新 Builder，进而重新调用各分支的构建器。现在按需保留分支 Builder，只将新路由和回调配置交给选中分支；其他隐藏分支复用原 Widget。缓存以既有五个固定根分支为界，没有增加预加载或无界页面缓存。

首页与动态仍由同一个 FeedScreen 及其控制器保留已加载频道，独立一级频道组和页内滑动沿用当前工作区实现。我的保留选中内容标签和各自列表，设置保留分类和滚动位置。检查确认分页通过 WorkspaceActivity 隔离，已有内容由控制器缓存恢复，一级导航不主动刷新列表。进入可见状态时仍允许既有首屏补页规则检查，不能将这一行为误称为永远零请求。

隐藏根分支保持 WorkspaceActivity、焦点隔离和账号作用域，继续接收 Riverpod 更新。没有在整个根分支外禁用 TickerMode，避免 Riverpod 暂停监听而延迟账号清理。Offstage 的隐藏布局语义保持；本轮减少的是无关导航引起的构建和动效期间的重建，没有宣称隐藏页零布局或实际帧率提升。

## 首页与视频动态切换复查

2026-10-25 根据窄屏底栏切换轻微卡顿的反馈，继续检查已访问频道之间的切换，修正两处可避免的工作：

- [RetainedTabView](../../lib/shared/ui/retained_tab_view.dart)之前在频道组每次失活时都会替换 TabController，即使分页已停稳。现在空闲分页器沿用原控制器；拖动、回弹或路由选择动画尚未结束时，仍替换控制器并恢复路由选中的页。失活时继续推进 generation，隔离尚未提交的旧滑动回调。该修改共用于首页频道和其他保留式分页，不改变一级滑入／淡入动效。
- [HomeContent](../../lib/features/feed/presentation/home_content.dart)的列表缓存之前将登录回调对象作为失效条件。真实路由每次构建会创建新的回调，导致动态／视频动态的数据未变时也替换列表 delegate 和已挂载卡片。现在只按登录入口是否存在判断缓存失效，卡片经 State 上的稳定方法转发到最新回调；登录入口移除、账号状态／查询／数据改变、完整刷新仍按原规则更新或清空缓存。视频动态继续按视口懒构建。

新增回归在修改前均失败：一个证明停稳后隐藏分页器仍被替换，另外两个证明动态和视频动态在回调变化时替换原有卡片。修改后这三个回归及所在文件全部 37 项测试通过，覆盖 390 逻辑像素视口下的隐藏／返回、原有卡片和滚动位置保留、最新登录动作及移除入口、列表不重复读取。日志：`build/primary-switch-baseline.log`、`build/primary-switch-targeted.log`。

本轮根检查的五处格式、静态分析及平台打包边界检查通过。首轮根测试 2695 项通过、1 项同期下载页面用例失败（`queue actions and delete cancellation preserve files choice`）；该用例单独复跑通过，随后 `tool/check.ps1 -SkipPub -Stage RootTests` 全部 2696 项通过。四个包单独运行检查脚本的 PackageTests 阶段，bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2 项通过；10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志：`build/primary-switch-check.log`、`build/primary-switch-download-blocker.log`、`build/primary-switch-root-recheck.log`、`build/primary-switch-packages.log`。文档相对链接及 `git diff --check` 通过。

这是组件工作量的验证，不能换算为帧率或卡顿下降比例。当前没有连接 Android 设备或 Flutter 调试应用，未进行设备 Profile/Release 帧时长对比；整页 FadeTransition 的合成成本、首次打开的页面构建和图片恢复仍需在出现卡顿的设备上区分 UI 与 raster 耗时。本次没有用 debug 测试耗时作为性能结论，也没有为此增加预加载或扩大缓存容量。

按用户要求另构建 Android arm64 Release 测试包：`artifacts/android-arm64-navigation-20261025-232324/BiliSail-1.2.1+0-android-arm64-navigation.apk`，约 58.6 MB，版本 1.2.1+0、versionCode 12100。先运行 `tool/build-download-mux.ps1 -Target android-arm64`，再强校验锁文件并构建 APK；复用本机已有受保护的固定签名，实际 APK 证书与预期指纹一致，仅包含 arm64-v8a ABI 及对应 `libbili_mux.so`。产物旁保留 SHA-256 和 metadata，记录源码 HEAD、工作区非空状态及两处优化源码的哈希；构建前后这两处源码未改变。日志：`build/primary-switch-android-mux.log`、`build/primary-switch-android-release.log`。构建存在既有 CupertinoIcons 字体缺失及第三方 Java 8／弃用 API 提示；未修改相关依赖或资源。尚未在 Android 设备安装、启动、覆盖升级或实测切换流畅度，交由用户安装确认。

## 验证

- [动效组件测试](../../test/shared/ui/primary_navigation_transition_test.dart)：方向、动画中途重选、状态保留、逐帧不重建内容、详情跳转取消、减少动画和运行中关闭动效。
- [根分支测试](../../test/app/workspace_root_page_test.dart)：从五种入口分别开始，验证懒创建、双向状态与 PageStorage 保留，隐藏分支构建器不因其他入口切换被调用，隐藏 Riverpod 消费者仍接收更新。
- [真实路由回归](../../test/app/workspace_router_test.dart)和[外壳回归](../../test/app/shell_layout_test.dart)：Android/Windows/macOS、390/1280 宽度和双/多标签的入口动效开关、一级切换和页内分组隔离、重复选择当前入口，以及已有账号 epoch、焦点和状态保留行为。

- 最终 `tool/check.ps1 -SkipPub` 通过：根应用 2319、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 2951 项测试通过；五处格式和静态分析、Android 版本/签名及 Windows/macOS 打包边界检查通过。10 项 mux 原生用例因没有配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。日志：`build/primary-navigation-check-final.log`。
- 12 组真实路由动效及分页边界定向回归通过，覆盖 Android/Windows/macOS、390/1280 宽度与双/多标签；日志：`build/primary-navigation-motion-routing-final.log`。
- `tool/build-download-mux.ps1 -Target android-arm64` 通过。Android Release APK 构建在 `:app:preReleaseBuild` 被仓库的签名检查阻止，当前进程未配置 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`；没有更改签名保护或生成替代 Release 签名。日志：`build/primary-navigation-android-mux.log`、`build/primary-navigation-android-build.log`。
- `flutter build apk --profile --target-platform android-arm64 --no-pub` 通过，产物 `build/app/outputs/flutter-apk/app-profile.apk`（约 102.9MB），日志 `build/primary-navigation-android-profile.log`。这是默认调试签名的 Profile 测试包，不能覆盖使用正式发布签名安装的版本。构建存在第三方 Java 8/弃用 API 提示；Release 尝试还输出既有 CupertinoIcons 字体缺失提示，本轮未改动相关资源。

本地没有连接的 Android 设备或可热重载的 Flutter 调试应用，实际触感、Android Profile/Release 帧时长与 GPU 合成开销尚未实测；组件工作次数不能换算成帧率收益。未构建 Windows/macOS；按用户要求与首页子标签滑动隔离修复整体提交，未推送。
