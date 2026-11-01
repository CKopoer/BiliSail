# 触摸长按临时倍速

日期：2026-10-07。

## 行为与设置

- 普通视频、影视与离线点播共用播放面板：触摸长按视频画面达到设置中的「长按触发延迟」后，使用「长按临时倍速」播放；松开或收到手势取消事件后恢复按下前的倍速。默认延迟 400 毫秒、临时 2.0x，复用现有设置，不新增持久化字段。2026-10-12 将默认临时倍速由 3x 改为 2.0x，缺失或无效设置也回退到 2.0x，已保存的有效倍速保持原值。
- 普通画面和全屏均支持，控制栏显示或隐藏时行为一致。加速期间显示当前倍速提示；长按不切换控制栏、不跳转进度，也不主动改变播放／暂停意图。
- 页面隐藏、切换播放源、打开弹窗、修改长按设置、应用失活／进入后台和页面销毁都会取消等待或恢复临时速度。旧手势尚未达到触发延迟时发生上述变化，继续按住也不会对新页面／新播放源加速；需要重新按下。
- 短按沿用当前控件交互模式；2026-10-27 起，触屏双击改为播放／暂停，鼠标双击保留切换全屏，详见[触屏双击记录](responsive-player.md#触屏双击播放暂停2026-10-27)。触发前拖动超过手势容差不会加速。播放器按钮与滑块保留自己的交互。仅触摸设备识别长按倍速，鼠标点击保留原行为；直播不开放倍速。
- 快捷键总开关仅影响键盘／侧键，触摸长按仍可使用现有延迟与倍速设置。设置中的倍速项增加触摸操作说明。

## 状态归属

[PlaybackShortcutController](../../lib/features/playback/application/playback_shortcut_controller.dart) 由播放面板持有，普通／全屏视图共用。触摸按下先登记输入来源及播放源代次，再由手势识别器通知开始加速，让既有输入取消和路由／焦点隔离也能取消尚未触发的触摸。键盘与触摸交替时只保留最近一次长按，旧输入的松开不会结束新输入的长按。

[PlaybackPanel](../../lib/features/playback/presentation/playback_panel.dart) 使用 Flutter 的 [LongPressGestureRecognizer](https://api.flutter.dev/flutter/gestures/LongPressGestureRecognizer/LongPressGestureRecognizer.html)，指定触摸设备与设置中的延迟，复用原单击／双击识别器；延迟修改后重建识别器。开始／恢复都调用现有 `PlaybackSession.beginTemporaryRate`／`endTemporaryRate`，沿用源代次隔离和串行媒体命令，不直接调用原生后端。

临时速度不会进入工作区播放快照或应用内手动倍速记忆；原有会话恢复和迟到调速防护见 [应用会话内继承倍速](session-playback-rate.md)。没有新增依赖、数据库迁移或播放器包契约。

## 验证

- 播放面板与会话共 168 项定向回归通过，日志：[播放回归](../../build/touch-hold-playback-tests.log)；随后增加的 2 项键盘／触摸交替长按回归也通过，日志：[交替输入回归](../../build/touch-hold-input-handoff.log)。新增共 26 项用例覆盖设置的延迟／倍速、普通／全屏和控制栏显隐、保持播放／暂停意图、松开恢复、原生调速未完成时松开、触发前／后的七类取消、设置修改后下一次手势、短按、拖动、鼠标、按钮、直播和交替输入边界。既有鼠标／触摸双击、键盘长按和临时速度不写入快照／继承记录的回归继续通过。
- `tool/check.ps1 -SkipPub` 完整通过：根应用 1264、`bili_api` 319、`bili_player` 32、`bili_danmaku` 52，共 1667 项测试；根应用与三个包的格式、静态分析均通过，日志：[完整检查](../../build/touch-hold-check.log)。上述后加的 2 项交替输入回归单独验证。
- Windows 原生播放器定向回归通过：真实 `MediaKitEngine` 与本地音视频分轨，在普通／全屏画面注入触摸长按，验证实际 1.5x → 3x → 1.5x，正常松开及取消均恢复、暂停／位置／控制栏／播放源保持，并继续通过六轮全屏和既有弹幕验证。日志：[Windows 原生回归](../../build/touch-hold-windows-native-final.log)。这项测试包含 Windows Debug 构建；触摸由测试框架注入，不能替代移动设备人工操作。

按用户要求，通过测试后直接提交，不再额外构建。当前仅连接 Windows 与 Edge，没有 Android 实机；本轮未构建 Android／发布产物，Android 真实触摸手感、原生音画倍速及 macOS 运行仍未验证。测试不使用真实账号或 Bilibili 在线请求，不作性能结论。

## 上滑固定倍速（2026-10-31）

- 长按触发后，左上角保留当前倍速，第二行显示“上滑固定倍速”。在本次触摸起点上方移动至少 48 个逻辑像素，且向上位移大于水平位移时固定；松手后保持设置中的长按倍速。短距离抖动、侧滑、下滑以及长按触发前的拖动不固定。
- 固定时再次长按临时使用 1.0x，提示第二行改为“上滑解除固定”；直接松手或取消手势恢复固定倍速，上滑后解除固定并保持 1.0x。每次手势只提交一次固定／解除，达到阈值后显示“已固定倍速”或“已解除固定”；松手后的速度提示短暂显示后消失。
- 视频、影视和离线点播的普通／全屏、控件显隐共用这一行为。键盘长按仍使用原有临时倍速，不显示上滑提示；直播、鼠标、画面按钮和进度／音量手势沿用原边界。固定及临时恢复均不改变播放／暂停意图、位置或播放源。
- 固定标记由播放面板的 `PlaybackShortcutController` 持有，普通／全屏切换保留；页面隐藏、弹窗、应用失活取消当前手势并恢复固定速度，保留已完成的固定。切换播放源或手动改为另一倍速后清除标记，旧手势不能固定新源。
- 上滑是明确的手动调速，固定／解除调用现有 `PlaybackSession.setRate`，更新当前临时手势的恢复目标并沿用串行命令及运行内倍速记忆；后续新源可继承最近成功选择的速度，但不继承固定标记。未上滑的临时调速不写入记忆。不新增设置、存储字段、依赖或播放器包契约。

本轮验证：

- `tool/check.ps1 -SkipPub` 完整通过：根应用 **3668**、`bili_api` **497**、`bili_player` **101**、`bili_danmaku` **136**、`bili_mux` **5** 项，共 **4407 项通过**。13 项 Windows 符号链接测试因权限跳过；10 项 mux 原生测试因未设置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。格式、静态分析及打包边界检查通过，见[完整检查日志](../../build/touch-rate-pin-check.log)。
- 新增 **19 项组件回归通过**，覆盖普通／全屏与控件显隐、第二行提示、固定／临时恢复／解除、手势阈值与单次提交、原生调速等待、指针取消、页面／应用／弹窗取消、键盘交替、切源、手动调速及影视／离线的自定义倍速，见[定向日志](../../build/touch-rate-pin-targeted.log)。
- 末次播放面板整文件 **344 项通过**，全库静态分析再次通过，见[面板回归](../../build/touch-rate-pin-panel-final.log)与[末次分析](../../build/touch-rate-pin-final-analysis.log)。
- Windows 真实 `MediaKitEngine` 本地音视频分轨专项通过：普通与全屏均确认 1.5x → 长按 2x → 上滑后松手保持 2x → 长按 1x／松手恢复 2x → 上滑解除并保持 1x；暂停意图、位置与源代次保持。使用 `BILI_TEST_MEDIA_DIR=test/fixtures/media` 运行 `integration_test/windows_playback_test.dart` 中的 `Windows native touch hold pins and unpins playback rate inline and fullscreen`。初次 Debug 构建遇到 MSVC PDB 写入冲突，重试仅在命令进程中设置 `CL=/FS` 同步写入后构建和专项均通过，未修改构建配置，见[原生专项日志](../../build/touch-rate-pin-windows-retry.log)。

Windows 触摸事件由测试框架注入；Android／iOS／macOS 实机触摸手感与原生音画表现仍需逐平台验收，本轮未构建这些平台或发布安装包。无真实账号或在线媒体请求，不作性能结论。

## 长按触发后的额外停顿（2026-11-01）

后续在已切换至 PiliPlus 锁定核心的工作区继续复现到音频输出队列造成的停顿；前一轮常驻滤镜／去重并未覆盖这条路径。实际 Windows Profile 对照及修复见[音频输出缓冲记录](hold-rate-output-buffer-2026-11-01.md)。以下保留前一轮的依赖快照与验证边界。

### 调用链与原因边界

- 键盘右方向键 Down 由 `PlaybackShortcutController` 启动设置中的定时器，Repeat 不重置定时器；到期进入 `beginTemporaryRate`。触摸识别器已等待相同设置中的延迟，`beginTouchHold` 直接进入该方法，没有第二轮延迟。默认 400 ms 用于区分短按 seek／单击与长按，本次保持原值及所有有效用户设置。
- `PlaybackSession` 的临时开始／恢复与永久选择共用有界 `MediaCommandPump`，`MediaKitEngine` 再隔离 source generation 并串行调用固定 `Predidit/media-kit` 的 `Player.setRate`。锁文件 ref 为 `83b7ca63772856e1ea0158916177e136f7b7b0be`；其 `media_kit/lib/src/player/native/player/real.dart` 在 `pitch == false`（当前配置）时设置 mpv 的 `speed`，没有主动 pause、seek 或重开媒体。
- 可定位的原生额外工作是 mpv 默认自动变速音频滤镜在跨越 1x 时改变处理链。[官方说明](https://mpv.io/manual/stable/#audio)确认非 1x 会自动插入 `scaletempo2`；[上游自动滤镜实现](https://github.com/mpv-player/mpv/blob/v0.40.0/filters/f_auto_filters.c#L321-L371)会在所需滤镜改变时经过 `mp_subfilter_drain_destroy`，再创建／移除滤镜。这是输入判定结束后的音频链切换，不能靠缩短手势阈值解决。
- 另有可直接复现的重复下发：原实现“已是 1x → 长按目标 1x → 松开”仍调用两次原生 1x；“长按 2x → 上滑固定 → 松开”调用三次 2x；永久 2x 尚未完成时取消后续临时长按，又下发重复的 2x 恢复。新增调用序列断言在关闭去重的对照中均失败，恢复去重后通过，日志见[修复前对照](../../build/hold-rate-before-dedup-tests.log)和[修复后对照](../../build/hold-rate-after-dedup-tests.log)。

本轮只核对源码机制和 fake 引擎调用序列，没有采集用户故障现场或实际原生音画轨迹。上述自动滤镜机制是额外工作的明确来源，但不能据此认定所有平台停顿的唯一原因或给出停顿时长／改善百分比。固定原生 bundle 的平台构建不同，也不能把上游版本的机制说明当成该二进制已通过运行验收。

只读对照相邻 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441`：`lib/plugin/pl_player/view/view.dart` 的 `longPressRecognizer` 在识别后直接调用 `setLongPressStatus`；`controller.dart` 的 `setPlaybackSpeed` 已跳过与当前 `state.rate` 相同的目标，其长按开始／结束也直接调用倍速方法。没有采用它仅播放中才接受长按的产品规则或替换本项目手势时长。其锁文件使用 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`，与本工程固定 Predidit 提交不同，不能把该参考应用的顺畅表现视作当前后端的运行证据。PiliPlus 应用源码为 GPLv3；本次只比较调用职责和行为，没有复制其源码，媒体适配仍基于本工程既有 MIT media-kit 依赖。未修改参考仓库或 Pub 缓存。

### 修复

- 点播在 `loadfile` 之前一次配置并回读 `af=scaletempo2`，让音频解码一开始就使用同一保留音调的变速滤镜；后续长按／恢复继续只修改 `speed`。[上游速度分发](https://github.com/mpv-player/mpv/blob/v0.40.0/filters/f_output_chain.c#L432-L465)优先交给用户滤镜，并给自动滤镜传入 1x，从而避开跨 1x 时自动滤镜的插入／排空／移除路径。不关闭音调校正，不启用 SDK 的 pitch 模式，不在长按时重写 `af`。
- 配置复用开源的总 deadline，写入／读取前后检查当前源；拒绝静默失败，超时后不继续读取。直播、无音轨预览及明确无声 DASH 不安装该滤镜；点播独立音轨和离线普通媒体沿用同一配置。没有调整音量、响度增益、缓冲策略或依赖版本。
- 会话在倍速命令实际出队时比较当前引擎速度，相同目标不再下发；引擎在其队列内也比较 `player.state.rate`。去重保留永久选择成功后的倍速记忆提交，因此上滑固定仍能被新视频继承。比较放在队列内，不能在提交恢复时因旧快照仍是原速度而漏掉正在进行的临时变速。
- 保留触发即登记长按、松开恢复、短按 seek、暂停／缓冲意图、固定标记，以及隐藏／关闭／切源和迟到响应隔离。没有修改播放面板或手势识别阈值。

### 本轮验证

- `flutter test --no-pub test/features/playback/playback_session_test.dart --reporter expanded`：**240 项通过**，新增 6 项覆盖精确 399+1 ms 触发、不被 Repeat 延迟、播放／暂停／缓冲意图、相同目标不调用原生、触摸直接开始、固定与继承，以及尚未执行的临时命令取消；既有快速松开、失败、旧源／关闭／隐藏隔离继续通过。日志：[会话回归](../../build/hold-rate-session-tests.log)。
- 在 `packages/bili_player` 执行 `flutter test --no-pub test/native_tempo_filter_test.dart test/media_kit_engine_test.dart test/native_audio_gain_test.dart --reporter expanded`：**18 项通过**，其中新增 7 项覆盖配置回读、拒绝静默失败、源替换和超时后的迟到写入；既有音量增益测试继续通过。测试使用 fake 属性读写，没有创建原生播放器。日志：[播放器回归](../../build/hold-rate-player-tests.log)。
- `flutter test --no-pub test/features/playback/playback_panel_test.dart --name 'hold|rate pin|touch rate|long press|keyboard.*touch|touch.*keyboard' --reporter expanded`：**49 项通过**，覆盖普通／全屏、控件显隐、上滑固定／解除、手势取消、页面隐藏／销毁、应用后台、弹窗、设置／播放源改变、触摸与键盘交替及异步变速未完成时松开。日志：[组件回归](../../build/hold-rate-panel-tests.log)。
- 本任务 Dart 文件格式检查、定向静态分析及 `git diff --check` 通过。

按本次用户要求未运行整仓检查、构建、安装、在线账号、原生媒体或设备／性能测试。未发现可连接的 Flutter 调试实例，未启动应用进行热重载。用户后续需确认各平台键盘／触摸真实触发手感、音画连续性及音调；自动单元／组件测试不替代这项验收。
