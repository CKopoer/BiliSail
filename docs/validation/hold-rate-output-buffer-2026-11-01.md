# 长按倍速的音频输出缓冲

日期：2026-11-01。基线源码：`8bd3cdf`。

## 原因与参考

键盘右方向键和触屏长按共用 `PlaybackShortcutController` → `PlaybackSession.beginTemporaryRate/endTemporaryRate` → `MediaKitEngine.setRate`。当前已具备命令去重、串行恢复、固定倍速及源代次隔离；点播还在打开前安装常驻 `scaletempo2`，避免跨 1x 时插入／移除自动滤镜。以上仍不能消除本次复现的停顿。

只读核对相邻 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441`：`lib/plugin/pl_player/controller.dart` 的 `setPlaybackSpeed` 跳过相同速度，开始／结束长按直接调速；`lib/pages/video/widgets/player_focus.dart` 的右键长按定时器不在 Repeat 时重启。其 `lib/utils/storage_pref.dart` 默认 `video-sync=display-resample`，Android 另用 `autosync=30`。本应用与它已使用同一核心提交 `73771ec38176be2d984a3049c28177bce23b54a0`，不能再把依赖不同当作当前原因。本次只借鉴职责、比较配置，未复制 GPLv3 应用源码、修改相邻仓库或 Pub 缓存。

实际 Windows bundle 的 mpv 为 `v0.41.0-725-g43b14a4c9`。用本地合成分轨和它的原生 DLL 独立复现：保留常驻滤镜，默认同步模式在 1x→2x 后仍出现约 109 ms 的位置更新间隔；单独改为 PiliPlus 的同步模式或加入 `autosync=30` 未消除该现象。把音频输出缓冲从 200 ms 改为 50 ms 后，同一独立探针约为 32 ms。这只是机制定位，最终采用下面的 Flutter 输出对照。

[mpv 音频输出缓冲说明](https://mpv.io/manual/stable/#options-audio-buffer)明确将更大的输出队列与变速问题关联。这里缓存的是已按旧速率处理、等待声卡播放的音频，并非 CDN 下载数据；改变速度时旧队列不能立即消失，音频时钟切换会使视频等待，恢复时则可能追帧。结合下面仅改变输出缓冲的 ABBA 数据，支持它是当前剩余停顿的来源之一，不把它描述成所有设备唯一的卡顿原因。

## 修改

- 将原 `configureNativeTempoFilter` 扩展并重命名为 [configureNativeRateAudio](../../packages/bili_player/lib/src/native_rate_audio.dart)。点播打开前依次写入／回读 `audio-buffer=0.05` 和 `af=scaletempo2`。两项共用原打开截止时间，每一步前后检查当前源，拒绝未应用的配置；数值回读允许 mpv 的小数格式标准化。
- 50 ms 是输出最小缓冲请求，保留多个音频设备周期；设备仍可能选择更大的队列。调速期间继续只改 `speed`，不暂停、seek、重开媒体或重写滤镜，保持音调校正。
- 配置沿用原常驻滤镜的范围：有音轨的点播 DASH、普通／影视／离线媒体及听视频；直播、视频预览和明确无声 DASH 不调整。每次打开创建新原生播放器，不向直播残留点播配置。
- 网络前后向缓存、预缓冲门槛、用户音量／响度增益、400 ms 手势默认延迟和有效设置、暂停意图、固定倍速及运行内记忆保持原规则。没有新增依赖、设置字段或迁移。

## Windows Profile 对照

使用 [rate_transition_probe.dart](../../packages/bili_player/tool/rate_transition_probe.dart)，同一 Profile 二进制、固定核心／视频插件、`MediaKitVideoOutput` 与 `VideoSurface`、`d3d11va-copy` 硬解、`video-sync=audio`。每次新建播放器，预热 1 秒后执行三组 1x→2x→1x，每个速度采样 750 ms；顺序为 200 → 50 → 50 → 200 ms。基线只在打开前覆盖输出缓冲为 200 ms，其他配置与修复相同。通过原生 `time-pos` 每约 5 ms 轮询记录位置更新间隔，另读 `avsync`、显示／解码掉帧计数；这是位置连续性的代理指标，不是屏幕逐帧摄像测量。

本地素材为仓库的 320×180、24 fps、12 秒合成 H.264 视频和 48 kHz AAC 正弦音轨；播放器音量为 0，仍实际解码音频。无在线媒体、账号或写请求。

| 顺序／输出缓冲 | 升速最大位置间隔 ms | 恢复时最大 A/V 差 ms | 三次往返累计显示掉帧 | 解码掉帧 |
| --- | ---: | ---: | ---: | ---: |
| A1／200 ms | 142.793 | 218.303 | 14 | 0 |
| B1／50 ms | 76.160 | 92.301 | 6 | 0 |
| B2／50 ms | 55.437 | 87.958 | 4 | 0 |
| A2／200 ms | 154.558 | 226.954 | 15 | 0 |

两轮修复均缩短等待并减少恢复追帧，仍有瞬态和显示掉帧，不能声称完全零停顿／零掉帧。命令本身为微秒量级，不支持“等待长按阈值后又阻塞很久才下发”的解释。与首轮独立探针渲染路径不同，不混合计算改善比例，也不把它当作 PiliPlus 应用的端到端性能对比。

汇总含每次转换指标：[机器可读数据](data/hold-rate-output-buffer-2026-11-01.json)。原始位置轨迹为本机 `build/validation/hold-rate-flutter-20261101-abba.json`，运行日志为 `build/hold-rate-profile-probe.log`。

复现命令（使用新 label，避免覆盖已有数据）：

```powershell
$env:BILI_RATE_LABEL = 'new-label'
flutter run --profile -d windows -t packages/bili_player/tool/rate_transition_probe.dart
```

更换本地分轨目录可设置 `BILI_RATE_MEDIA_DIR`，目录需含 `video.mp4` 与 `audio.m4a`，长度至少 12 秒。

## 自动检查与验收边界

[配置回归](../../packages/bili_player/test/native_rate_audio_test.dart)共 17 项，通过 fake 属性读写验证输出缓冲、常驻滤镜、标准化回读、拒绝静默失败、每一步源替换、超时后的迟到写入和共享 deadline；保留网络缓存及音量／增益。Windows 既有普通／全屏上滑固定回归扩展为真实播放中分别执行键盘／触摸 1x→2x→1x，确认音视频仍解码、位置继续前进、播放意图与源代次保持；该行为断言不替代 Profile 连续性测量。

- 根检查脚本分阶段通过：根应用 **3922** 项，`bili_api` **540**、`bili_player` **131**、`bili_danmaku` **153**、`bili_mux` **5** 项，共 **4751 项通过**。根应用 13 项符号链接用例因权限条件跳过；mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计作原生封装通过。根应用通过记录在 `build/hold-rate-output-check-final.log`；最终四包日志为 `build/hold-rate-output-package-check-final.log`。
- 最后执行 `tool/check.ps1 -SkipPub -Stage Lint`，格式、全库静态分析、Linux 插件分析和打包边界检查通过，见 `build/hold-rate-output-lint-final.log`。新增文档相对链接及 `git diff --check` 通过。
- `tool/test-windows-media.ps1` 串行复跑完整通过，共 **33 项**，包含普通／全屏的两种长按输入、倍速／音量继承、重播、原生错误／启动／首帧、听视频、系统媒体、视频中断、预览缓冲、音量均衡及长视频网络缓存。日志：`build/hold-rate-output-windows-media-retry.log`。只用本地 HTTP／文件 fixture，未启用 `-Online`。
- 单独以 Debug 启动本地探针，连接 DTD 后执行 hot reload 成功；Debug 结果不用于上表性能结论，验证后退出该实例。
- `flutter build windows --release -t lib/main.dart` 成功，普通应用入口为 `build/windows/x64/runner/Release/bilisail.exe`，分发须保留整个 Release 目录。日志：`build/hold-rate-output-release.log`。未把探针或集成测试入口留作普通 Release。

首次同时运行离线测试和 Windows 原生构建，两者争用 `build/native_assets/windows/sqlite3.dll`：构建删除资产失败，63 项后续离线测试无法加载 SQLite。随后改为串行验证，保留 `build/hold-rate-output-check.log` 和 `build/hold-rate-output-windows-media.log` 中的首次失败，不计为通过。串行 `All` 调用的根应用已通过，但包阶段发现新增测试的 `anyOf` 列表参数误用；改为显式 `equals` 匹配器后，以 `PackageTests`／`Lint` 阶段完成最终复验。因此该次 `All` 日志的总退出状态仍为失败，最终结论采用上述分阶段结果。

本机没有连接 Android 设备，macOS 不可在 Windows 主机构建／运行。Android／iOS／macOS／Linux、其他声卡及蓝牙输出、4K／HDR、长期负载下的音频连续性和真实触摸听感尚未验收。mpv 文档提醒较小输出缓冲可能增加音频欠载风险，本轮测量不能替代这些设备验收，也不能据此推导音频没有爆音或短缺；网络弱网缓冲策略未被缩小。
