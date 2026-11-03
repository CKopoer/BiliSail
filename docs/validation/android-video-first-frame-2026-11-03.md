# Android 打开视频时的灰黑／单色首帧

日期：2026-11-03～04（Asia/Shanghai）。用户报告使用 `1.2.6+5` 打开视频时，先出现灰黑画面再开始播放。

## 原因与修复

Android 为 MediaCodec 提前连接 Surface，但其初始缓冲只有 `1×1`。视频参数到达后才更新尺寸，首张缓冲可能被拉伸为单色；暂停打开还可能一直停在这张图。原生插件会把这张缓冲通知为首帧，应用此前的首帧门槛只控制弹幕，没有遮住视频纹理。

- [视频输出](../../packages/bili_player/lib/src/media_kit_video_output.dart)绑定播放器时，先按实际播放视口的物理像素设置 SurfaceTexture 缓冲及 `android-surface-size`，再允许 `on_load` 创建并连接 Surface。没有已挂载视口时使用当前 Flutter view，尺寸缺失时使用有界的 640×360 初始值。仅在 `on_preloaded` 调整尺寸仍可能晚于 GPU 初始缓冲的创建。
- `on_preloaded` 中再通过公共方法通道按[容器元数据](../../packages/bili_player/lib/src/native_video_surface.dart)校正，完成后才继续解码。读取限制轨道数量与尺寸，处理像素比例和旋转；容器尺寸只是初始提示，后续仍以解码参数校正。[mpv 的 hook 和属性定义](https://mpv.io/manual/stable/#hooks)
- [加载观察器](../../packages/bili_player/lib/src/native_load_observer.dart)允许异步准备，保留原生打开总预算与源代次隔离。通道操作最多等待 2 秒，失败按视频输出错误处理；销毁弱客户端后，迟到回调不再继续已释放的 hook。
- [Android 原生适配](../../android/patches/media_kit/first-frame.gradle)保留 SDK 的输出准备信号，另提供 `BiliSail.WaitForVideoFrame` 等待有效尺寸后的画面缓冲。部分 gpu-next 输出需要开始播放才提交视频帧，因此实际画面等待放在启动播放之后，并沿用剩余打开预算；不能用实际画面信号阻止产生它的播放启动。暂停的普通视频仍确认画面，暂停的杜比转换源保持意图并在实际画面到来前隐藏纹理。
- 每个原生输出最多保留一个画面等待结果，帧到达后缓存成功状态，释放时回报取消并清理回调；旧 Future 由绑定 revision 隔离。JNI 反射不可用时使用 Flutter 的公开帧消费回调，画面信号不在输出创建时提前报成功。
- 原生适配只修改构建副本，核对固定 `fd8421d21eade4d6d12de137fa7df902fec20292` 的三份 MIT Java 源码；每处替换锚点必须唯一。不修改 Pub 缓存、相邻仓库或锁文件；依赖升级须重新审核。归一化换行后的 SHA-256：

  | 源码 | SHA-256 |
  | --- | --- |
  | VideoOutput.java | `c2cd529fdec78274ad1aa3890bb7dac050aed6d718c851bb1334f36eabce5f3d` |
  | VideoOutputManager.java | `411c5c5912a8bcbd95e90db0b974c5fd28181b595a6fd756b1bfec3077d41813` |
  | MediaKitVideoPlugin.java | `2db42dc040455b7a6fc7f506a8b47b131c89124db1c47c5c7c909a2dd2f4039d` |
- 首帧就绪前用颜色过滤隐藏纹理 RGB，同时继续绘制和消费原生缓冲。直接用不透明黑层覆盖 Texture 可能阻止消费并卡住暂停启动。就绪后移除过滤合成层，保留同一 Video 状态、纹理和播放 owner；正常播放不保留过滤层，不新增固定等待时间。弹幕仍沿用既有就绪门槛。
- 自动模式仍使用 `mediacodec,auto-safe`；软件解码和 Dolby Vision 的策略不变。

## Android 真机验证

设备 Xiaomi 13（2211133C），Android 16 API 36，ADB `950c21ca`。使用独立 `dev.bilisail.bilisail.test` Profile/AOT 包、FFmpeg 生成的 SDR 色条与独立正弦波音轨；不访问账号或在线 CDN。

修复前，自动硬解暂停打开的纹理为均匀灰色，15 秒采样没有得到色条画面，实际解码器为 `mediacodec`。最终四组启动均得到正确色条，采样没有非黑的单色帧：

| 解码偏好 | 打开意图 | 实际解码器 | 单色帧 |
| --- | --- | --- | --- |
| 自动 | 暂停 | mediacodec | 0 |
| 自动 | 播放 | mediacodec | 0 |
| 软件 | 暂停 | no | 0 |
| 软件 | 播放 | no | 0 |

四组均验证独立音轨解码、期望播放状态与重复换源；另验证准备完成但画面尚未发布时取消打开，旧等待被释放，最终保持 idle 且无迟到异常。该采样用于首帧正确性，不作启动性能或长期稳定性结论。

```powershell
.\tool\test-android-video-startup.ps1 -DeviceId <adb-id>
```

脚本先保留普通入口开发 Release，核对包名、名称、版本、AOT、不可调试属性和已有签名，再覆盖安装 Profile。`flutter drive --keep-app-running` 结束后在 finally 恢复普通入口 Release、设备常亮原值和本次端口转发，保留应用数据。已有目标 mux 资产时可用 `-SkipMuxBuild`；`-AllowStartupFlash` 仅供记录基线，默认检查不允许闪屏。

证据位于忽略目录 `build/validation/android-video-startup-before/`、`build/validation/android-video-startup-presized/` 和 `build/android-video-startup-*.log`；APK、截图及日志不提交 Git。

## 其他验证与边界

- 最终 `tool/check.ps1 -SkipPub` 通过：根应用 4112、bili_api 547、bili_player 148、bili_danmaku 161、bili_mux 5，共 **4973 项通过**；格式、静态分析及打包边界通过。根应用 13 项按既有环境条件跳过，mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生封装覆盖。日志为 `build/android-video-startup-check-final-delivery.log`。
- Windows 受控媒体回归 32 项通过、在线烟测 1 项跳过；最终绘制方案的首帧原生回归另有 6 项通过，原生生命周期／队列／尺寸检查 9 项通过。日志为 `build/android-video-startup-windows-media.log`、`build/android-video-startup-readiness-final.log` 和 `build/android-video-startup-dispose.log`。
- 独立 Windows Debug 分轨夹具完成热重载，随后运行时错误查询为空；夹具已退出。这是功能检查，不是性能结论。
- 最终 Android Dolby Vision 专项通过：自动／软件偏好的颜色 MAE 均为 **8.08（阈值 15）**，实际解码均为 `no`；独立音轨、播放推进、seek 与暂停通过，暂停时钟差均为 0 ms。切回 SDR 后自动模式恢复 `mediacodec`，软件模式保持 `no`。日志为 `build/android-video-startup-dolby-complete.log`，结果与纹理／屏幕截图在 `build/validation/android-dolby-vision/`。
- 专项截图服务器按 UTF-8 解码 adb 输出，修复 Windows 中文环境中按 GBK 解码导致截图请求中断的问题。修改前 `102a2cc` 隔离版因该截图请求失败退出；该退出不代表相同的原生错误。隔离构建首次受 SQLite 下载中断影响，复用本机缓存后由依赖自身 SHA-256 校验通过。
- 最终普通入口开发 Release 已覆盖恢复并启动：`1.2.6+5`／12605、`dev.bilisail.bilisail.test`、arm64 AOT、不可调试、既有开发签名。设备 APK 与本机 `build/development/android-arm64/BiliSail-test-arm64-release.apk` 的 SHA-256 同为 `7a18752bd3809126ab0cc7ba7ace9c9bd8aa8dc7fad596a30d39deb74c04b5b7`。保留应用数据；屏幕常亮恢复原值 0，最终无 adb reverse 残留。中途 USB 断连的一次安装不计验证，连接恢复后完成上述最终复测与恢复。

本机 JNI 反射可用，反射不可用的公开回调分支没有真机覆盖。Android 其他设备、真实账号／CDN、长时间播放以及 macOS／iOS／Linux 本平台设备未验收。
