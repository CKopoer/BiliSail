# 跳转后音视频同步恢复

日期：2026-11-07。Windows 用户反馈点击进度条后音频先开始，视频仍在准备，产生约 1–2 秒的暂时不同步。本文记录 media-kit 共享后端的修复；不将用户反馈中的时长作为本机测量结果。

## 原因与修复

[MediaKitEngine.seek](../../packages/bili_player/lib/src/media_kit_engine.dart) 原先只等待 position 距目标不超过 250ms。mpv 在目标视频数据到达之前就可能更新 time-pos，命令确认和位置更新不能证明目标画面已准备好。原生受控测试故意延迟视频 HTTP Range 响应、让音轨保持可用，修改前的播放／暂停两个用例均提前结束 seek。

现在有视频轨道的 seek 先暂停同一个 native player，使声音和画面一起等待。在既有 weak client 中观察本次 `MPV_EVENT_SEEK` 及随后 `MPV_EVENT_PLAYBACK_RESTART`，同时确认暂停状态下的目标位置，才按用户意图恢复播放。该事件的用途见固定 SDK 的生成绑定注释及 [mpv 事件文档](https://mpv.io/manual/stable/#list-of-events)。不解析 native 日志，不轮询同步 FFI，不修改 Pub 缓存或媒体 fork。

- 源内 seek 计数使首次打开／前一次完成的信号不能满足下一次等待；源 generation 继续隔离新旧播放器。沿用 seek 的 12 秒总准备预算和命令超时，不额外延长加载窗口。
- 新跳转会取消旧目标的等待，并跳过尚未执行的旧请求；旧请求不会被当作失败触发自动恢复。会话层也记录请求代次，只有当前 seek 可以确认弹幕位置、刷新对应窗口及保存续播检查点。
- 手动暂停的请求代次在调用时立即记录，包括 seek 尚未进入命令队列执行的情况；等待结束后不能覆盖暂停意图。stop／换源仍通过原 generation 信号取消等待。
- 纯音频沿用既有位置确认，不等待视频事件。正常 seek 不重建引擎、不清空纹理，不改变音量、倍速、解码偏好或音频缓冲配置。
- 共享播放页在 `isSeeking` 时保留原视频 surface，居中显示准备提示；普通／全屏、控件展开／收起一致。只在目标就绪后清除 seeking，避免误导性地提前结束加载。

## 验证

- [原生信号状态测试](../../packages/bili_player/test/native_load_observer_test.dart) 18 项通过，新增覆盖首次 restart 不能完成新 seek、连续 seek、旧时钟失效及释放后的迟到事件。
- [共享播放控件测试](../../test/features/playback/playback_panel_test.dart) 的六种窄／宽／全屏及控件显隐组合通过，seek 提示出现时保持原 `VideoSurface` state。
- [会话测试](../../test/features/playback/playback_session_test.dart) 新增连续 seek 的检查点隔离：修改前旧请求会保存过期检查点，修改后只有最新请求保存。
- [Windows 同步回归](../../integration_test/windows_seek_synchronization_test.dart) 使用本地无账号 DASH、1 秒预读，阻止目标视频响应而保持本地音轨可用；检查 seek 未提前完成、两轨暂停、等待期间的音频时钟、目标帧像素、恢复后的 avsync，以及原本暂停、立即暂停、等待中暂停、stop 和改目标等行为。已接入 [完整 Windows 媒体验证脚本](../../tool/test-windows-media.ps1)。
- 同步组最终六项通过：视频被阻止时等待 1.5 秒不恢复音频，补数后 300ms 采样已出现不同于旧位置的非黑画面；正常／改目标后恢复的后端 avsync 分别为 0.000069／0.000372 秒，低于 150ms 断言阈值。首次像素验证曾在第六个夹具的跳转前取到尚未解除首帧遮罩的画面；补齐 `VideoFrameReadiness` 等待及遮罩移除的绘制帧后，六项重跑通过，不放宽目标帧或时钟断言。
- `tool/check.ps1 -SkipPub` 通过：根应用 4558、API 678、播放器 196、弹幕 161、mux 5，共 5598 项通过。格式、静态分析及打包边界检查通过；最终像素测试另做定向静态分析，无问题。13 项符号链接用例因本机权限、10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。
- Windows 媒体各分组最终 45 项通过、1 项交互桌面用例按开关跳过，包含基础分轨、重播、诊断、启动取消／超时、视频就绪、纯音频、系统媒体、断流／静默冻结、上述六项同步、预览、音量均衡、fvp 既有回归和五分钟缓存窗口外 seek。完整脚本首轮在新夹具的首帧采样处失败；修正夹具后重跑同步组，并单独续跑余下各组，未将首轮脚本记为整次通过。对应日志为 `seek-sync-windows-media.log`、`seek-sync-native-pixels.log`、`seek-sync-media-tail.log`，公网分支未启用。
- 后续主工作区出现同期播放信息功能修改，当时在 `ConfigurablePlayerEngine.inspectPlaybackInformation` 处编译失败。本次没有修改该功能，最终构建使用 `ae75579` 加本次补丁的隔离工作区；MDK／libmpv／ANGLE 复用本机固定归档，仍按原清单检查摘要，独立 mux 使用相同来源的现有构建资产。
- 隔离工作区的本地 DASH fixture 完成 Windows Debug 热重载，未发现运行时错误；随后通过控制端口等待播放器释放并退出，没有运行真实账号流程或替换已安装应用。
- 隔离工作区的普通入口 `flutter build windows --release --no-pub -t lib/main.dart` 成功（259.0 秒）；完整 Release 目录保存到 `build/validation/seek-sync-release/`，入口 `bilisail.exe`，须保留全部 DLL 与 data。AOT `data/app.so` 的 SHA-256 及构建日志留在本地验证产物中；没有将混合工作区的编译失败表述为通过，也没有发布安装包。
- 同期功能随后独立提交为 `a5620ac`；本次补丁与其合并后，全目录静态分析无问题，连续 seek 检查点及六种共享播放控件回归共七项再次通过。Release 验证产物仍是上述隔离基线，未混入该同期功能。

本地日志位于忽略目录 `build/validation/seek-sync-*.log`。原生回归使用 Windows Debug 和零音量；时钟、暂停标志与纹理检查不替代真实账号 CDN、人工可听和长视频验收。Android／macOS 设备未在本轮验证；fvp 的既有受控烟测通过，但本次延迟视频 seek 的修复与专项仅针对 media-kit，不提供性能结论。

## 后续：准备中改目标立即替换旧读取

同日用户要求跳转未加载完时直接转向新目标。加强原生夹具后发现，仅取消 Dart 等待仍可能被 mpv 的旧 HTTP 读取拖住。现在视频 seek 尚在准备时，直接在同一个 native player 上执行 `loadfile replace`，以最新位置重新加载当前源，保留相同纹理、分轨请求头和用户播放意图；不创建第二个会话或音频。使用公开 NativePlayer 命令，不修改媒体 fork 或 Pub 缓存。

重新加载开始与完成使用独立的 load／restart 计数确认，旧 seek 的完成不能解锁新目标；on_preloaded 应用最新位置，覆盖原媒体的旧续播起点。重加载中的暂时空 tracks 仍沿用已确认的视频属性，继续等待视频后再恢复；只取消文件读取，不调用会清空画面的 Player.open／stop。原生自有媒体选项与请求头仍沿用当前源的加载 hook。纯音频保留既有 seek 路径。

Windows 专项增加连续第三次改目标、重加载中暂停及停止。旧 HTTP 响应保持不返回，仅放行新请求，确认最新目标先完成、重加载期间非黑、源代次与 native player 保持一致及恢复后的 avsync；最终九项通过。完整记录、fvp 对应实现及两后端检查边界见 [准备中替换目标](fvp-seek-synchronization-2026-11-07.md#后续未加载完时直接转向新目标)。
