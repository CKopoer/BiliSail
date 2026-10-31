# 连续鼠标滚轮的时间衔接

日期：2026-10-31。Flutter 3.47.6 / Dart 3.13.5。基线为卡片优化提交 `b1d2171`；本轮进一步修正共享滚轮动画。既有设置和接入范围见[平滑滚动](smooth-scrolling.md)，卡片绘制结果见[上一轮记录](card-scroll-lifecycle-2026-10-31.md)。

## 问题与实现

[共享滚轮](../../lib/shared/ui/smooth_scroll_behavior.dart)已经使用一个 Ticker、同向保留速度的官方 ScrollSpringSimulation。问题在输入时刻：旧实现用上一帧缓存的位置/速度重新创建模拟器，并把开始时间设为上一帧。因此两帧之间的输入被提前到上一帧，第一帧又可能等待 Ticker 的时间归零；不同帧分组和输入相位会改变中途位移，最终距离相同仍可能顿挫。

新增[时序回归](../../test/shared/ui/wheel_scroll_timing_test.dart)在旧实现上先复现三个失败：固定输入时刻，96ms 时 8ms/16ms 分帧的偏移相差 12.928px；把第二次输入从 17ms 改到 31ms，旧实现两者的下一帧位置却完全相同。日志 `artifacts/wheel-timing-baseline.log`。

本轮改动：

- 将 PointerScrollEvent.timeStamp 对齐到 SchedulerBinding.currentSystemFrameTimeStamp 与当前 Ticker 时间。Flutter 自身手势重采样同样使用这个未经 epoch/timeDilation 调整的帧时间对齐事件；适配层再换算动画时间，保留调试时间缩放。
- 同向新输入到达时，按其真实时刻推进旧弹簧，再衔接速度、剩余距离和尚未绘制的位移。最终只在帧回调中一次更新 pixels，不在输入回调里补跳位置。
- 事件可能在 vsync 之后、动画回调之前送达。晚于当前帧的输入留到相应帧处理，避免对模拟器求负时间以及提前提交位移。队列每个活动最多 64 项；极密输入合并同向队尾、保留反向最新意图，剩余距离仍受 1500px 上限约束。
- 没有时间戳时沿用帧时钟；迟到/乱序事件不倒退已经绘制的时间。反向或弹性回弹接管仍清除旧意图。到边界丢弃旧动量，等待中的后续输入可以继续独立处理，分页扩展不会复活撞边的旧距离。
- 沿用现有弹簧 mass=1、stiffness=1600，默认阻尼 1.3 和已保存的 0.5–2.0 选择；设置、SQLite 和快照版本未变。信号仲裁、嵌套边界、Shift 换轴、触摸/触控板、减少动画、PageStorage 和隐藏页面停止规则保留。没有新增 Timer、逐帧 Provider 或额外 Ticker；释放活动同时清空待处理输入。

## Windows Profile 对照

[探针](../../tool/validation/wheel_scroll_profile.dart)使用真实 FeedScreen + ScrollHeaderLayout、500 条固定视频、预热的 640×360 内存 PNG。窗口为 430px 两列和 1800px 六列，DPR 1，Windows Impeller / OpenGLES；主机 Ryzen 7 7700，未核实实际选用的 GPU。没有账号、CDN、磁盘图片缓存或原生悬停预览。

这次注入真正经过 Flutter 滚轮信号分发的 mouse PointerScrollEvent，未使用 animateTo 代替滚轮。每次 120px，分别按 70ms×32 次和 16ms×64 次发送，记录实际事件时间戳与每帧 pixels。原版与优化版在同一进程按原—新—新—原顺序运行，各条件两份样本；最终复测期间没有并发测试/构建。每组最终距离分别为 3840px、7680px。

轨迹参考为**同一弹簧对实际输入时刻的理想线性叠加响应**，在引擎帧时间采样；误差衡量动画时序，不是帧耗时或物理鼠标主观评分。晚到输入不回写已绘帧、结束容差等仍可能留下少量偏差。原始逐帧数据在 `artifacts/wheel-scroll-2026-10-31/paired.json`，[脱敏汇总](data/wheel-scroll-timing-2026-10-31.json)随代码提交。

| 场景 | 原版轨迹误差 P95 | 优化版轨迹误差 P95 |
| --- | ---: | ---: |
| 两列，70ms 间隔 | 42.363px | <0.001px |
| 两列，16ms 间隔 | 82.101px | <0.001px |
| 六列，70ms 间隔 | 41.603px | <0.001px |
| 六列，16ms 间隔 | 83.665px | 0.721px |

上表为两个样本 P95 的中位数；六列密集输入最大偏差由 100.804px 降至 2.973px。它说明跨帧输入的提前/滞后显著减少，不代表 GPU 性能提高相同比例。

| 场景 | UI P95 原→新 | raster P95 原→新 |
| --- | ---: | ---: |
| 两列，70ms | 1.777 → 1.649ms | 5.431 → 5.158ms |
| 两列，16ms | 1.921 → 1.893ms | 4.311 → 4.452ms |
| 六列，70ms | 4.474 → 4.644ms | 10.549 → 10.886ms |
| 六列，16ms | 7.572 → 7.589ms | 10.151 → 11.010ms |

没有建立 UI/raster 耗时改善结论；六列密集输入的 raster P95 此次上升 0.859ms，仍需后续关注。六列 70ms 两版各有 2 帧超过 16.67ms，其余条件没有；六列仍未全面满足 120Hz 的 8.33ms 预算。此次修正针对滚轮时序，图片/文字渲染掉帧仍是独立问题。

## 回归与边界

定向回归覆盖 8/16/32/96ms 分帧一致性、普通/顶部协调列表、timeDilation=1/2、首帧响应、迟到/缺失时间戳、vsync 后输入、200 次密集输入容量、反向/弹性回弹、边界后扩展及释放；并保留原有阻尼、轴切换、信号仲裁、触摸、隐藏页与悬停回归。定向 81 项通过，日志 `artifacts/wheel-timing-targeted.log`。

- `tool/check.ps1 -SkipPub` 完整通过：根应用 3774、bili_api 499、bili_player 105、bili_danmaku 145、bili_mux 5，共 4528 项通过；13 项 Windows 符号链接权限用例、10 项未配置 `BILI_MUX_LIBRARY` 的原生 mux 用例跳过。格式、静态分析与打包边界检查通过，日志 `artifacts/wheel-check.log`。
- Windows Debug 离线六列页面通过 computer-use 发送原生滚轮输入；实际收到正/反向各 500px，时间戳有效，最终位移对应为 +500/-500px，回到原位置后活动停止。回读数据已并入汇总 JSON；热重载成功，运行时异常查询为空，测试进程已退出。该输入注入验证与上面的 Profile 性能测量分开，不用 Debug 帧率作性能结论。
- Windows Profile / Debug 已重新构建普通 `lib/main.dart` 入口，日志 `artifacts/wheel-restore-profile.log`、`artifacts/wheel-restore-debug.log`。173 个本地文档链接、汇总 JSON 和 `git diff --check` 通过。

Android/iOS 不使用这段桌面滚轮动画；本轮没有 macOS/Linux 实机或用户物理鼠标长时间手感验收。
