# 全屏切换保留点播弹幕

日期：2026-10-06。普通视频和影视共用 `DanmakuController`，本次修复其视口变更行为。

## 原因

之前的控件显隐修复只处理了底部避让高度变化。全屏／退出全屏改变播放器宽高，`setViewport` 仍执行清空活动弹幕、清空文字布局和回退调度游标。重新调度时，密度限制或轨道冲突可能让之前丢弃的历史弹幕先占位，将原本可见的滚动弹幕挤掉。播放会话和原生播放器没有重建。

## 修复

- 所有视口变化保留活动项的事件身份、开始时间、轨道、调度游标和文字布局；滚动坐标按相同时间进度投影到新宽度，固定弹幕重新居中／按底部定位。
- 缩小区域只移除超出可用轨道的弹幕，重新放大不重播被移除或此前丢弃的项。临时零宽／零高只停止输出画面，保留未到期活动项与待调度项。
- 暂停和缓冲仍冻结弹幕时钟；恢复播放继续滚动，实际 seek 和源切换仍按原有逻辑重建。未改变直播的独立到达时间调度与组件生命周期。

## 验证

- 回归用例在修改前复现进入全屏后 `visibleCount` 从 1 变为 0；修复后通过。
- 包测试覆盖四次往返尺寸变化、此前丢弃的历史弹幕与未来弹幕隔离、时间进度、文字缓存、缩小轨道、零尺寸过渡和显式 seek。
- 共用播放面板测试覆盖控件初始显示／隐藏、画面双击反复进入／退出全屏、暂停与恢复播放，并检查进度、媒体 generation、一次源打开和单一 surface。
- `tool/check.ps1 -SkipPub` 通过当前工作区根应用与三个包的格式、静态分析及 989 项测试：根应用 723、`bili_api` 227、`bili_player` 16、`bili_danmaku` 23。日志：`artifacts/danmaku-fullscreen-check.log`。工作区同时存在其他改动，以上是该次检查快照的总数。
- Windows 原生用例 `Windows native responsive controls, fullscreen and Esc preserve one playback source` 通过。使用本地 DASH 音视频分轨与脱敏弹幕事件，覆盖 F／按钮／Esc 六次切换及控件显示／隐藏时的鼠标双击往返，检查同一活动弹幕、调度游标与丢弃计数保留。日志：`artifacts/danmaku-fullscreen-windows.log`。
- `flutter build windows --profile --no-pub -t lib/main.dart` 通过，可运行版本位于 `build/windows/x64/runner/Profile/bilisail.exe`，须保留同目录依赖和资源。日志：`artifacts/danmaku-fullscreen-build-profile.log`。Release 尝试在 CMake 安装阶段失败；该输出目录中的 `bilisail.exe` 当时正在运行，本轮未关闭它或完成 Release 打包。失败日志：`artifacts/danmaku-fullscreen-build-windows.log`。
- Android/macOS 本轮未构建或实机验证；未执行真实账号写操作，未测量性能。

## 独立动画时钟后的原生用例复查

同日后续检查发现，上述 Windows 原生用例在进入全屏前的弹幕准备阶段失败：期望 `visible`，实际为 `warmup`。今天 [弹幕速度与播放倍速](danmaku-playback-rate.md) 将活动弹幕寿命改为独立动画时间；暂停时该时间冻结。旧测试在无时间流逝的循环中始终传入 `playing: false`，只把确认媒体位置从 0 秒改到 5 秒，误以为固定弹幕也会经历四秒寿命并退场。该准备方式不再符合暂停／位置校正语义。

暂时移除本轮悬停的请求帧修复后，旧用例仍在相同的准备断言失败（日志 `build/hover-preview-idle-fullscreen-baseline.log`）；恢复请求帧修复后单独运行也同样失败（`build/hover-preview-idle-fullscreen-recheck.log`）。因此这次失败不能归因于悬停初始化或全屏切换。

[原生测试](../../integration_test/windows_playback_test.dart) 现在通过已有的 `PlaybackSession.danmakuNow` 接缝注入可控单调时钟，用 500 毫秒、Playing 的样本累积五秒动画时间，再同步为原生源的实际暂停位置。500 毫秒小于 700 毫秒过期样本边界。仍保留 `warmup`／容量丢弃项／`visible`／未来项，并额外确认未来队列和丢弃计数各为 1；六次 F／按钮／Esc 和显隐两种状态下的鼠标双击往返断言保持。只修正测试准备，不修改弹幕运行代码或放宽断言。

调整后 Windows 原生播放套件报告 8 项全部通过（公网 UGC 分支未启用），包括该全屏用例、本地音视频分轨、headers／重定向／Range／seek、独立标签与工作区切换；日志 `build/hover-preview-idle-playback-corrected.log`。真实线上悬停另行验证，见 [预览初始化复查](video-preview-loading.md#静止窗口初始化阻塞复查)。Android/macOS 本轮原生未测。

## 直播全屏切换（2026-10-24）

直播的 `LiveDanmakuController.setViewport()` 已保留有效视口变化时的活动弹幕、到达时间和文字缓存，但原先 `LivePlayerDanmaku` 位于 `PlaybackPanel` 的 overlay builder 内。进入／退出全屏会卸载旧 `_PlayerView`，连带销毁直播弹幕控制器、时钟和消息订阅，新画面因此从空状态开始。点播控制器归持续存活的 `PlaybackSession` 所有，没有这个组件生命周期问题。

应用组合根现在将 `LivePlayerDanmaku` 放在 `PlaybackPanel` 外，通过 builder 将共用控制器的 `LiveDanmakuOverlay` 交给普通／全屏画面。视图可以重新创建，直播弹幕的状态、时钟和实时消息订阅持续保留；切换空档收到的消息进入原有有界队列，仍遵守过期和限流规则。隐藏页面、系统后台、关闭弹幕、换房、账号变化和销毁继续走原有清理流程，历史聊天不重播。

- 修改前，新增组件回归确认进入全屏后控制器身份发生改变；日志 `build/live-fullscreen-before.log`。
- 修改后 `test/features/live/live_player_danmaku_test.dart` 7 项通过，覆盖滚动／顶部／底部弹幕三次往返、按钮及 F／Esc、消息身份和文字布局保留、短房号连接复用、同一媒体 generation、单一 surface、进出全屏空档收消息，以及隐藏后不重播积压。日志 `build/live-fullscreen-targeted.log`。
- `tool/check.ps1 -SkipPub` 的脚本边界检查、根应用格式及静态分析通过；根应用测试 1990 项通过、1 项失败，失败为同期修改的 `live_screen_test.dart` 中 `one click reveals an SC again after its card scrolls away`（SC 卡片滚动后的可点击性断言），未修改该任务文件。日志 `build/live-fullscreen-check.log`。
- 根检查在上述失败处停止后，单独完成四个包的格式、静态分析和测试：`bili_api` 426、`bili_player` 78、`bili_danmaku` 93、`bili_mux` 2 项通过；mux 另有 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不能算作原生验证。日志 `build/live-fullscreen-packages.log`。
- `tool/test-windows-content.ps1` 通过 Windows 受控 HLS／FLV 原生解码、headers 和共享会话回归，并完成 Windows Debug 构建；未启用 `-Online`，其中公网 PGC／直播分支未执行。日志 `build/live-fullscreen-windows-content.log`。
- 随后以 `flutter run -d windows --no-pub -t lib/main.dart` 恢复普通应用入口，Debug 启动和热重载成功；连接 DTD 后未发现运行时错误，检查结束正常退出应用。这不替代真实直播全屏的手动验收。
- 两份更新文档的 47 条本地链接及本任务差异空白检查通过。真实直播手动全屏、Android／macOS 实机和性能尚未验收。

## 控件显隐保持弹幕区域高度（2026-11-14）

共享 `PlaybackPanel` 原来在控件显示时将 `DanmakuOverlay.bottomInset` 设为 100，隐藏时改为 48。`DanmakuController` 会按底部留白重新计算可用高度和轨道数，因此底部固定弹幕上下移动，较低的活动轨道也可能在控件出现时被移除。原组件测试只检查第一条滚动弹幕，且明确接受了 100／48 的切换，没有覆盖区域底边和多轨道保留。

播放面板现在固定使用原隐藏状态的底部 48 逻辑像素，不再将控件显隐传给弹幕构建方法。普通视频、影视和离线播放共用修复；普通／全屏继续响应真实尺寸变化，弹幕区域比例、顶部距离和行距保持已有设置语义。直播由自定义 overlay 提供，本来就没有这处显隐相关的留白变化。

- 新增 12 项组件回归，覆盖三类点播内容、点击／动态模式、320／800 宽度与 75%／100% 弹幕区域。每项均在普通和全屏下填充滚动／顶部／底部多轨道，反复显隐控件，检查全部活动弹幕的身份与坐标、待处理数量、丢弃计数、暂停意图、媒体 generation 和单一 surface 保持不变。使用固定单调时钟隔离动画推进；原代码 12 项全部失败，日志 `build/danmaku-controls-before.log`。
- 播放面板与直播弹幕定向回归共 501 项通过，日志 `build/danmaku-controls-targeted.log`。
- `tool/check.ps1 -SkipPub` 通过格式、静态分析、脚本边界与全仓离线测试：根应用 5487、`bili_api` 935、`bili_player` 298、`bili_danmaku` 161、`bili_mux` 5，共 6886 项通过。根应用 13 项因 Windows 符号链接权限不足跳过；播放器包 3 项未配置 `BILI_TEST_NATIVE_MPV`／`BILI_TEST_MEDIA_DIR`，mux 包 10 项未配置 `BILI_MUX_LIBRARY`，均不算原生通过。日志 `build/danmaku-controls-check.log`。两份文档的 131 条本地链接与 `git diff --check` 通过。
- 按用户要求不构建、不执行实机或性能测试，实际显示效果留待用户自行构建后确认。未找到运行中的调试应用／DTD，热重载未执行成功。
