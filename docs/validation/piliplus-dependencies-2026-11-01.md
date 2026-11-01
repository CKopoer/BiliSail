# 与 PiliPlus 对齐播放器和弹幕依赖

日期：2026-11-01。按用户后续要求，替换此前 Predidit 依赖；保留现有播放会话和刚完成的弹幕分层。本次不以依赖切换本身宣称 GPU 性能提高。

## 固定来源

只读核对相邻 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的 pubspec、overrides 和锁文件，使用其 **resolved-ref**，没有跟踪可变的 `native`／`main` 分支。

| 组件 | 仓库及完整提交 |
| --- | --- |
| media_kit、media_kit_libs_video、Android／iOS／Windows 库插件、原生事件桥 | [My-Responsitories/media-kit](https://github.com/My-Responsitories/media-kit/tree/73771ec38176be2d984a3049c28177bce23b54a0)，`73771ec38176be2d984a3049c28177bce23b54a0` |
| media_kit_video | [bggRGjQaUbCoE/media-kit](https://github.com/bggRGjQaUbCoE/media-kit/tree/fd8421d21eade4d6d12de137fa7df902fec20292)，`fd8421d21eade4d6d12de137fa7df902fec20292` |
| canvas_danmaku | [bggRGjQaUbCoE/canvas_danmaku](https://github.com/bggRGjQaUbCoE/canvas_danmaku/tree/275046d8647a6a26cba1d0dadb9e28688cb3dbf1)，`275046d8647a6a26cba1d0dadb9e28688cb3dbf1` |
| macOS／Linux 库插件 | 与 PiliPlus 相同的 hosted 版本 `media_kit_libs_macos_video 1.1.4`／`media_kit_libs_linux 1.2.1` |

根应用和 bili_player 同时固定所有核心／库插件 overrides，避免 Pub 忽略传递包 overrides；根应用、播放器、弹幕三份锁文件重生成，另外两份锁文件仍执行可复现解析检查。保留应用原有 `wakelock_plus 1.8.1`，不改变 package_info_plus 兼容组合。

这些依赖的 LICENSE 均为 MIT。未复制 GPLv3 的 PiliPlus 应用源码，没有修改相邻仓库、SDK 或 Pub 缓存。原生二进制的许可与包装源码分开处理，见[第三方说明](../../THIRD_PARTY_NOTICES.md)。

## 适配边界

- PiliPlus 的 `Player` 直接别名到 NativePlayer，播放器与 VideoController 都异步创建。初始化纳入源的 deadline／generation 取消，迟到的播放器必须释放；控制器迟到不能发布到新会话。同步 property API 通过小型异步端口适配现有缓冲／音量／倍速逻辑；这不会把同步 FFI 调用变成可中断操作。
- 分支不再接受 `Media.httpHeaders`，改为打开前显式设置 player headers，并把 User-Agent／Referer 从普通字段中分离。DASH 仍要求两轨请求策略一致，保留 Range、重定向与源隔离；独立 weak client 观察外部音轨身份及加载终止，不消费或替换库的事件队列。
- 固定核心的私有 FLAG 写入仍分配 `Bool`，而 mpv 的公开 client ABI 要求 C int。应用通过其公开的 stop／add／playlist 命令和字符串 pause 属性执行打开、播放和暂停，保留状态事件及结束重播，避免重新走单字节写入路径；不修改固定依赖源码。默认未启用核心的 pitch 分支，倍速及音调滤镜沿用应用适配。
- 分支使用合并的 size 流。首帧仍同时等待实际解码、有效纹理／尺寸和 Flutter 绘制；Windows 显示尺寸显式转发到 SetSize，供应用原有视口上限补丁使用。
- Windows 使用与 PiliPlus 相同的 ANGLE／libmpv 归档。应用仍在校验后的构建副本保留线程转发、合并渲染通知、共享设备队列、视口尺寸、稳定纹理 ID、descriptor 资源保留和 Dispose 完成确认。消息转发使用每个插件实例的 message-only HWND，兼容隐式 view／独立播放窗，不替换全局 WndProc。
- Native Assets 的媒体打包退出当前路径；Windows 增补归档／DLL SHA-256 并排除旧媒体资产，禁止历史 LGPL DLL 覆盖。Apple 去除 Predidit 专属 C 绑定 staging，使用匹配库插件与 CocoaPods；Linux 恢复发行版 libmpv 依赖及 notices。原部署下限保持。
- canvas_danmaku 的 painter 基类只公开图像采样，其滚动 painter 为 final。适配器调用该库的采样 API，并保留有界位置池与 Picture 批次；不引入其第二套时钟、轨道或无界缓存。固定／滚动分层、组透明度、字体效果、暂停／seek、倍速和 32 MiB 文字像素预算保持。

当前 Windows 原生来源及摘要见[来源文件](../../windows/native/PILIPLUS_SOURCE.md)。补丁入口和说明见[Windows 适配](../../windows/patches/media_kit_video/README.md)。此前 [Predidit 记录](../predidit-media-migration.md)及[分层性能记录](danmaku-layers-performance-2026-11-01.md)是历史配置的数据，不能作为本轮新原生后端的性能结果。

## 验证

- 五份锁文件的 `pub get --enforce-lockfile` 解析通过，相关锁文件的 resolved-ref 与 PiliPlus 逐项核对一致。最终 `tool/check.ps1 -SkipPub` 全量通过：根应用 3908、bili_api 538、bili_player 121、bili_danmaku 153、bili_mux 5，共 **4725 项通过**；格式、分析与打包边界通过。根应用 13 项及未配置 `BILI_MUX_LIBRARY` 的 mux 原生 10 项跳过，不计作原生封装覆盖。
- Windows 最终串行原生回归 **38 项通过**：媒体脚本 33、内容／音质／直播脚本 4、实际窗口缩放 1。覆盖 DASH 音视频分轨、headers／重定向／Range、续播／seek、倍速／音量、普通／全屏／独立窗口、取消／替换／超时、首帧、纯音频、重播、系统媒体键、断流／缓冲、预览及音量均衡。
- 串行启动复核的 stop／replace／dispose 分别约 345／424／341ms，timeout 恢复约 2305ms，均在原 3 秒断言内。此前并行检查时替换一项曾耗时约 3.31 秒；最终复核不与构建或全量检查并行。没有放宽启动时限。
- 原生生命周期／队列／尺寸 9 项通过；真实 ANGLE/D3D11 的 100 帧共享、复制回退、缩放和共享 display 生命期通过，生产 resize／descriptor 资源保留回归通过。实际 Flutter 窗口在暂停／播放、信息区与尺寸切换后保持同一 surface／texture，并通过像素检查。
- 弹幕 153 项包含分层、缓存淘汰及阴影／描边／纯色、DPR 1／1.25／2 的像素对照。新增播放器回归覆盖异步创建迟到释放、headers 分离、避免核心 FLAG 写入及结束重播。
- Debug 合成播放＋混合弹幕／控件夹具热重载成功，Dart 运行时错误查询为空；该运行用于功能检查，不作性能测量。Windows 普通入口 `lib/main.dart` 的 Release 构建通过，实包 libmpv SHA-256 与上述归档提取结果一致，包含匹配 ANGLE／库插件／原生事件桥，没有 integration_test 注册或旧媒体 Native Assets DLL。
- Linux 12 项打包与 6 项 apt 镜像 Python 回归通过；Shell／PowerShell 语法、文档相对链接和 diff 检查通过。另 7 项依赖 POSIX 可执行脚本的 Linux 运行时检查在 Windows 上不能启动，未计通过；不是 Linux 本机打包验证。

夹具修正两处环境／边界假设：独立播放窗先显式恢复普通状态，再测全屏还原；断流恢复等待进度严格大于 6 秒，避免样本恰好等于 6 秒时提前结束等待。产品窗口逻辑及进度断言目标未改变。

Android 构建曾停在自动准备缺失的 SDK Platform 31，随后按用户要求停止，仅复核 Windows；没有生成本轮 Android APK 或执行安装。既有 APK、签名和设备数据保留。

本机 Debug 夹具实际输出为 960×540，`hwdec-current=d3d11va-copy`，GPU 纹理交付为 `copied`，与此前 Predidit 的 D3D11／`d3d11va` 路径不同。PiliPlus [桌面默认设置](../../../PiliPlus/lib/plugin/pl_player/models/hwdec_type.dart)也使用 `auto`，但本轮没有采集它在本机的实际解码器选择。上述运行不能证明已经解决最初的 GPU 负载差距，仍需新的同条件 Profile／Release 性能对照。

本地日志与产物位于忽略目录 `build/piliplus-*`。没有执行真实账号／CDN、跨 GPU、长期播放或新的 GPU 性能对照；macOS／iOS／Linux 的本平台构建和设备播放仍待验证。

## CI #266：Android 插件编译 SDK

[CI #266 的 Android 任务](https://github.com/CKopoer/BiliSail/actions/runs/41300058977/job/124830948861) 对应 `900a0f65a1807fa26f71a85e0fef2dc1ebc642ab`，失败于 `:media_kit_video:checkReleaseAarMetadata`。固定视频插件的 `android/build.gradle` 仍声明 `compileSdkVersion 31`；当前 Flutter embedding 引入的插件依赖包含要求 SDK 36 的 `wakelock_plus`、`screen_brightness_android` 等，AAR 元数据检查共报告 25 项不兼容。根应用自身使用 SDK 36，单独修改应用配置不能修复库模块。

本地完整构建同时发现 `media_kit_libs_android_video` 也固定 SDK 31，其 Release AAR 检查报告另外 20 项依赖不兼容。新增[应用侧 Gradle 适配](../../android/patches/media_kit/apply.gradle)，在两个插件的 `com.android.library` 应用时注册 `androidComponents.finalizeDsl`，将它们的 `compileSdk` 提高到 Flutter SDK 的默认编译版本（当前 36），并保留上游可能更高的值。[根构建入口](../../android/build.gradle.kts)在子项目求值前加载适配；回调在上游 DSL 求值后、创建 variant／任务前执行，时机依据 [AGP API](https://developer.android.com/reference/tools/gradle-api/9.1/com/android/build/api/variant/AndroidComponentsExtension)。仅适配这两个媒体插件，不修改 Pub 缓存、固定提交、锁文件、`minSdk`、`targetSdk` 或签名配置。

Windows 本地修复前运行同一 Release AAR 检查，复现 SDK 31 和 25 项错误；完整构建另复现库插件的 20 项错误。修复后使用 `--rerun-tasks` 强制执行两个插件在 Debug、Profile、Release 下的六项 AAR 检查，全部通过。日志位于忽略目录 `build/ci-266-android-baseline.log`、`build/ci-266-android-libs-baseline.log` 和 `build/ci-266-android-aar.log`。

按开发测试入口构建 Android arm64 mux 后，`tool/build-android-development.ps1 -Mode Release -SkipMuxBuild` 生成普通 `lib/main.dart` 的 Release/AOT 测试包，日志为 `build/ci-266-android-development-release.log`。脚本校验测试包名、名称、版本、不可调试标志、仅 arm64 ABI、AOT 资产、通知资源及既有开发签名；本轮没有安装、升级、实机播放或账号验收。远端修复后的正式签名打包结果仍需新 CI 验证。

最终 `tool/check.ps1 -SkipPub` 全量通过：格式、静态分析、打包边界及 **4729 项测试**（根应用 3912、API 538、播放器 121、弹幕 153、封装 5）。根应用 13 项 Windows symlink 用例因权限跳过，mux 原生 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，不计作原生覆盖。五份锁文件没有差异；本节本地链接及 `git diff --check` 通过。完整日志为 `build/ci-266-check.log`。
