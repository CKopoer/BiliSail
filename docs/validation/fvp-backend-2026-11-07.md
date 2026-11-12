# 可选 fvp 播放后端

> 历史记录：fvp／MDK 已于 2026-11-12 移除。下文保留当时实现与验证事实，相关源码、资产和专属命令已退役；当前行为见[移除记录](fvp-removal-2026-11-12.md)。

日期：2026-11-07。保留 media_kit 默认后端，新增 fvp／MDK 实验后端，供用户在同一应用中做实机对照。本次不依据包说明宣称性能提升。

## 使用与状态

同日后续设置改为先选软件／硬件解码，硬解下显示播放后端与 GPU；Windows fvp 可独立指定视频解码设备。当前快照 schemaVersion 为 43，迁移与逐平台边界见 [GPU 设备设置](gpu-device-settings-2026-11-07.md)。下段 schemaVersion 41 为初版记录。

在「设置 → 播放 → 视频编解码 → 播放后端」选择 `media_kit（默认）` 或 `fvp（实验性）`。保存成功后，下次打开或重新加载播放源时生效；已打开的源继续使用原后端，暂停、倍速或普通／全屏切换不更换播放器。不需要重启应用。设置沿用 `preferences.v1`，快照 schemaVersion 为 41，不修改数据库表。旧配置、缺失／非法值和恢复默认均选择 media_kit；有效旧设置保留，保存失败回退。

视频、影视、直播、离线播放、听视频和悬停预览统一经过 `ConfigurablePlayerEngine`。它只在打开源时读取已保存设置，等待旧 engine 完成 stop／dispose 后创建目标后端；对外保持同一个 `VideoOutput`、独立递增的源代次和现有 `PlaybackSession`。不会因切换后端创建第二个音频会话，也不会在 fvp 失败时偷偷回退，影响对比结论。

## 固定来源与许可

- fvp：官方 [wang-bin/fvp](https://github.com/wang-bin/fvp/tree/e81637411c58a9ae28de246ee73ad06e3418f10e)，完整提交 `e81637411c58a9ae28de246ee73ad06e3418f10e`，其 pubspec 版本为 0.40.0。根应用与 bili_player 都直接固定此提交，保留 Flutter 原生插件注册。
- MDK：官方 [v0.39.0](https://github.com/wang-bin/mdk-sdk/releases/tag/v0.39.0)，Windows x64、Android、Linux x64 和 Apple archive 的 SHA-256 见 `native/fvp/assets.lock.json`。Windows 仅在 build 目录为官方带工具链后缀的 archive 创建通用文件名；不改变其内容。Android／Linux 通过 fvp 的 CMake 参数固定下载；Apple 使用本地 podspec 固定 URL／SHA-256，避免官方同版本 podspec 的 nightly 地址漂移。
- fvp 插件是 BSD-3-Clause。MDK 的 SDK 授权独立，官方说明 Flutter 用户可免费商用；原许可文本保留在本地 podspec。FFmpeg、libass 和 SDK 可选插件仍分别遵守自己的许可，不能将整个 SDK 视作 BSD 或 MIT。
- media_kit 的现有个人 fork、Git ref、原生资产和补丁保持原来源。bili_mux 的 FFmpeg 与两种播放后端继续独立。

## 实现边界

fvp 使用公开 `package:fvp/mdk.dart` API，DASH 主视频和外部音轨交给同一个 MDK Player 同步。主／外部轨要求相同的安全请求头，不支持的每轨不同 headers 明确失败。画面等待公开 `render.video / 1st_frame` 信号，再经一帧 Flutter 发布可叠加弹幕状态。

MDK 0.39 的外部音频管线未向 Dart 转发音频解码器事件，因此分轨源先进行静音、暂停状态的音轨解码探测，确认音轨存在且解码器成功打开。探针完成原生释放后，才创建实际播放实例；不会同时播放两路音频。主视频完成准备后再挂载外部音频，避免 fvp.prepare 的停止操作打断外部管线初始化。Android content 音轨为探针另开租约，避免 dup 共享文件偏移。此过程增加一次音轨打开／读取，首播耗时会包含这项开销。输入 URL 仅驻留内存，没有生成或落盘带签名 URL 的清单。

后端映射暂停、seek、倍速、音量、独立增益、缓冲、结束和错误事件；250 ms 局部采样沿用有界播放停滞检测。直播通过短暂静音推进管线确认首帧，不执行 seek；确认后按用户意图暂停或播放。源代次、取消信号和原生释放屏障隔离旧结果；Android content URI 通过原有文件描述符租约持有至 native 释放。MDK 日志关闭，不把媒体 URL、headers 或原生日志转发到应用日志；结构化事件新增 `backend=media_kit/fvp`。

实验边界：fvp 当前按原视频显示尺寸分配纹理，不继承 media_kit 的平台视口纹理缩小优化；比较 GPU 开销时应记录两者实际纹理／输出尺寸。初版采用 MDK 最多 4 秒的短窗口；同日按用户后续要求，两个后端现统一为普通播放最多 2 分钟、预览 5 秒，见 [统一缓冲窗口](unified-buffer-window-2026-11-07.md)。Flutter 的视频、弹幕、字幕和控件仍走既有合成路径。本轮不承诺 HDR 屏幕直通、全链路零复制。初版未持续检测 MDK 外部音频；同日后续通过实际音频解码活动补齐单轨停滞检测与有界恢复，见 [中途断音修复](fvp-audio-recovery-2026-11-07.md)，不将解码活动等同于独立音频输出时钟或可听输出证明。系统媒体控制、导航和后台意图继续由原有会话管理器负责。

## 验证入口

同日后续补齐精确 seek 与目标帧等待：准备期间暂停同一个 MDK Player，保留最后画面，只在目标解码后按用户意图恢复。连续跳转、取消及平台验证边界见 [fvp 跳转同步专项](fvp-seek-synchronization-2026-11-07.md)。

```powershell
./tool/check.ps1 -EnforceLockfile
./tool/test-windows-media.ps1
./tool/test-windows-video-dispose.ps1
./tool/test-windows-fvp.ps1
./tool/build-android-development.ps1 -Mode Release
```

Flutter 原生测试、开发运行和 Android Release 构建必须串行执行，避免并发命令覆盖插件注册文件。开发包沿用 `dev.bilisail.bilisail.test` 与现有开发签名。

本轮验证：

- `tool/check.ps1 -EnforceLockfile` 通过：格式、静态分析、打包边界、五份锁文件解析；根应用 4557、bili_api 678、bili_player 191、bili_danmaku 161、bili_mux 5 项通过。根应用 13 项按原条件跳过；未配置 `BILI_MUX_LIBRARY`，mux 的 10 项原生用例跳过，不计为原生通过。
- Windows fvp 原生用例 3 项通过：独立音频、两个后端反复切换、受控 HTTP 分轨及 Referer／Range、首帧、进度、暂停、倍速、seek、surface 重新挂载、缺失／错误音轨失败、听视频，以及 FLV／HLS 直播启动和分片 headers；全程静音，没有真实账号操作。最后修改直播首帧后重新通过根静态分析和播放器包 191 项测试。
- `tool/test-windows-media.ps1` 全量通过，共 36 项原生用例通过，在线烟测及无直播环境变量的用例跳过；随后通过 `test-windows-fvp.ps1` 补齐全部 3 项 fvp 用例。原生释放检查另有 9 项通过。
- Windows 普通入口 `flutter build windows --release -t lib/main.dart` 通过，输出 `build/windows/x64/runner/Release/`；同时保留 media_kit 与固定 MDK／FFmpeg DLL，未打包可选专业解码插件。独立本地 fvp 画面入口启动和热重载通过；该入口不包含账号，也不是交付入口。
- Android arm64 普通入口开发 Release 构建通过，包名 `dev.bilisail.bilisail.test`，名称 `BiliSail 测试版`，版本 `1.2.7+0`，沿用已有开发签名。APK 位于 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256 为 `801a7b37dba859fc740e2924785bc6f620b9ec72d255b3b85f83bc89a3af11db`；检查确认同时包含 libmpv、libmdk、libfvp、独立 mux 和许可材料。
- 按用户后续要求，已于 2026-11-07 13:32 覆盖安装至 Xiaomi 13（`950c21ca`）并成功启动。安装前确认 APK 摘要、测试身份、不可调试和与已安装测试包的签名一致；使用 `adb install -r`，保留原 firstInstallTime，无卸载、清数据或正式包操作。安装元信息见 `build/development/android-arm64/BiliSail-test-arm64-release.apk.install.json`。
- Android 实机目前仅确认安装与启动；播放、在线 Bilibili 分轨、长时间音画同步／性能及 Apple／Linux 构建与设备验收仍未完成。自动播放测试使用本地受控素材；不据此宣称 4K／高倍速性能收益。

对比时建议固定片源、编码、分辨率、帧率、播放速度、窗口物理尺寸、刷新率、电源模式和弹幕密度，用 Profile／Release 记录实际解码器、视频掉帧、CPU／GPU、音画偏差和功耗。自动检查和 Debug 功能回归不作为性能结论。
