# fvp 播放中途断音检测与恢复

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
