# 连续播放与下一集

日期：2026-10-11。

## 行为与边界

设置的“播放”分类新增“连续播放”，默认关闭，与“自动播放”（打开内容后是否立即播放）分别保存。设置快照 `preferences.v1` 的 schemaVersion 升至 17，旧快照缺失或非布尔值按关闭处理，不修改 SQLite 表结构或清空用户数据。

开启后，普通视频先播放剩余分 P，再进入合集原始顺序中的下一个视频；从稍后再看进入的播放页仍优先沿用原队列。影视按当前正片/SP 分组的原始顺序播放下一集，不受选集面板倒序显示影响。末尾停止且不循环，下一集已知不可播放时停止；播放接口返回权限/网络错误时沿用现有错误提示和显式重试。相关视频默认不接续；2026-10-30 新增的独立开关见下节。电影、直播与离线文件不会自动跳到推荐内容。

## 相关视频接续（2026-10-30）

设置“播放”分类增加“连续播放相关视频”，默认关闭，独立于“自动播放”和原有“连续播放”保存。`preferences.v1` 快照版本升至 33；缺失／非法值回退关闭，恢复默认同样关闭，不修改 SQLite schema。

普通视频当前分 P 和合集已无下一项时，开启该设置可自动接续经过现有推荐过滤的首个其他相关视频，从零点开始。只开启此项不会跳过尚未播放的分 P／合集；这些内容仍由原有“连续播放”控制。稍后再看、UP 播放列表等显式队列保持末尾停止，影视／直播／离线不接入相关视频。

相关列表正在加载时最多等待 25 秒，失败显示提示并停止；空列表停在末尾。等待期间关闭设置、暂停、切源、账号变化或页面销毁会拒绝旧结果。同源重复 EOF 只触发一次，原播放页原地推进，不抢走隐藏标签的焦点。

手动听视频和 Android 自动后台听视频都在分 P、合集、队列、影视和相关视频接续时继承。显式下一项意图优先于旧页面的视频模式检查点，避免重访下一项时意外退出听视频。后台自动模式不写入检查点，回前台恢复原模式；详见[Android 后台听视频](android-background-playback.md)。

播放/暂停按钮右侧新增“下一集”：宽屏与窄屏均位于底部控件栏左侧，展开弹幕输入时仍保留。连续播放关闭时仍可手动使用，没有下一项时禁用；直播与单文件离线播放不显示。手动切换保留播放/暂停意图，已结束时切换继续播放。自动切换从下一项零点开始，不读取该项本地或云端续播位置。

## 完播后手动重播（2026-10-31）

点播结束后，再次点击播放按钮或收到系统播放命令时，先跳转到零点，等后端确认位置后明确发送播放命令。复用当前媒体源和播放器，保留倍速、音量与清晰度；普通暂停后继续仍从暂停位置播放。重播等待期间的手动暂停和播放许可撤销仍然生效。

播放阶段和 `desiredPlaying` 是独立状态。结束后跳转可能保留旧的播放意图，不能仅根据该标记跳过播放命令。会话回归覆盖结束时意图标记的两种取值、按钮／系统播放入口，以及跳转期间的暂停和许可撤销；原生回归入口为 [playback_replay_test.dart](../../integration_test/playback_replay_test.dart)，使用本地 DASH 音视频分轨检查实际完播、零点重播、双轨解码和普通暂停恢复。

本轮 `tool/check.ps1 -SkipPub` 在执行时的工作区快照通过：根应用 3677、API 497、播放器 101、弹幕 136、mux 5，共 4416 项；13 项符号链接用例和 10 项未配置 `BILI_MUX_LIBRARY` 的原生 mux 用例跳过。追加的重播竞态定向回归和受影响文件静态分析通过，日志为 `build/replay-check.log`、`build/replay-race-tests.log`、`build/replay-target-analysis.log`。

Windows 在独立源码副本重新编译并通过上述原生完播／重播用例，播放会话源码与本次提交暂存内容一致，日志为 `build/replay-native-after.log`；普通 Windows EOF 原路径可重播，保留旧意图的边界由 fake engine 回归覆盖。Android/macOS 实机与人工音画同步未验证；没有活动 DTD/debug 会话可供热重载，原生验证使用重新编译的测试进程。

Windows 受控媒体回归的基础播放、重播、诊断、启动、就绪、听视频、系统媒体控制、断流、预览、音量均衡和缓冲组最终均通过，未开启公网烟测。主脚本在音量均衡组启动前因 Flutter 临时报告 `Could not determine engine revision` 退出，确认固定 SDK 正常后单独续跑最后两组通过；日志为 `build/replay-snapshot-windows-media.log` 和 `build/replay-windows-media-remaining.log`。

## 实现

`video_playback_sequence.dart`、`pgc_playback_sequence.dart` 为纯 Dart 顺序规则，页面提供共享 `PlaybackPageCommands`。`PlaybackPanel` 订阅确认结束状态，延后至当前事件结束再执行，并核对播放 owner、source generation、当前媒体身份与最新设置；同源重复结束事件只推进一次。`PlaybackSession.prepareNextVideo` 记录播放意图、起始位置及账号 scope/session epoch，换源时检查并消费。合集加载下一视频详情期间保留当前播放器 owner；标签路由原地更新，隐藏播放标签推进不抢焦点。

普通与全屏视图共享一个会话和最新页面命令通知器，切换内容后全屏下一集状态与回调同步更新。高频播放位置不重建内容页面，无新增原生库、网络端点或账号写入。

## 验证

自动化覆盖旧设置兼容、保存/重载、分 P 优先、合集及稍后再看顺序、影视分组/权限边界、关闭时不推进、手动下一集、重复 EOF、零点开始、暂停意图及账号 epoch 拒绝。组件覆盖 390/1400 像素、普通/全屏及隐藏影视页，并模拟下个视频详情加载间隙。

`tool/check.ps1 -SkipPub` 通过：根应用 1708 项、bili_api 379 项、bili_player 34 项、bili_danmaku 84 项、bili_mux 2 项，共 2207 项通过；7 项需外部 `BILI_MUX_LIBRARY` 的测试按既有配置跳过。根与各包格式、静态分析通过，日志为 `build/continuous-playback-check.log`。

Windows 本机原生回归通过：`tool/test-windows-media.ps1` 的基础播放 8 项、失败诊断 1 项、启动 4 项、预览缓冲 1 项、普通播放缓冲 1 项；`tool/test-windows-content.ps1` 的影视/直播 2 项；`windows_watch_later_queue_test.dart` 的连续队列 1 项。队列以本地分轨夹具验证暂停意图、隐藏播放页 A1→A2→B、详情加载间隙同一播放器与末尾停止。日志分别为 `build/continuous-playback-native-media.log`、`build/continuous-playback-native-content.log` 和 `build/continuous-playback-native-queue.log`。

原生控件回归最初在固定等待 400 毫秒后检查淡出完成时失败，诊断时淡出透明度仍为 0.5。测试改为沿用已有有界等待，直到实际渲染移除控件，再检查普通/全屏显隐；生产淡出与隐藏计时未调整。修正后上述原生回归完整通过。

`flutter build windows --release --no-pub` 成功（47.1 秒），产物为 `build/windows/x64/runner/Release/bilisail.exe`，日志为 `build/continuous-playback-windows-release.log`。既有 WebView 插件 CMake CMP0175 开发警告不阻断构建。文档相对链接与 `git diff --check` 通过。

Android/macOS 与真实账号连续播放尚未验证；本轮未启用在线 smoke，没有自动执行账号写操作。
