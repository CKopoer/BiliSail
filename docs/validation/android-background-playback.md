# Android 后台听视频与相关视频连播

日期：2026-10-30。

## 行为与边界

- Android 收到 `hidden`／`paused` 后，当前播放 owner 自动切换独立音轨并继续播放；只进入 `inactive`（例如临时系统遮挡）不切源。隐藏的工作区播放页仍按播放所有权处理系统生命周期。
- 回到 `resumed` 恢复退后台前的模式。手动开启听视频的页面继续听视频，原来是视频的页面恢复 DASH；暂停意图、确认进度、倍速和音量保留，不因回前台自动播放已暂停或播完的内容。
- 后台状态是会话的临时覆盖，不保存为用户设置或页面检查点。新分 P／剧集／视频、重试、清晰度切换继续经过同一模式选择；后台期间打开的新源不会先打开视频流。
- 视频、影视与离线 DASH 分轨支持独立音轨。直播、渐进 MP4 和合并离线文件没有独立音轨时维持暂停；听视频的下一项不支持独立音轨时明确报错，不回退下载混合视频。直播音频流接入不在本轮范围。
- 共享 Android 媒体通知继续控制原会话。`audio_service` 设置 `androidStopForegroundOnPause: false`，避免换源／下一项间隙的暂停撤下前台服务；停止、关闭播放、退出／任务移除仍沿用既有清理。暂停时保留媒体通知，用户可通过停止按钮结束。
- iOS 和桌面的前后台策略保持各自既有行为。当前没有 Android 实机连接，构建与自动测试不能代替系统锁屏、通知权限、音频中断、电池管理和长时间后台验收。

## 连播与模式所有权

“连续播放相关视频”默认关闭，行为和持久化见[连续播放记录](continuous-playback.md#相关视频接续2026-10-30)。显式播放队列在末尾停止，相关视频应用现有推荐过滤，失败不自动重试写请求或改变账号状态。

会话分别保留手动听视频意图和 Android 后台覆盖。分 P、合集、稍后再看、影视下一集和相关视频通过已有下一项意图继续，优先继承当前手动模式，避免旧检查点意外恢复视频。快速退后台／回前台沿用 source generation 与取消隔离，迟到音轨请求不能覆盖前台 DASH。

## 自动与原生验证

定向测试覆盖模式往返、手动暂停、倍速／音量／进度、初次解析及快速切换竞态、检查点隔离、无独立音轨和完播后恢复；组件测试覆盖 Android 生命周期、分 P／合集／相关视频、显式队列末尾、影视换集、等待期间暂停／设置／账号／销毁及网络失败。设置测试覆盖缺失／非法值、保存、重载、恢复默认及保存失败回退。

本轮执行：

- 根脚本分阶段完成：`tool/check.ps1 -SkipPub -Stage Lint` 的打包边界、全仓格式、根与 Linux 适配器分析通过；`RootTests` 为 **3554 通过、13 既有条件跳过**；`PackageTests` 为 bili_api **496**、bili_player **96**、bili_danmaku **118**、bili_mux **5** 通过。10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计原生覆盖。
- 最后补上“后台被系统停止后，回前台不重开旧源”用例。共享构建目录随后出现 `sqlite3.dll` 占用，因此从 `1a3771e` 加本任务补丁创建独立源码副本；排除同期未提交功能后，播放／生命周期／系统媒体／设置的 **470 项定向回归全部通过**，独立根 `lib` 分析无问题。独立副本的全仓分析第一次因四个包未解析各自 dev 依赖失败；根工作区的完整分析已按脚本通过。
- Android 普通入口开发 **Release／arm64／AOT** 最终构建通过，使用测试包名 `dev.bilisail.bilisail.test`、名称 `BiliSail 测试版`、版本 `1.2.5+1`（共享工作区当前版本）、versionCode `12501`，沿用原开发签名并校验不可调试。APK：`build/development/android-arm64/BiliSail-test-arm64-release.apk`；SHA-256：`0d3ebc9c643c69509ef49d148f7850768b59b4f77a271d198db1903c551ce44b`。没有安装、卸载或清理设备数据。
- 本轮 164 个文档本地链接与 `git diff --check` 通过。日志位于 `build/validation/background-audio/`：`lint-final.log`、`root-tests.log`、`package-tests.log`、`task-source/task-tests-cached.log`、`task-source/task-lib-analyze.log`、`android-release-final.log`。

Android 锁屏、系统媒体按钮、长时间后台、真实账号和在线媒体未验收，未做性能测量或其他平台构建。

## Windows 补充回归

- `tool/build-download-mux.ps1 -Target windows-x64` 成功；组件构建不替代 mux 原生测试。
- 在独立源码副本执行 `integration_test/audio_only_playback_test.dart -d windows`，**1 项通过**。本机 HTTP 分轨夹具确认：手动听视频及自动后台听视频只请求音轨；后台换 P 仍为音轨、音频实际解码且没有视频输出；回前台恢复 DASH 视频并保留暂停。没有访问公网媒体或真实账号，日志：`build/validation/background-audio/runtime/native-audio-cached.log`。
- 首次隔离构建缺少 NuGet 路径，随后 SQLite／media-kit 下载遭遇 TLS 握手失败。补齐本机 `.dart_tool/native-tools/nuget.exe` 的 PATH，并复制既有构建钩子的下载缓存到隔离目录；SQLite 与固定 media-kit 钩子继续校验 SHA-256，没有修改 Pub 缓存、校验规则或 TLS 设置。最终 Windows Debug 构建及原生用例通过。
- 使用经过定向验证的本任务应用源码启动独立 Windows 调试入口；入口不恢复真实账号、不打开用户数据库、不请求媒体。DTD 连接后热重载成功，运行时错误查询为空，验证后已退出该程序。没有操作用户正在运行的正式客户端。

## 退后台仍暂停的修正（2026-10-31）

用户反馈实际退后台后仍暂停。复查固定 media-kit 依赖发现两个未覆盖路径：

- `media_kit_video` 的真实 `Video` 控件默认 `pauseUponEnteringBackgroundMode: true`，在 `paused`／`detached` 时直接暂停原生 Player。此前根应用的 fake engine 生命周期测试未挂载该真实控件，无法捕获这条绕过会话的命令。
- 所有换源都无条件创建 `VideoController`；固定依赖的控制器构造需要等待 `addPostFrameCallback` 才能完成原生初始化。进入 `paused` 后 Flutter 不再生产帧，纯音频也可能因此卡在打开流程。此前原生测试持续 pump 帧，没有模拟这一约束。

修正后，视频输出显式关闭控件自身的自动暂停／恢复，生命周期仍由 `PlaybackSession` 统一决定，因此 Android 自动听视频与 iOS 既有暂停策略分别保留。主应用将已确认的独立音轨标记为 `ProgressiveSource.isAudioOnly`；引擎对该类源完全跳过视频控制器与 surface 初始化，并在播放时验证实际音频解码。发现意外视频轨时拒绝该音频源，不静默回退混合视频。

新增真实视频控件的生命周期回归，覆盖进入后台前播放／暂停和后台手动暂停后回前台。原生用例改为真正发送 `inactive → hidden → paused`，确认 `framesEnabled == false`，同时用 `benchmark` frame policy 关闭测试框架的强制帧并监测 post-frame 回调，确保后台没有实际绘制帧；在没有 pump 的异步区内切音轨、检查进度推进并换下一 P，最后恢复前台视频和暂停意图。

本轮结果：

- `tool/check.ps1 -SkipPub` 完整通过：根应用 **3649**、bili_api **497**、bili_player **101**、bili_danmaku **136**、bili_mux **5** 项通过；根应用 13 项既有条件跳过，mux 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不算原生覆盖。格式、静态分析和打包边界通过；强化后的集成测试另行静态分析无问题。日志：`build/validation/background-pause-fix/check-final.log`、`integration-analysis.log`。
- Windows 本地分轨原生对照：只在隔离源码副本临时撤掉独立音轨标记，严格无帧用例在后台切源处 **8 秒超时**；恢复标记后 **1 项通过**，并确认后台无 post-frame 回调、只请求音轨、进度推进、后台下一 P、前台恢复视频及手动暂停意图。对照期间保留视频控件生命周期修正，单独复现控制器初始化等待。日志：`build/validation/background-audio/runtime/native-background-before-strict.log`、`native-background-final.log`。
- 当前共享工作区的普通入口 Android arm64 开发 Release／AOT 重建通过，包名 `dev.bilisail.bilisail.test`、版本 `1.2.5+1`／12501，签名与不可调试检查通过。测试包仍位于 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256：`b0ba63ce486f1b817252170fb3181f57e813604062baffbf92b25f9b191acb15`。日志：`build/validation/background-pause-fix/android-release.log`。没有连接 Android 设备或安装操作，系统锁屏、长时间后台和真实媒体仍需实机确认。
- Windows 独立调试入口热重载成功；补齐调试入口自己的 `AppNoticeHost` 后，运行时错误查询为空，验证后已退出。该入口不加载真实账号或用户数据库。
