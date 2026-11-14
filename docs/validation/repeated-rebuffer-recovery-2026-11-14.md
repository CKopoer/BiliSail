# 点播反复短播与缓存暂停恢复

日期：2026-11-14（Asia/Shanghai）。

## 现场与原因

用户报告系统安装的 BiliSail 播放视频时，进度尚未到缓冲条终点就显示“播放缓冲中”，恢复播放 2–3 秒后再次缓冲。

本机实际进程来自 WindowsApps 的 `JerryHsu.BiliSail_1.2.9.7_x64`。读取其当前进程日志 `playback-1794653792077931-34260.log`，对应 DASH 实例 `playerId=48`：北京时间 19:03:18–19:05:07 有 7 次缓冲开始，6 次已结束的缓冲累计等待 97.730 秒。

- 全程 `generation=1`，没有自动重开，也没有对应的音视频解码错误；不能归因为自动恢复代码反复主动打断。
- 2 倍速，进入缓冲时位置为 10.866、13.200、15.433、19.700、24.700、29.700、31.866 秒。缓冲条估计终点只领先约 145–216 毫秒。
- 原生 `paused-for-cache=true`、`core-idle=true`，前向包缓存大部分为 0，`cache-duration=0`。这是真实缓存暂停，并非只显示了错误文案。音画差约 0–1 毫秒，视频／解码丢帧均为 0。
- 例如 19:03:44 缓冲结束后，媒体位置从 10.900 秒推进到 13.200 秒，19:03:46 再次暂停；随后再等约 26 秒。多次只补入约 2 秒估计缓存就恢复，随后很快再次耗尽。

缓冲条来自 SDK `demuxer-cache-time`，是估计的包时间戳终点，不是每条轨道已可解码、呈现的保证；[mpv 属性说明](https://mpv.io/manual/stable/#properties-demuxer-cache-time)明确将其列为估计值。[原生缓存暂停说明](https://mpv.io/manual/stable/#options-cache-pause-wait)说明缓存耗尽后会暂停并等待补数。因此“播放位置小于估计终点”本身不构成禁止缓冲的条件，不能通过强行清除 buffering 或继续推动进度修复。

已确认的软件缺口是**无错误、持续少量补数的反复缓存暂停没有恢复出口**：

1. `NativeErrorMonitor` 需要错误信号，现场没有这类信号。
2. `NativeBufferRecovery` 负责断流／静默停止预读；每次缓存增长超过 50ms 就取消这次故障探测，持续少量补数会反复清除证据。
3. `NativeVideoBufferMonitor` 专门处理带视频解码错误的停顿，不应拿它把纯缓存暂停归为解码故障。

本轮没有保存、重放现场相同 CDN 的响应，没有证据断言其根因是网络延迟、线路限速、服务端供数或本地读取性能中的哪一种。修复的是已复现的恢复策略缺口，不声称增加带宽或修复了服务器。

## 实现

- 新增 [NativeRebufferMonitor](../../packages/bili_player/lib/src/native_rebuffer_monitor.dart)，只接收原生 `paused-for-cache`，不把 SDK 的一般 buffering／core-idle 当作缓存耗尽。沿用 SDK 事件路由，没有第二个原生客户端或常驻属性轮询。
- 仅对 HTTP(S) 点播／听视频启用；直播、静音预览和本地离线文件不进入该策略。
- 90 秒窗口内至少 2 次有效缓存暂停，扣除按实际倍速换算的媒体推进后累计停滞至少 12 秒，沿用现有失败链交给 `PlaybackSession` 刷新地址和选择备用线路。单次小于 1 秒不计入，最多保留 8 段；第二次暂停仍在进行时，也可由有界定时器触发，无需等它结束或等错误日志。
- 单次普通长等待保持当前连接。补入少量缓存、短播 2–3 秒不会抹掉重复停顿；连续 10 秒且确认媒体按当前倍速推进后才清除证据。
- 暂停、seek、换代、准备、结束与释放清除证据和定时器；迟到结果不能覆盖用户意图。每个源只报告一次。继续使用会话最多 3 次总打开和原有截止预算，不叠加重试，不创建第二路音频。
- 新增脱敏 `repeatedCacheUnderrun` 原因与累计停滞时长，区别于解码故障。没有媒体 URL、Cookie、Token 或账号信息。
- 不改缓存条含义、不隐藏真实缓冲、不修改正常起播门槛、不新增设置／存储迁移／依赖／锁文件。

## 验证

Flutter 3.47.6 / Dart 3.13.5，媒体依赖保持固定提交 `302d60eedc55ca677e911e529569b1e14d8c2e7e`。

- [单元回归](../../packages/bili_player/test/native_rebuffer_monitor_test.dart)覆盖少量补数、2 倍速短播、第二次等待中恢复、单次长等待、正常推进、一般 buffering、健康恢复、窗口淘汰及暂停／seek／代次／准备／结束／释放边界。
- 新增 [Windows 原生 DASH 回归](../../integration_test/windows_rebuffer_recovery_test.dart)，使用本机 HTTP 两条真实音视频轨道：第一次供给约 4 秒媒体、暂停供给 7 秒、再补约 4 秒并继续保持连接。播放器在 2 倍速下实际耗尽两次缓存；Repository 提供健康备用地址。验证自动重新解析、切换两条轨道、保留倍速和播放意图、音视频解码恢复，只有 1 次失败、2 次解析，坏／好线路各 2 次媒体请求。已接入 [缓冲回归脚本](../../tool/test-windows-buffer.ps1)。
- 首次原生回归通过：第一次停在 3.708 秒、第二次停在 7.708 秒，切换后确认推进到 11.750 秒。此为 Debug 受控行为证据，不是性能结论，也不替代现场同 CDN 的复测。
- 以任务开始时 `13f0f64b` 的 `MediaKitBackend`／`NativeLoadObserver` 在忽略目录构成隔离播放器包，保留相同依赖和原生素材，运行同一回归：确实进入两次缓存耗尽，但在等待自动解析／备用线路恢复处超时失败（`windows_rebuffer_recovery_test.dart:163`），形成原始实现失败／修复实现通过的对照。临时 package 路由由 `finally` 按原始字节恢复，并核对 SHA-256；没有改 Pub 缓存或生产文件。
- `tool/check.ps1 -SkipPub` 通过格式、打包边界、根应用与四个包静态分析及 6900 项离线测试：根应用 5487、API 935、播放器 312、弹幕 161、mux 5。13 项符号链接权限用例、3 项未配置原生媒体环境的播放器用例跳过；`BILI_MUX_LIBRARY` 未配置，10 项 mux 原生用例跳过，均不计为原生通过。
- Windows HTTP 初始续播 0／400 秒两项通过；正常直播长等待、短补数后继续等待、充分补数后恢复一项通过，只有 1 次请求、0 次失败。
- 独立本机 HTTP 双轨运行入口经 DTD 热重载成功，运行时错误为空；验证入口关闭前等待播放器释放并关闭本机服务，没有读写账号或凭据。
- 三份受影响文档的相对链接、缓冲脚本 PowerShell 语法及 `git diff --check` 通过。
- 恢复正式 package 路由后，最终 Windows 原生 DASH 用例再次通过，位置仍为 3.708／7.708 秒，备用恢复后到 11.750 秒；Windows x64 普通 `lib/main.dart` Release 构建通过，产物为 `build/windows/x64/runner/Release/bilisail.exe`，须保留完整 Release 目录。构建保留现有 WebView 插件 CMake 警告，没有修改插件缓存。记录见 `native-final.log`、`release.log`，源码及产物摘要见同目录的 `release-manifest.json`。

本轮日志与脱敏现场摘录位于忽略目录 `build/validation/rebuffer-2026-11-14/`。Windows 以外平台未做本轮构建／设备验收；系统安装的商店版不会因为修改源码而自行更新。
