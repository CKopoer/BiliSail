# 窄屏视频卡切换优化结果

日期：2026-10-30。生命周期调查起点为 `0a009e5`；最终隔离基线为 `6241bba`，包含同期已经提交的窄屏头部调整，避免把其他任务的收益算入本轮。调查细节见[生命周期分析](narrow-video-card-navigation-analysis-2026-10-30.md)。

## 问题与实现

热切换没有销毁整页或全部视频卡。主要成本是恢复页面时的活动依赖更新，以及 220ms、4% 整页平移期间的重复光栅工作。仅降低 `VideoCard.build` 没有意义：它在原版热切换中已经是 0。

[工作区外壳](../../lib/app/shell.dart)移除整页 `SlideTransition`，保留稳定的 `RepaintBoundary`；一级入口立即呈现保留的内容，底栏仍保留 220ms 选中反馈。首页频道、动态频道、账号内容分页的触摸滑动保持原行为。没有为切页增加截图、页面预加载或图片容量。

同时减少活动切换引起的重复配置更新：

- [VideoCardCover](../../lib/shared/ui/video_card_cover.dart)按静态内容、实际悬停／焦点、操作状态、主题和减少动画配置复用封面子树；活动变化仍执行取消及代次处理，隐藏预览和操作按钮仍及时更新。
- [ScrollAwareHoverRegion](../../lib/shared/ui/scroll_aware_hover_region.dart)复用未变化的 MouseRegion，事件仍从当前 State 读取最新回调。
- [AppNetworkImage](../../lib/shared/ui/app_network_image.dart)按缓存实例及 generation、URL、解码尺寸复用 Provider，复用未变化的 Image Widget。已就绪帧只改变加载需求／几何状态时不额外 setState；URL、账号、缓存代次和显示配置变化仍失效，滚动离屏仍释放帧。
- [HomeChannelSwipe](../../lib/features/feed/presentation/home_channel_swipe.dart)把活动订阅移到频道组的小门控，避免为未变化的分页器重新传入配置。
- [AccountScreen](../../lib/features/auth/presentation/account_screen.dart)复用账号资料栏，账号或资料变化仍更新，动作通过 State 转发到最新导航／登录回调。

页面缓存上限、列表 cacheExtent、图片 LRU、播放器所有权、设置、依赖与数据库版本均未改变。取消整页平移是本轮有意的交互调整，底栏提供切换反馈；不是通过延长动画掩盖阻塞。

## 取舍

独立试验过过滤质量、硬边裁剪、直接圆角图像着色、物理像素对齐位移和过渡快照。前四项没有稳定降低热点峰值；快照虽减少累计光栅工作，却将动态页一次对照的峰值中位数从约 5.3ms 抬至约 8.3ms，且增加临时整页图资源。这些候选均撤回，保留原封面画质与抗锯齿圆角，不交付快照或诊断编译开关。

## 对照方法

使用真实路由／外壳／业务组件，390×844 逻辑视口、640×360 内存 PNG、三类各 300 条内存数据，视频动态仍执行 200 条上限。Flutter 3.47.6 / Dart 3.13.5，Windows x64 Profile，Impeller OpenGLESSDF。原版从 `6241bba` 的独立 worktree 构建，优化版从本任务工作区构建，使用同一诊断入口。

主机 CPU 为 AMD Ryzen 7 7700。系统枚举 NVIDIA RTX 4070 Ti SUPER、AMD 集显及 Virtual Display Driver，存在 165Hz 和 60Hz 输出；没有采集 Flutter 的实际图形设备绑定，不能把显卡枚举当成所选渲染设备的证据。

每版各测 1× 和 3×，每档两轮，每轮预热后按视频动态、稍后再看、设置、推荐循环 8 次，共 32 次；总计 256 次热切换。调用实际 NavigationBar.onDestinationSelected，每次记录 900ms。测试和构建不与本任务的计时循环并行。

两版分别激活诊断窗口。保留桌面其他应用运行，未隔离系统 GPU 负载。首轮中途帧回调节奏变化的样本、优化版尚未激活窗口的初轮均排除，按相同窗口活动条件补测。最终各入口区间的帧数中位数约 35～38，前后量级一致；原始帧数据保留供复核。

3× 通过 Windows 1170×2532 完整渲染表面、Transform 和 MediaQuery 产生更高像素负载，逻辑内容仍为 390×844；不是仅修改 MediaQuery，也不是裁到显示器高度。先验证 snapshot 的 viewport 和 simulatedDpr。该方法不能模拟手机的 GPU、调度器、刷新率、触摸输入或驱动。

`FrameTiming.buildDuration` 是 UI 帧流水线，`rasterDuration` 是光栅线程耗时，均不是 GPU 硬件计数器。先求每次切换的累计／峰值，再取同一入口 16 次的中位数。累计值表示区间各帧耗时之和，不是用户等待时长、FPS 或单帧峰值。区间包含底栏反馈和延迟绘制，不能用帧数直接宣称吞吐提升；本探针也不测系统输入到首帧延迟。

## 结果

以下数值单位均为 ms。“累计”是一次切换区间内各帧的光栅耗时之和；“峰值”是该区间最慢光栅帧。每格均取同一入口 16 次的中位数。

| 密度 | 入口 | 光栅累计：原版 → 优化版 | 累计降低 | 光栅峰值：原版 → 优化版 |
| --- | --- | --- | --- | --- |
| 1× | 视频动态 | 73.15 → 50.62 | 30.8% | 5.22 → 5.79 |
| 1× | 稍后再看 | 68.92 → 49.55 | 28.1% | 4.30 → 4.60 |
| 1× | 推荐 | 89.40 → 64.53 | 27.8% | 9.11 → 12.20 |
| 1× | 设置 | 43.87 → 37.63 | 14.2% | 1.69 → 1.39 |
| 3× | 视频动态 | 111.55 → 50.77 | 54.5% | 10.54 → 6.56 |
| 3× | 稍后再看 | 100.91 → 49.91 | 50.5% | 8.30 → 5.50 |
| 3× | 推荐 | 121.53 → 65.76 | 45.9% | 14.28 → 14.14 |
| 3× | 设置 | 48.71 → 37.70 | 22.6% | 1.77 → 1.40 |

三个视频卡入口的累计光栅工作在 1× 降低约 28～31%，在 3× 降低约 46～55%；3× 视频动态／稍后再看峰值降低约 38%／34%。3× 推荐最慢观测帧从 22.01ms 降到 15.35ms，但峰值中位数基本未变，不能由单次最慢值推导持续帧率。

**恢复首帧仍有明确边界：1× 推荐峰值中位数从 9.11ms 增至 12.20ms，设置页 UI 峰值从约 2.58ms 增至约 3.54ms。** 稍后再看的 UI 峰值中位数约从 3.73ms 降至 3.36ms，动态与推荐 UI 峰值大体持平。本轮证明了重复绘制负担下降及部分高密度入口峰值改善，没有证明每个页面的每个指标都更快。后续若继续改善 120Hz，推荐页恢复首帧应优先于再减少已为 0 的 VideoCard.build。

256 次采样的 VideoCard、AppNetworkImage Element 身份、内容页 Scrollable／ScrollPosition 及偏移均保留，没有新增数据读取。外壳中根页面之外的横向频道条会随可用频道组切换而替换 Scrollable；这是原版与优化版共有的行为，不能笼统称为所有滚动控件都保留。

[脱敏帧数据](data/narrow-primary-switch-2026-10-30.json)包含每次切换的 UI／Raster 微秒值、生命周期布尔校验、原始文件 SHA-256 与两版 AOT SHA-256；可独立复算本表。

## 复现

准备 Windows mux 原生资产后运行（诊断目标不用于日常构建）：

```powershell
flutter run -d windows --profile --target tool/validation/narrow_primary_switch_profile.dart --disable-service-auth-codes
# 用上一步输出的实际 VM URI 替换下方端口。
$env:SWITCH_OUTPUT = 'artifacts/primary-before.json'
dart run tool/validation/narrow_primary_switch_driver.dart ws://127.0.0.1:PORT/ws sample
# 更高像素负载；snapshot 须显示 1170×2532 的完整表面。
dart run tool/validation/narrow_primary_switch_driver.dart ws://127.0.0.1:PORT/ws density ratio=3
dart run tool/validation/narrow_primary_switch_driver.dart ws://127.0.0.1:PORT/ws snapshot
$env:SWITCH_OUTPUT = 'artifacts/primary-before-3x.json'
dart run tool/validation/narrow_primary_switch_driver.dart ws://127.0.0.1:PORT/ws sample
dart run tool/validation/narrow_primary_switch_driver.dart ws://127.0.0.1:PORT/ws quit
```

原版／优化版须使用相同诊断入口、图像与逻辑视口，分别预热，禁止把 Debug 结果作为性能对照。真实页面只读复查可额外传 `--dart-define=REAL_APP=true`，缩放窗口后用 go 与 sample 采样；3× 密度负载仅用于离线 fixture。诊断输出只含 Element 身份、组件类型、滚动位置、请求次数与帧耗时，不保存标题、图片、Cookie 或带 query 的网络地址。

原始数据保存在本机忽略目录 `artifacts/navigation-switch-20261030/`，最终对照文件为 `fresh-before{1,3}-{1,2}.json` 与 `fresh-after{1,3}-{1,2}.json`。误用被原生最大尺寸裁短的早期 3× 样本和中断的采样不纳入结果。

## 回归与边界

[真实外壳回归](../../test/app/primary_switch_layout_test.dart)覆盖一级切换内容位置稳定、VideoCard Element 身份与 ScrollPosition 保留、热切换不重读数据、快速重选，以及 320／599／600／960 逻辑宽度恢复布局。路由矩阵继续覆盖 Android／Windows／macOS、单／双／多标签。账号资料新增最新导航回调回归；现有图片账号／URL／缓存开关、动画帧、离屏释放、队列容量，以及悬停预览取消与操作状态回归继续执行。

本轮验证结果：

- `tool/check.ps1 -SkipPub` 退出码 0：格式、静态分析、打包边界脚本通过；根应用 3406、bili_api 496、bili_player 96、bili_danmaku 118、bili_mux 5，共 4121 项测试通过。另有 13 项符号链接相关用例及 10 项未配置 BILI_MUX_LIBRARY 的 mux 原生用例跳过。
- 进一步限定内容列表而非外壳横向频道条的 State 存在性后，定向补跑 `primary_switch_layout_test.dart` 1 项通过。不能仅持有旧 State 引用就声称它仍在树中。
- Windows Profile 受控对照完成上述 256 次切换；当前源码普通入口 Windows Release 构建通过，输出为 `build/windows/x64/runner/Release/bilisail.exe`，运行或分发需保留整个 Release 目录。
- Windows Debug 真实入口缩窄窗口，执行 32 次只读一级切换与热重载，运行错误查询为空。Debug 数据只用于功能检查，不计入性能结果。

日志位于本机 `artifacts/navigation-switch-20261030/final-check.log`、`final-retention-test.log`、`final-release-build.log`、`final-debug-real.log`；脱敏数值证据已随文档保留。

本轮未进行账号写操作、Android 安装或发布。Windows 的累计开销改善不表示所有首帧峰值都已解决，也不替代 Android 120Hz、macOS／iOS、冷网络或长期内存压力验收。
