# fvp 连续跳转与片尾竞态

日期：2026-11-08（Asia/Shanghai）。用户在 Xiaomi 13 的普通入口开发 Release `1.2.8+5` 连续拖动进度条后看到“fvp 跳转失败”。

## 证据与原因

设备保留的脱敏日志显示，10:36:47 的失败位置为 75533ms，媒体时长为 75567ms，处于最后一帧附近。日志没有记录该次 MDK seek 返回值，不能仅凭这份日志确定每次拖动的具体顺序。

同机、同签名的 Release 本地 DASH 分轨夹具先确认普通单次跳转正常；随后连续跳至片尾附近、再次跳到片尾，在兼容输出得到 MDK `-2`，直出得到 `-3`，均进入同样的失败提示。固定 SDK 的 [Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#bool-seekint64_t-pos-seekflag-flags-stdfunctionvoidint64_t-ret-cb--nullptr) 定义：`-2` 是前次跳转仍未完成，`-3` 是媒体已卸载；状态请求异步执行，EOF 可能先释放管线，再送达 Dart 状态事件。

原实现只依据异步的 `_ended` 标记重新准备，所有负返回值直接导致播放失败。另有两处隔离缺口：跳转中的旧 EOF 会清除 `isSeeking`，使下一次拖动不能取消在途准备；旧跳转抛出的异常只检查源代次，没有检查跳转代次。

扩大为每种输出／意图三轮原生回归后，进一步捕获 fvp 绑定在 `Libfvp.seek` 直接返回 false 时映射的 `-10`，以及 Android 主进程将最新确认位置 2000ms 又覆盖成旧采样位置的问题。第一次四组 Release 复现通过并未覆盖这两个缺口，最终验收保留更严格的多轮回归。

## 修复边界

- 跳转中的 EOF 不发布为当前会话的结束状态；普通播放结束仍走原结束与重播流程。
- 只有当前跳转代次可以发布失败或中断 native player。
- 最新目标遇到 `-2`／`-3`／绑定拒绝请求的 `-10` 时，在原有 15 秒总预算内最多恢复一次同一源、同一播放器与纹理，重新挂载外部音轨并等待目标解码。IO／范围错误不因此自动重试。
- 连续改目标复用已完成的取消屏障，避免重复停止同一个已退役管线；每个异步边界检查跳转代次，取消中的旧操作不能继续发出下一条原生命令。
- Android 直出在重新准备后同样确认 native pause；兼容渲染保留既有异步暂停和 seek 回调边界。没有通过关闭硬解、切换后端或永久保持 EOF 管线来绕过问题。
- Android 位置采样和状态事件携带跳转代次，准备期间不发送会改变播放状态的事件，主进程丢弃旧时间线事件并立即保存成功 seek 的确认位置；旧请求的迟到回复不能覆盖新位置，也不能将新目标误报为提前结束。

## 回归入口

- [跳转协调测试](../../packages/bili_player/test/fvp_seek_test.dart)：EOF 与暂停竞态、`-2`／`-3` 有界恢复、准备／暂停／seek 中取消、真实错误不重试。
- [引擎测试](../../packages/bili_player/test/fvp_engine_test.dart)：旧 EOF 与旧异常不能清除最新目标，也不能恢复旧播放意图。
- [真实播放器回归](../../integration_test/fvp_seek_end_test.dart)：连续跳到片尾、再次跳转、返回前段、暂停、正常结束与重播；Android 覆盖两种输出。
- Windows 入口 [test-windows-fvp.ps1](../../tool/test-windows-fvp.ps1) 已纳入新增原生回归。

设备夹具使用本地公开素材、静音和无账号入口；切换 fixture 前保留普通入口开发 Release，结束以同签名 `adb install -r` 恢复。没有卸载、清数据或操作正式包。日志与 APK 验证材料保存在忽略目录 `build/validation/fvp-seek-release/`。

## 验证结果

- `tool/check.ps1 -SkipPub` 完整通过，根应用 4696 项、13 项按既有条件跳过。最后补齐 IPC 代次隔离后，在基于 `b78f8cd7` 的独立检出重新验证静态分析及四包：bili_api 719、bili_player 308、bili_danmaku 161、bili_mux 5 项通过，锁文件按 `--enforce-lockfile` 解析。未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过，不计为原生通过。
- Xiaomi 13／Android 16：Debug 原生回归的 4 种输出／意图组合通过，每种运行三轮连续片尾跳转，并检查普通结束与重播。随后连接该 fixture，DTD 热重载成功，无运行时错误。
- 同机最终 Release／AOT 再次通过 12 轮连续跳转，覆盖两种输出的播放与暂停；额外通过两种输出的普通 EOF／重播。每轮返回 2 秒后等待跨越采样周期，确认旧位置不会回写。最终 Release 报告无错误。
- Windows `tool/test-windows-fvp.ps1` 完整通过，共 18 项：实际双轨健康 4、后端与 HTTP／直播 3、原有跳转同步 9、新增片尾连续跳转 2。`tool/test-windows-video-dispose.ps1` 的 9 项原生生命周期／渲染队列／尺寸检查通过。
- Windows 独立构建首次遇到固定资产下载 TLS 失败、NuGet 路径缺失及中断配置留下的安装前缀；复用本机同摘要缓存、现有 NuGet 工具，并仅修正该检出的 CMake cache 后完成上述原生回归，没有改变依赖版本或 TLS 校验。失败构建日志保留，不计为测试通过。
- 11:21:27（Asia/Shanghai）已恢复并启动普通入口开发 Release `1.2.8+5`／12805；测试身份 `dev.bilisail.bilisail.test`、原开发证书与不可调试属性均已核对。设备实际 APK SHA-256 与本次归档一致：`e2a312def2c9e9cf846059b658b39035475e50f30f6a72d7425c58d35ef2a252`。`firstInstallTime` 仍为 `2026-10-26 23:13:25`。

本次普通入口 APK 单独归档为 `build/validation/fvp-seek-release/BiliSail-test-arm64-release.apk`，安装记录为同目录 `install.json`。共享工作区另有后端移除改动，因此原生验证和交付使用独立检出；该归档没有包含同期移除改动，也没有覆盖另一任务已生成的开发 APK。本次安装的五个播放器实现文件已与共享工作区逐一核对摘要一致。

本轮不测性能，不将静音自动测试表述为人工可听音画同步验收；真实账号 CDN、长时间拖动及 Apple／Linux 设备仍需另行验收。
