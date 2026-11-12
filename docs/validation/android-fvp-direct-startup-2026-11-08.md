# Android fvp 直出起播回归修复

> 历史记录：fvp／MDK 已于 2026-11-12 移除。下文保留当时实现与验证事实，相关源码、资产和专属命令已退役；当前行为见[移除记录](fvp-removal-2026-11-12.md)。

日期：2026-11-08（Asia/Shanghai）。范围为 Android fvp／MDK 直出 Surface 的首次初始化；修复后由用户自行构建、实机确认。

## 定位依据

- 连接设备为 Xiaomi 13，安装 `dev.bilisail.bilisail.test`，版本 1.2.8／12805，安装时间 19:12:52，包标志不含 `DEBUGGABLE`。本轮仅通过 ADB 读取安装信息和现存日志，没有启动、安装、卸载或清理应用。
- fvp worker 的现存日志显示 `c2.qti.avc.decoder` 成功打开；最后一次尝试在 19:17:34 至 19:18:02 间等待约 28 秒，统计为 `Qin:10`、`DQout:1/28`、`Render:0`。这支持“已解码但未提交画面”，不能将后续销毁时的 codec 错误当作起播失败原因。
- `4f41f082` 将 `confirmVideoFrame` 改成先暂停 seek 再等 Surface 首帧，移除了此前 Android 必需的 Surface 初始化步骤。直出插件在 `prepare` 后绑定 Surface，并通过 `setDecoders` 重开 AMediaCodec；暂停状态下新解码器尚未提交图像，首帧屏障因而不能完成。与此同时，过早绑定暂停的外部音频主时钟也不允许初始化视频正常推进。
- SDK 的 [AMediaCodec Surface 契约](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#amediacodec)及本地固定 fvp 插件 `android/fvp_plugin.cpp` 均说明，外部 Surface 改变时需要重开解码器。此前同类启动顺序的实机证据见[11 月 7 日黑屏修复](android-fvp-direct-black-2026-11-07.md)；该历史通过记录不替代本次设备验收。

## 修改

- 仅在 Android 实际选择直出时，先让视频原生管线向新 Surface 提交真实图像，等待已有非零纹理时间戳消费确认；随后等待原生暂停完成，才执行续播位置 seek。直播不发起网络 seek。
- DASH 视频自身音轨仍关闭，真实音频伴随管线始终暂停；Surface 初始化完成并重新暂停定位后才接入音频主时钟。共享双轨起播、用户暂停意图及后续 seek／恢复规则保持原契约。初始化图像仍被现有准备态黑色滤镜遮挡。
- 对带内嵌音频的单文件／直播直出，视频与音频属于同一个 SDK 管线，因此仅在 Surface 初始化期间屏蔽该管线音量；暂停后恢复最新用户音量。并发音量更新不能提前解除这一限制。这是 Android Surface 初始化的局部例外，不是恢复共享层的静音起播门。
- 首帧失败、取消或抛错均经过暂停清理；在每个异步边界重新检查取消，旧初始化不能继续 seek 或宣告就绪。沿用原有打开总 deadline、进程隔离和释放流程。

## 本轮验证

- `bili_player` 定向执行 `fvp_surface_preroll_test.dart`、`fvp_engine_test.dart`、`android_fvp_player_test.dart`、`fvp_seek_test.dart`、`playback_startup_test.dart`：69 项全部通过，其中新增 8 项 Surface 初始化行为回归。
- 改动的三个 Dart 文件格式化、定向 `flutter analyze --no-pub` 和 `git diff --check` 通过。
- 按用户要求不构建、不安装、不重跑根全套及原生媒体回归。现存手机日志用于定位，修复后的 Android 实际播放尚未验证；其他平台没有新增设备验证。本轮没有执行 mux 原生测试。
- DTD 检查未发现运行中的 Debug 应用或服务，无法热重载；未为此另行启动或构建应用。
