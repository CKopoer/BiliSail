# 缓冲充足时的播放冻结检测（#83）

日期：2026-11-06。反馈：[issue #83](https://github.com/CKopoer/BiliSail/issues/83)，Windows 11／GTX 1070、发布版 1.2.6+5。长视频的 position 停止，缓存仍领先 94–300 秒，`desiredPlaying=true`、`buffering=false`，没有自动恢复。

## 定位结论

日志不能确认硬解、驱动或 CDN 是冻结根因。`hasDecodedVideo`／`hasVideoOutput` 是已建立解码／输出的元数据，不证明后续画面持续推进；主 demuxer 的缓冲端点同样不证明视频输出正常。

issue 对「缓冲充足就不会进行健康检查」的推断需要修正：[NativePlaybackHealth](../../packages/bili_player/lib/src/native_playback_health.dart) 已有独立的 8 秒总 position 无进展截止时间，不依赖 buffering 或 native error。可确认的代码问题是：

1. [MediaKitEngine](../../packages/bili_player/lib/src/media_kit_engine.dart) 周期检查先等待 `getPropertyAsync('audio-pts')`，但[适配器](../../packages/bili_player/lib/src/native_player_properties.dart)只是把同步 `getProperty` 包在 `async` 方法里，最终同步执行 `mpv_get_property_string`。原生读取若阻塞，外层 `Future.timeout` 和同一 isolate 的健康计时都无法运行。这是可确认的阻塞风险，尚未证明它就是反馈设备冻结时的调用栈。
2. 原健康判断对任意小幅 position 回退重置截止时间，随后微小向前抖动又算进展，可能无限延长停滞窗口。
3. 原实现从长 buffering 退出时，可能直接用已有等待时间判断 8 秒静默停滞，没有留出重新推进的窗口。

## 实现

- 复用 [NativeLoadObserver](../../packages/bili_player/lib/src/native_load_observer.dart) 已有的独立 weak client，通过现有 libmpv 生成绑定的 `mpv_get_property_async` 读取音频时钟。仍每 250ms 采样，最多一个读请求在途；原生不回复时不阻塞 Dart 计时，也不堆积请求。不消费 media-kit 的事件，不改其 wakeup callback，不修改 Pub 缓存或 Git 依赖。
- 健康判断只读音频时钟缓存。暂停、seek 和非活动阶段清空缓存并增加采样代次，迟到回复不能写入新阶段；关闭／换源释放 weak client，旧回调不能访问已销毁句柄。高倍速的音频滞后阈值包含缓存采样的时间余量。
- 总 position 使用 50ms 的累计前进门槛，小幅往返抖动不续期；超过 1 秒的后退仍视为时间轴跳转，显式 seek 继续重置检测。缓存端点增加也不延长停滞截止时间。
- 非 buffering 的总 position 无进展仍在约 8 秒后进入恢复，正常 buffering 保留 30 秒等待；退出 buffering 后给予一次推进宽限，只有确认进展才重新获得宽限，反复切换 buffering 标记不能无限续期。原视频缓冲越界和音频 EOF 检测保持。
- 发出失败前记录 `playbackStalled`，包含 `stallReason`、可用的最后确认音频位置、停滞时长和原有安全快照。恢复用的原生暂停也通过 weak client 异步确认，保留 2 秒截止时间及原来的暂停失败释放路径。
- 共享 [PlaybackSession](../../lib/features/playback/application/playback_session.dart) 的 URL 重解析、备用线路、进度／参数／播放意图保留及次数／deadline 预算继续复用，不新增无限重试，不强制关闭硬解，也不改变有效用户偏好。

## 验证

状态测试见 [native_playback_health_test.dart](../../packages/bili_player/test/native_playback_health_test.dart)，覆盖充足／增长缓存、无日志／无新事件停滞、进度抖动、0.25／1／4／8 倍速缓存采样、长缓冲恢复、暂停／seek／换源／结束和单轨 EOF。采样代次、非法时钟、释放后迟到回复及安全日志字段另有测试。

Windows 受控原生回归见 [windows_video_stall_test.dart](../../integration_test/windows_video_stall_test.dart)。新增用例在缓存充足时直接暂停 native，保持 engine 的播放意图、不注入 native 错误，并按固定核心的暂停适配逻辑抑制这次 `core-idle` 被误当作 buffering。验证约 8 秒触发停滞、实际停止，以及完整会话自动重开并从原位置继续。故障注入模拟健康信号，不等同于重现 GTX 1070 驱动故障。

本次在独立 Git 工作区执行，保留主工作区同期修改与正在运行的程序。复用相同来源的完整 Windows mux 资产；libmpv／ANGLE 归档由构建脚本重新校验哈希。新工作区补齐本机已有 NuGet 工具路径后完成原生构建。测试专用的传递依赖导入用于检查真实 renderer，不增加产品依赖。

- `tool/check.ps1 -SkipPub` 通过：根应用 4502、API 677、播放器 181、弹幕 161、mux 5，共 **5526 项通过**；13 项符号链接用例因本机权限、10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。格式、全目录静态分析和打包边界检查通过，日志 `build/validation/issue83-check-final.log`。
- 三组定向状态／日志回归 **43 项通过**，日志 `build/validation/issue83-unit-final.log`；全目录静态分析无问题，日志 `build/validation/issue83-analysis-final.log`，最终根检查也重新执行分析。
- `tool/test-windows-video-dispose.ps1` **9 项通过**，覆盖原生生命周期、渲染队列和尺寸，日志 `build/validation/issue83-dispose.log`。

- `tool/test-windows-media.ps1` 完整通过，覆盖基础播放、续播、诊断、启动、视频就绪、听视频、SMTC、预览、音量均衡和五分钟缓存。断流／静默冻结分组 **7 项通过**，静默中断分别在 8013ms／8007ms 触发，自动重开保留原位置并继续推进；日志 `build/validation/issue83-windows-media-final.log`。交互桌面分支有 1 项跳过，公网烟测未启用。
- `tool/test-windows-content.ps1` 完整通过，覆盖本地 UGC／PGC DASH、HLS／FLV 共用播放窗、音质切换及直播长网络间隙等待。直播停在 4229ms，补数后从同一连接推进到 6021ms，`requests=1`、`failures=0`；日志 `build/validation/issue83-windows-content-final.log`。公网与保存账号分支未启用。
- 热重载尝试未连接成功，原生验证均通过重新编译测试进程加载改动。文档相对链接与 `git diff --check` 通过。

## 验收边界

本机 SDK 实测 `video-pts` 返回空值，不能把它当作可用的独立视频时钟。当前[官方属性文档](https://mpv.io/manual/stable/#properties)也未提供该属性；不能用近似帧号等总时间派生量冒充独立的 GPU 呈现证据。因此本次覆盖 issue 两段日志都出现的总 position 停止，以及既有的单轨缓冲／音频中断，不宣称已检测所有「音频／总 position 继续但画面不动」的情况。

尚未取得反馈机器冻结瞬间的线程栈，未在 GTX 1070 上进行长视频重现，也未执行 Android／macOS 实机验收。整个 native core 永久死锁时，后续 native 释放仍可能受阻；受控重载通过不能推导为能恢复所有驱动死锁。本轮不提供性能结论，也未重建或替换用户正在运行的 Release。
