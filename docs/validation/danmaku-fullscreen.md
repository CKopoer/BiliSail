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
