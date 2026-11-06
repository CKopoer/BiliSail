# Android 预测式返回

日期：2026-10-25；导航栏模式启停更新于 2026-10-27。

## 播放页侧滑返回被状态栏通知中断（2026-11-07）

- 现象：播放页左上角返回及普通系统返回键可用，系统侧滑却停留在播放页。Xiaomi 13（Android 16、手势导航）开发测试包复现：预测预览切入首页时收到窗口指标通知，原实现无条件取消已接管的手势，后续确认事件因不再处于跟踪状态被忽略。
- 临时真机诊断确认，播放页黑色状态栏与首页状态栏样式切换期间，Android 会重新发布**值未改变**的窗口指标。修复后同样收到通知，但快照比较为未变化，手势确认正常返回首页；诊断输出未保留在代码中。
- [共享手势区域](../../lib/core/presentation/predictive_back_region.dart)在手势开始时保存窗口物理尺寸、像素密度、padding、viewPadding 与 viewInsets 的值快照，仅在实际几何变化时取消。保留播放页黑色状态栏及首页样式；旋转、分屏、缩放、安全区和键盘变化仍使旧手势失效，不将迟到确认转交新页面。
- [组件回归](../../test/app/predictive_back_test.dart)新增 24 组重复指标用例，覆盖单／双／多标签、视频／影视／直播／离线播放，以及拖动取消和确认动画两个阶段；旧实现全部失败，修复后通过。另增加真实尺寸、密度、padding 和 viewPadding 变化的取消验证，既有键盘／路由／模态隔离继续覆盖。
- 定向预测返回与移动状态栏回归共 111 项通过（`build/android-back-targeted.log`）；Android 开发 Debug 构建及热重载通过。Android arm64 开发 Release 构建通过（`build/android-back-release-build.log`），APK 为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，确认测试包身份、1.2.7+0 版本、原开发签名及不可调试后覆盖安装，未清除数据或修改正式包。
- `tool/check.ps1 -SkipPub` 通过（`build/android-back-check.log`）：格式、静态分析和打包边界通过，根应用 4545、bili_api 677、bili_player 181、bili_danmaku 161、bili_mux 5，共 5569 项通过。根应用 13 项按既有条件跳过；另有 10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计原生集成通过。本页相对链接及 `git diff --check` 通过。
- 同一台 Xiaomi 13 使用最终 Release 产物，左右边缘各两次进入视频后侧滑返回首页均通过（`build/android-back-device-results.json`）。本轮未测性能，未对其他 Android 设备、影视／直播／离线实际播放或其他平台作原生验收；这些路由的共享返回行为由组件回归覆盖。

## 行为与边界

- Android Manifest 显式开启 `android:enableOnBackInvokedCallback`。Android 14 及以上、工作区采用底栏布局时，通过 Flutter 的系统返回手势事件驱动工作区的两页横向平移：当前页沿手势方向移出，上一页从另一侧移入，两页边缘相接并保持原尺寸与垂直位置；左右边缘均支持，取消手势回到原位。侧栏布局停用工作区预测动画，确认手势直接执行普通返回。导航栏默认自动，按安全区内可用宽度 600 逻辑像素断点选择；手动固定底栏／侧边栏后，动画跟随所选布局。旧系统、实体返回键及三键导航沿用现有返回入口。
- 工作区保留页面，不在 go_router 的占位路由上执行 pop。`WorkspaceTabs.backDestination` 只读取返回目标；手势确认动画结束后才调用既有返回逻辑。双标签关闭离开的临时浏览页，播放先回退媒体历史，历史为空才关闭会话；多标签沿访问历史选择上一页。
- Android 双标签播放页隐藏顶部返回、标题与关闭按钮所在的整行，不保留该行的 44 逻辑像素占位；横屏和大屏同样处理。系统返回键与返回手势继续沿用上述页内详情、媒体历史、关闭会话的优先级。
- 上一页以完整的实时组件参与横向预览，包括搜索／频道栏、列表和底部导航。预览保持 `WorkspaceActivity.active=false`、`previewing=true`，允许图片和只读列表布局／加载，保持输入与播放所有权停用。历史视频区显示黑色，不为预览调用播放器构建器、切换媒体或抓取整页截图。
- `PageBackHandler` 的页内详情优先于工作区返回。弹窗、图片查看和全屏等已有独立路由继续由自己的返回入口处理；本轮不新增这些路由的手势动画。根页保留退出确认，因此不直接触发系统返回桌面的预览。
- 手势期间页面特征树不随进度逐帧重建，只有局部变换更新。路由、导航模式、账号身份、页内返回能力、模态、窗口尺寸、输入法或应用活动状态改变时废弃旧手势；迟到的确认不能返回新页面。遵循系统减少动画设置，省略位移和结束过渡。

## 按底栏布局自动启停（2026-10-26）

- 用户要求宽屏 Android 自动关闭预测式返回动画，仅窄屏底栏布局启用。工作区手势区域与底栏共用 600 逻辑像素断点，按父布局实际宽度减去左右安全区计算，不按设备类型、物理分辨率或当前视频页是否显示底栏判断。
- 可用宽度小于 600 时保留完整组件预览与两页平移；达到 600 时不接受预测预览，当前页及侧栏在拖动期间保持原位，确认后由 Flutter 普通返回入口执行原有媒体历史／页面返回。Manifest 返回回调继续启用，宽屏返回键、手势及退出确认保持原有语义；独立弹窗／全屏路由沿用各自行为。
- 横竖屏、分屏或窗口缩放后自动重新判断，不切换导航模式、不替换缓存页面。进行中的预览遇到尺寸变化仍废弃旧手势，迟到确认不能误返回；缩回窄屏后可重新开始预测手势。
- 组件回归覆盖三种导航模式、左右边缘、599／600 断点、844／1280／1600 宽度、DPR 1／2，以及安全区扣除后 598／600 的边界，检查启停与根页底栏一致、宽屏无预览位移、取消不返回、确认可正常返回。另验证预览中从窄屏变宽屏会取消旧手势，缩回窄屏后恢复动画且页面实例不变。
- 48 组宽度启停用例在旧代码上复现 30 组宽屏仍接受预测手势的问题；修正后导航／返回专项 300 项通过，日志为 `build/predictive-back-compact-targeted.log`。`tool/check.ps1 -SkipPub` 通过：根应用 2774、bili_api 460、bili_player 81、bili_danmaku 93、bili_mux 5，共 3413 项测试通过；格式、静态分析和打包边界检查通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，完整日志为 `build/predictive-back-compact-check.log`。
- Android arm64 封装组件准备及 Profile APK 构建通过，日志为 `build/predictive-back-compact-android-mux.log`、`build/predictive-back-compact-android-profile.log`；产物为 `build/app/outputs/flutter-apk/app-profile.apk`（约 118.5 MB、调试签名），仍有已有的 CupertinoIcons 字体资源提示。未进行 Android 实机手势／原生画面／性能验收；未发现活动调试应用，热重载请求未能执行；未构建其他平台。本页与架构文档 39 个本地链接和 `git diff --check` 通过。

## 两页横向过渡修正（2026-10-25）

- 用户反馈视频页预测返回时向反方向和下方收缩。原实现叠加中心缩放与固定 24 逻辑像素横移；缩放会让顶部下移，宽屏下还可能盖过横移量。
- 共享过渡改为按实际内容宽度进行分数平移，取消缩放、圆角和淡出；上一页与目标名称占位使用相同进度从另一侧移入。手势区域增加固定裁剪，避免横屏／大屏的移动页面绘制到侧栏和工具栏之外。
- 新增视频页回归覆盖 390×844、844×390、1080×844 和左右边缘，在多个前进／回撤进度检查原尺寸、垂直坐标、运动方向、两页边缘相接与裁剪区域；继续验证取消保留页面、确认后释放原页面。初版的目标名称占位已由下方完整组件预览替代。
- 定向回归 19 项通过（`build/predictive-back-horizontal-targeted.log`）。新增几何用例在旧实现上先复现页面缩小失败，修正后通过。`tool/check.ps1 -SkipPub` 通过：根应用 2606、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 3238 项测试通过；格式、静态分析和打包边界检查通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。完整日志为 `build/predictive-back-horizontal-check.log`。
- Android arm64 封装组件准备及 `flutter build apk --profile --target-platform android-arm64 --no-pub` 通过，日志为 `build/predictive-back-horizontal-android-mux.log` 和 `build/predictive-back-horizontal-android-profile.log`，测试包为 `build/app/outputs/flutter-apk/app-profile.apk`（约 118.5 MB，调试签名）。构建保留已有的 CupertinoIcons 字体资源提示。未连接 Android 实机或可热重载的调试应用，本轮未启动模拟器；真实解码画面与系统手势手感仍待设备确认，几何测试不替代实机验收。未构建 Windows/macOS；本页 6 个本地链接和 `git diff --check` 通过。

## 完整组件预览与播放器隔离（2026-10-25）

- 用户反馈历史视频只有“返回 BV…”占位、回首页后工具栏等组件才补出来；随后明确要求其他组件正常准备，视频区可以黑屏，确认返回时只加载播放器。
- Android 每个页面框架包含自己的完整 Scaffold 与导航组件，整页共同平移；预览和提交使用同一套组件、控制器和 PageStorage，不在确认后重建首页框架。搜索输入控制器按标签保留，预览不会显示当前视频标签的搜索草稿。
- 同一播放标签的媒体历史保留各自的视频／影视／直播／离线页面 UI，共享标签级 ProviderScope 和唯一 PlaybackSession。非当前历史源通过 `WorkspaceMediaPermission` 返回黑色视频区，不构建播放器；确认返回后才挂载该源的播放器，详情和评论继续使用原状态。普通隐藏播放标签仍遵循原并发／暂停策略。
- `WorkspaceActivity.isVisible` 允许预览图片和列表准备，`isActive` 继续隔离输入、页内返回和播放所有权。取消手势不选择目标、不重新打开媒体；确认后保留最终位置两帧，让同一实时页面完成布局再结束过渡。账号变化清理旧私有页面及历史，旧手势仍按账号／导航身份隔离。
- 工作区当前页面与媒体历史 UI 共用 16 页上限，URI 视图及滚动存储随淘汰释放，不增加无界页面缓存。同槽根页面切换或容量限制下没有保留目标视图时，沿正常返回路径处理，不展示 BV 文字占位。缓存淘汰、账号变化及显式刷新后的数据仍按原规则读取。
- 实际路由组件回归检查：返回预览、取消和确认后，VideoScreen、CommentsPanel 及评论 Scrollable 保持同一实例与滚动位置，详情／评论请求计数不增加；播放器仅在确认后重新创建。首页搜索与底栏在预览及提交后保持同一实例及几何位置。连续 22 个媒体访问保持 UI 数量不超过 16。
- “我的 → 视频／UP 空间 → 返回”曾多出公共头像与搜索框：工具行显隐错误读取外壳 State 的 context，使隐藏／预览页面使用了当前视频或空间页的导航配置。`_navigationToolsVisible` 改为接收该页面框架的 BuildContext；导航工具按各自页面身份判断。三种导航模式的六组回归在旧代码均复现，在修正后验证预览与提交均无额外工具行，且“我的”内容实例和位置不变。
- 最终组件专项 30 项通过，日志 `build/predictive-back-live-preview-targeted-final.log`；路由／账号／启动恢复专项 122 项通过，日志 `build/predictive-back-live-preview-routing.log`。`tool/check.ps1 -SkipPub` 通过：根应用 2693、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 3325 项测试通过，格式／静态分析及打包边界检查通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。最终完整日志为 `build/predictive-back-live-preview-check-final.log`；这是包含同期导航修改的共享工作区快照。
- Android arm64 封装组件准备及 Profile APK 构建通过，日志为 `build/predictive-back-live-preview-android-mux.log`、`build/predictive-back-live-preview-android-profile-final.log`，产物为 `build/app/outputs/flutter-apk/app-profile.apk`（约 118.5 MB、调试签名）。保留已有 CupertinoIcons 字体提示。本轮未连接 Android 实机或调试进程，未进行手机手感／原生解码画面与性能验收，热重载请求因无活动应用未能执行；未构建 Windows/macOS。

## 实现与来源

- [手势区域与局部变换](../../lib/core/presentation/predictive_back_region.dart)、[工作区接入](../../lib/app/shell.dart)、[只读返回目标](../../lib/app/workspace_tabs.dart)、[Android Manifest](../../android/app/src/main/AndroidManifest.xml)。
- [实时预览状态](../../lib/app/workspace_back_presentation.dart)、[可见性与媒体许可](../../lib/core/presentation/workspace_activity.dart)、[标签级作用域和播放器门控](../../lib/app/router.dart)、[页面复用回归](../../test/app/predictive_back_page_reuse_test.dart)。
- 采用 Flutter 3.47.6 自带的 `WidgetsBindingObserver` 预测手势 API，不增加依赖，不修改 Flutter SDK 或 Pub 缓存。普通 Material 路由沿用 SDK 默认的预测式返回过渡。
- 官方依据：[Android 预测式返回迁移](https://docs.flutter.dev/release/breaking-changes/android-predictive-back)、[Flutter 默认 Android 过渡](https://docs.flutter.dev/release/breaking-changes/default-android-page-transition)、[Android 接入要求](https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture)。本轮使用公开 API 和独立工作区变换实现，没有复制上游实现代码。

## 验证

- 顶部工具行调整的定向回归 139 项通过：工作区外壳、路由与预测返回 135 项，以及播放面板的双／多标签会话 4 项。覆盖 Android 横竖屏／大屏无按钮行及占位、返回播放保留页面状态、系统返回恢复媒体历史及关闭释放；iOS 和桌面标题栏显示回归通过。本轮未执行平台构建或实机验证，未发现可连接的调试应用，热重载请求未能执行。
- 顶部工具行调整后，`tool/check.ps1 -SkipPub` 通过：根应用 2600、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 3232 项测试通过，格式／静态分析及打包边界检查通过；10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。完整日志为 `build/android-dual-header-check-final.log`，定向日志为 `build/android-dual-header-targeted.log` 和 `build/android-dual-header-playback.log`；这是包含同期其他修改的共享工作区快照。
- [平台通道组件测试](../../test/app/predictive_back_test.dart)覆盖双／多标签、左右边缘、取消保留页面状态、确认关闭、媒体历史、根页退出确认、页内返回／模态／全屏优先、路由／键盘／模态中途变化、确认收尾期间导航、减少动画及逐帧构建次数。[工作区模型测试](../../test/app/workspace_tabs_test.dart)比较预览与实际返回目标，验证读取不消耗历史。
- 导航、评论详情和工作区专项回归 174 项通过，日志 `build/predictive-back-regression.log`。此后新增的全屏、减少动画和确认收尾竞态用例随完整检查通过。
- `tool/check.ps1 -SkipPub` 通过：根应用 2355、bili_api 456、bili_player 81、bili_danmaku 93、bili_mux 2，共 2987 项测试通过，五处格式／静态分析和打包边界检查通过。10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。日志 `build/predictive-back-check.log`；这是检查时的共享工作区快照，包含同期其他任务改动。
- `tool/build-download-mux.ps1 -Target android-arm64` 通过，日志 `build/predictive-back-android-mux.log`。
- `flutter build apk --profile --target-platform android-arm64 --no-pub` 通过，产物 `build/app/outputs/flutter-apk/app-profile.apk`（约 118.5 MB），日志 `build/predictive-back-android-profile.log`。这是使用调试签名的 Profile 测试包，不能覆盖正式发布签名安装的应用；构建仍输出已有的 CupertinoIcons 字体资源提示，本轮未修改字体依赖。
- 本地未连接 Android 设备，本轮未启动模拟器；真实系统边缘手势、输入法关闭优先级、画面手感与 Profile/Release 性能仍待设备验收。组件事件注入不等同于系统手势验收。未构建或实机验证 Windows/macOS；现有 Windows/macOS 导航组件回归通过。没有运行中的 DTD／调试应用，热重载请求未能执行。
- 文档索引和本页共 135 个本地链接、Manifest XML 解析及任务文件的 `git diff --check` 通过。
