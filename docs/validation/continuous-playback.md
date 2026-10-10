# 连续播放与下一集

日期：2026-10-11。

## 行为与边界

设置的“播放”分类新增“连续播放”，默认关闭，与“自动播放”（打开内容后是否立即播放）分别保存。设置快照 `preferences.v1` 的 schemaVersion 升至 17，旧快照缺失或非布尔值按关闭处理，不修改 SQLite 表结构或清空用户数据。

开启后，普通视频先播放剩余分 P，再进入合集原始顺序中的下一个视频；从稍后再看进入的播放页仍优先沿用原队列。影视按当前正片/SP 分组的原始顺序播放下一集，不受选集面板倒序显示影响。末尾停止且不循环，下一集已知不可播放时停止；播放接口返回权限/网络错误时沿用现有错误提示和显式重试。单个视频、电影、直播与离线文件不会自动跳到推荐内容。

播放/暂停按钮右侧新增“下一集”：宽屏位于底部控件栏，窄屏位于中央播放控件组。连续播放关闭时仍可手动使用，没有下一项时禁用；直播与单文件离线播放不显示。手动切换保留播放/暂停意图，已结束时切换继续播放。自动切换从下一项零点开始，不读取该项本地或云端续播位置。

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
