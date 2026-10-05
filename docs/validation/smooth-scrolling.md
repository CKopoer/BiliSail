# 全局桌面滚轮平滑过渡

日期：2026-10-05。工具链：Flutter 3.47.6 / Dart 3.13.5。

## 行为与接入

根应用的 `MaterialApp.router.scrollBehavior` 使用共享 `SmoothScrollBehavior`，为普通桌面滚动区域增加 160 毫秒的 `easeOutCubic` 滚轮过渡。没有新增设置项、依赖或持久化字段。首页、搜索、动态、用户空间、评论、设置、选集以及继承应用滚动行为的弹窗使用同一实现，列表保留自己的控制器、滚动物理模型和 PageStorage 位置。

同方向连续输入累积目标，反向输入从当前已显示的位置计算，目标始终限制在列表边界内。内层列表先处理滚轮，到达边界后允许外层接管；子控件已经认领的滚轮信号不交给平滑层。Shift 的轴切换及反向列表保持 Flutter 的原有语义。Ctrl/Alt/Meta 组合键、触摸拖动、trackpad 类型的滚轮信号和原生 PanZoom 手势沿用原有处理；不根据滚轮 delta 猜测设备。操作系统若将触控板报告成 mouse 类型信号，会按鼠标滚轮处理，真实设备表现仍需用户确认。

刷新、回到顶部、滚动条拖动和手势操作可以取消原来的滚轮目标。工作区隐藏、TickerMode 禁用或系统请求减少动画时停止当前平滑过渡；恢复页面不继续旧目标。动画由当前 ScrollPosition 驱动，不添加全局逐帧状态或额外 Ticker，也不替换播放和网络会话。

## 实现依据与限制

Flutter 的默认 [pointerScroll](https://api.flutter.dev/flutter/widgets/ScrollPositionWithSingleContext/pointerScroll.html) 直接改变位置；只调整 ScrollPhysics 不能增加滚轮动画。实现利用 [ScrollBehavior](https://api.flutter.dev/flutter/widgets/ScrollBehavior-class.html) 装饰入口，在本列表的原生滚轮信号监听之前注册平滑处理，但保留后代命中目标和变换顺序，让 [PointerSignalResolver](https://api.flutter.dev/flutter/gestures/PointerSignalResolver-class.html) 正常仲裁子控件与嵌套滚动。使用公开的 render/hit-test 接口，不修改 SDK；这一接入位置按固定 SDK 验证，升级 Flutter 时须复测信号顺序。

PageView、文本输入区域等自行覆盖滚动装饰的控件保留其原有行为。Android/iOS 保留平台默认滚动。macOS/Linux 分支尚未在实际设备验证。

此前使用 Computer Use 对本机官方哔哩哔哩与旧版 Bili Lite 做过短滚轮输入，但静态截图无法可靠量化逐帧平滑度，长滚动采样又混入用户操作。因此 160 毫秒是本项目的初始手感参数，不是测得的官方客户端参数，也不构成性能或等效手感结论。最终手感由用户在新版 Windows 窗口确认。

## 验证

- 13 项定向 Widget 回归通过：中间位置、连续输入/反向响应、嵌套边界传递、子控件信号优先、trackpad/减少动画、弹窗及隐式控制器、禁用滚动/移动平台、触摸/滚动条拖动、Shift 横向滚动、反向列表/边界、程序化跳转/关闭、隐藏/恢复和自动分页。
- `tool/check.ps1 -SkipPub` 通过：根应用 483、bili_api 154、bili_player 16、bili_danmaku 10 项测试，共 663 项；四处格式检查和静态分析通过。
- Windows 构建与启动结果待本轮执行后记录。
- Windows 鼠标实际手感由用户验收；Android/macOS/Linux 的实际设备体验未测。没有修改原生播放实现。
