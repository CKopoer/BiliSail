# 直播与点播弱网缓存调整

日期：2026-11-01。工作区基线 `fc771e6`。用户反馈直播在弱网下频繁显示“正在准备音视频”，要求对照 dart_simple_live 与 PiliPlus 检查直播、点播缓存。

## 现状与参考

- 本项目固定 Predidit media-kit `83b7ca63772856e1ea0158916177e136f7b7b0be`，SDK 每个 demuxer 默认前向、后向各 32 MiB。应用在打开前关闭磁盘缓存，限制 `cache-secs` / `demuxer-readahead-secs` 为最多 300 秒，悬停为 5 秒，并启用 `cache-pause`；SDK 同时将 `network-timeout` 设为 5 秒。原来直播和点播没有区分容量、恢复门槛；后者沿用 mpv 约 1 秒默认值。
- 2026-10-30 的健康检查和原生错误监测对静默停滞及正常网络缓冲均采用 8 秒截止时间；过早重开会放弃已收到的数据。页面将准备、缓冲和自动恢复显示为同一句提示，因此提示本身不能证明每次都重新请求了地址。
- 本地 dart_simple_live `ba828e6783b176ea5709fcd09f0eb01dfaceeb51` 的 `simple_live_app/lib/modules/live_room/player/player_controller.dart` 没有自行设置缓存容量或恢复门槛，TV 容量参数已注释。其应用声明 `media_kit ^1.2.2`，本地没有锁文件，不能将其实际解析版本或默认值当成本项目的值。
- 本地 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/utils/storage_pref.dart` / `lib/plugin/pl_player/controller.dart` 将点播默认设为 4 MiB 前向、4 MiB 后向及 16 秒，时间随倍速调整；直播使用两倍前向容量、不保留后向缓存。本项目采用按源类型分配前后向容量的思路，保留已有点播容量、预读上限和悬停规则，不照搬其较小容量或 hysteresis 参数。其实际 override 指向 `My-Responsitories/media-kit` 的 `native` 分支，与本项目的固定依赖不同。
- 两个 GPLv3 参考应用仅只读调研行为；本轮自行实现，没有复制源码、资源、增加运行时依赖或修改相邻仓库。

[mpv 官方缓存说明](https://mpv.io/manual/stable/#options-cache-pause-wait)区分可预读最大量与缓冲后恢复门槛；扩大容量不会让直播端提前产生数据。`cache-pause-initial` 可在首次播放建立短缓冲，代价是启动等待。到达片尾或容量等限制时，mpv 可能提前恢复。

## 调整

| 场景 | 前向 packet 配额 | 后向 packet 配额 | 时间上限 | 缓冲后恢复门槛 | 首次预缓冲 |
| --- | --- | --- | --- | --- | --- |
| 直播 HLS / HTTP-FLV | 64 MiB | 0 | 最多 300 秒 | 约 3 秒媒体时间 | 开启 |
| 视频 / PGC / 音频 / 本地播放 | 32 MiB | 32 MiB | 最多 300 秒 | 约 2 秒媒体时间 | 关闭 |
| 静音悬停预览 | 32 MiB | 32 MiB | 5 秒 | 约 1 秒媒体时间 | 关闭 |

- 时间、字节限制先到者限制预读；容量是每个 demuxer 的 packet 配额，不是进程内存上限。直播将原有前后向总配额用于前向数据，仍关闭追加式磁盘缓存，不落盘媒体 URL 或凭据。
- `ProgressiveSource` 增加默认关闭的 `isLive`；共享会话明确标记 HTTP-FLV，HLS 沿用 `ManifestSource.isLive`，不靠 URL 后缀猜测身份。离线 progressive 和点播不受直播配置影响。
- 在媒体装载前设置并回读核对所有缓存属性，沿用打开预算及 generation 取消。每次换源创建独立实例，不将直播配置带入下一次点播。就绪时同步原生 buffering 状态，playing 事件不覆盖仍处于 buffering 的 phase。
- 原生 HTTP 网络 I/O 超时从 SDK 的 5 秒调至 30 秒，与缓冲恢复窗口匹配，避免底层先终止可恢复连接。首次打开仍受 6 秒首地址／35 秒共享准备预算和取消约束；不会借此延长故障 CDN 的首次打开预算。
- 网络 buffering 连续无播放进展的等待上限改为 **30 秒**；非 buffering 的静默停滞仍为 **8 秒**。错误日志监测同步采用缓冲等待期；重复日志或缓存进度不能无限续期。单轨 EOF、音频时钟落后及视频 buffer 越界的停止规则、最多三次 native open / 35 秒准备恢复预算保留。
- 暂停、seek、关闭、换源及账号代次继续取消或隔离旧检查。普通、全屏共用提示分别为“正在准备音视频…”、“网络缓冲中…”及“正在恢复播放…”。

## 验证

- `tool/check.ps1 -SkipPub` 最终通过：根应用 3862、API 536、播放器 108、弹幕 145、mux 5，共 **4656 项通过**，格式、静态分析与打包边界检查通过。另有 13 项 Windows 符号链接测试因权限跳过、10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。日志 `build/validation/network-buffer-check-final.log`。
- `tool/test-windows-content.ps1` 通过：受控 UGC／PGC／HLS／FLV 共用播放窗口、FLAC／E-AC-3 音轨，以及新增直播弱网用例均通过；公网分支未启用，不计为在线验证。日志 `build/validation/network-buffer-content.log`。
- 新增 `native_live_buffer_test.dart` 使用无账号本地 FLV，按 tag 时间戳分段供给：缓冲耗尽后，原生位置稳定在 4229ms，等待 9 秒保持不变；补入 2 秒媒体数据仍保持缓冲，补齐后推进至 6063ms，整个过程只有 1 次 HTTP 请求、无失败且 generation 未变。首次断言的基准时刻现等待解码／音频设备已有队列消耗后再采样，不将短暂队列消耗误判为持续播放。该用例已接入内容验证脚本。
- `windows_video_stall_test.dart` 的双轨共同等待／补数恢复、视频／音频各自提前终止与自动恢复五项通过；网络停顿延长至 9 秒，仍在原 generation 恢复。最终配置的日志 `build/validation/network-buffer-windows_video_stall_test.log`。
- 其余定向 Windows 原生验证：启动终止／取消／超时 5 项、视频就绪 6 项、预览 5 秒窗口 1 项及普通 300 秒窗口 1 项均通过。普通窗口在暂停、推进及窗口外 seek 后保持上限，seek 后预读 300.125 秒，符合既有 500ms 分包／解码容差。日志为 `build/validation/network-buffer-windows_playback_startup_test.log`、`network-buffer-native_video_readiness_test.log`、`network-buffer-windows_preview_buffer_test.log`、`network-buffer-window.log`。
- `tool/test-windows-media.ps1` 在首文件 7 项通过、2 项失败后退出，完整脚本不能标为通过：`windows_playback_test.dart:888` 未找到 `standard-control-row`，`:1379` 切页后仍找到 `VideoSurface`。在独立 worktree 的未修改基线 `fc771e6` 仅运行这两项，完全相同的断言再次失败，确认是基线界面回归；未修改这些控件／导航行为或测试。日志 `build/validation/network-buffer-media.log`、`network-buffer-baseline-final.log`。临时基线 worktree 已清理。
- `tool/build-download-mux.ps1 -Target windows-x64` 按固定源码准备组件通过；正常入口 `flutter build windows --release --no-pub -t lib/main.dart` 成功（51.8 秒）。日志 `build/validation/network-buffer-mux-build.log`、`network-buffer-release.log`。运行入口 `build/windows/x64/runner/Release/bilisail.exe`，分发须保留整个 Release 目录；未安装或替换已有应用。

正常 `lib/main.dart` Windows Debug 入口启动、DTD 热重载成功，重载后未发现运行时错误，随后退出本次调试进程。日志 `build/validation/network-buffer-debug.log`。

受控本地 HTTP 行为验证不代表真实 CDN 或全部弱网已改善；持续吞吐低于码率时，有限缓存仍会耗尽。直播首次约 3 秒缓冲增加启动等待及直播延迟，需要实际网络体验确认。Windows 测试使用零音量，不代替人工可听与长期播放验收；Android／macOS 本轮未构建、未实机验证。
