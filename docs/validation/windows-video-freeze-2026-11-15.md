# Windows 有声停帧与视频错误恢复

日期：2026-11-15（Asia/Shanghai）。

同日后续：按用户要求，仍有缓存且两轨继续推进时，硬解／输出及软件解码错误先进入统一的半窗口静默等待；实际单轨停滞或窗口耗尽才进入有界恢复。本文的立即恢复是原修复阶段的验证事实，现行时机及回归见[静默恢复记录](silent-prefetch-retry-2026-11-15.md)。

## 现场与证据边界

用户报告本地 `build/windows/x64/runner/Release/bilisail.exe` 有声音持续播放、画面停住。核对正在运行的进程 15696，启动时间 10:10:21，执行路径确为此目录；没有使用安装版或其他进程的日志。原始产物摘要与该进程的脱敏播放日志保存在忽略目录 `build/validation/windows-video-freeze-2026-11-15/`。

同一 DASH 播放器（playerId=7，generation=1）为 1080p H.264／AAC、D3D11VA，时长 783,445ms，2 倍速：

- 10:14:07 的错误发生在 position=351,974ms，缓存领先 119,769ms；`paused-for-cache=false`、`cacheReading=false`、缓存时长 120,000ms。读取空闲与窗口达到上限一致，不能据此认定缓存耗尽或下载线程死锁。
- 10:15:40 在 position=537,919ms 记录 `vd`／`hardwareDecoder` warning，总进度仍在推进，未进入 buffering，之后没有自动恢复记录。
- 前一条 error 的组件／原因均已脱敏为 `other/unknown`，不能从现存日志还原原文。现场没有独立视频帧时间戳或 GPU 呈现计数，不能精确确认停帧起点，也不能把原始错误进一步归因为某个驱动、码流或纹理资源缺陷。

能确认的应用缺陷是视频故障没有可靠进入恢复：

1. `MediaKitBackend` 只将视频 error/fatal 接入原有进度检测，忽略 warning。固定 [mpv 源码的 handle_err](https://github.com/CKopoer/mpv/blob/afd6da8843a07f463ba4c736a2ea636b1a92e23e/video/decode/vd_lavc.c#L1110) 将真实硬解帧错误报告为 warning，不是单纯的优化建议。
2. 原有 `NativeErrorMonitor` 用总 position 的推进清除错误等待。[mpv 的 time-pos](https://mpv.io/manual/stable/#properties-time-pos) 是播放位置，并不提供独立视频呈现证明；音频独自推进也能满足这一条件。
3. `vo/libmpv/...` 等输出子组件不在原来的固定组件表中，会丢失视频输出归类。无法据此证明现场那条 unknown 就来自 VO，但这是另外一个可确认的诊断与恢复缺口。

## 修复行为

新增 [NativeVideoErrorMonitor](../../packages/bili_player/lib/src/native_video_error_monitor.dart)，只处理明确的硬解失败和 error/fatal 级别的视频输出错误。硬解帧失败即使为 warning，也暂停整对音视频并交回现有会话恢复；音频／总进度、剩余缓存不能清除这条明确失败。每个源只请求一次，沿用既有 URL 重解析、备用线路、最多三次打开与 deadline，没有新增重试层。

这是明确硬件／输出失败后的保守重开策略：即使原生随后可能自行回退，也不再仅凭音频推进判定其恢复。普通压缩坏帧、缺少参考帧、软件解码 warning、原生尝试下一解码方式、硬解建议、普通网络缓冲继续走既有处理，避免将所有解码日志都变成重开。

暂停时的明确失败等待显式继续播放；seek、源代次变化、停止与销毁清除旧证据，打开阶段沿用已有就绪检查。没有改变保存的硬解偏好、缓存容量、双轨来源或依赖。输出子组件只规范化为固定 `vo` 分类，原始组件文本和媒体 URL 均不落盘；硬解 warning 也可以触发原有的限频状态采样。

## 验证

新增状态测试覆盖 warning 硬解失败、充足缓存／buffering／音频继续、单源去重、暂停继续、seek／换源／结束／销毁隔离、普通坏帧／硬解建议／正常回退不误触发，以及嵌套输出组件脱敏。

[Windows 原生回归](../../integration_test/windows_video_stall_test.dart) 在真实播放器中先停用视频轨，确认音频仍能让播放位置推进且不进入 buffering，再通过固定 SDK 的既有日志流注入硬解 warning 或输出 error。此故障注入验证应用边界，不等于重现原始 GPU／CDN 故障。分别验证整对暂停和自动重开恢复两轨，共四个场景。关闭新报告入口的对照中，硬解 warning 后等待 8 秒仍没有失败／恢复，新增断言失败；恢复入口后四项均通过。原始错误文本的合成敏感值不得进入诊断。

- Windows 原生相关分组 **11 项通过**，覆盖四项新增硬解／输出故障、两种暂时断供保留画面、连续网络 seek，以及视频／音频截断的暂停和自动恢复。截断视频实际可先产生硬解错误，因此断言同时核对明确的硬解诊断及 `nativePlayback`；只有由提前结束检测触发时才要求 `videoInterrupted`。日志：`native-stall-final.log`。
- 首次完整旧分组还运行了两项既有 `silent buffered clock freeze`：均在故障注入前，因本地文件的 `buffered - position` 为 0、不满足预设的 8 秒缓存准备断言而失败。最终 11 项分组没有包含这两项，不把它们计为通过；本轮不宣称验收无任何错误信号的视频冻结。日志：`native-stall-full.log`。
- 独立、无账号的正常双轨入口构建并运行，DTD 热重载成功，运行时错误为空；结束前等待播放器释放并关闭本机控制端口。日志：`runtime-debug.log`。
- 普通 `lib/main.dart` 的 Windows x64 Release 在 `build/video-freeze-source` 快照构建成功，交付目录为 `build/windows-video-freeze-fixed/Release/`，完整复制后逐一核对 **110 个文件**。三个本任务播放器生产文件与主工作区摘要相同，见 `built-source-manifest.json`；交付文件见 `delivery-manifest.json`。`data/app.so` SHA-256 为 `F96AFD77D3CD4E9AEC2CBBF95013B41DBD243CD3178C328741BDFB881139CF6A`，原生 mpv DLL 保持原始 `8FA6AF29A94623D7D1E16BC6DB48668F321E3FC9F1EAA86A8DF8D61EC57F00E3`。需保留整个 Release 目录；未替换原先运行中的用户进程。
- 冷构建首次因原生资产下载失败而退出；复用与固定摘要匹配的现有 SDK／ANGLE 原始归档，由原生准备脚本重新校验，设置快照安装目录及已有 NuGet 工具路径后完成构建。没有修改媒体 fork、依赖缓存、固定版本或锁文件来绕过检查。
- `tool/check.ps1 -SkipPub` 最终全阶段通过：打包边界、格式、静态分析及 **6,996 项离线测试**（根应用 5,525、API 972、播放器 333、弹幕 161、mux 5）。根应用 13 项符号链接权限用例、播放器 3 项可选原生契约用例跳过；`BILI_MUX_LIBRARY` 未配置，mux 10 项原生用例跳过，均不计为原生通过。首次检查发现故障注入触及 SDK 的 protected 日志控制器，已在测试调用处说明用途并局部标明，生产代码未放宽分析规则。日志：`full-check-final.log`。
- 本轮三个文档的 417 个本地链接及 `git diff --check` 通过。

未执行 Android、Apple 或 Linux 构建／设备验收，也不提供性能与原始 GPU 故障已排除的结论。工作区已有另一项 Android 缓冲恢复修改，本次保留；普通 Release 快照包含这些既有修改，不能把它们称为本次 Windows 修复的新增内容。
