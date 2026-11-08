# 两播放后端共享状态机

日期：2026-11-08（Asia/Shanghai）。设计入口：[后端重构方案](../player-backend-refactor-design.md)，架构决定：[D75](../decisions.md#d75两个播放后端共用包内播放状态机)。

后续同步门已改为暂停中确认双轨，取消静音预滚；本记录中的静音门描述为改动前快照。现行实现见[双轨同步屏障](paused-pair-synchronization-2026-11-08.md)。

## 实现与所有权

- 应用继续使用原有 `PlayerEngine`、`PlaybackSession`、`PlaybackManager` 和设置工厂。`MediaKitEngine(...)`／`FvpEngine(...)` 保留构造参数、可注入 fvp 端口及原生诊断／基准入口，均委托 [SharedPlayerEngine](../../packages/bili_player/lib/src/shared_player_engine.dart)。
- [PlaybackBackend](../../packages/bili_player/lib/src/playback_backend.dart) 提供原生命令、可取消且带单调截止时间的操作上下文，以及轨道、解码、呈现、实际暂停、目标位置和健康观测。[MediaKitBackend](../../packages/bili_player/lib/src/media_kit_backend.dart) 保留 mpv 弱客户端、外部音轨核对、色彩映射、Surface 和 seek／restart 屏障；[FvpBackend](../../packages/bili_player/lib/src/fvp_backend.dart) 连接已有进程内／Android IPC 端口，保留 MDK 的回调排空与一次有界重准备。
- 共享层独占快照、播放意图、seek 版本、起播／首次 play 静音门槛、EOF／重播、250 ms 健康采样、增益平滑及终止／释放流程。适配器不发布 `PlaybackSnapshot`，也不另设业务播放状态机、恢复预算或健康计时器。共享层不导入 SDK，不按后端名或平台分支。
- [统一源计划](../../packages/bili_player/lib/src/validated_source.dart) 在原生分配前检查参数、scheme、缺失音轨和相同请求头。拒绝凭据头、换行、重复大小写头名及 URI user-info；普通无音轨完整视频、静音预览和听视频分别表达。预览最多五秒，普通源最多两分钟；直播使用 1×、零起点和不可 seek。实际列出音频但无视频的渐进源，两端均可接受；列出视频但不能解码的源必须失败。

## 竞态与兼容边界

- 暂停打开后的首次 play 同样保持原生静音，直到实际音频就绪；自动起播另等必需视频和当前显示目标的呈现。音量与增益在放行时读取最新用户值。暂停立即撤销在途 play，短命令只串行下发，不让轨道／目标帧等待挡住新的 seek 或暂停。已确认音轨的 seek 在恢复推进前先恢复音量；MDK 基础音量变更不重复重建相同增益滤镜。
- 连续 seek 立即撤销旧操作，保留上次确认位置，只有最新目标可以提交时间线或恢复声音；旧 EOF、错误、采样和回调不能改变当前目标。正常 EOF 只发布一次终态，尾随原生通知不能恢复播放；重播恢复采样。直接构造时保留 media_kit 对负 seek 抛错、fvp 夹零的历史区别，应用可切换入口统一夹零。
- 可切换包装层的命令失败和失败流均映射到同一外部源代次。后端工厂尚未返回时，`ConfigurablePlayerEngine` 也保存暂停意图并撤销排队的旧 play。同步快照监听器在 opening／ready 中换源或关闭后，旧操作不能释放新实例或再执行原生命令。
- 短命令、准备和采样错误沿用统一分类；一次失败供命令 Future 与失败流共同消费。进程退出单列 `nativeProcessExited`，不自动换后端。CDN 主备、URL 刷新、账号及自动恢复预算仍归应用会话。
- 原生暂停返回实际确认结果；MDK 主视频已 EOF 而外部音频仍存活时，不把空暂停当作成功，先打断并等待释放再提交失败。这种终态可撤下输出；缓冲与 seek 仍保留最后一帧。stop／dispose 取消等待、解绑输出并等待线程／进程、纹理及租约释放；重复 dispose 共用屏障。打断失败仍执行最终释放，释放状态未知时阻止新分配。工厂或 Android provider 迟到的资源仍有人回收，不靠超时丢弃句柄。
- Android fvp 增加可等待的静音／播放／倍速应答与原生产生的暂停确认结果，保留旧同步端口兼容；worker 位置、状态和 seek 回复继续按产生时的 seek 版本隔离。没有修改 Pub 缓存、升级依赖、引入第二路影子播放或改变应用恢复策略。

## 验证入口与结果

自动检查按根 [check.ps1](../../tool/check.ps1) 的 Lint／RootTests／PackageTests 分阶段执行；构建、原生夹具和设备操作分别记录。工作区原有的 fvp 连续 seek／EOF／IPC 修复一并作为本次基线保留。

- 根应用离线测试：4718 项通过，13 项按既有条件跳过。
- 四包离线测试：`bili_api` 719、`bili_player` 320、`bili_danmaku` 161、`bili_mux` 5 项通过。未配置 `BILI_MUX_LIBRARY`，mux 的 10 项原生测试跳过，不计为原生通过。Windows 和 Android mux 资产另已构建，不能据此代替 mux 原生测试。
- 新增 [共享层用例](../../packages/bili_player/test/shared_player_engine_test.dart) 和 [源计划用例](../../packages/bili_player/test/validated_source_test.dart)，覆盖最新意图、同步监听器换源、迟到工厂、未知释放屏障、单轨健康、30 秒缓冲、增益目标取代及两端相同的提前失败。已有工厂、fvp 进程退出、IPC 应答和 Android 租约用例补齐相应边界。
- [同一份原生契约](../../integration_test/player_backend_contract_test.dart) 经过真实 `ConfigurablePlayerEngine` 工厂验证两端的暂停打开／首次 play、连续 seek、普通 EOF／重播、增益、不带视频的音频源与源替换。Windows 自动／软件解码共 4 组通过；已加入 [Windows 媒体入口](../../tool/test-windows-media.ps1)。
- Xiaomi 13／Android 16：Debug 与 Profile/AOT 各 8 组通过，覆盖两个后端、兼容／直出设置和自动／软件解码。软件解码在直出设置下仍按原生能力走兼容呈现，不将设置值当成实际硬件输出证据。Debug fixture 的 DTD 热重载成功，无运行时错误。
- Android 使用 `dev.bilisail.bilisail.test`、`BiliSail 测试版`，测试前保留当前普通入口 Release，fixture 验证后在 `finally` 中同签名 `adb install -r` 恢复并启动。普通入口为 `1.2.8+5`／12805，首次安装时间仍为 `2026-10-26 23:13:25`；没有卸载、清数据、复制凭据或操作正式包。临时常亮设置恢复原值。

Windows 专项按既有脚本分组执行，修正后的失败项定向复跑，最终结果如下；并非声称最初一次串行脚本没有失败：

| Windows 受控原生组 | 最终结果 |
| --- | --- |
| 应用控制／续播／多标签与窗口生命周期 | 8 通过，1 项交互桌面条件跳过 |
| 两后端普通 EOF／重播 | 6 通过 |
| 诊断、延迟双轨起播、视频就绪 | 分别 1、9、6 通过 |
| 听视频／定时停止、系统媒体控制 | 分别 7、1 通过 |
| mpv 双轨断流／缓冲／静默停滞 | 9 通过（含修正后的 2 项视频断轨复跑） |
| mpv seek、MDK seek | 各 9 通过 |
| MDK 音频／视频分别提前 EOF 与会话恢复 | 4 通过；失败发布后音频解码计数不再增加 |
| fvp 后端／HTTP／直播、连续片尾 seek | 分别 3、2 通过 |
| 预览五秒、普通两分钟滚动缓冲 | 各 2 通过；满缓冲、暂停、推进与 seek 均核对时间终点 |
| 原生增益；完整无音轨视频 | 分别 2、2 通过；后者 2 项在线条件跳过 |
| 内容播放、音质、直播长断流 | 分别 2、1、1 通过 |
| C++ 原生视频释放／渲染队列／尺寸 | 9 通过 |

测试把完整无音轨视频改用 `DashPairSource(isIntentionallySilent: true)` 表达；`DashVideoSource` 专用于五秒预览，不再用它检查普通两分钟缓冲。最初并行执行 Windows 原生测试与 Android 构建触发了 Flutter 生成插件注册文件冲突，改为串行正常构建后恢复；没有手改生成文件。另一次 Windows 调试连接启动失败，原用例复跑通过，未据此修改播放器策略。

Android 最终受控子进程故障专项通过：实际杀死的 worker 从 32218 更换为 32417，UI PID 17724 保持，失败为 `nativeProcessExited`，显式重新打开后恢复解码。普通入口 Release 在 `finally` 中覆盖恢复并启动；设备 APK 的 SHA-256 与最终构建一致，为 `63e4ed9a7ddbb3c5bba47ac2ffb0b4e6419750116d5e6cfa887484e105e18289`，首次安装时间未变。最终构建继续沿用原开发证书，版本与包名已校验。

最终 Android 进程夹具尝试 `flutter attach` 时，Flutter 工具本身出现 `Future already completed` 并退出；该次重载未计为通过，应用受控进程回归已完成，恢复 Release 不受影响。随后用最终代码启动 Windows 原生契约夹具，四组行为完成后通过 DTD 执行热重载成功，未发现运行时错误，并正常退出该夹具。崩溃报告保存在 `build/validation/player-refactor-flutter-attach.log`。原始检查与构建日志在忽略目录 `build/validation/player-refactor-*.log`，Android fixture／安装材料位于 `build/validation/player-refactor-android/`，普通测试 APK 与摘要位于 `build/development/android-arm64/`。

## 未覆盖范围

本轮未做人工扬声器／屏幕的音画同步验收、性能比较、长期播放或真实账号 CDN 测试。macOS／iOS／Linux 无本机设备验证；保留各适配器原有能力，不能由 Windows／Android 结果推导这些平台已通过。Android 前后台、PiP、SAF、共享子进程多实例和全部业务选流／投屏流程，仍需按方案矩阵逐项扩充设备证据。
