# 点播打开优化

日期：2026-10-10。基于 Windows 当前环境检查“正在准备音视频…”耗时，承接[非阻塞云端续播](cloud-playback-progress.md#2026-10-10-非阻塞续播与打开耗时检查)。

## 对照与选择

使用 Flutter 3.47.6 Windows Profile、锁定的 media_kit 1.2.6 / mpv 0.36，通过实际游客 GET 解析两段 480P H.264/AAC 双轨。每个样本解析一次，交替比较原首地址与同响应常规 CDN，再交替比较视频就绪后 `audio-add` 与打开前 `audio-files`。每组 3 次；不读取已保存凭据、不发账户写请求。结果仅表示本机本轮小样本，不是统计分位数或所有网络环境的结论。

| 样本 | 首地址 + audio-add 中位数 | 首地址 + audio-files 中位数 | 常规 CDN + audio-add 中位数 | 常规 CDN + audio-files 中位数 |
| --- | ---: | ---: | ---: | ---: |
| BV14sHj62EzS | 368 ms | 396 ms | 782 ms | 826 ms |
| BV1rhHv6sEVm | 715 ms | 717 ms | 240 ms | 230 ms |

常规 CDN 并非总是最快，所以自动模式首地址仍按接口顺序。`audio-files` 没有稳定缩短正常网络耗时，本轮采用它的依据是取消与恢复能力：锁定 SDK 的 `setAudioTrack(uri)` 在命令锁内等待 `audio-add`，Dart Future 超时不能取消底层命令；[mpv 0.36 文件加载源码](https://github.com/mpv-player/mpv/blob/v0.36.0/player/loadfile.c) 将预配置外部文件交给 worker，加载期间可响应 stop/abort。视频和音频的网络 demux 仍有顺序依赖，本轮不声称并行下载。

Profile 对照探针和脱敏结果位于本地忽略目录 `artifacts/playback-open-analysis/optimization_probe.dart`、`optimization-results.jsonl`。普通播放五分钟预读、悬停五秒预读保持现有配置。

## 当前实现与竞态边界

- 点播有不同的备用视频或音轨地址时，首地址打开预算最多 8 秒，两次源打开共用 35 秒总预算，包含前一次打开及释放耗时。最多尝试两次；没有不同备用地址的点播及直播源保持原来的 35 秒预算。API 解析和后续 play 解码确认仍使用各自既有 deadline。
- 自动模式在首地址失败后，从本次响应剩余地址优先挑选常规 `upos-*.bilivideo.com`，避免两次尝试都落在 PCDN/edge 而遗漏第三个常规备选。显式 CDN 偏好继续遵守对应顺序。视频与音频各自选择，仅一轨有备用时保留另一轨原地址；不重写签名 URL。
- 只有 nativePlayback 故障可尝试备用。无效源、请求头不支持及 disposed 立即结束；每次尝试前重新检查 source generation、账号 scope/epoch、取消及销毁，旧源不能启动备用。
- 外部音轨在 loadfile 前配置 `audio-files`，读回核对并转义 mpv 的平台路径列表分隔符；原始 URL 的 query、编码、端口不变。[mpv 路径列表语义](https://mpv.io/manual/stable/#list-options)规定 Windows 用分号、Unix 用冒号。
- 继续使用单个播放器和同一份允许的请求头。通过原生 `current-tracks/audio/external-filename` 确认选中了当前源的外部文件，避免把内嵌音轨误判为外部音轨成功；播放时仍等待真实音频解码。就绪信号随 generation 变化中断，原生观察器由播放器持有，成功时取消观察，异常/取消时随播放器销毁。
- 保留暂停意图、seek、倍速、音量、缓存窗口与实际纹理就绪规则；没有引入代理、第二个音频播放器或新依赖。

## 验证

`tool/check.ps1 -SkipPub` 通过：根应用 1618、API 350、播放器 34、弹幕 72、合并包 2 项通过，合并包另有 7 项因未提供原生库跳过；格式和静态分析通过。会话与 CDN 专项 124 项通过，覆盖备用选择、签名 URL 保留、预算、故障分类及失败后账号切换不重试。

新增 Windows 原生测试 `windows_playback_startup_test.dart` 4 项通过，受控服务器保持音轨请求无响应，验证 stop、换源、dispose 和 deadline 后恢复；确认带分号/冒号的 query 完整到达，释放迟到响应不会改变新 generation 或制造旧失败。停止/销毁与换源均在 3 秒行为断言内完成；2 秒 deadline 后也能重新打开本地双轨。测试绑定持续 pump 帧，避免新 VideoController 的 post-frame 初始化被测试自身阻塞。上述 Debug 耗时仅为取消上界断言，不能作为性能基准。

既有 Windows 请求头/302 重定向/Range/双轨解码/seek/重复打开专项通过；完整播放套件 7 项通过、1 项仍失败于 `windows_playback_test.dart:798` 的控件隐藏断言（期望没有 player-controls，实际仍有 1 个）。它与前一轮同样失败；本轮保留控件实现。非阻塞云进度、本地优先、多标签、工作区恢复用例通过。原生脱敏 HTTP 403 诊断和预读窗口各 1 项通过。

修改后的实际 `MediaKitEngine` Windows Profile 探针通过：本地 3 次打开 151–251 ms，两段游客在线视频共 4 次打开 479–1343 ms，实际双轨解码与 native 视频输出均确认，硬解为 `d3d11va-copy`。入口与结果为本地 `optimized_engine_probe.dart`、`optimized-engine-results.jsonl`。CDN 地址会随每次解析变化，不能将这些结果与前一轮直接相除当作固定提速比例。完整原生套件未启用线上游客开关；本轮线上证据来自上述 Profile 探针，不代表真实账号高清或完整页面性能验收。

最后 `flutter build windows --profile --no-pub -t lib/main.dart` 成功，已恢复默认 Profile 产物为正常应用入口，日志 `artifacts/playback-open-analysis/optimized-app-profile-build.log`。

日志位于本地 `artifacts/playback-open-analysis/optimization-check.log`、`startup-races-native.log`、`optimization-full-native.log`、`optimization-diagnostics-native.log`、`optimization-buffer-native.log`。Debug SDK 将热重启指针保存在带 PID 的系统临时文件中；初次完整验证在 `NativeReferenceHolder: Located` 后退出，疑似进程 ID 重用读取了旧指针。重跑使用独立 TEMP/TMP 目录后正常，未修改 SDK 或用户应用。构建重跑时串行执行，避免共享 Windows 构建目录的安装目标互相覆盖。

Android/macOS 原生音轨加载、真实账号高清双轨和更广泛 CDN/设备尚未验证；Windows Profile 正常源优化幅度不能从这两段样本概括为统一百分比。未提交或发布。

```powershell
$env:BILI_TEST_MEDIA_DIR = (Resolve-Path test/fixtures/media).Path
flutter test integration_test/windows_playback_startup_test.dart -d windows --no-pub
flutter test integration_test/windows_playback_test.dart -d windows --no-pub --plain-name 'Windows native DASH pair: headers, redirects, ranges, seek and lifecycle'
```
