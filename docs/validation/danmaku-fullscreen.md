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
