# 全局桌面滚轮平滑过渡

初版日期：2026-10-05；连续输入修正及速度驱动改版：2026-10-06。工具链：Flutter 3.47.6 / Dart 3.13.5。

## 行为与接入

根应用的 `MaterialApp.router.scrollBehavior` 使用共享 `SmoothScrollBehavior`，为普通桌面滚动区域增加连续的滚轮过渡。按用户反馈将 position-target spring 改为 velocity-based smooth scrolling，仍复用 Flutter 的 `ScrollActivity` 生命周期，没有新增设置项、依赖或持久化字段。首页、搜索、动态、用户空间、评论、设置、选集以及继承应用滚动行为的弹窗使用同一实现，列表保留自己的控制器、滚动物理模型和 PageStorage 位置。

2026-10-06 直播聊天顶部的 SC 气泡列表单独开启 `horizontalMouseWheel`：普通鼠标滚轮的纵向输入在横向 delta 为零时映射为左右滚动，原生横向输入和 Shift 轴切换仍沿用原语义。该选项默认关闭，仅在 SC 气泡区域启用；减少动画模式仍可横向滚动，但立即更新位置。底部 3 逻辑像素的滚动条在内容溢出时常显，可用鼠标拖动；列表与滚动条共用独立控制器，由页面释放，关闭自动滚动条避免重复绘制。再次点击已展开的 SC 气泡收起详情，移除原来的关闭按钮。

同方向连续输入累积驱动速度，显示速度平滑跟随，使用同一个帧时钟，不重新启动 Ticker 或改变当前显示位置/速度。停止输入后速度自然衰减；反向输入清除原方向的驱动和显示速度，下一帧开始朝新方向移动。每帧积分位移并限制在列表边界内，到边界立即丢弃余下动量；内容扩展时只有尚未到边界的滚动继续，内容缩短则在新边界停止。内层列表先处理滚轮，到达边界后允许外层接管；子控件已经认领的滚轮信号不交给平滑层。Shift 的轴切换及反向列表保持 Flutter 的原有语义。Ctrl/Alt/Meta 组合键、触摸拖动、trackpad 类型的滚轮信号和原生 PanZoom 手势沿用原有处理；不根据滚轮 delta 猜测设备。操作系统若将触控板报告成 mouse 类型信号，会按鼠标滚轮处理，真实设备表现仍需用户确认。

刷新、回到顶部、滚动条拖动和手势操作通过 ScrollPosition 的活动生命周期取消原来的滚轮动量。工作区隐藏、TickerMode 禁用或系统请求减少动画时停止当前平滑过渡；恢复页面不继续旧动量。每个活动滚动区域只有一个本地 Ticker，使用 Scrollable 自身的 vsync，活动结束或页面关闭时释放。不添加全局逐帧状态，也不替换播放和网络会话。

## 实现依据与限制

Flutter 的默认 [pointerScroll](https://api.flutter.dev/flutter/widgets/ScrollPositionWithSingleContext/pointerScroll.html) 直接改变位置；只调整 ScrollPhysics 不能增加滚轮动画。实现利用 [ScrollBehavior](https://api.flutter.dev/flutter/widgets/ScrollBehavior-class.html) 装饰入口，在本列表的原生滚轮信号监听之前注册平滑处理，但保留后代命中目标和变换顺序，让 [PointerSignalResolver](https://api.flutter.dev/flutter/gestures/PointerSignalResolver-class.html) 正常仲裁子控件与嵌套滚动。使用公开的 render/hit-test 接口，不修改 SDK；这一接入位置按固定 SDK 验证，升级 Flutter 时须复测信号顺序。

初版为每次输入调用 `animateTo`，使用 160 毫秒 `easeOutCubic`。新增行为测试在旧实现上复现：第二次输入立即改变速度；持续以 8 毫秒或 16 毫秒间隔输入时，下一帧位置与前一帧相同。原有测试仅验证最终位置，未发现这两种接续问题。

前一版由 Flutter 的 [ScrollSpringSimulation](https://api.flutter.dev/flutter/physics/ScrollSpringSimulation-class.html) 计算位置、速度及终止条件，采用 mass=1、stiffness=1024、damping=64 的临界阻尼弹簧。静止状态输入 120 逻辑像素时，数学响应约 210 毫秒到达 99%；该模型仍按目标位置追赶，用户反馈真实页面滚轮视觉上存在跳变，因此本轮替换。

当前模型仅保存驱动速度 `u` 和显示速度 `v`，不保存目标位置：滚轮输入令 `u += delta / 0.075s`，同向输入保留 `v`；随后按 `du/dt = -u/0.075s`、`dv/dt = (u-v)/0.020s` 推进，位移为显示速度的积分。首次试用为 90 毫秒衰减和 25 毫秒跟随，用户确认方向正确，但感觉过于平滑；据此适度调整为 75 毫秒衰减和 20 毫秒跟随，缩短起步延迟和收尾拖行。它们均为本项目试验参数，不是官方客户端测量值。未触发限速/边界时总滚动距离保持不变。使用解析积分，8/16/32/96 毫秒帧间隔下相同时间的位移与速度一致，不以逐帧固定插值比例推进，也不反复建立动画或按位置误差补追。

未触发限速/边界时，单次输入的总积分位移等于滚轮 delta。驱动速度限制为 24,000 逻辑像素/秒，异常大 delta 和瞬时密集输入不会无限积累；显示速度也受该上限约束。剩余积分位移小于 0.01 逻辑像素且速度小于 5 逻辑像素/秒时，一次积分完不足 0.01 像素的尾部并释放活动，避免多次独立输入积累截断误差。ScrollPosition 正常发送开始/更新/结束通知，分页和 PageStorage 继续工作；替换滚动活动时框架负责释放旧 Ticker。

PageView、文本输入区域等自行覆盖滚动装饰的控件，以及不实现 ScrollActivityDelegate 的自定义位置，保留其原有行为。Android/iOS 保留平台默认滚动。macOS/Linux 分支尚未在实际设备验证。

此前使用 Computer Use 对本机官方哔哩哔哩与旧版 Bili Lite 做过短滚轮输入，但静态截图无法可靠量化逐帧平滑度，长滚动采样又混入用户操作。本项目参数不是测得的官方客户端参数，也不构成性能或等效手感结论。Widget 测试验证接续算法，无法排除真实列表图片解码、布局或绘制造成的掉帧；如仍卡顿，应使用 [Flutter profile 性能采样](https://docs.flutter.dev/perf/ui-performance) 分别检查 UI 和 raster 帧耗时。最终手感由用户在新版 Windows 窗口确认。

## 验证

- 2026-10-06 参数微调：用户试用确认 90ms/25ms 的速度驱动滚动方向正确，但认为过于平滑；衰减调为 75ms、跟随调为 20ms，积分模型与未限速/未到边界时的总距离不变。29 项共享滚动及共 92 项定向回归通过，日志 `artifacts/velocity-scroll-tuning-targeted.log`。`tool/check.ps1 -SkipPub` 的根格式/分析通过，根测试仍为 688/700 通过、同样的 12 项已有失败，与前轮失败名称对比没有新增；三个包独立格式/分析及 227/16/21 项测试全部通过。日志 `artifacts/velocity-scroll-tuning-check.log`、`artifacts/velocity-scroll-tuning-packages.log`。新参数的实际手感待用户再次确认。
- 参数微调后的 Windows Release 构建通过，日志 `artifacts/velocity-scroll-tuning-windows-build.log`；已正常关闭上轮预览进程并启动 `build/windows/x64/runner/Release/bilisail.exe` 供比较，未更新 MSIX 安装。仅修改 Dart 滚轮参数，没有原生播放改动；Android/macOS 实机及帧耗时未测。
- 2026-10-06 速度驱动改版：共享滚动 29 项测试和共享分页/首页/直播页面共 92 项定向回归通过。新增独立输入累计位移、速度渐增/自然衰减、反向逐帧不残留正向运动、8/16/32/96ms 积分一致、异常大输入与速度上限、内容扩展保留动量、边界丢弃动量（含 BouncingScrollPhysics）；日志 `artifacts/velocity-scroll-targeted.log`。真实鼠标手感和 UI/raster 帧耗时尚未验收。
- 本轮 `tool/check.ps1 -SkipPub`：根应用格式/静态分析通过，700 项测试中 688 通过、12 失败。将共享滚动临时恢复为原 position-target spring 并保留其他现有修改，三份失败测试文件重跑后同样复现全部 12 项失败：工作区编辑框 Ctrl+W 旧预期、播放器测试缺少 AppNoticeHost、视频/合集测试缺少 AuthRepository 注入。未修改这些已有代码或测试；日志 `artifacts/velocity-scroll-check.log` 和 `artifacts/velocity-scroll-baseline.log`。检查脚本因根测试失败未继续子包，因此独立完成三个包的格式、分析和测试：bili_api 227、bili_player 16、bili_danmaku 21，全部通过；日志 `artifacts/velocity-scroll-packages.log`。
- 本轮 `flutter build windows --release --no-pub` 通过，输出 `build/windows/x64/runner/Release/bilisail.exe`，日志 `artifacts/velocity-scroll-windows-build.log`。已启动该构建供用户比较滚轮手感；未更新现有 MSIX 安装。构建/启动成功不等于真实鼠标操作验收或帧耗时采样，Android/macOS 实机仍未测。
- 2026-10-06 SC 交互修正：旧实现的普通鼠标滚轮测试复现横向位置停在 0；修正后直播页面与共享滚动的 33 项定向测试通过，覆盖正反向滚轮、原生横向输入、末尾气泡展开／再次点击收起、底部拖动条、减少动画及侧栏隐藏后位置／播放器保留。`tool/check.ps1 -SkipPub` 完整通过：根应用 599、bili_api 206、bili_player 16、bili_danmaku 19，共 840 项测试，四处格式与静态分析通过；日志 `artifacts/sc-scroll-check.log`。Windows Release 构建通过，输出 `build/windows/x64/runner/Release/bilisail.exe`，日志 `artifacts/sc-scroll-windows-build.log`。该轮未进行真实直播窗口的鼠标操作验收，Android/macOS 实机未测。
- 22 项定向 Widget 回归通过：保留初版全部覆盖，新增速度连续、8ms/16ms 连续输入无停帧、活动中减少动画/TickerMode 禁用、trackpad 接管、内容缩短、回顶部动画接管和移除滚动装饰的生命周期验证；触摸拖动在活动中的滚轮动画上验证。
- 2026-10-06 `tool/check.ps1 -SkipPub` 通过：根应用 597、bili_api 206、bili_player 16、bili_danmaku 19 项测试，共 838 项；四处格式检查和静态分析通过。
- 2026-10-06 `flutter build windows --release --no-pub` 通过，输出 `build/windows/x64/runner/Release/bilisail.exe`；已启动此构建供用户确认鼠标手感。仅构建/启动和 Widget 行为验证，不将其计为真实设备帧耗时采样。
- Windows 鼠标实际手感由用户验收；Android/macOS/Linux 的实际设备体验未测。没有修改原生播放实现。
