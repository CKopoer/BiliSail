# fvp HTTP 断流与读取无响应的有界续读

> 历史记录：fvp／MDK 已于 2026-11-12 移除。下文保留当时实现与验证事实，相关源码、资产和专属命令已退役；当前行为见[移除记录](fvp-removal-2026-11-12.md)。

日期：2026-11-11（Asia/Shanghai）。针对本机已安装 Windows x64 MSIX
`1.2.9+4`、MDK `0.39.0` 的播放进度追上缓冲问题。

## 现场证据与归因边界

- 22:50:33.913，进程 5832，fvp、2 倍速，位置 723166ms，时长
  806033ms，共同缓存端点 723463ms；出现 `audioClock / stalledForMs=0`，
  没有 `audioPositionMs`。22:50:34 从同一位置重新开流。
- 22:25:38，进程 524，1 倍速，位置 403200ms、时长 539133ms、缓存端点
  403306ms，出现相同事件。
- 对应实现中，这种即时事件来自伴随音频的提前 EOF，而不是两秒健康检测或
  三十秒 buffering 超时。原生日志已禁用，没有当时 TCP FIN/RST、完整接收
  字节数或持续读包记录，不能追溯断流起点，也不能断言首次原因一定属于 CDN。
  现场已进入音轨停止／EOF 分支，不支持将该时刻描述为一直堵在读取调用里。
- 安装目录的 AOT 与当前工作区构建摘要不同；确认安装版本、SDK 摘要及已导出
  `bili_fvp_audio_end` 端点观察器，没有把当前未安装源码视作已安装修复。
- 使用该视频公开 playurl，未读取账号凭据，三个返回的音频 CDN 地址均能返回
  `206` 和 65536 字节，耗时 235–281ms。这仅说明复查时这些连接可读。
- 后续对公开音轨 30232 的三次完整读取均取得声明的 6751086 字节，耗时
  422／735／437ms，SHA-256 一致。其中 mcdn 返回 200、两个 UPOS 备用条目
  返回 206；后两项为同一 CDN host，不计为三个独立节点。没有发现该公开
  音轨固定截断的数据证据，仍不能用当前读取排除过去某条连接瞬断。

现场日志已复制到忽略目录 `build/validation/fvp-read-interruption/`。
原视频为 `BV1KqKZ6REMq`，本轮没有持久化其带签名媒体 URL。

## 已复现的缺口与修复

应用在打开主视频和伴随音频前显式设置 `avio.reconnect=0`。受控 HTTP 服务
声明完整 247528 字节 AAC 音轨，但发送 60000 字节后断开连接；旧代码只发一次
`Range: bytes=0-`，缓存消耗到约 6.3 秒后，两个倍速都产生与现场同形的提前
音频结束事件。服务端剩余媒体一直可读，但播放器不会从断点续读。

[MDK 官方属性契约](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#ffmpeg-properties)
允许 `avio.*` 传入 FFmpeg 的 HTTP 选项；固定 fvp 包的默认播放器本来开启
HTTP reconnect，而本应用覆盖为关闭。依据
[FFmpeg HTTP 实现](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/http.c)，
本轮在原生 HTTP 层恢复同一 seekable 点播资源的字节续读：

- HTTP(S) 点播开启 reconnect，每次失败的底层读取最多一次续连，延迟上限及
  总延迟上限均为一秒；读取无响应门槛由 30 秒缩短至 5 秒。实际 FFmpeg
  demuxer 可以再次调用读取，持续无数据的受控用例共观察到三次 HTTP 请求，
  然后正常进入现有有限恢复，不能将该选项表述为整个播放只发一次额外请求。
- 不在自然 EOF 重连、不从零重启非 seekable 流、不重试建立连接错误或 HTTP
  业务状态；直播及本地源仍关闭 reconnect，保留原 30 秒 I/O 参数。
- 保留两个原生管线的头部、Range、音频主时钟、暂停／seek／释放屏障；没有
  增设应用 HTTP 代理、字节缓存、后台定时重试，也没有扩大应用恢复预算。
- Windows 进程内音频 EOF 的诊断新增原生音频呈现位置、解码端点、自身时长、
  音视频 packet 队列时长和 media status 数值。没有输出 URL、请求头或原始
  SDK 文本。Android worker 尚未转发这些新数值，不能宣称已有该项观测能力。
- 新回归还复现出正常片尾的独立缺口：完整音轨停止后，把视频外部时钟固定在
  视频时长会让 MDK 停在最后一帧，约两秒后被总时钟检测判为中断。确认音轨
  完整结束后，原生桥注销外部音频时钟，让 MDK 自身时钟完成视频排空；seek／
  replay 重新接入音频时钟。没有伪造播放位置、放宽末尾容差或关闭健康检测。
  C++ 测试覆盖注销、重复 EOF、暂停不复活旧时钟及 seek 重新接入；FFI 沿用
  `ffigen 23.0.0`，以 `dart run tool/ffigen.dart` 重新生成绑定和 record-use 映射。

实现：[HTTP 策略](../../packages/bili_player/lib/src/fvp_http_options.dart)、
[原生端口](../../packages/bili_player/lib/src/fvp_native_player.dart)、
[诊断契约](../../packages/bili_player/lib/src/player_diagnostics.dart)。

## 验证

[原生 HTTP 回归](../../integration_test/windows_fvp_http_recovery_test.dart)
已加入 [Windows fvp 脚本](../../tool/test-windows-fvp.ps1)。分别模拟 socket
提前关闭、连接仍存活但停止发送、持续断流及在等待数据时释放。瞬断和无响应
覆盖 1／2 倍速，检查精确的 `60000` 字节 Range 续传、真实播放推进及没有整源
失败；同时检查自然 EOF 不再发请求、持续失败有限退出、取消不等待续连。

原视频公开流通过普通生产端口从 650 秒以 2 倍速播放 45 秒，实际推进至
739833ms，越过原 723166ms 故障位置，无失败；公开接口返回 480P、音轨
30232，没有账号／上报。Debug 入口 DTD 热重载成功，运行时无错误，并完成
原生释放及退出。结果保存在忽略目录 `online-debug-original.json`。该项是功能回归，
不作为性能、原账号清晰度或首次故障根因的证明。

全部修复后的同一公开流再次从 650 秒以 2 倍速运行 60 秒，确认无失败；
DTD 热重载成功、没有运行时错误，随后完成原生释放并以 0 退出。
本次结果为 `online-debug.json`，交付目录继续使用普通 `lib/main.dart` 入口。

`tool/check.ps1 -SkipPub` 最终完整通过：格式、静态分析及资源边界检查通过；
根应用 5142、API 886、播放器 375、弹幕 161、mux 5 项，共 6569 项通过。
13 项符号链接权限条件跳过；未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例
跳过，不计为原生通过。五份锁文件未变。C++ 时钟回归通过 MSVC C++17
`/W4 /WX` 编译与实际运行；生成物仅增加本次公开的时钟结束函数。

`tool/test-windows-fvp.ps1` 最终以 0 退出：HTTP 续读 6 项、双向提前结束及
自动恢复 8 项、后端／直播／听视频 3 项、跳转同步 9 项、自然 EOF／重播／
跨 EOF 连续跳转 4 项，共 30 项原生用例全部通过。所有本地媒体均使用零音量，
不代替人工可听验收。探索阶段的 HTTP 片尾回归曾检出上述真实时钟冻结，
修复后定向用例及最终整套均通过；取消用例改为在请求未完成时执行，确认
释放在两秒内完成且没有发出后续 Range 请求。

`flutter build windows --release --no-pub -t lib/main.dart` 成功，普通入口完整
目录复制到 `build/development/windows-x64/fvp-http/Release/`，保留全部原生库、
资源和许可。AOT、原生桥、MDK、FFmpeg 及 runner 的 SHA-256 与构建目录逐项
一致，摘要、源码基线和版本记录在旁边的 `build-info.json`。没有将受控入口
混入交付目录，也没有替换仍在运行的系统 MSIX 安装；版本未递增、未发布。
构建只有既有 CMake CMP0175 与链接器警告，没有编译失败。

受控回环 HTTP 不能证明最初 CDN 主动断开；原视频公开流也与用户账号可用的
清晰度／音质不一定相同。不执行账号写入、进度上报或性能测量；Android、
macOS、iOS、Linux 与 Windows ARM64 没有本轮构建／实机验证。
