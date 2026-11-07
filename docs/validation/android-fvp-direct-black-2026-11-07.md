# Android fvp 直出纹理启动黑屏修复

日期：2026-11-07。用户症状为打开时偶发黑屏，此后画面一直缺失，声音仍播放。范围为 fvp／MDK 解码直出 Flutter Texture 的启动确认；保留现有 Flutter 弹幕、字幕和控件，不改变默认输出或依赖版本。

## 原因与修复

Xiaomi 13（Android 16，Impeller Vulkan）上的受控 4K60 H.264 DASH 复现中，播放位置持续推进、`hasVideoOutput=true`，截图却没有视频。原生消费回调顺序为：

```text
confirm direct=true first=false
consume timestamp=0
first frame confirmed
decoder.video/AMediaCodec
```

Flutter 在首次绘制空纹理时也会调用消费通知。固定 Flutter 版本的 [SurfaceTextureWrapper](https://github.com/flutter/flutter/blob/5fc346839b/engine/src/flutter/shell/platform/android/io/flutter/embedding/engine/renderer/SurfaceTextureWrapper.java) 在 `updateTexImage()` 后通知监听方；通知本身不能证明这次已经取得视频图像。原实现立即确认首帧，结束静音预滚并异步暂停，但此时 Surface 绑定引起的 MediaCodec 重开尚未完成，初始化 seek 又与启动过程重叠。

- UI 进程继续使用公开 `setOnFrameConsumedListener`，忽略时间戳不大于零的消费，保持预滚，直到后续有带时间戳的图像；视频首个时间戳为零时等待后续帧，不接管 Flutter 内部帧监听。
- worker 分开保存 MDK 渲染首帧与直出 Surface 消费信号，旧渲染回调不能放行直出。
- 直出先静音播放至实际图像，再等待原生暂停完成后定位续播位置；预滚结束也确认暂停完成，避免迟到暂停覆盖调用方的自动播放。
- 继续沿用打开总 deadline、取消、源代次和释放屏障。软件解码、HDR 回退、其他平台兼容渲染保留原路径。

仅过滤空纹理回调的中间版本恢复了首个场景，但续播场景仍发生首帧超时，因此最终修复同时包含启动顺序调整。最终日志可观察到先忽略 `timestamp=0`，再由 `timestamp=50000000` 等实际图像完成确认。

## 验证

素材沿用[直出性能对照](android-surface-output-2026-11-07.md)的公开 Big Buck Bunny Sunflower：3840×2160、60 fps、H.264、约 25 Mbps，独立 AAC，固定本地文件。音量为零但保留音频解码和时钟；本轮是功能回归，不更新性能结论。

- 修复前探针出现 11 次“状态成功但持续无图”，截图中央区域灰度均值约 7.52、标准差约 0.63；另一次首帧确认失败。
- 最终直出连续打开 12 次通过，覆盖 1×／3×、自动播放／暂停打开、0／5 秒续播；打开和继续播放共 24 张截图均有视频，源切换间隔为 2 秒。
- 提交的可复现探针另通过 6 次打开（直出 4、兼容 2）及 12 次截图像素断言，确认音频解码、播放意图和恢复后的时钟推进。像素阈值仅适用于明确指定的可见样片，不用于判断用户视频的正常黑场。
- 根应用 4602、bili_api 678、bili_player 232、bili_danmaku 161、bili_mux 5 项通过。新增 7 项覆盖渲染／直出信号隔离、真实图像与暂停屏障、直播无 seek、取消及失败传播。根测试 13 项环境跳过；未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过。
- 根静态分析、本任务格式及探针分析通过。完整 `check.ps1 -SkipPub` 仍在既有 `test/core/platform/mini_player_window_service_test.dart` 格式检查处退出；未修改该文件，RootTests／PackageTests 分别补跑通过。
- Android Profile 探针与普通入口 Release 构建通过。未发现可连接的 Debug／DTD 应用，热重载工具未能执行；原生及 Dart 修改以重新构建的 AOT 包验证。遵照用户后续要求停止扩展测试，未重做整轮性能对照、其他平台构建或完整前景面板实机验收。

早期 300 ms 换源压力探针还记录到 MDK 读取线程原生崩溃（包括未修复基线）。本次不将该压力场景计为已解决或通过；2 秒间隔通过不代表无间隔切换稳定性。

## 复现与交付

场景配置沿用 `video`／`audio` 本地 URI、`name`、`direct`、`seconds: 5`，新增可选 `play`、`startSeconds`、`rate` 和 `verifyStartupPixels: true`。最后一个字段只在已知非黑场样片上启用；主机需要 ffmpeg。

```powershell
./tool/test-android-surface.ps1 -DeviceId <device> -ConfigPath <config.json> -Label <fresh-label> -StartupOnly
```

脚本先保留普通入口 Release，在 finally 中覆盖恢复并核对设备 APK 摘要，不卸载或清数据。当前设备已安装版本码为 12801，故仅在隔离构建目录将开发版本设为 `1.2.8+1`，仓库版本不变。

最终普通入口包为 `dev.bilisail.bilisail.test`／“BiliSail 测试版”，版本码 12801，不可调试。沿用已有开发签名证书 SHA-256 `1a69fd8175656b4c091bea4dda3f30772901280f193a4c774c1412679ca30d1b`，APK SHA-256 `d925fce008aa7cf85e2b9967b6b295ff2a04320675fa131c292f661014a92115`。最后一轮已覆盖恢复并启动该普通入口 Release，设备拉回摘要一致。

日志、截图、配置与构建保存在忽略目录 `build/validation/fvp-direct-black/`；正式可复现场次为其 `source/build/validation/android-4k60/fvp_startup_fixed_final/`。临时媒体清理和开发 APK 归档沿用测试包边界，不操作正式包数据。
