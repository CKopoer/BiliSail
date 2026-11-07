# 缓冲时保留画面与误恢复修复

日期：2026-11-07。用户在 Windows 发现播放追上缓存时黑屏，并补充连续拖动、尤其向前跳转时反复显示“正在恢复播放…”，最后提示音视频加载中断。

## 定位

共享播放页的缓冲提示只是透明前景；正常弱网等待时，media-kit 纹理本来能够停留在最后一帧。问题在 [NativePlaybackHealth](../../packages/bili_player/lib/src/native_playback_health.dart)：即使 `isBuffering=true`，仍立即执行单轨中断判断。主视频缓存端点落后 position 超过 250ms，或缓存的外部音频时钟落后超过 750ms（高倍速另有采样余量），都会触发失败。

这些信号独立到达。缓存耗尽、seek 后等待数据时，落后的缓存端点／音频时钟不能证明单轨已经提前结束。误判随后进入 [PlaybackSession](../../lib/features/playback/application/playback_session.dart) 的有界重开路径，释放当前输出，才产生黑屏；重复误判还会耗尽恢复次数。单纯移除加载提示无法修复这个路径。

修复前，新增视频／音频边界状态用例均失败。Windows 实际播放器和正式 `PlaybackPanel` 的故障注入用例，在正常 HTTP 断供进入 buffering 后投递一条落后的缓存事件，确认旧逻辑在约 500ms 内创建了新的播放器和纹理，保持原纹理的断言失败。该注入复现已确认的状态误判，不等同于抓到了用户实际 CDN 的事件序列。

## 修复

- 后端明确 buffering 时暂不根据单轨时钟差立即重开，继续使用原连接、解码器和纹理，让最后一帧停住并叠加原加载提示。
- 同步等待仍有原来的 30 秒无进展截止时间，缓存事件不能无限续期。退出 buffering 后恢复单轨检测；非 buffering 的 8 秒静默冻结、真实单轨断流和有界恢复预算保持。
- 不缓存 Flutter 截图，不逐帧复制视频，不调整解码、缓存容量、播放意图或依赖来源。这是 media-kit 共享适配层的修复，覆盖使用该后端的视频／PGC 等 DASH 播放；没有修改可选 fvp 后端。

## 验证

- [状态测试](../../packages/bili_player/test/native_playback_health_test.dart)：28 项通过，包含新增的缓冲期间视频／音频边界落后、正常补数恢复和 30 秒超时。
- [Windows 原生回归](../../integration_test/windows_video_stall_test.dart)：正常断供及落后缓存事件两种情况都保持同一纹理、surface 和 generation；等待 9 秒前后抽样像素一致且非黑，补数后同一播放器继续推进，恢复画面发生变化，失败数为 0。修复后的完整原生分组 8 项通过，包含视频／音频提前断流及静默冻结的手动／自动恢复。
- 同文件追加连续网络 seek：仅 1 秒预读，本地 HTTP Range 响应延迟 350ms；在 1×／2×／4×／8× 下各执行六次前后跳转，共 24 次，覆盖实际新 Range 请求，等待健康采样后没有失败或重开，原生用例通过。
- `tool/check.ps1 -SkipPub` 全量通过：根应用 4557、API 678、播放器 194、弹幕 161、mux 5，共 5595 项通过；格式、静态分析和打包边界检查通过。根应用 13 项符号链接用例因本机权限跳过，mux 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为通过。
- 独立本地 DASH fixture 的 Windows Debug 热重载成功，未发现运行时错误；随后通过控制端口等待播放器释放并退出，未操作用户已安装的应用或账号。
- `tool/build-download-mux.ps1 -Target windows-x64` 准备原生组件通过；普通入口 `flutter build windows --release --no-pub -t lib/main.dart` 构建通过（59.7 秒）。入口 `build/windows/x64/runner/Release/bilisail.exe`，使用时保留整个 Release 目录；未安装或替换已有应用。组件构建不代表上面跳过的 mux 原生测试通过。
- 文档相对链接 294 项及 `git diff --check` 通过。

本地日志位于忽略目录 `build/validation/buffering-*.log`。原生用例使用 Windows Debug 和无账号本地媒体，验证功能与画面保持，不作为性能结论。Android／macOS 未进行设备验收，真实 CDN、长视频及用户现场网络仍需要运行构建确认。
