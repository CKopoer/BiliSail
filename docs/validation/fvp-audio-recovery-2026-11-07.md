# fvp 播放中途断音检测与恢复

> 历史记录：fvp／MDK 已于 2026-11-12 移除。下文保留当时实现与验证事实，相关源码、资产和专属命令已退役；当前行为见[移除记录](fvp-removal-2026-11-12.md)。

日期：2026-11-07。

同日后续修订：下面的 8 秒阈值和对应测量记录属于首次断音修复。现行实现由[双轨两秒同步](paired-stall-synchronization-2026-11-07.md)覆盖，双向轨道检测复用 `NativeTrackHealth`，新增视频提前结束的原生回归。

## 现场证据与原因边界

本机运行的是商店 MSIX `JerryHsu.BiliSail` 1.2.8.0；版本号不能反推出其精确构建提交。用户描述音频开始正常、播放到中途突然消失，视频继续，重新打开后声音恢复。本轮只读该进程已有的结构化日志，没有替换安装包、修改账号或操作现场播放状态。

该进程的播放日志全部标为 `backend=fvp`，包含 `openStarted`／`openReady`，没有故障或自动恢复事件。旧日志没有持续音频活动、原生音频错误或系统输出设备信息，因此不能证明这次首次断音由 CDN、解码器还是音频设备触发；也不能由“没有错误日志”推断音轨健康。

对照当前提交 `ee48300`，确认最新代码仍有可复现的漏检：

- [FvpEngine](../../packages/bili_player/lib/src/fvp_engine.dart) 只把总 position 交给 `NativePlaybackHealth(paired: false)`。有视频时 MDK position 反映画面进度，视频继续前进就不会触发总进度停滞。
- 外部音轨先由静音、暂停探针确认解码器能打开，随后实际播放实例直接沿用该确认。探针就绪不能证明实际音轨持续出帧。MDK 外部管线的 decoder／EOF 事件没有通过原有主播放器状态进入应用故障流。
- [PlaybackSession](../../lib/features/playback/application/playback_session.dart) 已有重解析、备用线路与次数／deadline 限制；缺少的是能触发它的音频故障信号。media_kit 原有独立音频时钟检测继续保留。

## 修复

使用固定 MDK 0.39 的公开 C API `mdkPlayerAPI::onAudio`。本机原生探针确认它会为实际外部音轨持续调用，即使主播放器未转发其 decoder 事件。回调只在原生线程递增一个原子计数，不读取、复制或保存 PCM，不逐音频帧调用 Dart。

- 实际播放时确认当前 native player 确实产生音频帧，不能只接受启动探针结果。暂停打开仍保留“首次播放才确认”语义。
- 首次修复中的 `FvpAudioHealth` 每 250ms 观察计数；当时活动播放连续约 8 秒没有新音频帧时记录 `playbackStalled / audioFrames`，暂停同一个 native player，并发出原有 `nativePlayback` 故障。该类现已并入 [NativeTrackHealth](../../packages/bili_player/lib/src/native_track_health.dart)，按两秒上限判断。会话按既有预算恢复，保留当前位置、音量、速率和用户意图，不另起无限重试。
- 暂停、seek、明确 buffering、结束、换源与倍速改变重置或避开音频停滞判断。音量为零、编码内容是静默，仍会正常解码出帧，不会据此判断断音。视频末尾保留已有 500ms 容差。
- Android worker 在原有 250ms 样本中携带计数，不增加逐帧 Binder 事件；关闭／换源后忽略旧实例样本。
- 原生计数状态一直保留到 MDK 实例销毁并等待其线程退出之后，再释放内存。源码由 package build hook 编译，三个 Dart 绑定由 ffigen 23.0.0 生成。SDK 头文件来源、完整摘要及许可范围见 [SOURCE.md](../../packages/bili_player/third_party/mdk/SOURCE.md)；没有增加另一套 MDK／FFmpeg，也没有修改 Pub 缓存。

## 验证

首次修复的状态测试现已并入[双轨状态测试](../../packages/bili_player/test/native_track_health_test.dart)，覆盖视频继续而音频停止、静音／静默内容、0.25／1／4／8 倍速、暂停／seek／缓冲宽限、源代次和计数重置、正常片尾。Android 端口测试补充 worker 音频样本传输。

[Windows 原生回归](../../integration_test/windows_fvp_audio_recovery_test.dart) 使用无账号本地 30 秒视频和带完整时长元数据、但中途截断媒体数据的 AAC 音轨。先确认实际音轨持续出帧，随后检查视频继续时的故障检出；自动分支通过真实 PlaybackSession 重解析为完整音轨，验证从中断位置继续并重新产生音频帧。回归已经加入 [Windows fvp 脚本](../../tool/test-windows-fvp.ps1)。

- `tool/check.ps1 -SkipPub` 通过：根应用 4615、API 696、播放器 255、弹幕 161、mux 5，共 **5732 项通过**；格式、静态分析与打包边界检查通过。13 项符号链接用例因本机权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。新工作区先完成全部包的依赖解析，根锁文件与另外三个包的锁文件没有变化。
- 回归前后对照：仅将 engine 恢复为 `ee48300` 的旧健康判断，同一原生夹具在视频正常推进时等待 20 秒仍没有失败信号，预期一次故障的断言失败（`Actual: []`）。还原修复后两项重新通过：手动分支在 position 14708ms、连续无音频帧 8000ms 时暂停；自动分支在 14625ms／8000ms 触发，完整会话只重开一次，保留进度并重新产生实际音频帧。
- `tool/test-windows-fvp.ps1` 全部 **14 项原生用例通过**：新增断音 2 项、分轨／headers／直播／听视频 3 项、暂停意图与连续跳转 9 项。最后源码上的断音两项再次通过；不将重复执行累计为更多不同用例。`tool/test-windows-video-dispose.ps1` **9 项通过**。
- 追加的全目录 `flutter analyze --no-pub` 无问题；三个绑定和 record-use 映射重新生成。Windows 构建复用本机已固定原生归档，构建脚本仍检查其完整 SHA-256；独立 mux 复用同源完整资产，不将资产准备当作 mux 原生测试通过。
- 独立、无账号本地 fvp fixture 完成 Debug 热重载，未发现运行时错误，随后通过本地控制端口等待原生释放并退出。普通入口 `flutter build windows --release --no-pub -t lib/main.dart` 构建通过；完整目录位于 `build/windows/x64/runner/Release/`，包含 `bili_fvp_audio_activity.dll`、AOT 应用和原有 MDK／libmpv 资产，未安装或替换旧应用。
- 包的 hook／生成器静态分析无问题；补充的两组状态／Android 端口测试 12 项通过。相关文档 348 条相对链接与 `git diff --check` 通过。

验证在 `ee48300` 加本补丁的独立 Git 工作区执行，保留主工作区同期修改和已安装应用。日志保留在忽略目录 `build/validation/audio-*.log`。

## 未覆盖范围

此检测证明音频解码管线仍有活动，不能证明扬声器实际发声；系统混音器静音、错误输出设备或“仍接收 PCM 却没有可听输出”的设备故障不由它判断。真实账号 CDN、长视频及原反馈的瞬时故障没有在本轮重新捕获。Windows 原生用例使用零音量，不代替人工可听验收或性能测量。Android／macOS 设备验收另行保留。

## 2026-11-11：Android 正常片尾误报音频中断

用户提供 Xiaomi 2211133C／Android 16、应用 `1.2.9+1` 的两份诊断包。
第二份包含同一进程的后续事件；以下时间为北京时间：

- 13:08:37，45567ms 视频在 43966ms 收到 `playbackStalled / audioClock`，
  `stalledForMs=0`；重新打开后在 44533ms 再次失败。
- 13:10:29，164000ms 视频在 162000ms 收到同类故障；两次有界恢复分别从
  162000ms、162700ms 重开，又在 162700ms、162766ms 失败，最终显示播放失败。
- 更早 13:05:53 的 16200ms 中途停滞属于 `playbackClock / 2000ms` 分支，
  不能据此认定与片尾故障同因。本次没有声称修复该次尚无原生现场证据的中途停滞。

片尾事件来自 `_MdkPlayerPort._companionStatus` 的即时 EOF 判断，并非两秒
健康检测器。原实现将可能已经归零的音频输出位置与滞后的视频位置取较大值，
再要求距离主视频时长不超过 500ms；正常音轨已经完整解码时，视频位置仍可能
落后 1–2 秒，因而误发 `audioEnded`。应用随即进入原有有限重试，重复同一误判。

使用固定、摘要匹配的 MDK 0.39.0 Linux SDK 做无账号原生对照，1／2 倍速结果一致：
完整 12000ms 音轨停止事件里的输出位置为 0，实际最后解码帧端点为 11999ms；
声明时长 30016ms、保留头部元数据但截断数据的音轨，输出位置同样为 0，解码端点
仅为 6634ms。这证明输出归零不能区分完整结束与真实截断。另一个带非零起始时间
的受控文件，原始帧端点为 42009ms、容器起点为 29978ms；必须归一化为相对进度，
否则偏移也会掩盖提前结束。这些测试采用 null 音频输出，不代表扬声器或设备验收。

修复在原有原生音频观察器中只保留最后一帧的 timestamp + duration 标量，忽略
EOS 哨兵、无样本帧及非法时间戳，不读取 PCM、不保留帧指针、不在回调调用 Dart。
音轨停止后，按容器起点归一化并与该音轨自身声明时长比较，沿用 500ms 的末尾
容差；确认完整结束才允许视频完成既有的片尾排空。纯音频的终态位置也保留实际
解码端点，避免 EOF 归零或旧 seek 目标进入后续状态。新帧覆盖旧端点，正常播放
期间继续使用真实输出位置，没有用解码进度替代播放时钟。两秒停滞门槛、30 秒
缓冲预算及重试额度均未增加；有效解码端点显示真实截断时，仍报告音频中断。

回归入口：

- [片尾判定](../../packages/bili_player/test/fvp_audio_end_test.dart)：重放两段现场
  视频的位置／时长关系，覆盖音轨独立时长、截断、未知端点和容器时间戳偏移。
- [原生观察器](../../tool/native_tests/fvp_audio_clock_test.cpp)：EOS 归零／哨兵、
  倒退 seek、新帧覆盖、非法帧时间戳，并保留原有真实时钟、暂停及 seek 代次测试。
- [原生 EOF 与重播](../../integration_test/fvp_seek_end_test.dart)：新增从头正常
  播完及重播的 1／2 倍速用例；Android 覆盖两种输出，复用原有原生测试入口。

本次在基于 `a6194dc0` 的独立工作区修复，原检出仍停留于 `1.2.6+6`，未覆盖它。

验证结果：

- 使用固定 Flutter 3.47.6／Dart 3.13.5，五份锁文件均以 `--enforce-lockfile`
  解析且没有变化。根应用、四包及集成用例共 1126 个 Dart 文件格式检查通过，
  Linux 平台适配文件的格式／分析另行通过；`flutter analyze --no-pub` 无问题。
- `tool/check.ps1 -Stage RootTests -SkipPub` 通过：根应用 5080 项通过、6 项按
  既有条件跳过。四包分别为 API 848、播放器最终版本 372、弹幕 161、mux 5 项
  通过；共 6466 项通过。未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过。
- 受控 C++ 时钟／音频端点测试使用 GCC C++17、`-Wall -Wextra -Werror` 通过，
  AddressSanitizer／UndefinedBehaviorSanitizer 版本也通过。上述实际 MDK 原生
  观察器对照覆盖完整／截断音轨的 1／2 倍速，以及非零容器起点；全部使用本地
  公开夹具与 null 音频输出。没有账号或真实 CDN 操作。
- `tool/check.ps1 -EnforceLockfile` 的全量入口在 Linux 上被未修改的
  `tool/test-macos-release-validation.ps1:320` 阻塞，报告独立父进程未终止停滞
  worker 及其子进程。其后的格式、静态分析、根／包测试与资源边界检查已分别
  执行；后续 10 组资源检查均通过。最初缺少 CMake 的三组检查，安装独立工具后
  重新通过。完整入口仍不计为通过。

本轮没有 Android SDK／设备，未构建 APK，也没有运行新增 Android 片尾／重播
集成用例；Windows／Apple 的本轮构建及实机验证同样未执行。原生 Linux 对照
不代替 Android 输出、真实 CDN、人工听音或持续性能验收。日志保存在该工作区
忽略目录 `build/validation/`。
