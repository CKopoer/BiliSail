# fvp 跳转后同步恢复

日期：2026-11-07。用户反馈 media_kit 的跳转同步修复后，fvp 仍存在声音先开始、视频随后出现的问题。本项补齐 fvp／MDK 路径，与 [media_kit 专项](seek-av-synchronization-2026-11-07.md) 分别验证。

## 原因与处理

[FvpEngine](../../packages/bili_player/lib/src/fvp_engine.dart) 原先播放中直接调用 seek，等待期间没有暂停共用的 MDK Player；音轨可用而视频 Range 响应尚未到达时，声音仍可能继续运行。另外，[原生适配器](../../packages/bili_player/lib/src/fvp_native_player.dart) 直接使用低层 `mdk.Player.seek` 的默认标志，包含 `keyFrame`，与 fvp 上层播放器默认的精确跳转不同。

现在跳转先暂停同一个原生播放器，使用 `fromStart | inCache` 精确跳转，等待本次 MDK seek 回调确认目标帧解码，再恢复用户原有播放意图。首帧确认使用相同的精确标志，不重新创建纹理。回调语义以固定 SDK 绑定及 [MDK Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#bool-seekint64_t-pos-seekflag-flags-stdfunctionvoidint64_t-ret-cb--nullptr) 为依据；首次打开时的 `1st_frame` 信号不用于确认后续跳转。

原生回归进一步发现，适配器原来在 `Player.state` 已为 paused 时跳过暂停调用。新挂载的外部音轨因此没有重新接收暂停请求：暂停打开后再跳转，回调目标正确，但 MDK 位置会额外增加视频等待时长。现在每次都向 MDK 重申暂停，包括初次暂停打开和后续跳转；相同延迟用例中目标与原生时钟一致，保留位置断言，不通过隐藏时钟偏差处理。

- 跳转期间不采样 MDK 提前暴露的目标位置，不提前更新弹幕时钟或解除 seeking；buffered 事件不能将未完成的跳转标为播放。
- fvp 的 Dart 包仅保存一个 seek 完成槽。首版修复等待旧请求结束后再发新目标；用户后续要求不等待旧视频加载，现改为立即取消旧等待、中断旧原生读取，并在同一个 MDK Player 上按最新位置重新 prepare。取消不作为播放故障，未执行的旧目标仍跳过；旧结果不发布检查点。
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

## 后续：未加载完时直接转向新目标

2026-11-07 用户进一步指出先等旧位置加载会增加等待。直接调用新 seek 的实验中，MDK 虽立即暴露新目标位置，仍可能等待旧 HTTP 读取；为各请求生成独立回调绑定也不能解决原生读取等待，最终未采用该方案，没有变更 fvp／MDK 固定版本、原生 ABI 或 Pub 缓存。

现在 `cancelSeek` 先使旧 Dart 等待正常取消，并暂时卸载同一个 native player 的旧媒体，停止旧读取。单独请求 stopped 不足以取消已处于 stopped 状态的媒体打开，因此重新 prepare 尚未完成时再次改目标也必须卸载旧媒体。新请求在既有 15 秒总预算内，以 `waitFor(stopped, timeout: 0)` 确认原生停止；每次未就绪让出事件循环 10ms，不同步等待网络。停止完成后让已排队的旧回调先处理，再恢复当前源及分轨，用公开 `prepare(position, preciseFlags)` 准备最新位置并暂停确认音视频，避免复用 fvp 完成槽时混入旧结果。

使用 SDK 公开的 `videoout.clear_on_stop=0` 保留原纹理及最后一帧；只在本次改目标需要取消旧读取时重准备，普通 seek 沿用暂停与目标解码确认。重新准备期间的中间 stopped／invalid 事件不作为播放结束或线路故障，音轨和画面继续暂停，准备完成才按用户意图恢复；stop／dispose 的源取消仍立即生效。纹理最终仍由正常释放路径销毁，不增加第二个播放器或音频输出。SDK 选项及停止／prepare 契约见 [MDK Player API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)。

原生回归保留旧位置的 HTTP 响应不返回，只放行新请求，要求旧 Future 在 500ms 内取消、新位置在 3 秒断言窗口内完成，并保持同一源代次、纹理非黑及正确的原生时钟；另加入重新 prepare 尚未完成时再次改目标，验证最后一次目标才恢复。断言时间仅是受控夹具上限，不是公网 seek 耗时或性能承诺。

本次后续验证：

- `tool/check.ps1 -SkipPub` 完整通过：根应用 4567、API 678、播放器 211、弹幕 161、mux 5 项。13 项符号链接、10 项 mux 原生用例仍按原环境条件跳过；最终播放器源码和专项定向静态分析也通过。
- `tool/test-windows-fvp.ps1` 最终整次通过：既有三项与跳转同步九项，共十二项；新增连续第三次改目标、重准备中暂停及停止，检查重准备期间非黑画面、恢复后的原生时钟、同一纹理只创建一次以及无错误恢复。首轮第三次改目标用例曾暴露 stopped 状态下仍在打开媒体的取消缺口，补齐卸载旧媒体后，三项连续取消场景单独重跑通过，再完整重跑十二项通过。
- 本次没有修改同期的重播／会话测试改动，仅提交播放器取消和本专项文件；上述计数包含检查时工作区的同期测试。
- 随后对默认 media_kit 后端加强相同夹具，发现其原生读取也可能等待旧响应。改为同一 native player 的 `loadfile replace`，避免高层 open 清空纹理，增加新 load 对应的 restart 确认并保留视频恢复屏障；完整九项通过，重加载中仍显示非黑画面，恢复后的 avsync 小于 150ms。详见 [media_kit 后续记录](seek-av-synchronization-2026-11-07.md#后续准备中改目标立即替换旧读取)。
- 默认后端调整后补跑根脚本 Lint 与全部子包：API 678、播放器 212、弹幕 161、mux 5 项通过；最终又对两后端源码和专项做定向分析。跳过项沿用前述记录，不新增 mux 原生通过声明。
- 最终 Windows Debug 本地 DASH 入口热重载成功，无运行时错误，随后等待 native 释放并退出；`tool/test-windows-video-dispose.ps1` 九项生命周期／渲染队列／尺寸测试通过。普通入口 Windows Release 构建通过（52.8 秒），完整目录仍为 `build/windows/x64/runner/Release/`；本轮 AOT `data/app.so` SHA-256 为 `52d34651b335f3590f74a3280a960fd0bef41c50e6795c2829bcc574d1d34301`。包含同期独立提交 `537b52f` 的重播修复；Android／macOS、真实 CDN 与人工可听验收未在本轮执行。
