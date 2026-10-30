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
