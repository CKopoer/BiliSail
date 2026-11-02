# 杜比视界 Profile 5 跨平台处理与兼容回退

日期：2026-11-03。承接 [#54 首轮 Windows 修复](dolby-vision-profile5-2026-11-02.md)。用户要求继续检查 Android 和其他平台，并明确选择“优先正确播放，必要时自动回退兼容画质”。测试账号无大会员权限，使用同一 Dolby 官方 Profile 5 公开样片，不绕过账号权益。

## 原因与实现

Profile 5 的基础层不能作为普通 YUV／HDR10 显示。PiliPlus 及本项目固定的 media-kit 视频插件在桌面使用 libmpv render API、Android 默认使用 gpu；这些路径不能完成所需的 Dolby RPU 重塑。固定提交和只读参考范围沿用首轮记录，没有复制 PiliPlus GPL 应用实现，也没有改动相邻仓库、Pub 缓存或依赖锁文件。

Android 的第二个问题是真机 MediaCodec 硬解没有把 RPU 传给 libplacebo：只改 gpu-next，自动解码仍为绿／紫色；软件 HEVC 加 gpu-next 才得到正确颜色。当前 Android 固定库没有 FFmpeg libplacebo 滤镜，但包含 gpu-next，因此不能直接照搬 Windows 滤镜。

- 所有平台在 `on_preloaded` 中检查 demuxed Profile 5。旧原生库缺少 profile 属性时，对调用方提供的 `dvh1`／`dvhe` 编码标记采用保守转换路径；已明确识别的 Profile 8 不改。纯音频跳过检查。
- Android 仅对此源设 `hwdec=no`、`vo=gpu-next`、BT.709／sRGB 目标。播放器配置跟随源，避免 SDK 在迟到的视频参数事件里恢复为 gpu；通过现有 SurfaceTexture 公共通道同步输出尺寸，并隔离旧播放器的异步结果。
- 其他嵌入式后端采用首轮的 `lavfi/libplacebo` RPU 转换和 copy 硬解。通过公开 `option-info/vf`／`option-info/vo` 的 choices 检查能力，不探测私有 FFmpeg ABI，也不从操作系统名称推断支持。
- 转换不可用时停止该视频轨道并返回 `unsupportedVideoColor`；解码／输出失败及输出模式不符合配置时也拒绝作为成功播放交付。滤镜必须输出 BT.709，Android 必须实际使用 gpu-next。检测到需要转换后，输出准备最多等待 6 秒，避免不支持的滤镜／VO 耗尽全部启动预算；成功、失败及换源均取消该限时器。
- 共享 `PlaybackSession` 对 UGC／PGC 在线内容最多重新解析一次兼容流：优先最高可用且不高于原画质的非杜比档，编码优先 H.264。原始偏好不落盘改写；暂停意图、位置、倍速、音量、音轨及账号／source generation 边界保留。兼容源的网络重试继续使用兼容编码，沿用剩余启动预算和原生打开次数上限。
- 第二次仍不支持时提示无法取得兼容流，不无限换 CDN。离线内容不联网替换，提示当前设备不支持该离线格式。直播不适用本次点播回退。

这是向 SDR 纹理映射，未实现 Dolby Vision／HDR 显示器透传。Android Profile 5 软件解码有 CPU／功耗成本，本轮没有性能或长期播放结论；普通 SDR 和其他兼容源仍使用原硬解路径。

原生语义依据：[mpv gpu-next 与 render API 差异](https://github.com/mpv-player/mpv/wiki/GPU-Next-vs-GPU)、[mpv 属性／选项文档](https://mpv.io/manual/master/)、[FFmpeg libplacebo](https://ffmpeg.org/ffmpeg-filters.html#libplacebo)。Android MediaCodec 丢失 RPU 的结论来自下述本设备 A/B 结果，不推导所有硬件解码器都相同。

## Android 真机证据

设备 Xiaomi 13（2211133C／SM8550／Adreno 740），Android 16 API 36，ADB `950c21ca`。全部通过独立 `dev.bilisail.bilisail.test` Profile 构建测试，开发签名与既有测试包一致，覆盖安装保留数据。未读写正式包凭据。

| 同一样片路径 | 自动解码 | 显式软件解码 |
| --- | --- | --- |
| 修复前 gpu | 实际 MediaCodec，绿／紫偏色 | 绿／紫偏色 |
| 只设 gpu-next | MediaCodec copy 仍偏色 | 颜色正确 |
| 按 Profile 5 配置软件 HEVC + gpu-next | 实际 hwdec=no，颜色正确 | 实际 hwdec=no，颜色正确 |

最后一次已完成真机测试：自动模式在 510 ms 截图，320×180 RGB MAE **8.08/255**；软件模式在 527 ms 截图，MAE **7.49/255**，均小于 15 的回归阈值。参考为样片约 510 ms 的 Dolby-aware SDR 转换图，阈值允许缩放和邻近帧差异，不是显示器色准校准。实际屏幕截图和 Flutter 纹理截图一致。两模式均有独立音轨解码，播放推进、seek 和暂停通过，暂停时钟差为 0 ms。换回 SDR 后实际恢复 `mediacodec`。

该真机运行已完成颜色路径修复，随后加入的能力／输出保护、异步尺寸保护及应用兼容流回退没有再次在 Android 实机执行。设备断开后，用户明确要求不用重新测试。测试后已覆盖恢复普通入口开发 Release、恢复屏幕常亮原值 0，并移除本轮 adb reverse；未卸载或清空测试应用。

本地证据位于 `build/validation/android-dolby-vision/`：`results.json`、`texture-*.png`、`screen-*.png`、原生日志和普通 Release 元信息。媒体／截图／APK 不提交 Git。

## 可复现入口

公开样片来源、32 MiB 前缀 SHA-256、6 秒截取范围和版权范围见首轮记录。准备逻辑共用 `tool/dolby-vision-fixtures.ps1`，不将样片入库。需要带 libplacebo／Vulkan 的本机 FFmpeg。

```powershell
.\tool\test-windows-dolby-vision.ps1 -PrepareSample
.\tool\test-windows-dolby-vision.ps1 -WithoutVulkan
.\tool\test-android-dolby-vision.ps1 -DeviceId <adb-id> -PrepareSample
```

Android 脚本先保留新构建的普通入口开发 Release，再构建独立测试包 Profile，校验包名／名称／签名，执行 `flutter drive --keep-app-running`。`finally` 覆盖恢复普通 Release、移除自己的端口转发、恢复设备电源设置并关闭自有本地样片服务器。音视频经 loopback／Range 服务交付；测试不访问账号。已有对应 mux 资产时可显式使用 `-SkipMuxBuild`。

测试入口 `integration_test/android_dolby_vision_test.dart` 覆盖两种 Profile 5 解码偏好、实际纹理颜色、独立音频、seek／暂停以及换回普通源。Android 新规范入口已静态检查，最终新增的 SDR 软件模式断言尚无设备执行记录。

## 验证结果与边界

- 最终 `tool/check.ps1 -SkipPub` 全量通过：格式、静态分析、打包边界脚本、根应用 4066、bili_api 544、bili_player 142、bili_danmaku 153、bili_mux 5，共 **4910 项通过**。根应用 13 项跳过；未配置 `BILI_MUX_LIBRARY` 的 mux 原生 10 项跳过，不计为原生封装覆盖。日志：`build/validation/dolby-vision/check-final-2026-11-03.log`。
- 播放会话定向回归 266 项通过，包含 UGC／PGC、暂停／播放、位置／倍速／音量保留、兼容源重试、剩余预算、重复失败边界、离线边界和旧响应取消。
- Windows 色彩测试正常模式通过：自动／软件均为 MAE **9.82/255**，SDR 换源恢复 d3d11va。`-WithoutVulkan` 模式通过：仅为该测试进程设置不存在的 Vulkan ICD 路径，验证约 6 秒内返回不兼容错误，随后同一 engine 成功打开普通分轨视频；进程环境在 finally 恢复。没有修改系统驱动。
- Windows 受控媒体回归 **32 项通过，在线烟测 1 项跳过**。前 23 项通过后，后段构建曾遇到同期单测占用共享 SQLite DLL；定向补跑受阻及未执行的 9 项全部通过，包括断流、预览、音量均衡和五分钟前向缓冲。证据为 `windows-media-final.log`／`windows-media-remaining.log`，位于同一验证目录。
- 独立公开样片 Debug 夹具完成热重载，随后运行时错误查询为空；未访问账号。
- `flutter build windows --release --target lib/main.dart` 普通入口构建通过，注册不含 integration_test；最终 libmpv DLL SHA-256 仍为 `222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`。
- `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 使用已有对应 mux 资产构建最终普通入口成功，验证独立测试包名、名称、1.2.6+4／12604、开发签名、arm64 AOT 和不可调试属性。产物 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256 `fcc3c45903f68276216946181a3e46a4181cf3f739da1efa90ccbbd7057a2f59`。设备断开后未安装该最终版本。
- 新 Android 包装脚本通过 PowerShell 解析，服务器通过 Python 编译及本地启动检查，Dart 夹具／driver 静态分析通过；未把这些检查记作最终 Android 设备测试。文档相对链接和 `git diff --check` 通过。

macOS／iOS／Linux 共用原生能力检查和应用兼容流回退；本 Windows 主机没有这些平台的构建工具链与设备，未声明本平台原生播放通过。缺少 libplacebo 的库会拒绝 Profile 5 并尝试兼容在线流，而非继续显示错误颜色。没有真实大会员账号，因此未验证 Bilibili 在线杜比源到兼容源的端到端切换；该编排使用脱敏 fake repository／engine 行为测试验证。未验证报告者显卡、其他 Dolby Profile 的色准、HDR 透传或长期稳定性。
