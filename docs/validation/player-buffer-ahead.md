# 播放器向前预读窗口

日期：2026-10-07。普通播放默认最多预读当前位置之后 5 分钟的媒体数据；悬停预览保留 5 秒窗口。窗口使用媒体时间，倍速不改变这 5 分钟的含义，暂停时不继续预读到片尾；播放推进和 seek 后按新位置补充。

## 实现边界

- [OpenOptions](../../packages/bili_player/lib/src/player_contract.dart) 将 `maxBufferAhead` 默认值与允许上限统一为 5 分钟，不再依赖后端默认的超大时间窗口。适配器拒绝非正数或超过上限的值，预览仍可显式传入 5 秒。
- [MediaKitEngine](../../packages/bili_player/lib/src/media_kit_engine.dart) 在任何媒体 URL 装载前设置并回读验证 `cache-secs` 和 `demuxer-readahead-secs`；每次换源创建独立播放器，普通点播、影视、直播与本地分轨均通过该入口。音频添加使用同一原生实例。
- 同时关闭 `cache-on-disk`，使用现有 SDK 的内存缓存与 32 MiB 向前字节限额；回看缓存另有 SDK 的 32 MiB 限额。这是每个 demuxer 的 packet 配额，不能作为整个播放器进程的内存上限。高码率可能提前触及字节限额，5 分钟是上限，不是要求填满的最低量。
- 原生配置限制的是 demuxed packet 的时间戳窗口；解码器、帧边界和网络 I/O 有少量超出，不能解释为精确到毫秒或严格下载字节配额。已保留的回看缓存不属于向前窗口；短于 5 分钟的视频仍可缓存到片尾。

[mpv 官方手册](https://mpv.io/manual/stable/#options-cache-secs) 说明缓存开启时采用 `cache-secs` 与 `demuxer-readahead-secs` 中较大的值，所以必须同时限制。手册同时说明磁盘缓存文件只追加、释放 packet 元数据不回收文件空间；本实现沿用预览的内存策略以避免播放期间临时文件持续增长。

## 验证方式

- 根播放会话断言普通视频、影视与直播打开的窗口为 5 分钟；播放器包验证 0、负值和超过 5 分钟的值在创建原生播放器之前被拒绝。现有预览编排继续断言 5 秒。
- [Windows 原生用例](../../integration_test/windows_buffer_ahead_test.dart) 由 [验证脚本](../../tool/test-windows-buffer.ps1) 生成 12 分钟无账号分轨素材，通过本地 HTTP/Range 验证两轨解码、初始/暂停/播放推进/窗口外 seek 后的 5 分钟窗口，以及短视频重开。允许 500 毫秒的原生帧/解码边界误差。
- [Windows 媒体回归脚本](../../tool/test-windows-media.ps1) 一并执行普通播放、诊断、5 秒预览和 5 分钟窗口用例。

## 本轮结果

- `tool/test-windows-buffer.ps1` 通过：初始/暂停向前 299.750 秒，播放推进后 300.083 秒，seek 到 400 秒后 300.208 秒；两轨解码、HTTP/Range 与短视频重开均通过。小于 0.25 秒的边界超出在用例允许的 500 毫秒范围内。日志 `build/player-buffer-native.log`。这是本地 Windows Debug 功能验证，不是性能或下载流量基准。
- `tool/check.ps1 -SkipPub` 全部通过：根应用 1158、API 包 307、播放器包 22、弹幕包 52，共 1539 项测试，根应用和三个包的格式与分析通过。日志 `build/player-buffer-check.log`；这是该次检查的工作区快照，包含当时其他并行改动。
- 单独运行 5 秒预览原生用例通过：初始向前 4.916 秒，播放推进后 5.083 秒，seek 后 5.125 秒；随后普通打开完整缓存 60 秒短视频，预览配置没有污染普通播放。
- 单独运行 `windows_playback_diagnostics_test.dart` 通过，受控 HTTP 403 仍进入明确失败状态并只记录脱敏诊断（`httpStatus=403 phase=failed rawUrlRetained=false`）。
- 正常 `lib/main.dart` 入口 `flutter build windows --release` 通过，日志 `build/player-buffer-release.log`。这是本轮工作区快照的构建验证，不替代三端运行或安装验收。
- 初次 `tool/test-windows-media.ps1` 的普通播放文件为 7 项通过、1 项失败：工作区隐藏播放用例遇到 `WindowCaption` 的 `BoxConstraints forces an infinite height`。该次工作区包含并行的标题栏布局修改，尚不能宣称整套原生回归通过。日志 `build/player-buffer-windows-media.log`；未修改对应界面代码。

Android/macOS 原生运行、真实 CDN 下载字节数与人工音画同步尚未验证；本地 HTTP 的媒体时间窗口验证不等同于公网流量或性能测量。
