# 窄屏视频卡页面切换与生命周期分析

日期：2026-10-30。分析源码检出提交：`0a009e50673bf90b4ad1a2ca77afc45762c30ded`。范围：底栏推荐、动态中的视频动态、我的中的稍后再看，并以设置页作为轻内容对照。Windows 当前源码 Profile 构建缩窄窗口，补做真实账号页面、内存数据、深滚动返回和快速连续切换。

本轮是调查，没有修改应用或包的业务代码，没有宣称修复卡顿。此前的[一级导航复查](primary-navigation-performance-2026-10-28.md)和[Android 记录](android-primary-switch-2026-10-26.md)仅用于核对已解决的问题；下面的计数和 Windows 数据重新采集。

本文保留优化前的调查口径；后续实现与前后对照见[窄屏切换优化结果](narrow-video-card-navigation-results-2026-10-30.md)。

## 结论

1. **热切换没有销毁并重建整页或全部视频卡。** 三组各 32 次采样中，已挂载 `VideoCard` 的 Element 身份集合均不变。组件探针中四类入口的 `VideoCard.build` 均为 0 次。列表、卡片和滚动状态已有有效复用，继续缓存整页或提前创建全部视频卡不是当前优先方案。
2. **保留页面仍有一轮活动依赖更新。** 390×844 受控组件探针中，一次切换记录约 1,200～1,500 次重建回调，包含 10～20 个 `VideoCardCover`、20～40 个 `ScrollAwareHoverRegion`、10～30 个 `AppNetworkImage`。重建主要在页面外壳、活动门控和卡片内部组件，不能把它们全部称作视频卡内容重建。
3. **本机真实页面更明显的时间热点是进入时前一两帧的 Raster。** 推荐、视频动态的每次切换 Raster 峰值中位数约 9ms，推荐深滚动返回约 11.8ms。UI 峰值一般约 3～5.5ms。本轮没有复现 60Hz 下的明显长停顿，但这些光栅帧已经超过 120Hz 的 8.33ms 预算。Windows 数值不能直接折算 Android 性能。
4. **整页平移、图片恢复与 Windows 无障碍更新要分别测量。** 动画后续帧没有反复执行业务卡片 build，但仍需合成图片页面。启用 Windows UI 自动化后的时间线还有可观的语义更新成本，不能将这部分归因于普通 Android 页面。

## 页面树与所有权

### 底栏入口并不一一对应独立根页面

[底栏处理](../../lib/app/shell.dart)中，推荐和动态最终选择首页频道；我的进入 `/me`，设置进入 `/settings`。[路由组合](../../lib/app/router.dart)将它们交给同一工作区根页面。

```text
BiliAppShell / 工作区页面作用域
└─ WorkspaceRootPage
   ├─ feed：FeedScreen
   │  └─ HomeChannelSwipe
   │     ├─ 首页频道组 → RetainedTabView → 推荐
   │     └─ 动态频道组 → RetainedTabView → 视频动态
   ├─ account：AccountScreen
   │  └─ RetainedTabView → 稍后再看 → HomeContent
   ├─ messages
   ├─ downloads
   └─ settings
```

只有访问过的根分支、频道组和子页才逐步创建。推荐与视频动态切换可能仍在 `feed` 根内；切到稍后再看才改变 `feed/account` 根的可见性。因此分析必须包括根分支和内部频道两层，单测一个裸 `FeedScreen` 不足以覆盖实际路径。

### 各层当前保留什么

| 层级 | 实现与保留对象 | 隐藏时的行为 |
| --- | --- | --- |
| 工作区 | [shell](../../lib/app/shell.dart)、[页面作用域](../../lib/app/router.dart)保留页面身份、ProviderScope、播放所有者和 PageStorage | `Offstage`、焦点与输入门控；普通切页不等于关闭页面 |
| 根分支 | [WorkspaceRootPage](../../lib/app/workspace_root_page.dart)保存已访问根的 Widget 和独立 PageStorageBucket | 只为当前选中根更新路由配置；隐藏根仍接收自己的 Provider/Inherited 更新 |
| 首页频道组 | [HomeChannelSwipe](../../lib/features/feed/presentation/home_channel_swipe.dart)保存各组选择和分页进度 | 非当前组 Offstage，保留组内已访问页面 |
| 内部子页 | [RetainedTabView](../../lib/shared/ui/retained_tab_view.dart)的访问标记和 AutomaticKeepAlive | 未访问页不创建业务内容；已访问页保留 Element；离开时中断未完成的分页动作 |
| 页面约束 | [RetainedPageLayout](../../lib/shared/ui/retained_page_layout.dart)保存最后可见约束 | 隔离其他底栏入口头部高度的影响；重新显示时使用当前窗口约束。它不冻结脏后代，也不完全禁止隐藏布局 |
| 列表查询 | [FeedController](../../lib/features/feed/application/feed_controller.dart)、[HomeController](../../lib/features/feed/application/home_controller.dart)及对应作用域 | 挂载订阅保留查询；autoDispose 并不意味着隐藏即释放。关闭作用域或账号代次变化才走取消/重置 |
| 列表内容 | [FeedVideoGrid](../../lib/features/feed/presentation/feed_video_grid.dart)、[HomeContent](../../lib/features/feed/presentation/home_content.dart)、[共享网格](../../lib/shared/ui/responsive_card_grid.dart) | 委托和未变内容复用；Sliver 按视口创建行，滚出缓存范围的行仍可销毁 |
| 卡片 | [VideoCard](../../lib/shared/ui/video_card.dart)按实际内容、菜单与反馈比较缓存 `_card` | 回调由 State 转发到当前配置；内容不变时不重新构造整张卡片 |
| 图片 | [AppNetworkImage](../../lib/shared/ui/app_network_image.dart)保留已就绪帧和流 lease | 隐藏时释放加载需求、移除滚动观察及待几何检查；已就绪图片不因底栏隐藏直接丢弃；列表内部滚出视口仍释放帧 |

首次访问包含建页、请求、创建可见卡、图片传输/解码；热切换主要是路由配置更新、活动通知、恢复图片监听和绘制。关闭页面、账号变化、滚动离屏又是不同的释放路径，不能混用结论。

## 热切换为什么仍有工作

主要链路是：

```text
底栏回调 → 路由/工作区选择变化
  → 当前根/频道收到新配置
  → WorkspaceActivity 变化
  → PagedScrollViewport / AccountTabContent 等更新活动和 TickerMode
  → 封面、悬停、图片及滚动门控 didChangeDependencies
  → 图片可见性复核、监听恢复，必要时再安排一帧
  → 首次恢复布局/绘制 + 220ms 不透明平移动画的后续合成
```

`WorkspaceActivity` 是 InheritedWidget；通知会让订阅者重新进入依赖更新。`TickerMode` 停止隐藏动画，**不承诺取消所有 Widget 更新、Provider 通知或布局**。`Offstage` 也不能单独解决上述工作。

调查时的 `PrimaryNavigationTransition` 已经把业务页作为稳定 child 放进 `SlideTransition`，并有 `RepaintBoundary`，没有整页透明度补间。问题不在“220ms 内每帧重建业务页面”；剩余成本需要区分首帧恢复和后续 Raster/语义变换。后续迭代已删除该组件，现行一级页面呈现入口见[工作区外壳](../../lib/app/shell.dart)。

## 组件计数

探针：本机忽略目录 `artifacts/navigation-switch-20261030/structure_test.dart`。真实路由和页面，390×844，每类 300 条内存条目，视频动态沿用 200 条数据上限，1×1 内存 PNG。四页预热后循环两轮，使用 `debugOnRebuildDirtyWidget` 计数，并比较页面、卡片、图片和列表的 Element 身份。

| 进入目标 | 全树重建回调 | VideoCard.build | VideoCardCover | ScrollAwareHoverRegion | AppNetworkImage | 去掉封面图片后的全树回调 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 视频动态 | 1202 | 0 | 20 | 40 | 30 | 1072 |
| 稍后再看 | 1519 | 0 | 20 | 40 | 28 | 1399 |
| 设置 | 1270 | 0 | 10 | 20 | 10 | 1230 |
| 推荐 | 1489 | 0 | 10 | 20 | 20 | 1399 |

计数包括同一 Element 在不同帧的重复回调，不是新 Widget/State 数量，也不是耗时排名。去图片探针只说明结构性工作仍存在，不能据此认定图片绘制只占某个百分比。

三类视频卡列表的 Element 均保留，没有把 300 条内容全部挂载。不同入口的头部滚动容器可以增加/移除，这是外壳布局变化，不能误报成保留列表被重新创建。`VideoCard.build` 为 0 也不意味着所有后代或 RenderObject 均零更新。

原始结果：`structure-covers.json`、`structure-no-covers.json`。

## Windows Profile

Flutter 3.47.6，Dart 3.13.5，Windows x64 原生 Profile，运行日志报告 Impeller OpenGLESSDF。复用已有 Windows mux 资产，没有执行播放器或封装性能回归。

诊断入口位于忽略目录 `artifacts/navigation-switch-20261030/profile.dart`；`driver.dart` 通过本地 VM service 调用诊断扩展。常规切换调用实际 `NavigationBar.onDestinationSelected`，每次间隔 900ms，先预热四页，再各采样 8 次。它覆盖实际处理函数与后续帧，**不测量真实指针输入到 DWM 显示的完整延迟**。手动检查、滚动和截图在计时循环之外进行，没有并行运行 Flutter 测试或其他本任务基准。

UI 使用 `FrameTiming.buildDuration`，包含 UI 帧流水线工作，不等于单独 Widget.build；Raster 使用 `rasterDuration`。两条线程流水线的时长不能直接相加判断是否掉帧。表中中位数先取每次切换区间的最大值，再对同一入口的 8 次结果取中位数。

### 内存图片对照

390×844 逻辑视口、Android 主题/单标签、640×360 内存渐变 PNG、无真实 API/CDN/账号。最终图片解码缓存 19 项、约 5.69MiB。推荐、视频动态、稍后再看仓储读取分别为 1 次，预热后不增加。

| 目标 | 每次 UI 峰值的中位数 ms | 每次 Raster 峰值的中位数 ms |
| --- | ---: | ---: |
| 视频动态 | 3.51 | 5.95 |
| 稍后再看 | 3.83 | 4.71 |
| 设置 | 2.48 | 1.86 |
| 推荐 | 3.37 | 9.22 |

数据：`profile-offline.json`。此对照的主题、窗口装饰、内容和图片身份均与真实页面不同，不能把两表差值解释成某次优化收益。

### 真实账号、实际封面

调用生产 `main` 启动当前源码，逻辑视口 404×874，检查推荐、视频动态和已选择的稍后再看，鼠标停在底栏，避免悬停预览混入切换采样。没有点击视频、加入/删除稍后再看、点赞、发送等账户写操作。没有修改或关闭原先运行的商店版应用。

| 目标 | UI 峰值中位数 ms | Raster 峰值中位数 ms | UI 最大 ms | Raster 最大 ms |
| --- | ---: | ---: | ---: | ---: |
| 视频动态 | 3.94 | 8.90 | 4.98 | 11.81 |
| 稍后再看 | 4.08 | 6.28 | 5.31 | 7.14 |
| 设置 | 2.96 | 1.39 | 4.45 | 1.67 |
| 推荐 | 4.12 | 9.17 | 5.52 | 10.10 |

32 次共 496 帧，UI/Raster 均没有超过 16.67ms；Raster 有 19 帧超过 8.33ms，其中视频动态 12 帧、推荐 7 帧。每次切换高值主要在前一两帧，后续动画帧仍有光栅开销。例如一轮推荐前两帧 UI/Raster 为 4.20/10.10、1.59/5.69ms，之后 UI 多数约 0.2～0.4ms，Raster 逐步回落到约 1.4～4.4ms。

当时共挂载 28 张视频卡：推荐 10、视频动态 10、稍后再看 8，包含视口外缓存行。全部 32 次切换的卡片 Element 身份集合不变。真实 Repository 没有额外埋读取计数，不能将 fake 仓储的“各 1 次”写成真实网络请求实测。

数据：`profile-real.json`、`real-summary.json`。

### 深滚动与快速切换

- 推荐页手动滚动后稳定偏移为 1277.0625px，等待图片恢复，再按同一流程测 32 次。推荐挂载卡片为 12 张；返回推荐的 UI/Raster 峰值中位数为 **4.23/11.76ms**，Raster 最大 12.48ms。其他两张卡片列表仍在顶部。全部切换维持卡片身份和各自列表偏移；这不代表三页都做了长列表深滚动。
- 三个卡片入口以约 80ms 间隔连续切换 24 次，记录 150 帧，UI 最大 6.00ms、Raster 最大 10.07ms，Raster 有 5 帧超过 8.33ms，没有超过 16.67ms。最终仍回到已滚动的推荐页。该探针使用回调和诊断扩展，不等同于真实触摸输入延迟测量。

数据：`profile-real-scrolled.json`、`scrolled-summary.json`、`profile-real-rapid.json`。

### 分段时间线

另采四次预热路由切换的短时间线，省去每次切换前后的 Element 树快照，以减少诊断遍历和分配干扰。短记录包含 66 帧和 14391 个事件，避免把较长记录的环形缓冲尾段当成完整过程。

| 时间线阶段 | 本段最大事件耗时 ms | 解释 |
| --- | ---: | --- |
| BUILD | 1.32 | Widget 构建不是本段最大的单项 |
| LAYOUT | 2.89 | 主要恢复帧仍有布局工作 |
| PAINT | 1.05 | Dart 记录绘制指令的成本 |
| SEMANTICS | 4.07 | Windows UI 自动化已启用语义，需要单独看待 |
| GPURasterizer::Draw | 10.06 | 光栅/提交路径仍明显高于多数 UI 子阶段 |
| ReactorGLES::FlushOps | 8.31 | 渲染线程提交操作的耗时，不能直接当 GPU 硬件执行时间 |

阶段事件可能嵌套、分属不同线程，不能相加成一帧时间，也不能按表直接给各阶段分配 CPU 百分比。Dart CPU 样本数量很少，不据此给业务函数做耗时百分比排名。

该记录的 RasterCache 计数中 LayerCount/PictureCount 均为 0。说明虽然存在 RepaintBoundary，这段采样没有观察到整页栅格缓存命中；不能把重绘隔离等同于整页图片已缓存，也不能据此断言 Flutter 所有缓存失效。图片解码缓存是另一个概念。

Windows 语义保护见 [BiliWidgetsBinding](../../lib/core/presentation/bili_widgets_binding.dart)：它需要核对当前可达语义树、过滤子边并在保留节点重新连接时补发数据。整页位移期间也可能有语义几何更新。**当前只确认 SEMANTICS 整段的成本，没有单独量化 guard 的占比，不能直接移除这层崩溃保护来换速度。**

数据：`timeline-real-clean.json`。较早的 `cpu-real.json` 带逐次树快照且记录较长，仅作探索，不作为阶段排名依据。

## 可优化组件与建议顺序

### 1. 优先验证恢复帧与整页合成

位置：[工作区外壳](../../lib/app/shell.dart)（调查时为 `PrimaryNavigationTransition`）、[VideoCardCover](../../lib/shared/ui/video_card_cover.dart)、[封面绘制](../../lib/shared/ui/video_card.dart)。

先做同一组图片、同一滚动位置的消融对照：正常平移／禁用平移，完整封面／静态简化封面，图片已就绪／恢复中。分别记录首两帧、后续动画帧、Raster 和输入到首个可见变化的延迟。当前证据优先指向进入时的图片页面恢复与渲染准备，尚不能确定是哪个装饰或渲染操作占主导。

若禁用平移仅降低后续动画帧而首帧不变，应继续处理恢复突发工作；若简化封面稳定降低 Raster，再逐项检查圆角裁剪、渐变、文字和合成层。保留现有不透明设计，不增加整页淡入或盲目堆叠 RepaintBoundary。动效调整应有产品体验对照，不能用延长动画掩盖阻塞。

### 2. 缩小静止封面和悬停组件的活动订阅

位置：[VideoCardCover.didChangeDependencies](../../lib/shared/ui/video_card_cover.dart)、[ScrollAwareHoverRegion.didChangeDependencies](../../lib/shared/ui/scroll_aware_hover_region.dart)。

每张普通卡有外层卡片悬停区域和作者区域等活动订阅；封面也监听 WorkspaceActivity/TickerMode。即使没有指针、焦点、预览或待完成操作，这些后代仍在进出时更新。应将活动控制与静态封面内容分开，尽量让只有实际悬停/预览/写操作的组件监听需要及时处理的活动变化，静止绘制子树保持稳定。

必须保留：隐藏时立即关闭预览、停止写入结果提示，滚动时抑制悬停，键盘焦点和外接鼠标/触笔行为，以及账号变化和取消代次。不能因为设备窄就永久禁用桌面/外接指针交互。当前计数证明可缩小更新面，尚无修改后的帧耗时收益。

### 3. 减少图片恢复中的重复配置与状态更新

位置：[AppNetworkImage](../../lib/shared/ui/app_network_image.dart)、[AppCoverImage](../../lib/shared/ui/app_cover_image.dart)。

- `AppNetworkImage.build` 会解析和归一化 URL、建立等价 Provider 配置。可按缓存实例、URL、解码尺寸复用这些计算，活动变化本身不必重建源配置。
- 隐藏、重新激活、帧后可见性检查可能分别触发图片 build。可区分加载需求状态和已就绪帧的显示状态，在实际显示未变时避免额外 setState。
- 已有就绪流快路径和帧 lease，优先核对首次挂载就加载成功的图片与缓存后重新挂载图片，避免两条实现路径发生不必要的解析/监听恢复差异。

不能取消可见性和请求需求管理，也不能无限保留滚出列表的像素。必须覆盖嵌套视口、分页拖动、窗口缩放、缓存开关、图片错误/动画、队列容量、账号 scope 与重新挂载。AppImageCache 的 64MiB/256 项是解码 LRU 容量，不等于整个进程图片内存的硬上限；活跃流 lease、引擎资源等另有生命周期。

### 4. 稳定页面脚手架，避免把活动变化变成内容工厂更新

位置：[HomeChannelSwipe](../../lib/features/feed/presentation/home_channel_swipe.dart)、[RetainedTabView](../../lib/shared/ui/retained_tab_view.dart)、[AccountScreen](../../lib/features/auth/presentation/account_screen.dart)、[PagedScrollViewport](../../lib/shared/ui/paged_scroll_viewport.dart)、[路由组合](../../lib/app/router.dart)。

- HomeChannelSwipe 订阅活动状态，更新时会重新建立分页器配置。RetainedTabView 的配置缓存包含整个 widget 身份，祖先传来新 widget 时仍会重建页包装层。可进一步把分组/分页内容和活动门控分离，但不能删掉当前对父配置更新的响应。
- 返回我的时，路由创建新的 contentBuilder，AccountTabContent 会刷新 `_content`；账号资料栏和标签脚手架也重新构建。可按真实账号/列表配置拆分订阅，稳定未变资料与已访问列表的包装层。
- PagedScrollViewport 的活动更新会执行 builder，重新描述 CustomScrollView/RefreshIndicator 等脚手架；列表 sliver 虽已缓存，外壳仍有工作。可让活动/分页检查持有稳定 child，而内容订阅负责数据更新。

这些优化不能只缓存回调地址：同一 State 的方法可读取新字段，不同闭包也可能表达相同配置。需要覆盖登录态、主题/字号、回调新鲜度、刷新、分页、快速切页与滚动位置，不恢复已经修复的嵌套 Provider family 作用域问题。

### 5. Windows 语义与悬停作为独立平台专项

同一构建分别在无 UI 自动化/读屏、启用 UIA/读屏时测量，定位语义树规模、每帧几何更新和 guard 开销。确认占比后再减少无变化语义工作，保留无障碍信息和现有树连通保护。Windows 窄窗口仍有鼠标悬停、桌面字体和平台渲染差异，不等于 Android 真机。

窗口启动或切回后，静止鼠标落在卡片上可以启动默认开启的 Windows 悬停预览。本轮启动和手动滚动时观察到 native engine 创建日志，常规采样前已将鼠标移到底栏。因此后续还应把“纯切页”和“切页后指针命中卡片触发预览”分别测量，不能把原生预览创建混进移动设备切页结论。

## 容量与不建议的改动

- 工作区 16 页上限不等于只保留 16 个内部列表；已访问根、频道组、账号子页和 HomeContent 查询仍各自保留状态。HomeContent 最多保留 20 个已访问查询，视频动态数据上限 200、收藏 500；推荐完整已加载数据的增长是另一类长期内存议题。
- 当前懒列表不会因加载 300 条就挂载 300 张卡。不要将视频卡全部 AutomaticKeepAlive、扩大 cacheExtent、无限增加图片缓存或预建所有标签作为默认方案。
- 不用切页销毁列表、清缓存、重拉首屏来“释放压力”；这会损失状态并增加冷恢复成本。
- 本轮没有证据支持改播放器、弹幕 Ticker、HTTP 协议、数据库、导航所有权或依赖版本来解决这几页的热切换。

## 验证边界与后续验收

- 真实外壳约束/滚动保留、RetainedTabView 活动、图片可见性、一级过渡及本轮计数探针共 30 项定向测试通过；另一次无封面计数探针通过。文档相对链接和 `git diff --check` 通过。本轮没有业务源码改动，未执行完整根应用/四包检查或 mux 原生测试。
- 独立 Windows Debug 诊断构建启动成功，DTD 热重载成功，运行时错误查询为空。Debug 仅作工具与入口检查，不参与性能结论；结束关闭本轮诊断进程。
- 当前两次 Windows Profile 构建成功，真实页面、内存页面、深滚动返回与快速切换采样完成。没有使用 Debug 帧耗时下性能结论。
- Windows 自动化后，最初采用普通 WidgetsFlutterBinding 的离线诊断进程出现 AXTree 更新错误并断开；该次后续 CPU 采样作废。随后诊断入口改用生产 BiliWidgetsBinding；真实页面采样完成。不能把诊断 harness 缺少生产保护的故障报告成当前应用的新崩溃。
- 原始数据保存在本机忽略目录 `artifacts/navigation-switch-20261030/`，只采组件类型、数量、匿名 Element 身份、滚动偏移与帧数据；没有记录账号凭据、图片 URL、视频标题或原始网络响应。
- Android/iOS/macOS 未新构建或实机采样。没有测试 120Hz Android、冷启动/慢 CDN、三页全部深滚动、长期内存压力、系统后台恢复和触摸输入到实际显示的完整链路。
- 本机未复现用户描述的明显长停顿；当前结果只缩小热点范围。后续优化应以同素材前后对照和目标设备验收为准，不能将 Windows 60Hz 下未超预算写成“卡顿已经解决”。
