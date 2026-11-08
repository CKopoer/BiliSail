# 顶部连续滚动与子标签吸附

日期：2026-10-31。工具链：Flutter 3.47.6 / Dart 3.13.5。

## 行为

首页推荐等首页频道、我的、UP 主主页与我的主页，采用共享的 [ScrollHeaderLayout](../../lib/shared/ui/scroll_collapsing_header.dart)。它替代按滚动方向切换展开状态的旧动画：

- 向下浏览时，上方搜索工具或账号资料与内容按同一距离向上滚动，并按滚出比例淡出；子标签到达页面顶部后固定，剩余滚动继续交给列表。
- 反向滚动先返回当前列表开头，再使用同一手势的剩余距离带回顶部，途中没有定时展开、吸附或方向触发的闪现。
- 首页与我的沿用底栏布局时收起、侧栏布局时固定的选择；用户主页最初采用窄屏收起、宽屏固定，2026-11-05 调整为所有宽度随页面滚动收起。自己的主页和其他 UP 主页共用同一实现。
- 横向分页不主动展开顶部，各子页保留自己的位置、筛选、内容与草稿。回顶部及刷新按钮可以返回完整顶部；触摸下拉刷新沿用现有入口。
- 2026-11-05 移除用户主页介绍区的半屏最大高度和独立纵向滚动区，资料按内容自然布局。简介仍保留展开／收起，展开后随整页滚动，不在卡片内部滚动。

## 性能与生命周期

使用 Flutter 的 NestedScrollView 协调真实滚动距离，首页和我的子标签位于其 body 的列表外，用户主页采用后述吸顶 sliver，不采用浮动顶部。淡出直接在 sliver 的绘制层更新并复用 OpacityLayer，不逐帧重建页面、资料、卡片或列表委托，也不为顶部额外启动动画计时器。

[PagedScrollViewport](../../lib/shared/ui/paged_scroll_viewport.dart) 继续拥有独立的列表控制器；共享适配器只将活动列表接入协调器，隐藏时脱离并停止其滚动活动，防止已访问子页一起滚动。我的下载列表也使用同一适配器；进程级下载任务不受页面滚动生命周期影响。无协调需求的普通列表不自动继承嵌套控制器。

桌面沿用 [SmoothScrollBehavior](../../lib/shared/ui/smooth_scroll_behavior.dart) 的弹簧与阻尼设置，按与触摸相同的顶部／列表消费顺序应用每帧位移，两段 ScrollPosition 在整段运动中保持滚动状态，避免每帧结束滚动而重新触发悬停预览；减少动画时使用即时滚轮位移。活动 ticker 仅在滚轮运动期间存在，隐藏与销毁时释放。用户开始纵向滚动时释放顶部编辑框的焦点，避免搜索框要求重新露出而拉回顶部；程序滚动与键盘高度变化不释放焦点，搜索草稿仍由原控制器保存。

## 验证

- 顶部、滚轮及用户主页专项 95 项通过，日志 `build/continuous-header-targeted.log`。覆盖拖动中途顶部与首项的等距离位移、透明度、子标签吸附、反向到顶后的连续展开、横向分页、长简介、宽度变化、减少动画、回顶部、下拉刷新与隐藏／销毁停止 ticker；同时验证滚动不重建顶部和列表主体。
- 导航、键盘、预测返回及深滚动保留专项 294 项通过，日志 `build/continuous-header-navigation.log`。保留全部已访问列表和卡片的实例、位置、约束及请求计数，窗口宽度变化仍能正常重排。

- `tool/check.ps1 -SkipPub` 完整通过：根应用 3,752、bili_api 499、bili_player 105、bili_danmaku 145、bili_mux 5，共 4,506 项测试通过；根应用 13 项 Windows 符号链接权限相关用例、mux 10 项需要 `BILI_MUX_LIBRARY` 的原生用例跳过。格式、静态分析与打包边界脚本通过，日志 `build/continuous-header-check-final.log`。文档 163 个本地链接和 `git diff --check` 通过。
- Windows 本地重新构建固定来源的 mux 组件后，构建并运行 390px 宽的临时共享布局：下滚 600px 后子标签纵坐标由 120 变为 0，反向滚动 65px 仍为 0，继续回到列表开头后恢复为 120；单独下滚 65px 时为 55，画面中的顶部同步滚出并淡出。Flutter 热重载成功，运行时异常查询为空，验证进程已关闭。
- 验证后已通过 `flutter build windows --debug --no-pub` 恢复普通 `lib/main.dart` 入口，输出 `build/windows/x64/runner/Debug/bilisail.exe`，日志 `build/continuous-header-windows-debug-build.log`；临时验证界面没有留作日常入口。

本轮没有 Android／macOS 实机交互、真实账号长列表或 Profile／Release 帧耗时采样；组件与 Debug 运行结果不作为实际手感或性能提升幅度的结论。

## 2026-11-05：主页介绍区自然高度

UP 主与个人主页移除半屏高度限制和内部 `SingleChildScrollView`，统一使用外层协调滚动；宽屏也可把资料完整滚出，避免长简介或矮窗口永久挤占内容。投稿／动态等子标签改为自然高度的 `PinnedHeaderSliver`，列表通过标准 overlap injector 为子标签预留位置，避免介绍区接近整屏高度时，剩余空间不足导致导航栏 `RenderFlex` 溢出。首页和“我的”账号页不改变现有策略。

回归覆盖本人／访客、320／900／1000 宽、360／800 高、默认及两倍文字、超出整屏的展开简介、简介收回、顶部与手势等距离移动、子标签吸附、隐藏列表位置保留、桌面平滑滚轮与减少动画。

验证（2026-11-06）：

- 用户主页、共享顶部／平滑滚动和“我的”页面定向 332 项测试通过，本轮三个 Dart 文件静态分析无问题。
- `tool/check.ps1 -SkipPub -Stage RootTests` 完整复跑 4355 项通过，13 项 Windows 符号链接权限用例跳过；与四包合计 5321 项通过。首次全量检查遇到同期举报测试的导入告警与编译接口修改，待该功能完成后重新运行 Lint／RootTests，最终全部通过。
- `tool/check.ps1 -SkipPub -Stage Lint` 通过，覆盖根应用及四包格式、静态分析、打包边界脚本。四包测试 API 652、播放器 148、弹幕 161、mux 离线 5 项通过；未设置 `BILI_MUX_LIBRARY`，10 项原生用例跳过。
- 准备 Windows mux 资产后，临时离线假数据 `ProfileScreen` 的 Windows Debug 构建、DTD 热重启／热重载通过，Dart 运行时异常查询为空。窗口自动化两次返回 `failed to activate captured window`，原生日志存在 accessibility AXTree 更新错误，没有将截图或鼠标交互计为通过。验证进程已关闭，普通 `lib/main.dart` 的 Windows Debug 构建已恢复成功。
- 真实账号页面、Windows 完整界面交互、Android／macOS 实机和 Profile／Release 性能未验收；无依赖或数据库变更，没有执行账号写操作。

本机日志保存在忽略目录 `artifacts/`，前缀为 `profile-header-`。仅提交本轮布局、回归和本文档，同期消息与举报功能改动保留。

## 2026-11-08：触屏滑动后的顶栏回弹

Android Material 3 默认对滚动容器使用拉伸式越界反馈。共享顶部的外层 `NestedScrollView` 在列表仍可继续滚动时，已先结束自己的滚动；Flutter 3.47.6 的拉伸装饰会使用滚动结束通知中的速度启动回弹，即使没有发出越界装饰通知，也会连带吸顶子标签短暂位移。新增组件测试在修复前复现首轮滑动第 2 帧的约 1.1 逻辑像素偏移。

共享 [SmoothScrollBehavior](../../lib/shared/ui/smooth_scroll_behavior.dart) 按控制器身份识别 `NestedScrollView` 的外层，仅跳过这一层的越界装饰，保留平滑滚轮与隐藏页面停止滚动的包装。此规则同时覆盖 `ScrollHeaderLayout` 与播放页的嵌套布局，内部列表保留自身的边界反馈、下拉刷新和桌面平滑滚轮；顶部按距离收起、列表先回到开头才展开顶部的规则保持。

验证：

- 新增 Android 回归覆盖可收起／固定顶部、双向连续三次惯性滑动的逐帧位置、列表触底反馈和回到完整顶部后的下拉刷新；另验证鼠标在可见顶部区域滚动时继续使用平滑弹簧。
- 顶部、首页／我的、平滑滚轮、隐藏列表、用户主页及播放页布局／评论滚动定向 139 项测试通过，日志 `artifacts/touch-header-overscroll-targeted-2026-11-08.log`。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析与打包边界检查通过；根应用 4,726、bili_api 719、bili_player 325、bili_danmaku 161、bili_mux 离线 5 项，共 5,936 项测试通过。根应用 13 项 Windows 符号链接权限用例跳过；未配置 `BILI_MUX_LIBRARY`，mux 10 项原生用例跳过，不能算作原生集成通过。日志 `artifacts/touch-header-overscroll-check-2026-11-08.log`。
- 上述完整检查执行后，同期平台修改向 `tool/check.ps1` 新增 `test_apple_texture_handoff.py`。单独补跑这项新增检查得到 4 项通过、1 项失败：`test_apple_renderers_publish_new_buffers_after_completion` 在 Apple renderer 中仍检测到 `nextAvailable`。因此不将后来更新的完整检查脚本记为全部通过；本任务未修改 Apple 原生实现或这项新增检查，提交仅包含滚动行为、顶部回归测试和本文档。
- 按用户要求不构建应用，不进行设备交互或性能采样；实际触屏观感由用户后续构建并实机确认。
