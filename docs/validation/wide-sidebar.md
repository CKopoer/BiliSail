# 宽屏侧栏样式与收起

日期：2026-10-27。

## 行为

- 设置 → 外观 → **导航栏模式**：提供“自动”“底栏”“侧边栏”，默认自动。自动模式按安全区内可用宽度切换：小于 600 逻辑像素使用底栏，达到 600 使用侧栏；手动模式固定使用所选位置，不随窗口宽度切换。
- **侧栏样式**提供“随窗口宽度”“完整侧栏”“图标文字上下”，在侧栏布局时生效。默认仍在 1600 起展开为 164 宽完整侧栏，其余使用 76 宽导航轨；手动固定侧边栏时窄窗口也可使用这两种样式。切换底栏不覆盖样式或收起状态。
- 宽屏顶部左侧放置圆角描边的菜单／箭头按钮，浅色与深色均使用当前主题颜色，提供“收起侧栏／展开侧栏”提示。按钮在侧栏完全收起后仍留在原位；复用桌面标题栏或多标签栏，没有这些栏时显示 40 高工具栏，避免遮挡页面、搜索及播放操作。
- 收起／展开使用 240ms `easeInOutCubic` 宽度和透明度过渡，内容区及左留白同步调整，按钮图标轻微旋转。侧栏内部保持完整布局宽度并裁剪，避免文字在收起过程中挤压折行。快速反向点击从当前宽度继续；系统减少动画时立即到位，进入窄屏也立即让出空间。
- 收起期间侧栏停止接收指针、键盘焦点和无障碍导航；完全收起后不绘制侧栏。内容页保持同一组件树，不复制页面、播放会话或数据请求。主导航、消息／下载／设置的底部布局和短窗口滚动沿用现有实现。
- `AppSettings.sidebarStyle/sidebarCollapsed` 经设置控制器立即应用并串行保存，失败回退已保存配置并提示。`preferences.v1` 版本化快照追加两个字段，无数据库表变动；缺失／非法字段分别回退为自动、展开，保留其他合法旧设置。恢复默认同时恢复自动样式与展开状态。缩窄窗口不覆盖宽屏偏好。
- `AppSettings.navigationBarMode` 沿用同一保存／回退流程，快照版本从 27 增至 28，数据库版本保持 3。旧快照缺失或非法模式回退自动，恢复默认也回到自动；有效设置继续保留。直播归组和首页频道仍按页面宽度判断，窄屏固定侧栏不重复显示独立直播入口。Android 预测式返回动画和“返回播放／回到播放页”入口随实际底栏／侧栏布局选择。

## 导航栏模式验证（2026-10-27）

- [模式与路由组件回归](../../test/app/navigation_bar_mode_test.dart)覆盖 320／599／600／1280／1600 宽度、三种导航栏模式与侧栏样式组合、组件身份和输入草稿保留、收起偏好保留、三种页面导航模式下即时保存／重新加载／失败回退，以及 Android 返回动画和安全区下返回播放入口。
- [设置持久化回归](../../test/features/settings/navigation_bar_mode_test.dart)覆盖默认自动、复制／归一化、旧快照和非法字段回退、全部模式往返及恢复默认；原设置页回归增加了控件滚入视口的操作，适配新增选项后的页面高度。
- 受影响的 11 个 Dart 文件格式检查和静态分析通过，模式／侧栏／布局／预测返回／设置回归共 258 项通过，日志 `build/navigation-bar-mode-regression-final.log`。四包测试共 659 项通过；10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，日志 `build/navigation-bar-mode-package-tests.log`。
- 共享工作区的 `tool/check.ps1 -SkipPub` 在同期推荐设置代码格式检查处停止；另行执行根测试为 3137 项通过、13 项符号链接权限相关跳过、1 项设置分类连续滑动失败。失败来自同期新增推荐分类后仍断言原分类顺序，未修改该任务的分类逻辑；日志 `build/navigation-bar-mode-check.log`、`build/navigation-bar-mode-root-tests.log`。本次全量检查不记为通过。
- 以已提交源码加本任务差异导出独立源码快照，离线解析依赖后复测新增模式和设置滑动，共 17 项通过，包含共享工作区失败的连续滑动用例；日志 `build/navigation-bar-mode-snapshot-tests.log`。提交仅包含本任务差异，保留同期其他工作区修改。
- 本轮未进行平台构建、设备操作或性能测量；组件回归不代表实际设备手感验收。

## 验证

- [侧栏组件与真实路由回归](../../test/app/sidebar_test.dart)：浅／深主题、放大文字、599／600／1280／1600 宽度、两种排列方向、连续反向、完全收起后入口、宽窄往返、草稿和组件身份保留、减少动画中途启用；单／双／多标签设置即时应用、保存／失败回退及重新加载。
- [设置仓储](../../test/features/settings/sqlite_settings_repository_test.dart)：旧快照、非法字段、全部样式与两种收起状态往返；[设置页面](../../test/features/settings/settings_screen_test.dart)验证恢复默认；[外壳布局](../../test/app/shell_layout_test.dart)继续覆盖底栏、短窗口工具入口和内容保留。

- 本次 11 个 Dart 文件的格式检查与定向静态分析通过；三个文档共 55 个相对链接及 `git diff --check` 通过。使用真实 shell、主题和字体生成浅／深色的完整、紧凑、收起共六张组件渲染图，内容使用本地占位数据，未请求账号或网络；图像位于本地 `build/sidebar-*.png`。
- `flutter test --no-pub --concurrency=1 test/app/sidebar_test.dart test/app/shell_layout_test.dart test/app/workspace_shell_test.dart test/features/settings test/features/video/video_comments_controller_test.dart`：369 项通过，日志 `build/sidebar-regression-final.log`。包含侧栏全部路径、设置回归及同期评论输入失败项的复测。
- `tool/check.ps1 -SkipPub -Stage PackageTests`：bili_api 478、bili_player 83、bili_danmaku 93、bili_mux 5，共 659 项通过。10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成验证；日志 `build/sidebar-package-check.log`。
- 已运行 `tool/check.ps1 -SkipPub`：格式、分析及平台打包边界检查在该次运行通过；根应用 2992 项通过、13 项跳过，6 项同期新增评论 Enter 测试失败，后在上述 369 项回归中全部复测通过。未将这次全量脚本报告为通过，日志 `build/sidebar-check-final.log`。
- 后续全量 Lint 阶段遇到同期新增的 `test/shared/ui/retained_scroll_activity_test.dart`、`test/shared/ui/video_card_content_reuse_test.dart` 格式问题；最新全量分析另在后者第 46 行报告 `curly_braces_in_flow_control_structures`。保留这些独立任务文件，未为凑全量检查修改它们；日志 `build/sidebar-lint-final.log`、`build/sidebar-analyze-final.log`。

本机 DTD 未发现运行中的 Flutter 调试实例，热重载无可用连接。未进行新的平台构建、Windows／Android／macOS 实机操作、屏幕阅读器或 Profile／Release 动效帧耗时验收；组件渲染和行为测试不能替代这些验收。

## 宽屏返回播放页（2026-10-27）

- 安全区可用宽度达到 600 逻辑像素、当前浏览其他页面时，左上角侧栏开关旁显示“回到播放页”按钮。启用时配色与侧栏开关一致，没有保留播放页时仍显示为灰色禁用状态，不可点击；侧栏收起后仍保留，当前已在播放页时隐藏。
- 单／双／多标签共用工作区选择逻辑。点击侧栏首页、动态、直播等入口后，可直接回到原播放页面，沿用页面状态和播放会话。桌面双标签模式激活已有独立播放窗口；即使路由已经选中播放页，重复点击仍可唤回该窗口。
- 多标签按最近访问顺序选择仍保留的播放页，覆盖视频、影视、直播与离线播放。关闭最近播放页后回退到上一个保留的播放页，全部关闭后入口变为灰色禁用状态。访问顺序按开放页面去重保存，受 16 页上限约束，不依赖会被一级导航清空或被 64 次访问截断的返回历史；后台换源不改变访问顺序。
- 宽屏应用内双标签统一使用左上角入口；窄屏继续使用原“返回播放”浮动按钮。按钮位于标题栏拖动区域之外，不占用内容页、搜索和播放控件的位置。
- [外壳回归](../../test/app/workspace_shell_test.dart)覆盖三种模式、原生标题栏／普通工具栏、侧栏首页／动态／直播返回、页面与计数状态保留、侧栏收起、599／600 断点和关闭后的回退；[独立窗口回归](../../test/app/windowed_workspace_test.dart)通过 Windows／macOS 平台配置和 fake 多 view 验证重复激活、不重复创建窗口及原页面／view 保留；[工作区回归](../../test/app/workspace_tabs_test.dart)覆盖访问顺序、返回、后台换源、关闭和历史上限。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、平台打包边界检查、根应用 3027 项与四包 659 项测试通过；13 项根测试因 Windows 符号链接权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志 `build/return-to-playback-check.log`。
- 安全区边界修正后，五个工作区／侧栏／布局测试文件最终 224 项通过，覆盖总宽 620、左右安全区各 20 时仍使用窄屏浮动入口；日志 `build/return-to-playback-targeted.log`。最终根静态分析、两个文档共 38 个相对链接和 `git diff --check` 通过。未进行新的平台构建、原生媒体回归或实机操作验收。
- 后续统一按钮配色与灰色禁用态：外壳／独立窗口／侧栏／布局共 181 项定向测试及三个修改文件的静态分析通过，覆盖初始无播放页不可点击、打开后启用、全部关闭后禁用。日志为 `build/return-to-playback-disabled-targeted.log`、`build/return-to-playback-disabled-analysis.log`。本次 `tool/check.ps1 -SkipPub` 在根格式阶段被同期 `lib/features/feed/data/app_recommendation_identity_store.dart` 的格式问题阻塞，未改动该文件，不能将本次全量检查报告为通过；日志 `build/return-to-playback-disabled-check.log`。

## Windows 标题栏尺寸统一（2026-10-28）

- Windows 双标签主窗口标题栏从 32 调整到与独立播放窗口一致的 44 逻辑像素，标题从 12 调整为 13 号字，保持垂直居中与单行省略。共用此标题栏的单标签模式同步采用相同尺寸，多标签栏继续保持原有 42 高度。
- 两个窗口共用[标题栏尺寸和按钮组件](../../lib/core/platform/window_caption.dart)：返回、主页与窗口按钮采用 18 号图标、46 × 44 点击区域及一致的悬停样式，关闭按钮继续使用红色悬停。主窗口仍通过原有 window_manager 执行最小化、最大化／还原和关闭，播放窗口保留按 view 操作及拖动／双击最大化。
- 标题栏内的侧栏开关和“回到播放页”按后续要求改为播放窗口同款平面按钮，共用按钮样式、46 × 44 点击区域、18 号图标和悬停效果，移除圆角描边、常驻底色及额外间距；保留灰色禁用态、提示、侧栏图标旋转和点击行为。普通工具栏和多标签栏沿用各自原有导航按钮样式。
- [组件回归](../../test/core/platform/playback_window_chrome_test.dart)覆盖浅／深主题、420／600／1280 宽度、1／1.5 倍文字缩放、两个窗口的标题和按钮尺寸一致、窗口操作转发、最大化事件后切换还原按钮及监听释放。现有工作区回归同步更新标题栏和内容起点的高度断言。
- 根检查首次在同期弹幕文件的两条 `TickerMode.of` 弃用提示处停止；随后这些文件更新后，`tool/check.ps1 -SkipPub` 的 Lint、RootTests、PackageTests 三阶段均通过，根应用 3183 项、四包 682 项测试通过。13 项根测试因 Windows 符号链接权限跳过，10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/window-caption-check.log`、`build/window-caption-lint.log`、`build/window-caption-root-tests.log`、`build/window-caption-package-tests.log`；本任务七个 Dart 文件的定向分析和文档相对链接、`git diff --check` 同样通过。
- 后续将两个导航按钮改为平面样式后，185 项相关回归、三个 Dart 文件定向分析及完整 `tool/check.ps1 -SkipPub` 通过：根应用 3184 项、四包 692 项通过，仍有 13 项符号链接权限用例和 10 项未配置 `BILI_MUX_LIBRARY` 的 mux 原生用例跳过。日志为 `build/window-caption-flat-buttons-targeted.log`、`build/window-caption-flat-buttons-analysis.log`、`build/window-caption-flat-buttons-check.log`；文档相对链接及 `git diff --check` 通过。
- 本轮未进行平台构建、原生窗口目视验收或性能测量；组件测试不代表实际窗口视觉确认。

## macOS 宽屏按钮统一（2026-10-28）

- 单／双标签模式的桌面导航按钮按平台选择共用样式，不再依赖是否注入自绘窗口控制。macOS 主窗口的侧栏开关和“回到播放页”与 Windows 一样使用扁平按钮、46 × 44 点击区域和 18 号图标，移除常驻底色、圆角描边与额外间距，保留提示、禁用态和侧栏图标旋转。
- macOS 原生标题栏下的独立导航工具行同步使用 44 逻辑像素高度，避免压缩共用按钮。原生窗口控制、侧栏收起状态与返回播放行为沿用既有实现；多标签栏及移动平台的按钮样式不变。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、平台打包边界检查、根应用 3188 项及四包 699 项离线测试通过；13 项根测试因 Windows 符号链接权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志为 `build/macos-navigation-buttons-check.log`。文档的 11 个相对链接检查通过。
- 当前 Windows 主机没有运行中的 Flutter 调试实例，热重载因无 DTD 连接未执行成功。本轮未进行平台构建、macOS 原生窗口视觉确认或性能测量。

## 多标签按钮统一与关闭播放后侧栏交互（2026-10-29）

- 多标签此前被排除在桌面导航按钮样式之外。现三种页面导航模式共用扁平按钮样式、46 × 44 点击区域、18 号图标和悬停／禁用反馈；桌面多标签栏同步为 44 高，避免压缩点击区域。移动平台保留原有样式。
- 用户反馈 macOS 双标签播放窗通过快捷键关闭后，只有主窗侧栏按钮失效。源码检查发现输入宿主失焦时仅清理业务快捷键序列，没有取消 Flutter 控件自身未结束的鼠标手势。模拟旧窗口丢失 Up 后，保留的侧栏按钮继续持有旧点击，新的鼠标点击无法收起侧栏；该回归在修复前失败，补充清理后通过。此结果证明该输入边界存在缺口，尚不能替代用户 Mac 上对实际事件顺序的确认。
- [AppInputHost](../../lib/core/presentation/app_input_host.dart) 使用现有全局 pointer route 按所属 view 跟踪未结束的鼠标指针，在窗口失焦、应用失活、跨 view 迁移、设备移除和宿主销毁时，通过 Flutter `cancelPointer` 取消对应手势；不增加页面级监听，不重新挂载侧栏或页面，也不触发被取消的点击。迟到的抬起不会执行动作。
- [侧栏回归](../../test/app/sidebar_test.dart)覆盖 Windows／macOS、浅／深主题、三种导航模式的按钮样式与尺寸；[双窗口快捷键回归](../../test/app/playback_window_side_button_test.dart)覆盖丢失 Up、Command+W 关闭、修饰键尚未释放时再次点击、展开／收起和再次打开关闭，保留原按钮实例。[输入宿主回归](../../test/core/presentation/app_input_host_test.dart)覆盖两平台失焦／失活和迟到 Up；[真实路由回归](../../test/app/workspace_router_test.dart)补充关闭后的设置保存与侧栏展开／收起。
- `tool/check.ps1 -SkipPub` 最终通过：格式、静态分析、平台打包边界、根应用 3352 项和四包 709 项离线测试通过。13 项根测试因 Windows 符号链接权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。日志 `build/sidebar-navigation-check-final.log`；定向 39 项回归另见 `build/sidebar-close-targeted.log`。首次全仓测试发现三处旧多标签栏高度断言，已修正并在最终全仓检查复测通过。
- 本轮在 Windows 主机执行离线组件检查，未发现可连接的 DTD／Flutter 调试实例，无法热重载。macOS 构建、原生物理键鼠复测及性能测量未执行，设备验收需覆盖普通／全屏窗口和连续打开关闭后的侧栏按钮。

## 底栏页面顶部随滚动收起（2026-10-30）

- 底栏布局下，首页列表向上滑动时，头像和搜索框在 240 ms 内向上收起，并释放顶部空间；向下滑动即恢复，无需先回到列表顶部。频道标签与底部导航保留。宽屏手动选择底栏也采用独立的工具行，侧栏布局保留原有常驻工具。
- “我的”页使用相同动效收起完整用户资料，历史／稍后再看／收藏／下载标签保持可操作。切换内容标签保留资料收起状态、列表身份和滚动位置；向下滑动恢复资料。布局启用状态由外壳传入，不按账号页面自身宽度另行推算。
- [共享组件](../../lib/shared/ui/scroll_collapsing_header.dart)只响应活动页面的纵向用户滚动方向，忽略水平切页、程序滚动、隐藏页面和不足一屏的列表。通知继续冒泡以保留下拉刷新；收起时停用资料区域的点击、焦点与无障碍内容，系统减少动画设置即时生效。动画只更新顶部局部，不逐帧重建内容页面或更换其滚动控制器。
- 只读参考本地 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441` 的 [首页工具行](../../../PiliPlus/lib/pages/home/view.dart)、[滚动方向通知](../../../PiliPlus/lib/pages/common/common_page.dart)和[我的页资料区](../../../PiliPlus/lib/pages/mine/view.dart)。PiliPlus 应用为 GPLv3；这里只借鉴交互，独立实现 Flutter 组件，未复制应用源码、资源或增加运行时依赖。
- [共享动效回归](../../test/shared/ui/scroll_collapsing_header_test.dart)与[外壳和账号页回归](../../test/app/scroll_collapsing_headers_test.dart)共 13 项通过，覆盖动画中间态、未到顶部反向恢复、搜索草稿、内容身份、窄屏自动底栏、宽屏强制底栏、侧栏、账号内容切换、水平滚动、程序滚动、隐藏页面、短列表、下拉刷新及减少动画。
- 基于 `91cdff1` 只叠加本任务六个文件导出源码快照，五份锁文件使用 `pub get --offline --enforce-lockfile` 解析。`tool/check.ps1 -SkipPub` 的格式、全仓与 Linux 适配器分析、平台打包边界阶段通过，后续通过脚本的 `RootTests`／`PackageTests` 阶段完成全套测试：根应用 3407 项、四包 715 项通过。13 项根测试因 Windows 符号链接权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。日志为 `build/validation/scroll-collapsing-header-snapshot-check-final.log`、`build/validation/scroll-collapsing-header-snapshot-root-tests.log`、`build/validation/scroll-collapsing-header-snapshot-package-tests.log`。
- 快照首次启动测试遇到 SQLite 下载连接中断；随后复用当前工作区的 SQLite 与 libmpv 官方资产缓存，由原构建钩子继续验证 SHA-256 后运行，未修改 Pub 缓存或绕过来源／哈希校验。共享工作区的根应用 3412 项和四包 715 项同样通过；其全量入口最初被同期 `primary_navigation_transition.dart` 的格式问题阻塞，全仓分析另报告同期 `video_card_cover.dart` 两条 `invalid_null_aware_operator`。本任务文件定向分析、文档 22 个相对链接与 `git diff --check` 通过；未修改或提交上述同期差异。
- 本轮平台构建、Android／iOS／macOS 设备操作、实际触摸手感及性能测量未执行。已连接当前 Windows Flutter 实例并尝试热重载；该实例为 AOT 构建，VM 返回 `Compiler is disabled in AOT mode`，未将其记为更新后的运行验收。
