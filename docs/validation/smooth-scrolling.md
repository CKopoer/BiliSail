# 全局桌面滚轮平滑过渡

初版日期：2026-10-05；连续输入修正：2026-10-06。工具链：Flutter 3.47.6 / Dart 3.13.5。

## 行为与接入

根应用的 `MaterialApp.router.scrollBehavior` 使用共享 `SmoothScrollBehavior`，为普通桌面滚动区域增加连续的滚轮过渡。复用 Flutter 内置 `ScrollSpringSimulation` 与 `ScrollActivity`，没有新增设置项、依赖或持久化字段。首页、搜索、动态、用户空间、评论、设置、选集以及继承应用滚动行为的弹窗使用同一实现，列表保留自己的控制器、滚动物理模型和 PageStorage 位置。

同方向连续输入累积目标并保留当前速度，使用同一个帧时钟，不重新启动 Ticker。反向输入清除原方向动量，从当前已显示的位置计算目标；目标始终限制在列表边界内，内容/视口变化后重新校正。内层列表先处理滚轮，到达边界后允许外层接管；子控件已经认领的滚轮信号不交给平滑层。Shift 的轴切换及反向列表保持 Flutter 的原有语义。Ctrl/Alt/Meta 组合键、触摸拖动、trackpad 类型的滚轮信号和原生 PanZoom 手势沿用原有处理；不根据滚轮 delta 猜测设备。操作系统若将触控板报告成 mouse 类型信号，会按鼠标滚轮处理，真实设备表现仍需用户确认。

刷新、回到顶部、滚动条拖动和手势操作通过 ScrollPosition 的活动生命周期取消原来的滚轮目标。工作区隐藏、TickerMode 禁用或系统请求减少动画时停止当前平滑过渡；恢复页面不继续旧目标。每个活动滚动区域只有一个本地 Ticker，使用 Scrollable 自身的 vsync，活动结束或页面关闭时释放。不添加全局逐帧状态，也不替换播放和网络会话。

## 实现依据与限制

Flutter 的默认 [pointerScroll](https://api.flutter.dev/flutter/widgets/ScrollPositionWithSingleContext/pointerScroll.html) 直接改变位置；只调整 ScrollPhysics 不能增加滚轮动画。实现利用 [ScrollBehavior](https://api.flutter.dev/flutter/widgets/ScrollBehavior-class.html) 装饰入口，在本列表的原生滚轮信号监听之前注册平滑处理，但保留后代命中目标和变换顺序，让 [PointerSignalResolver](https://api.flutter.dev/flutter/gestures/PointerSignalResolver-class.html) 正常仲裁子控件与嵌套滚动。使用公开的 render/hit-test 接口，不修改 SDK；这一接入位置按固定 SDK 验证，升级 Flutter 时须复测信号顺序。

初版为每次输入调用 `animateTo`，使用 160 毫秒 `easeOutCubic`。新增行为测试在旧实现上复现：第二次输入立即改变速度；持续以 8 毫秒或 16 毫秒间隔输入时，下一帧位置与前一帧相同。原有测试仅验证最终位置，未发现这两种接续问题。

现在由 Flutter 的 [ScrollSpringSimulation](https://api.flutter.dev/flutter/physics/ScrollSpringSimulation-class.html) 计算位置、速度及终止条件；共享接入层仅负责连续输入、帧时钟和边界协调。弹簧参数为 mass=1、stiffness=1024、damping=64（临界阻尼）；静止状态输入 120 逻辑像素时，数学响应约 210 毫秒到达 99%，不是设备性能测量。结束容差为距离 0.1 逻辑像素、速度 5 逻辑像素/秒，最终准确定位目标，不弹跳。ScrollPosition 正常发送开始/更新/结束通知，分页和 PageStorage 继续工作；替换滚动活动时框架负责释放旧 Ticker。

PageView、文本输入区域等自行覆盖滚动装饰的控件，以及不实现 ScrollActivityDelegate 的自定义位置，保留其原有行为。Android/iOS 保留平台默认滚动。macOS/Linux 分支尚未在实际设备验证。

此前使用 Computer Use 对本机官方哔哩哔哩与旧版 Bili Lite 做过短滚轮输入，但静态截图无法可靠量化逐帧平滑度，长滚动采样又混入用户操作。本项目参数不是测得的官方客户端参数，也不构成性能或等效手感结论。Widget 测试验证接续算法，无法排除真实列表图片解码、布局或绘制造成的掉帧；如仍卡顿，应使用 [Flutter profile 性能采样](https://docs.flutter.dev/perf/ui-performance) 分别检查 UI 和 raster 帧耗时。最终手感由用户在新版 Windows 窗口确认。

## 验证

- 22 项定向 Widget 回归通过：保留初版全部覆盖，新增速度连续、8ms/16ms 连续输入无停帧、活动中减少动画/TickerMode 禁用、trackpad 接管、内容缩短、回顶部动画接管和移除滚动装饰的生命周期验证；触摸拖动在活动中的滚轮动画上验证。
- 2026-10-06 `tool/check.ps1 -SkipPub` 通过：根应用 597、bili_api 206、bili_player 16、bili_danmaku 19 项测试，共 838 项；四处格式检查和静态分析通过。
- 2026-10-06 `flutter build windows --release --no-pub` 通过，输出 `build/windows/x64/runner/Release/bilisail.exe`；已启动此构建供用户确认鼠标手感。仅构建/启动和 Widget 行为验证，不将其计为真实设备帧耗时采样。
- Windows 鼠标实际手感由用户验收；Android/macOS/Linux 的实际设备体验未测。没有修改原生播放实现。
