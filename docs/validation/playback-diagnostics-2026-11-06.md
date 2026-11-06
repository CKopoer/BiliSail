# 播放性能与倍速诊断日志

日期：2026-11-06（Asia/Shanghai）。用于 [#69](https://github.com/CKopoer/BiliSail/issues/69) 的独立诊断分支；只增加本地观测，不改变硬解选择、同步策略、音频缓冲或丢帧策略，也不将日志接入当作音画不同步已修复。

## 采样与操作时间线

- 生产组合根创建的每个 `MediaKitEngine` 都沿用播放日志回调。视频、影视、直播、离线和听视频走同一引擎，正常播放时每 **500ms** 尝试采样一次，不需要长按或先触发错误。暂停、缓冲、seek、结束等状态变化也记录事件；普通暂停不持续读取后端。
- `temporaryRateBegin` 在临时调速命令前记录，`temporaryRateEnd` 在松手恢复命令前记录；键盘／触屏共用会话入口。调速另有 `rateRequested`／`rateApplied`，可区分用户请求、应用状态及原生 `speed`。固定倍速播放同样持续采样。
- `rateContext` 为 `normal`（未处于长按或恢复窗口，可包含固定倍速）、`held`、`afterRelease`。松手后额外观察 **10 秒**，即使暂停也继续采样；之后正常播放仍继续，普通暂停停止采样。旧源松手不标记新源。
- 播放／暂停／seek／音量／增益记录 `commandRequested`／`commandApplied`。`commandValue` 的 seek 单位为毫秒，volume 为 0–100，audioGain 为 dB。停止／关闭记录 `stopped`，换源仍有 `openStarted`／`openReady`，故障／恢复沿用原事件。
- 通过 `engineId`（进程内递增，无账号或内容身份）、`generation` 关联播放源；文件名与 UTC `time` 区分进程／启动。`diagnosticVersion=2`，导出 manifest 记录版本与采样间隔。

## 记录内容与口径

| 信息 | 字段与单位 |
| --- | --- |
| 原生解码／输出 | `hwdec-current` 实际后端模式，`hwdec` 请求配置，`video-format`、`audio-codec-name`、`current-vo`、像素格式、色彩矩阵／传递函数、mpv／FFmpeg 数字版本 |
| 播放速度与同步 | `speed`、`avsync`、`total-avsync-change`、`video-pts`、`audio-pts`、`time-pos`、`audio-delay`、`audio-buffer`、音视频速度修正、`video-sync`、`display-sync-active`；时间类原生属性为秒 |
| 帧率与丢帧 | `container-fps`、`estimated-vf-fps`、显示刷新率估计，单位帧／秒；`frame-drop-count`、`decoder-frame-drop-count`、`mistimed-frame-count`、`vo-delayed-frame-count` 为后端累计计数 |
| 网络与状态 | 应用 position／buffered／duration（毫秒）、播放意图、buffering／seeking／phase／rate；原生 pause／paused-for-cache／seeking／core-idle，demux 缓存时长（秒）、输入速率（字节／秒） |
| 源与配置 | DASH 分轨／预览／progressive／manifest、live／audioOnly、自动／软件解码选择、所选轨道声明码率（bit/s）、解码与输出尺寸、音频声道／采样率、音量、帧队列是否应用及容量配置、杜比色彩转换是否启用 |
| Flutter 合成线索 | `flutterFrames` 的 `frames`、build／raster P95、raster 最大值（毫秒）、raster 超过 16.667ms 的数量、窗口时长与丢弃的 timing 样本数；每窗口最多保留 240 条 timing |

`native.properties` 只输出固定属性及允许的枚举／有限数值；`unavailable` 明确列出不支持、尚未建立或未通过白名单的属性，**不将缺失记为零**。批次采用 500ms 异步观察预算，超时输出已收集的部分字段与 `sampleStatus=timeout`，不因此报播放失败。固定核心的属性端口包装了同步调用，因此每读取 6 个属性让出一次事件循环；预算不能中断已进入的同步 FFI 调用。超时后在该批原生请求实际结束前不再排队新批次。

`sampleElapsedMs` 为该源采样器的单调起始时间，`sampleDurationMs` 为读取跨度；事件携带最近一次采样时用 `sampleAgeMs` 标明年龄。采样是分次读属性，非原子快照；长按开始／松手事件可能带有前一批样本，须结合年龄、原生 speed 与后续 `performanceSample` 判断。换源／停止／释放立即取消计时器与 Flutter timing 回调，忽略旧批次完成结果。

Flutter timing 使用 `scope=flutterApp`，共享应用／多窗口 timing 入口，不能归属某个视频，也不能当作视频解码或屏幕实际呈现 FPS。后端时钟不代表扬声器到屏幕的物理同步；日志不包含 Codec 厂商 `renderFps`／`discardFps`、硬件单元计数器、操作系统 logcat、Perfetto 或驱动实际 operating-rate。相关结论仍需设备日志或受控 A/B。

## 脱敏、容量与导出

- 不读取或保留媒体 URL、路径、track ID、账号／内容 ID、headers、Cookie、Token、标题、原始 native 消息或异常文本。枚举字段执行固定允许列表，版本只取数字发布号或 FFmpeg 数字构建序号。
- 普通播放也持续写日志，因此诊断分支将播放通道单文件上限调至 **512KiB**；核心通道仍为 256KiB。沿用每通道约 6 个文件及最多 64 条待写事件的边界，超限计数仍可见。未添加网络上传或持久设置。
- 设置页导出仍先 flush，再汇总现有核心与播放日志，包括轮转文件；单文件 512KiB、日志合计 8MiB、最多 32 个文件的 ZIP 边界不变。ZIP 内说明补充字段单位、关联方法及同步证据边界。复现后应及时导出，避免轮转覆盖问题窗口。

## 验证

- `tool/check.ps1 -SkipPub` 完整通过：打包边界、格式、静态分析、根应用 4425、bili_api 659、bili_player 154、bili_danmaku 161、bili_mux 5，共 5404 项；根应用 13 项 Windows 符号链接用例和 10 项 mux 原生用例按环境跳过。未配置 `BILI_MUX_LIBRARY`，不将跳过记为原生验证。日志：`build/issue-69-check.log`。
- 最后增加 native 不同步／慢播放／音频 underrun 分类后，重新执行 Lint 阶段及 291 项定向回归通过；最终四包测试也重新通过，bili_player 增至 155 项，其余数量不变，与根测试合计 5405 项。测试覆盖普通／倍速／恢复时序、请求单飞、部分超时、未知属性／非有限值过滤、换源／释放隔离、Flutter timing 上限与解除监听、ZIP flush／字段保留／脱敏和会话旧源松手。最终日志：`build/issue-69-final-lint.log`、`build/issue-69-targeted.log`、`build/issue-69-final-packages.log`。
- Windows Debug 原生集成 2 项通过：403 分类脱敏，以及真实本地音视频分轨的正常 1x、临时 2x、恢复 1x、暂停后观察窗口和设置生产仓储 ZIP 导出。最终轮记录 28 条采样，实际 `hwdec-current=d3d11va`、mpv 0.41.0／FFmpeg N-127388；独立 Python `zipfile` 校验 CRC、速度上下文与字段保留。SDK 未暴露 `video-pts` 等字段时明确保留 `unavailable`，实际音频 PTS／播放位置／avsync 可用。样本读取跨度中位数 2ms、最大 54ms，只是该 Debug 本地验证的观察值，不作为 Android 性能结论。日志及 ZIP：`build/issue-69-native.log`、`build/validation/issue-69/native-diagnostics.zip`。
- 隔离 Windows 预览入口的 DTD 热重载成功，运行时错误为空；已关闭本任务启动的进程。预览不读取真实账号／偏好，源码与日志位于忽略目录 `build/validation/issue-69/`、`build/issue-69-preview.log`。
- `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 复用现有 arm64 mux 资产构建成功；实际 APK 校验为 `dev.bilisail.bilisail.test`、`BiliSail 测试版`、1.2.6+7／12607、Release／不可调试和原有开发签名。产物为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256 `d910e05b9e9c9d73800f5e8844108b8d5c401a406b5e2532588120f9631f0bcf`。日志：`build/issue-69-android-build.log`。构建保留既有 KGP 与图标字体告警，无编译错误。
- 当前没有 adb 设备，未安装或执行真实 4K 复现；厂商 Codec 吞吐、感知音画同步、其他平台运行与长期日志开销仍待专项验收。
