# 桌面滚轮动画、参数与嵌套兼容

日期：2026-11-15。工具链：Flutter 3.47.6 / Dart 3.13.5。

## 行为与设置

“设置 → 外观 → 滚动动画”提供“原有弹簧”“Chromium 平滑”和“多平台平滑”。默认仍为 Chromium，缺失、错误类型或未知模式回退到 Chromium；原有两个有效选项继续保留。Chromium 可选 `EaseInOut` / `Impulse`，默认 `EaseInOut`，直接使用 `scroll_animator` 的对应算法，不尝试复刻原弹簧曲线。

| 设置 | 默认值与范围 | 作用 |
| --- | --- | --- |
| Chromium 动画类型 | EaseInOut / Impulse，默认 EaseInOut | 仅 Chromium 模式生效 |
| 滚动距离倍率 | 默认 1×，0.25–4×，步长 0.05 | 三种模式均生效，仅缩放鼠标滚轮 |
| 动画时长倍率 | 默认 1×，0.25–3×，步长 0.05 | Chromium／多平台模式生效，大于 1 放慢运动，不改变最终距离 |
| 原有滚轮阻尼比 | 默认 1.3，0.5–2 | 仅弹簧模式生效 |

多平台模式保留上游的基础速度 2、时长 380 毫秒、`Curves.easeOutQuart`；例如距离倍率 1× 时，120 逻辑像素输入最终移动 240 逻辑像素。设置页明确说明基础值，时长／距离倍率叠加于其上。倍率不缩放触摸、触控板或滚动条拖动；系统减少动画时仍应用距离倍率，但立即滚到目标，不播放动画。

“恢复默认滚动参数”只重置新曲线及两个倍率，保留当前模式和已保存的弹簧阻尼；全局恢复默认仍恢复 Chromium／EaseInOut／两个 1×／阻尼 1.3。

原有弹簧仍采用 Flutter `ScrollSpringSimulation`，mass=1、stiffness=1600，阻尼默认 1.3。阻尼滑块和恢复默认按钮仅在弹簧模式显示；原 `wheelDampingRatio` 数值不修改，切回弹簧时继续使用，Chromium 模式不受其影响。

切换沿用设置控制器的立即更新、串行保存和保存失败回退。模式字段保存 `spring` / `chromium` / `multiplatform`；新增 `chromiumScrollCurve`、`wheelScrollDistanceMultiplier`、`wheelScrollDurationMultiplier`，`preferences.v1` JSON 快照从 51 升至 52（首轮模式开关为 50 → 51）。不修改 SQLite 表结构，数据库 schema 仍为 3。旧快照缺失新字段、类型错误或非有限数值分别回退到 EaseInOut／1×／1×，有限倍率越界时夹紧到上述范围；保留有效旧模式、阻尼和其他设置。

## 嵌套滚动和标签状态

- 主应用与独立播放窗口在 Navigator／弹窗上方传入相同的 `SmoothScrollScope`，局部横向列表也继承模式、曲线及倍率。
- 保留各列表的 `ScrollController`、`ScrollPosition`、PageStorage 与既有分页；不替换 `HeaderScrollController` 或 `NestedScrollView` 的协调位置。
- 共享 `ScrollActivity` 负责输入仲裁、帧时钟、取消和边界，动画计算按模式交给 Flutter 弹簧、`scroll_animator` 或多平台兼容副本的公开插值。Chromium 同方向连续输入通过公开的 `ScrollAnimation.updateTargetValue` 更新目标；多平台模式按上游 `animateTo` 语义重建从当前位置到累计目标的插值。反向输入舍弃旧动量后建立新曲线。
- 折叠头部仍与正文共用合并距离，先收起头部再滚正文，回到正文顶部后再展开头部；内层到边界后继续允许外层接管。
- 模式或当前模式适用的参数切换停止旧动画，保留当前控制器和位置；隐藏标签停止动画，不在恢复可见时续播旧动量。触摸、触控板、Shift 换轴、减少动画和滚动条拖动继续沿用原有适配。
- 保留每区域单一 Ticker、按事件时间排队和每帧一次位置提交；队列最多 64 项，待滚距离最多 1,500 逻辑像素。不引入全局逐帧状态。

没有直接替换为依赖的 `AnimatedScrollController`：它创建自己的位置，不能覆盖现有 `NestedScrollView` 协调器创建的位置。也不使用依赖 `AnimatedScrollActivity` 的墙上时钟目标更新，而在既有帧时钟上调用其公开动画接口，避免改变原有取消、嵌套与标签归属。应用仅导入各包的公共入口，不从应用访问 `src/` 或修改 Pub 缓存；Chromium 算法仍由锁定包提供。

时长倍率通过统一缩放输入／采样时间实现，通知速度按倍率反向换算，避免连续输入时出现两套时钟。未触及距离限幅的时间戳输入分别在 8／16／32／96 毫秒帧分组与 `timeDilation` 1／2 下对照；极大输入另验证队列及距离限幅，不将限幅后的丢弃距离算作完整输入交付。

## 来源与许可

固定 [scroll_animator 0.3.0](https://pub.dev/packages/scroll_animator/versions/0.3.0)，上游 [kszczek/scroll_animator](https://github.com/kszczek/scroll_animator)。Pub 归档 SHA-256 为 `6b8b0f03b7eb47cd014a8aecf69e1504257da3af2f4b408fe3cbba4513814e5c`，根锁文件记录该值。包仅依赖 Flutter，无额外原生二进制；BSD-3-Clause，原 LICENSE 由 Flutter notices 收集。

包内两个 Chromium 移植文件的原始 BSD-3-Clause 版权头另保留为 `assets/licenses/scroll_animator_chromium.txt`，通过资产清单和 `LicenseRegistry` 随应用许可证页分发；不只保留包作者的根 LICENSE。PureLive 仅用于核对公开的依赖采用和接入方式，没有复制其应用源码或资源。

多平台模式采用 [smooth_scroll_multiplatform 1.0.8](https://pub.dev/packages/smooth_scroll_multiplatform/versions/1.0.8)（MIT）的仓库内兼容副本 `1.0.8+bilisail.1`，位置为 [third_party/smooth_scroll_multiplatform](../../third_party/smooth_scroll_multiplatform/UPSTREAM.md)。上游归档 SHA-256 为 `c3b8998c3c70eaf480e8ce16608ffc80c0aac1722697a08992fde10e1c97a742`；根依赖显式固定本地版本，源码随仓库追踪，不依赖相邻仓库或修改 Pub 缓存。

上游只有整块 `DynMouseScroll` 包装，要求使用其控制器并切换物理模型，无法直接保留嵌套位置。兼容副本保留其 MIT LICENSE 和列表包装实现，并新增公共 `SmoothScrollSimulation` / `SmoothScrollDefaults`，暴露与上游 `animateTo` 相同的插值及默认值；生产只使用该公开插值，累计目标、方向、边界和取消由既有适配器负责。通过真实上游包装的普通 `ListView` 连续两次滚轮对照验证插值位置一致。原始包装的 provider 不成为应用状态管理或业务服务入口；新包无原生二进制，`provider 6.1.5+1`／`nested 1.0.0` 及许可证由根锁文件和 Flutter notices 保留。

## 验证与边界

本轮动画／状态定向测试 63 项、设置定向测试 171 项通过，覆盖两种 Chromium 曲线的距离和时长采样、多平台上游对照、三模式嵌套／标签状态、参数切换取消、减少动画和触控板、设置保存／重载／失败回退、旧快照／非法值和恢复默认。静态分析无问题。日志为本地忽略目录 `build/scroll-options-*.log`。检查脚本额外覆盖兼容副本 `lib` 的格式检查，根静态分析和根组件测试覆盖该依赖。

### 本轮全量检查

`tool/check.ps1 -EnforceLockfile` 完整通过，覆盖五份锁文件可复现解析、根应用／四个包及兼容副本的格式检查、静态分析、打包边界脚本和离线测试；三种模式的时间戳回归计入根应用测试。模式扩展沿用共享协调，不把不同动画的速度曲线强行断言为同一条曲线。

| 测试范围 | 通过 | 跳过 |
| --- | ---: | ---: |
| 根应用 | 5,628 | 13 |
| bili_api | 997 | 0 |
| bili_player | 333 | 3 |
| bili_danmaku | 161 | 0 |
| bili_mux | 5 | 10 |

`BILI_MUX_LIBRARY` 未配置，10 项 mux 原生用例跳过，不能视为原生集成通过。另逐字比对保留的 Chromium 版权文本与锁定包内原始头部，内容一致；新包及传递依赖的 MIT LICENSE 已核对。文档相对链接与 `git diff --check` 通过。

按用户要求不构建、不启动应用或执行设备／性能验收；实际鼠标和触控板手感由用户自行构建后确认。组件测试不能证明真实 GPU 帧耗时和跨平台输入设备表现。
