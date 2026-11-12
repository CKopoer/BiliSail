# iOS 播放期间闪退：输出帧与原生生命周期

后续状态：已在原生受控回归中确认 Apple 输出的销毁确认过早、渲染通知无界积压和纹理被 Flutter 保留时上下文延后释放的问题，进一步修复并固定到 `302d60eedc55ca677e911e529569b1e14d8c2e7e`。实现、负向对照和 SDK 验证见文末；系统日志缺失，因此仍不把受控复现等同于现场退出原因已得到设备确认。

日期：2026-11-13（Asia/Shanghai）。反馈版本为当前 `1.2.9+5`，用户描述通常播放十几秒后退出、其他平台及 PiliPlus 未出现同类现象。[Issue #122](https://github.com/CKopoer/BiliSail/issues/122) 另有 iOS 16.6.1、巨魔安装、任意视频播放时随机退出而首页正常的报告。后续收到应用导出日志，复核见文末；仍没有系统原生异常堆栈或 JetsamEvent。

本轮定位并修复了可通过故障注入复现的 iOS 原生进程退出路径。尚不能把这些受控结果等同于现场十几秒闪退已经复现，也不能断言现场是内存耗尽、解码器错误或哪一种系统异常。

## 实际依赖与 PiliPlus 对照

- 修改前根应用和 `bili_player` 的八个媒体包均固定到个人 media-kit `eaae0273a93fbd23b24e3c951b99efd9b73e702b`；本轮以该提交隔离检出修改，没有改相邻仓库或 Pub 缓存。
- iOS 真机默认走 `TextureHW` → `TextureGLESContext` → CoreVideo/OpenGL ES → Flutter Metal 外部纹理。模拟器走软件输出，不能用模拟器正常替代真机路径验收。
- 相邻 PiliPlus 的当前锁文件将视频插件固定到 `bggRGjQaUbCoE/media-kit` 的 `85f0a69ea66b100882b27a3375c72e5155375343`，核心及 iOS 库插件为 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，不是本项目的媒体依赖组合。
- [PiliPlus 锁定视频源码](https://github.com/bggRGjQaUbCoE/media-kit/blob/85f0a69ea66b100882b27a3375c72e5155375343/media_kit_video/ios/Classes/plugin/TextureHW.swift) 在初始化或尺寸变化时建立三张输出缓冲并轮转。本项目此前为避免覆盖 Flutter GPU 尚在读取的旧帧，改为每次实际 render 分配独立输出图像，见[纹理交接记录](apple-linux-texture-handoff-2026-11-08.md)。因此两者触发分配、纹理创建和帧缓冲失败的频率不同；PiliPlus 无同类反馈不等于两套依赖的每条失败分支都安全。
- 本项目的原生点播包缓存已经设置前向 32 MiB、后向 32 MiB，直播前向 64 MiB、后向 0。本轮没有证据证明这些有界包缓存耗尽 iOS 内存，没有通过盲目调整缓存、关闭硬解或恢复旧纹理轮转掩盖问题。

## 已确认的缺陷

1. `OpenGLESHelpers.createPixelBuffer` / `createTexture` 仅 assert 返回码，再强制解包。在 Release 中 assert 不执行，CoreVideo 失败或返回空对象后仍会发生 Swift trap。
2. `TextureGLESContext` 遇到帧缓冲不完整会在同一帧内反复分配，四次失败后直接 `exit(1)`。受控注入 `GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT` 可使原实现退出码为 1；像素缓冲和纹理创建失败也可使原版测试进程异常结束。
3. 像素缓冲只声明 Metal 兼容，没有显式设置 OpenGL ES 兼容和 IOSurface 属性。[Apple QA1781](https://developer.apple.com/library/archive/qa/qa1781/_index.html) 说明非 IOSurface 支持的像素缓冲无法导入 OpenGL ES，并要求创建时设置 `kCVPixelBufferIOSurfacePropertiesKey`。Metal 兼容属性不能作为完整的跨 API 分配契约。
4. `TextureGLESContext.deinit` 对 CoreVideo 管理的 GL 纹理名调用 `glDeleteTextures`，但并没有释放 CoreVideo 包装对象。应该由 ARC 和纹理缓存管理该对象的生命周期；不能把手动删除 GL 名称当作 CoreVideo 缓存回收。[Apple 的纹理类型说明](https://developer.apple.com/documentation/corevideo/cvopenglestexture)明确其由 `CVOpenGLESTextureCache` 管理。
5. 初始化参数和每帧 FBO 参数的指针从 `withUnsafeMutableBytes` / `withUnsafeMutablePointer` 借用闭包中返回，之后才传给 mpv。借用作用域已结束，指针有效性没有保障；优化构建不能依赖当时栈布局恰好未改变。

其中 1、2 是已确认、可复现的进程退出缺陷。3、4、5 是需要修正的原生契约问题；没有设备证据证明它们各自造成了此次现场闪退。

## 修复与接入

个人 [media-kit 修复提交](https://github.com/CKopoer/media-kit/commit/ba953612ebfa83a4590f374c78a1ba479e1ea1df)：

- iOS 像素缓冲同时声明 IOSurface、OpenGL ES 和 Metal 兼容。
- 每帧分配和纹理导入改为可失败返回；帧缓冲创建失败返回空，不重试分配、不主动终止进程。当前 render 保留之前完整画面，后续正常 render 可继续发布新画面。
- CoreVideo 包装对象通过 ARC 释放；只删除本插件创建的 FBO。包装对象作用域结束后仍在对应 EAGL context 中 flush 缓存，失败路径也执行清理。
- 分配、绘制和清理处于对应 EAGL context；嵌套辅助方法和 render 恢复进入时的 context。拒绝无效、非有限、不能表示为 GLsizei 的尺寸。
- mpv 初始化和 render 调用放入指针借用闭包内；mpv render 返回失败时不发布未完成图像。
- 保留 `glFinish` 后发布、`CompletedFrameStore` 原子交接和消费者 retained 引用；不根据固定缓冲数量推断 Flutter GPU 已完成读取。

根应用及 `bili_player` 的核心、视频和所有平台库插件统一固定到该完整提交，两份锁文件由 Flutter Pub 重新生成。SDK 资产及解码器二进制没有更换，其他平台原生实现没有修改。

## 验证

- 新增 [回归入口](../../tool/test_ios_video_output.py) 和 [Swift 故障注入环境](../../tool/native_tests/ios_video_output_test.swift)。根检查既有的 `test_ios_*.py` 入口会执行源码契约检查；没有 `swiftc` 时明确跳过可执行用例。
- 在 WSL Ubuntu 22.04 / Swift 6.0.3 下，以 Swift 5 语言模式和 `-O` 编译真实生产 `TextureHW`、`TextureGLESContext`、`OpenGLESHelpers`、`CompletedFrameStore`。仅替换不可用的 Apple 图形 API 和 Flutter 协议，执行完整生产方法及 ARC 释放。
- 首轮原版 7 项检查全部失败，其中分配/纹理失败触发异常退出、无效 FBO 触发 `exit(1)`。修复后共 9 项通过：源码契约、连续 2,000 帧、像素缓冲分配失败、纹理导入失败、无效 FBO、非法尺寸、context 激活失败、mpv render 失败和真实 mpv C 参数类型检查。验证失败期间保留旧图像、故障解除后继续发布、旧图像不被覆写、FBO 与临时引用释放、context 恢复。
- C 参数检查使用 fork Makefile 指定的 mpv v0.36.0 头文件归档，先验证既有 SHA-256，再让真实生产 Swift 类型检查导入 C 声明，避免只用 Swift 替身函数签名掩盖 FFI 参数错误。该检查仍不包含 Apple SDK 类型。
- `tool/check.ps1 -EnforceLockfile` 完整通过：五份锁文件可复现解析、格式/静态分析、打包边界及 6,565 项离线测试（根应用 5,270、API 917、播放器 212、弹幕 161、mux 5）。根应用 13 项、播放器 1 项按环境跳过；mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。Windows 根检查没有 Swift 编译器，可执行 Swift 用例由上述 WSL 专项单独执行。
- fork 提供 `media_kit_video/test/ios_renderer_typecheck.sh`，使用 iPhoneOS SDK、固定 mpv C 头文件和最小 FlutterTexture 协议声明检查真实 Swift 文件。尝试通过隔离验证分支远端执行时，GitHub 返回 `422: Actions has been disabled for this repository`；没有产生成功的 SDK 验证结果，临时验证分支已移除。

检查日志位于忽略目录 `build/ios-playback-fix/check.log`，原版故障注入对照在同目录 `baseline.log`。交付前发现同期 `lib/features/pgc/presentation/pgc_screen.dart` 修改，已保留，未纳入本任务；以上全量结果对应此次检查运行期间的源码，不作为后续并行修改的验证结论。

这些替身 API 回归不验证 Apple 驱动、真实 CoreVideo/Metal 资源占用或系统内存终止，不能据此声称长期播放内存稳定。Windows 主机不能构建 iOS IPA，当前没有 iOS 设备；iOS SDK 编译、同版本真机长播放、原报告退出原因及修复接受度仍待验证。需要覆盖普通/全屏、暂停/seek、旋转/切清晰度、前后台、连续换视频，并核对崩溃记录或 JetsamEvent。

## 用户导出日志复核

2026-11-13 用户补充 `BiliSail-logs-20261112170829494323-61001.zip`，SHA-256 为 `b812822e716502ed5c85dd40c10c4ba4bdbaefa9735d54fe8e3656059bf60733`。原始归档及用户日志未提交仓库，仅记录以下结构化证据。

### 内容与时间范围

- `diagnostics.json`：版本 `1.2.9+5`、iOS 16.6.1 / 20G81、Dart 3.13.5 / ios_arm64；9 个日志文件共 23,382 字节，导出时没有跳过日志文件。
- 导出时间为 `2026-11-12T17:08:29.494323Z`，转换北京时间为 **2026-11-13 01:08:29.494**。归档文件名使用 UTC，不能直接当作本地日期/时间。
- 保留的日志涉及 6 个进程号，其中 5 个有核心启动记录；更早的 60052 仅保留播放通道。共有 7 次 `openStarted` 和 7 次 `openReady`、7 条原生 warning、9 条原生 error；104 次应用 API 请求结果为成功 99、取消 5，没有失败分类。
- 没有记录 `frameworkError`、`unhandledError`、`nativeError`、`failed` 或 `shutdown`。这只能说明这些应用事件未留在本包中，不能排除崩溃时待写日志尚未落盘，也不能凭缺少 `shutdown` 区分原生崩溃、系统终止和用户强制关闭。
- 这份导出早于应用修复提交 `82780dd0`（北京时间 01:16:43），且本轮未构建/安装新 iOS 包，不能将它作为修复后仍然闪退的验证结果。元信息没有源码提交或二进制 UUID，也不能仅凭相同版本号识别源码。

### 最后一次播放与新进程

以下均为北京时间 2026-11-13，进程 60958 → 61001：

| 时间 | 事件 | 能确认的事实 |
| --- | --- | --- |
| 01:07:09.038 | 前一视频 `openReady` | 时长 161.007 秒，音频、视频和输出就绪 |
| 01:07:49.583 / 01:07:50.147 | 两组原生 error | 位置 92.666 秒、缓冲端点 160.984 秒，`seeking=true` |
| 01:08:00.819 | 第三组原生 error | 同一位置，`paused`、`buffering=true`、`seeking=true` |
| 01:08:08.624 | 另一视频 `openStarted` | 同一进程仍在执行，并开始新一轮打开 |
| 01:08:09.564 | 另一视频 `openReady` | 时长 656.033 秒，音频、视频和输出均就绪 |
| 01:08:10.447 | 最后一条应用 API 成功记录 | 此时旧进程仍能处理请求 |
| 01:08:27.530 | 进程 61001 `startup` | 已进入新的应用启动；01:08:29.494 导出日志 |

最后一次 `openReady` 到新进程 `startup` 相隔 **17.965606 秒**。这与用户十几秒后退出的描述相容，但包含用户重新打开应用的时间，不能称为“精确播放 17.966 秒后崩溃”。当前日志不周期记录正常播放状态，`openReady` 处的 `paused` / `desiredPlaying=false` 也不能用于断言随后没有开始播放。

三组 error 每组各三条，均为 `cause=unknown`，每组包含 `media_kit` 和两个被归为 `other` 的模块。原始消息、mpv 错误码、调用名已被分类/丢弃，无法从归档逆推出具体失败函数。错误之后同一进程仍能打开并完成另一视频准备，不能将这些错误的时间直接当作进程退出时间；也不能排除它们与后续故障有间接关系。

### 硬解分类与失步线索

进程 60842 在 01:04:01.606、播放位置 0.366 秒处连续记录五条 `cplayer` warning，其中第三条为 `cause=hardwareDecoder`。此后同一进程于 01:04:34.186 又打开另一视频。

目前 [分类器](../../packages/bili_player/lib/src/player_diagnostics.dart)只要匹配到 `hardware` 就可能给出 `hardwareDecoder`；它不是 VideoToolbox 崩溃堆栈，也不表示已经确认硬解失败。固定 Apple mpv 来源 `f4210f84906c3b00a65fba198c8127b6757b9350` 的 [player/video.c](https://github.com/mpv-player/mpv/blob/f4210f84906c3b00a65fba198c8127b6757b9350/player/video.c#L53) 包含带空行的五行通用 A/V 失步提示，第三行正包含 `hardware`，并在音视频偏差绝对值超过 0.5 秒时报告。这与归档中的行数、模块、级别和分类顺序吻合，因此是一个**可能的音画失步线索**，不能将被删去的原文当作已恢复，更不能据此断定 VideoToolbox 是闪退根因。

### 收敛结论与缺失证据

已经确认全部 7 次媒体打开都记录了音视频及输出就绪，存在运行中的 seek/缓冲异常线索，最后一次视频准备后约 18 秒出现新进程。没有证据将故障定为 API 鉴权、播放地址取得失败、确定的硬解故障、内存耗尽或某个原生异常；应用 API 成功也不代表播放器自行访问的 CDN 请求全部成功。

上一轮修复仍消除了经过故障注入确认的 iOS 进程退出路径，但本包没有记录 CoreVideo 返回码、无效 FBO 状态、原生异常线程或内存终止原因，**不能据此确认现场根因就是该路径**。本次只补充证据分析，没有依据未知消息继续修改解码器/缓存设置。

下一份有决定性的材料是北京时间 **2026-11-13 01:08:10–01:08:28** 附近的系统 `.ips`，或同时间的 `JetsamEvent`。应用 iOS 可执行文件名为 `Runner`，可在系统“分析与改进 → 分析数据”中寻找 `Runner` / `BiliSail` 开头的崩溃记录，或 JetsamEvent；采集入口见 [Apple 官方说明](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)。

若只有 JetsamEvent，须确认其中被终止的进程就是本应用，再读取 `reason`、`rpages` 和 `pageSize`；仅在系统上找到一个 JetsamEvent 不能证明本应用因内存退出，见 [Apple 内存终止报告说明](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)。

## 没有系统报告时的候选原因排序

用户随后确认目前没有对应 `.ips` / JetsamEvent。以下继续依据同一份应用日志和固定源码排序；排序表示排查优先级，不是测得的发生概率，也不把“没有找到系统报告”当作某类故障的证明。

本节保留追加修复前的分析快照，所核对实现为 `ba953612`；下面的队列/销毁风险已继续通过受控测试验证并修正，见“后续修复”一节。

### 最高优先级：iOS 输出帧分配失败后的进程退出

与现象最相容的链路是：正常完成媒体准备 → 持续绘制时反复申请/导入 CoreVideo 输出帧 → 某一帧申请失败或 FBO 无效 → 旧代码强制解包或 `exit(1)` → 应用日志直接停止。

支持点是首页不触发视频输出、7 次媒体打开全部就绪、故障发生于进入视频之后，以及本项目与 PiliPlus 的分配频率差异。原版相关退出分支已经在受控环境复现；这是当前有具体可执行失败路径支撑的候选，优先于单凭 warning 归因于硬解。但日志没有 CoreVideo 返回码或 FBO 状态，仍不能确认现场走到了该分支。

既有修复已处理这个失败后退出、兼容属性和借用指针问题。它能避免普通分配/导入失败立即终止进程；如果上游仍在持续保留资源，修复失败分支本身不等于消除了全部资源压力。

### 次高优先级：输出图像驻留或渲染任务积压

独立分配输出图像并不自动等于内存泄漏。以假设的 1080p、BGRA、60 fps 为例，每张有效像素数据约 7.9 MiB，每秒分配周转约 475 MiB；这是分配吞吐量，不是常驻内存增长。只有存在未及时释放的引用、缓存或 GPU 工作时，额外帧才会叠加为驻留量。本包没有尺寸、实际 fps、存活帧数或内存数据，不能把示例当作设备测量。

[Worker.swift](https://github.com/CKopoer/media-kit/blob/ba953612ebfa83a4590f374c78a1ba479e1ea1df/media_kit_video/common/darwin/Classes/plugin/Worker.swift) 的数组队列没有容量上限或通知合并；[VideoOutput.swift](https://github.com/CKopoer/media-kit/blob/ba953612ebfa83a4590f374c78a1ba479e1ea1df/media_kit_video/common/darwin/Classes/plugin/VideoOutput.swift) 每次通知都排入渲染任务，并同步等待主线程通知 Flutter。实际绘制还包含每帧 CoreVideo 包装和 `glFinish`。如果通知产生速度超过完成速度，就存在积压和资源延后释放的条件；这不是本包已经记录了积压。

早先五行 `cplayer` warning 疑似 A/V 失步，与视频链路跟不上音频的方向相容，但并不指明是 CPU、GPU、音频时钟还是驱动。缓存 flush 也只回收不再使用的资源，不能强制释放消费者仍持有的图像，见 [Apple 缓存说明](https://developer.apple.com/documentation/corevideo/cvopenglestexturecacheflush(_:_:))。

### 中等优先级：换视频/恢复后的原生释放竞态

日志中确实存在 seek 长时间未结束、随后换到另一视频，因此需审查旧播放器与新播放器交叠的场景。当前 [输出销毁](https://github.com/CKopoer/media-kit/blob/ba953612ebfa83a4590f374c78a1ba479e1ea1df/media_kit_video/common/darwin/Classes/plugin/VideoOutputManager.swift) 主要移除 manager 的引用，MethodChannel 随即返回；Worker 内正在运行或排队的任务还可能持有 VideoOutput。[播放器释放](https://github.com/CKopoer/media-kit/blob/ba953612ebfa83a4590f374c78a1ba479e1ea1df/media_kit/lib/src/player/native/player/real.dart) 在执行 release 回调后按固定 5 秒延迟调用 `mpv_terminate_destroy`，没有由这个 Dart 返回值证明原生渲染队列已经排空。

因此存在“旧渲染任务/回调延后执行，而底层 handle 先释放”的静态风险条件；固定延迟不能替代释放完成确认。日志不含原生 handle、输出销毁或 Worker 排空记录，尚不能证明发生了悬空访问，也不能将 5 秒直接对应到约 18 秒的重启窗口。若用户从冷启动只播放一个视频、全程不 seek/换视频也稳定复现，则应下调此项相对于输出帧分配的优先级。

### 有条件的候选：后台继续执行 OpenGL ES

Apple 明确禁止后台使用 OpenGL ES，包括某些此前提交命令在后台执行的情况，可能直接终止应用，见 [后台图形约束](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/Introduction/Introduction.html)。当前输出插件没有直接观察 iOS 后台状态的原生渲染门禁；应用的后台音频策略也不能自动充当 GPU 停止屏障。

这只在退出前发生锁屏、切应用或相关系统状态转换时值得上调。日志没有生命周期事件，用户目前描述为普通播放，故不能把此项作为默认解释；如果确认全程前台，则优先级较低。

### 当前证据较弱的解释

- **特定 VideoToolbox/编码格式故障**：仍可能存在，但没有选中的 codec、硬解器或该模块异常；通用 `hardwareDecoder` 分类不足以支撑。7 次成功准备也不能保证后续每一帧都可解码。
- **普通网络/鉴权失败直接引起闪退**：应用 API 无失败分类，7 次打开均就绪，且 seek error 后仍能开始新视频。普通读失败更常表现为缓冲/播放错误，不能单独解释进程消失；播放器自身 CDN 请求未经过应用 API 日志，仍不能排除网络变化触发原生缺陷。
- **固定的起播超时或“十几秒定时退出”**：7 次 `openStarted` → `openReady` 实际为 0.910–1.715 秒，没有起播 deadline 到期记录。约 18 秒仅是最后一次就绪到重启的窗口，不能据此倒推出某个计时器。

### 不依赖系统报告的区分方式

后续验证应先使用已修复的同一构建，再分别比较：只播放单个视频且不 seek/换源；同素材的软件解码；听视频；保持前台与锁屏/后台。软件解码仍经过当前视频输出，若仍崩会削弱“仅 VideoToolbox”假设；听视频同时移除了视频解码和视频绘制，只能收窄到视频链路，不能单独证明是渲染器。切视频明显放大故障时，应提高原生释放竞态的优先级。

最有价值的新诊断字段是有界记录的 CoreVideo/FBO 失败码、已分配/存活输出帧数、渲染队列长度、进程内存、输出关闭完成和生命周期状态。它们可以区分“瞬时分配失败后退出”“资源持续积累”和“旧 handle 延后访问”；当前归档无法追溯补出这些数据。

## 后续修复：Apple 销毁屏障与通知合并

### 从候选变为可复现缺陷

[新增生命周期回归](../../tool/test_ios_video_lifecycle.py)编译并执行真实的 `MediaKitVideoPlugin`、`VideoOutputManager`、`VideoOutput`、`Worker` 和纹理锁包装。Flutter 声明/注册器和底层纹理采用受控替身，通过真实方法通道处理函数创建和关闭输出，不替换生产调度/销毁方法。

在上一修复 `ba953612` 的隔离源码上，7 项检查全部失败：

- `Dispose` 回复时，受控阻塞的 render 仍在执行，调用方不能据此安全释放底层句柄。
- Flutter 单独保留纹理包装时，原实现依赖 `deinit` 的 mpv render context 尚未释放；固定 5 秒延迟不构成完整的释放确认。
- 繁忙期间提交一万次更新会形成后续 render 队列，缺少合并和容量约束。
- 重复关闭、初始化期间关闭以及迟到通知没有完整的关闭屏障。
- 在调用方收到销毁响应后即回收句柄的受控案例中，旧渲染任务仍可能访问已回收对象。该测试验证响应契约，不用缩短后的模拟时序预测现场的精确退出时间。

这确立了原生调度和资源释放缺陷；并没有从用户 ZIP 恢复出缺失的异常线程或证明设备上已发生同一悬空访问。

### 实现

个人媒体 fork 已推送 [生命周期修复](https://github.com/CKopoer/media-kit/commit/46bf2151e1f4f505ccbb858d6c3860ea43621ad6) 和 [通道类型检查补充](https://github.com/CKopoer/media-kit/commit/302d60eedc55ca677e911e529569b1e14d8c2e7e)，应用与 `bili_player` 的八个媒体包及两份锁文件统一固定后一个完整提交。

- 关闭首先拒绝新任务、丢弃未执行的工作，再等待当前工作结束。在同一个 worker 中显式释放 mpv render context，随后在平台线程注销纹理，最后回复 `Dispose`。重复请求各自收到完成回复，完成后迟到通知不再接触播放器。
- 纹理增加幂等 `dispose()`，资源释放不再依赖 Flutter 什么时候销毁包装对象；消费者已经取得的完整像素缓冲仍由消费者独立持有。
- 渲染和尺寸更新分别按 key 合并，最多一个正在执行的 render 加一个待执行的最新 render。平台帧通知也合并，回调不再逐次派发到主线程或同步等待主线程。
- Worker 每项工作有独立 autorelease pool，并在再次等待前释放任务捕获，避免线程长时间持有已完成任务。
- 软件输出在 worker 内同步初始化，在同一线程绘制和显式释放；分配失败保留完整旧图像，mpv 软件绘制参数的借用范围覆盖完整 C 调用，绘制失败不发布新图像。
- 变更位于 Apple 共享实现及 iOS/macOS 图形适配。libmpv SDK 资产没有更换；已完成帧交接和独立像素缓冲语义继续保留。

### 检查入口修正

上一轮新增的 `test_ios_video_output.py` 需要 Pub 生成的 `.dart_tool/package_config.json`，但原 `tool/check.ps1` 在 Pub 前运行 `test_ios_*.py`。本地已有配置，冷检出的 [CI 43270740839](https://github.com/CKopoer/BiliSail/actions/runs/43270740839) 则因此失败并跳过构建。此次将该测试组移到依赖解析之后，保留全部检查，不以跳过测试解决问题。

### 本轮验证

- WSL Ubuntu 22.04、Swift 6.0.3、Swift 5 语言模式、`-O`：21 项检查通过，其中硬件/软件实际生产渲染器 14 项，真实插件通道/Worker 生命周期 7 项；使用固定 SHA-256 的 mpv C 头文件验证参数类型。
- 对 `ba953612` 运行同一生命周期回归，7 项均失败；修复后覆盖活跃渲染、Flutter 保留纹理、一万次通知合并、重复关闭、迟到事件、初始化期间关闭以及关闭后立即回收句柄。
- 10 份变更 Swift 源码语法检查、SDK 辅助脚本 Bash 语法、`git diff --check` 通过。
- `tool/test-windows-video-dispose.ps1`：9 项原生释放、渲染队列和尺寸检查通过，Windows 实现本轮未改变。
- Apple 原生 Release 编译在 [CI 43275138772](https://github.com/CKopoer/BiliSail/actions/runs/43275138772) 通过：iOS arm64 / macOS arm64，使用真实 Apple SDK、Flutter 3.47.6 框架和固定 mpv 头文件，以 Swift 5 / `-O` 编译完整插件公共类、实际方法通道和两种纹理实现，均生成 Mach-O arm64 对象。没有用 Flutter 协议替身代替这次编译；这是原生插件编译，不是 IPA/DMG 打包或设备运行。该独立验证分支的工作流改动不会进入主分支。
- 全量 `tool/check.ps1 -EnforceLockfile` 通过：五份锁文件可复现解析、格式/静态分析、打包边界，以及 6,565 项离线测试（根应用 5,270、API 917、播放器 212、弹幕 161、mux 5）。根应用 13 项、播放器 1 项按环境跳过；mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。Windows 根检查中没有 swiftc 的可执行 Swift 用例明确跳过，由前述 WSL 21 项专项独立验证。日志为忽略目录 `build/ios-playback-fix/lifecycle-check.log`。

受控图形替身测试不能证明真实 CoreVideo/Metal 内存曲线或 GPU 驱动行为；本轮仍没有 iOS/macOS 设备播放验收，也没有将用户提供的原始日志提交到远端。
