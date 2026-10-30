# 双轨中断同步与自动重试

日期：2026-10-30。用户反馈视频流停止但音频继续，要求音视频共同等待，并对两种流的加载失败自动重试。

## 原因与证据

当前锁定的 Predidit media-kit 为 `83b7ca63772856e1ea0158916177e136f7b7b0be`。应用用一个 mpv 播放视频，通过 `audio-files` 装载独立音轨。单个轨道提前 EOF 不一定结束整个文件；外部音频或视频仍可推进总 position。已有的错误监测把总 position 推进当成恢复，不能证明两轨都正常。

2026-10-28 的视频断流保护仍存在，但只检查视频主 demuxer 缓冲，要求位置越界 500ms 后持续 1 秒；不能检测音频先耗尽，且正常 buffering 被排除、没有错误日志时也没有总停滞截止时间。会话只有 `videoInterrupted` 能自动重载一次；普通 native 加载失败与音频中断没有统一的 URL 刷新恢复。

[mpv 官方手册](https://mpv.io/manual/stable/#properties-demuxer-cache-state)说明缓存状态只反映主 demuxer；[audio-pts](https://mpv.io/manual/stable/#properties-audio-pts)反映音频设备延迟后的音频位置，启动时可能为负。[cache-pause](https://mpv.io/manual/stable/#options-cache-pause)处理普通缓存不足，但不能保证单轨提前 EOF 后另一轨也等待。仅把 Dart phase 改成 failed 同样不会实际停止 native 音频。

本轮本地 HTTP/Range 故障注入分别只发送视频或音频前三分之一，声明完整长度后断开，并拒绝后续 Range。最终回归中视频故障确认的恢复位置为 3791ms，音频故障为 3212ms；音频故障时视频已缓冲到 11875ms，证实不能用视频 buffer 代替音频健康检查。故障资源恢复后，两种完整会话均自动重开并推进超过 6 秒。没有取得本次用户故障时刻的原始网络证据，不将此复现当成某个真实 CDN、显卡或驱动故障的证明。

## 实现边界

- [NativePlaybackHealth](../../packages/bili_player/lib/src/native_playback_health.dart)替代只监视视频的检测器。带外部音轨的 DASH 位置超过视频 buffer 250ms 时停止这组播放；音频时钟落后播放位置超过 750ms 时回到音频边界恢复，音频 EOF 后属性不可读时保留最后有效时钟，负启动时间不作为恢复位置。两轨均没有进展或持续 buffering 达 8 秒，即使没有错误日志或位置事件也进入失败恢复。接近正常末尾保留 500ms 容差；未知时长不禁用单轨检测。
- [MediaKitEngine](../../packages/bili_player/lib/src/media_kit_engine.dart)显式配置并回读 `cache-pause=yes`，由 mpv 对正常缓存不足暂停两轨；健康检查仅在有播放意图的活动阶段每 250ms 读取一次，只有 DASH 外部音轨需要额外读取 `audio-pts`。不经过全局 Provider，也不逐帧读 FFI。暂停、seek、换源、停止和释放取消计时，异步采样核对 player、generation 和 timer 身份，旧采样不得影响新源。
- 检测到中断先冻结恢复位置、暂停 native player，再发失败；暂停失败或超时则释放旧播放器。命令失败也先停止 native 输出，避免错误状态下仍有声音。保留同一个原生播放器内的正常音画同步，不拆成两个 Player。
- [PlaybackSession](../../lib/features/playback/application/playback_session.dart)对可恢复的 native/视频中断以及网络/超时解析错误自动重试。重新解析有效地址，已接受媒体在播放途中中断时优先尝试本次响应的备用 CDN；没有备用也可刷新同一资源。保留目标、进度、清晰度、配音、听视频模式、倍速、音量与最新播放意图，直播重新从实时点打开。
- 第一次恢复立即排队，第二次退避 1 秒。普通 CDN 备用和跨解析重试共享最多三次 native open，累计 native 准备预算为 35 秒，不能通过重载获得新的完整预算；退避计入预算，暂停用户时间不计入音频初始准备。连续正常推进 30 秒后重新获得额度，避免一次早期故障永久禁用后续自动恢复。显式手动重试与新内容另建预算。
- 暂停、播放许可撤销、换源、停止、关闭和账号 scope/epoch 改变取消或隔离恢复；恢复期间的暂停保持暂停。离线文件、非法源、权限和鉴权等错误不做网络重放。日志仍只输出既有脱敏字段，不落盘媒体 URL 或凭据。
- 后续按用户要求补齐中央提示：`PlaybackSession.isRecovering` 覆盖排队／1 秒退避和整次自动恢复，直到地址解析、native open、首次音频就绪检查全部结束。共享播放面板在缓冲、准备或自动恢复期间持续居中显示转圈与“正在准备音视频…”，不依赖控件展开或窗口布局；保持 `isResolving` 原有含义，不将等待重试冒充源解析。结束恢复的回调核对源代次，暂停、撤销许可、停止与换源清除旧状态，重试耗尽转入错误提示。

## 验证

- [Windows 故障注入](../../integration_test/windows_video_stall_test.dart)最终五项通过，覆盖短暂视频缓存不足的共同等待／恢复，视频／音频中断、native 实际停止和完整会话自动重载，日志 `build/validation/av-sync-native-final.log`。补数用例在 3583ms 等待，500ms 静置后位置不再推进，补齐数据后无需重开推进到 6125ms；中断用例既检查冻结的应用快照，也通过 `inspectDiagnostics()` 独立读取 media-kit 内部位置，避免快照冻结掩盖底层继续播放。测试使用零音量，不等同于人工可听验收。
- [纯状态回归](../../packages/bili_player/test/native_playback_health_test.dart)覆盖单轨 EOF、无错误停滞、正常推进、暂停／seek／代次／结束、未知 buffer／时长及负音频启动位置；[会话回归](../../test/features/playback/playback_session_test.dart)覆盖双轨恢复、备用选择、打开次数和 deadline、退避与取消、恢复额度重置、旧响应隔离和参数保留。
- `tool/check.ps1 -SkipPub` 在执行时的工作区快照通过：根应用 3597、API 496、播放器 99、弹幕 118、mux 5，共 **4315 项通过**；13 项 Windows 符号链接用例因权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。日志 `build/validation/av-sync-check.log`。后续新增补数／底层时钟断言由上述五项原生测试验证；本任务定向静态分析与后续全目录静态分析均无问题，日志 `av-sync-target-analysis.log`、`av-sync-final-analysis.log`。
- Windows 的 HTTP 脱敏诊断、启动终止／取消／超时、视频就绪／seek、纯音频、SMTC、五项双轨故障、预览缓冲、音量均衡和五分钟缓冲分组分别通过。`tool/test-windows-media.ps1` 在首文件的一项窄窗控件断言失败后退出：`windows_playback_test.dart:726` 在 640 宽度查找不存在的 `player-collapsed-progress`（当前窄窗布局不构建该条），所以完整脚本不能标为通过；该文件其余六项受控用例通过，公网分支未启用，后续分组另行顺序继续执行。首文件日志 `build/validation/av-sync-windows-media.log`，后半段原生输出保存在 `build/validation/av-sync-native-extended.log`。继续执行时首次漏设 SMTC fixture 脚本环境变量的启动断言失败，按原脚本补齐 `BILI_TEST_SYSTEM_MEDIA_SCRIPT` 后通过，未修改媒体键实现或窄窗界面。
- `tool/build-download-mux.ps1 -Target windows-x64` 从固定 FFmpeg `n9.0.2` 来源重新准备组件通过，来源归档哈希仍为 `6e374ed621e48faa40639307dff48ba6fe574a509977956d2cce9669b7cc27e9`；日志 `build/validation/av-sync-mux-build.log`。普通入口 `flutter build windows --release --no-pub -t lib/main.dart` 通过（72.0 秒），日志 `build/validation/av-sync-release.log`；运行入口 `build/windows/x64/runner/Release/bilisail.exe`，须保留整个 Release 目录。构建针对执行时的工作区，未制作或替换系统安装包。
- 文档相对链接、受影响文件格式与 `git diff --check` 通过。无活动 DTD/debug 应用连接，热重载尝试未能执行；原生验证使用重新编译的测试进程，Release 为重新生成的 AOT 产物。

Android/macOS 实机、真实账号长时间 CDN 故障恢复和人工音画同步尚未验证。缓存充足但 GPU 呈现停止不属于此处 buffer／audio-pts 能直接证明的范围，本轮没有改变硬解偏好或原生输出补丁。

## 中央提示补充验证

新增 10 项组件回归通过：窄窗／普通／全屏各自组合控件展开／收起，覆盖缓冲、完整 999ms＋1ms 退避、延迟解析、native 已报告 playing 但音频准备仍未完成、成功消失与额度耗尽；另覆盖暂停、撤销许可、停止和换源后不残留提示。修改前六种布局组合均在退避阶段找不到中央提示，修改后全部通过；日志为 `build/validation/retry-overlay-before.log`、`build/validation/retry-overlay-after.log`。这些用例使用 fake repository/player 与测试时钟，不依赖网络或账号。

补齐提示后再次执行 `tool/check.ps1 -SkipPub` 通过：根应用 3609、API 496、播放器 99、弹幕 118、mux 5，共 **4327 项通过**；13 项符号链接和 10 项未配置 `BILI_MUX_LIBRARY` 的原生 mux 用例跳过，不计为通过。日志 `build/validation/retry-overlay-check.log`。五项 Windows 受控缓冲／断流／自动恢复原生回归再次通过（`retry-overlay-native.log`），正常入口 Windows Release 再次构建通过（71.2 秒，`retry-overlay-release.log`），运行路径仍为 `build/windows/x64/runner/Release/bilisail.exe`，保留整个 Release 目录。未重复执行前述存在窄窗控件断言失败的完整媒体脚本，也未新增 Android/macOS 实机验收。
