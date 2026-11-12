# Android fvp 直出跳转准备态修复

> 历史记录：fvp／MDK 已于 2026-11-12 移除。下文保留当时实现与验证事实，相关源码、资产和专属命令已退役；当前行为见[移除记录](fvp-removal-2026-11-12.md)。

日期：2026-11-08（Asia/Shanghai）。用户反馈最新开发 Release 的 fvp 直通硬解在点击进度条后持续显示“正在准备音视频”。本轮按要求仅修复、运行相关单元测试并提交，由用户后续构建和实机验收。

## 定位

- ADB 只读核对 Xiaomi 13 上的 `dev.bilisail.bilisail.test`：版本 1.2.8／12805，最后更新时间为 19:28:51。没有启动、安装、卸载或清理应用。
- 现存 fvp worker 日志显示 `c2.qti.avc.decoder` 在跳转时 flush，并释放过 59.700000、72.033312、71.133312 秒等目标图像；部分目标之后长时间没有继续呈现。日志支持跳转后的确认／恢复受阻，不支持把它归因于未开启硬解；日志没有暴露具体 Dart 等待点，不能用它代替修复后的设备验证。
- 代码中的时钟阻塞条件是：seek 一开始就将视频的外部音频主时钟固定到请求位置，视频 seek 回调完成后才定位暂停的真实音频管线。如果直出目标图像的时间戳略晚于固定锚点，视频呈现会等待音频推进，而音频必须等待视频目标确认。后退跳转还会在原生视频暂停完成前改变旧画面的主时钟。
- MDK 的本地固定头文件及 [onSync 契约](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-onsyncstdfunctiondouble-cb-int-mininterval--10) 要求处理 seek 和 seek 完成；`DBL_MAX`／`TimestampEOS` 表示立即呈现图像。本轮使用这一公开契约，不修改 SDK、依赖固定版本或 Pub 缓存。

## 修复

- 原生暂停完成前冻结当前音频位置；执行暂停 seek 或已退休源的目标 prepare 时，临时让视频的 `onSync` 返回 `TimestampEOS`，使目标图像不再等待暂停的音频时钟。两条真实管线仍然暂停，不发起静音预跑。
- 视频及音频均确认目标后，当前 seek 在 `finally` 中恢复真实确认位置的暂停锚点，再由共享播放门恢复用户播放意图。失败同样退出临时时钟状态；旧 seek 的迟到清理不能覆盖新目标。
- seek 期间的用户暂停继续生效，同时保留目标解码所需的临时时钟状态。正常暂停、继续、自然片尾和旧音频时钟隔离沿用原契约。
- 新增原生 API 后通过 `dart run tool/ffigen.dart` 重新生成 FFI 和 record-use 映射，没有手改生成文件。本机生成器需设置 `LIBCLANG_PATH=C:/msys64/ucrt64/bin/libclang.dll`；首次未设置时生成失败，指定现有库后成功。

## 验证

- `flutter test --no-pub test/fvp_engine_test.dart test/fvp_seek_test.dart`：50 项通过，包含新增的目标视频已确认、音频仍等待时的恢复／手动暂停用例。
- `tool/test-windows-fvp-audio-clock.ps1`：原生时钟单元测试通过，覆盖略晚于请求位置的目标、前后跳转、暂停锚点恢复、取消后的新目标和旧音频时钟隔离。测试只调用 fake MDK API，并非实际 Android 解码／呈现验证。
- 改动 Dart 文件格式检查、四个 Dart 文件的定向 `flutter analyze --no-pub`、文档相对链接及 `git diff --check` 通过。
- 按要求未构建应用、未运行根全套或原生媒体集成回归、未操作设备播放；Android 修复效果及其他平台实际播放仍待验证。本轮未执行 mux 原生测试。
- DTD 未发现运行中的 Debug 应用，无法热重载；没有为此另行启动或构建应用。
