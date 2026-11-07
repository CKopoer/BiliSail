# fvp 跳转后同步恢复

日期：2026-11-07。用户反馈 media_kit 的跳转同步修复后，fvp 仍存在声音先开始、视频随后出现的问题。本项补齐 fvp／MDK 路径，与 [media_kit 专项](seek-av-synchronization-2026-11-07.md) 分别验证。

## 原因与处理

[FvpEngine](../../packages/bili_player/lib/src/fvp_engine.dart) 原先播放中直接调用 seek，等待期间没有暂停共用的 MDK Player；音轨可用而视频 Range 响应尚未到达时，声音仍可能继续运行。另外，[原生适配器](../../packages/bili_player/lib/src/fvp_native_player.dart) 直接使用低层 `mdk.Player.seek` 的默认标志，包含 `keyFrame`，与 fvp 上层播放器默认的精确跳转不同。

现在跳转先暂停同一个原生播放器，使用 `fromStart | inCache` 精确跳转，等待本次 MDK seek 回调确认目标帧解码，再恢复用户原有播放意图。首帧确认使用相同的精确标志，不重新创建纹理。回调语义以固定 SDK 绑定及 [MDK Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#bool-seekint64_t-pos-seekflag-flags-stdfunctionvoidint64_t-ret-cb--nullptr) 为依据；首次打开时的 `1st_frame` 信号不用于确认后续跳转。

原生回归进一步发现，适配器原来在 `Player.state` 已为 paused 时跳过暂停调用。新挂载的外部音轨因此没有重新接收暂停请求：暂停打开后再跳转，回调目标正确，但 MDK 位置会额外增加视频等待时长。现在每次都向 MDK 重申暂停，包括初次暂停打开和后续跳转；相同延迟用例中目标与原生时钟一致，保留位置断言，不通过隐藏时钟偏差处理。

- 跳转期间不采样 MDK 提前暴露的目标位置，不提前更新弹幕时钟或解除 seeking；buffered 事件不能将未完成的跳转标为播放。
- fvp 的 Dart 包仅保存一个 seek 完成槽，因此同源内等待正在执行的原生 seek 完成后，再发最新目标；跳过排队的过期目标。旧结果不发布检查点，两次操作之间保持暂停，不并发调用低层 seek。
- 请求时记录暂停代次，覆盖同一事件循环立即暂停及等待中暂停；stop／换源／dispose 沿用源代次与取消屏障。失败或超时清除 seeking、保持停止意图并中断旧原生槽，后续由现有会话恢复机制重新打开源。
- 纯音频同样沿用该播放器的暂停与 seek 回调；直播继续禁用 seek，不等待不存在的视频帧。

## 验证入口与范围

[播放器行为测试](../../packages/bili_player/test/fvp_engine_test.dart) 覆盖视频帧延迟、乐观位置采样、buffered 事件、连续跳转合并、两类手动暂停、停止取消、失败及迟到结果。

[Windows 原生专项](../../integration_test/windows_fvp_seek_synchronization_test.dart) 使用真实 MDK、受控 HTTP 视频、本地可用音轨和 1 秒预读，跳至非整数关键帧位置；阻止目标视频响应 1.5 秒，检查原生控制仍为暂停、seek 未完成、等待画面非黑、补数后的目标位置和画面，以及暂停、停止、连续改目标。已接入 [Windows fvp 验证入口](../../tool/test-windows-fvp.ps1)。端口包装仅观察命令及 SDK 时钟，不创建第二个播放器。

本轮记录：

- 修改前新增行为回归三项失败，确认视频等待期间仍播放、过期目标未合并以及失败后还能继续 seek；修复后 fvp 行为测试 14 项通过，包含实际 15 秒超时边界和换源后迟到结果。
- 原生首轮在原本暂停场景发现约 1.6 秒的额外时钟偏移；补齐无条件暂停请求后，同场景的 9375ms 解码结果与 MDK 时钟一致。正式 fvp 脚本完整通过既有三项与同步六项，共九项；不是仅运行 fake 后端。
- `tool/check.ps1 -SkipPub` 完整通过，根应用 4567、API 678、播放器 207、弹幕 161、mux 5 项；随后新增超时与换源测试，最终重新通过 Lint 阶段及四包测试，播放器增加至 209 项。根应用 13 项符号链接用例、mux 10 项原生用例按既有环境条件跳过，未配置 `BILI_MUX_LIBRARY`，不计为原生通过。
- 为避免只核对 seek 返回值，再补充恢复后 300ms 的 MDK 原生时钟断言，要求不包含等待视频的时间；保持此断言的同步专项六项重跑通过，等待期间的非黑像素与恢复后目标像素断言也通过。
- 本地无账号 DASH fixture 在 Windows Debug 完成精确 seek、暂停和热重载，Dart 工具报告无运行时错误；通过本地控制端口确认播放器释放后退出。
- 普通入口 `flutter build windows --release --no-pub -t lib/main.dart` 通过（62.6 秒），产物为 `build/windows/x64/runner/Release/`，保留完整目录使用。AOT `data/app.so` SHA-256 为 `4167fe45ccf0db42a04c1477897ad94466aba63806ed4434e9afafda6d7e531b`；未发布安装包。

本地检查、原生、构建日志保留在忽略目录 `build/validation/fvp-seek-*.log`。期间有两次非详细模式构建在 Flutter assemble 阶段返回通用 MSB8066，未进入测试；保留失败日志，详细模式重试及后续正式脚本构建成功，不把构建失败记为测试通过。同期播放信息功能由其独立提交 `4909a00` 保留，本次提交不包含该功能修改。

原生测试全程静音，不能代替人工可听同步验收；目前未暴露 MDK 外部音轨独立时钟，不将单一位置采样表述为两轨偏差测量。真实账号 CDN、Android／macOS 设备与长视频验收另行保留。
