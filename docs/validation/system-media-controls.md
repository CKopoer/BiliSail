# 系统媒体通知与控制

日期：2026-10-30。

## 行为与边界

- Android 使用媒体通知／锁屏媒体会话；iOS、macOS 使用系统“正在播放”；Windows 使用 SMTC；Linux 使用桌面环境提供的 MPRIS 控制入口。系统决定实际显示的按钮和位置，不保证各系统都有单独的关闭按钮。
- 视频、影视、直播和离线播放共用 `PlaybackManager` 的会话。系统控制目标优先为最近选择的播放页；切到首页等普通页面继续沿用该目标，关闭目标后回退到仍保留的媒体会话。并发播放时系统只显示一个目标。
- 播放、暂停和停止调用 `PlaybackSession`，不额外创建播放器。播放命令幂等；点播支持系统 seek，并限制到有效时长内，直播不提供 seek。停止终止该会话的媒体源并清理通知；关闭标签只影响自己的会话；账号变化、退出应用清理系统目标，Android 从最近任务移除应用时停止全部会话。
- 命令携带控制目标和源 generation，执行前检查账号 scope／epoch。普通／全屏沿用同一会话，隐藏绘制层不影响媒体状态同步。高频 position 样本按整秒去重，暂停、缓冲、seek、源和元数据变化立即同步。
- 保留原有移动端进入系统后台时的暂停策略；通知接入不代表后台连续播放、音频焦点、PiP 或长期保活已逐平台验收。
- 系统只收到标题、作者、时长、状态与公开封面。封面限 `hdslb.com`，移除 query、fragment 和凭据；不传媒体 CDN 地址、headers、账号 ID 或本地文件路径。平台初始化／通信失败使用固定诊断文案降级，不中断有效视频。

## 实现与依赖

- `core/platform/system_media_controls.dart` 是平台端口，`PlaybackSystemMediaController` 负责会话选择和命令分发；组合根注入 `PlaybackManager`，悬停预览不加入系统媒体会话。
- Android／Apple 采用 MIT 的 [`audio_service` 0.18.19](https://pub.dev/packages/audio_service/versions/0.18.19)，使用其官方 Android `AudioServiceActivity`、媒体服务与接收器。声明 WAKE_LOCK、FOREGROUND_SERVICE 和 FOREGROUND_SERVICE_MEDIA_PLAYBACK；单色图标以 `raw/keep.xml` 保留。媒体会话通知属于 [Android 通知权限豁免](https://developer.android.com/develop/ui/compose/notifications/notification-permission#exemptions)，此处不增加普通推送权限弹窗。
- Linux 采用 MIT 的 [`audio_service_mpris` 1.0.0-beta.3](https://pub.dev/packages/audio_service_mpris/versions/1.0.0-beta.3)。稳定版 0.2.1 依赖 dbus 0.7，与工程已有 wakelock_plus 1.8.1 的 dbus 0.8 不兼容；使用已支持 dbus 0.8 的固定 beta，未强制覆盖 dbus。该依赖仍为预发布，Linux 运行验收保留。Flatpak 仅增加 `org.mpris.MediaPlayer2.bilisail.*` 名称所有权。
- Windows 独立编写 runner 小型适配，通过 `ISystemMediaTransportControlsInterop::GetForWindow` 绑定现有主 HWND，使用 Video 元信息、状态、倍速与时间轴，不创建另一个 MediaPlayer。WinRT 事件只投递最多 32 条带源身份的命令，再经窗口消息在 Flutter 平台线程分发；关闭时撤销订阅。Dart 通道仅保留一个在途调用和一个待更新状态，并设 3 秒通信超时。线程约束依据 [Microsoft SMTC 文档](https://learn.microsoft.com/en-us/windows/apps/develop/media-playback/system-media-transport-controls)。
- iOS 声明 `UIBackgroundModes/audio` 以满足系统媒体会话插件配置；macOS 沿用已有最低系统和权限边界。未修改播放器 fork、SDK、数据库 schema 或持久化设置。

## 参考与许可

只读参考本机 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/services/audio_handler.dart`、`lib/services/audio_session.dart` 和 Android Manifest，借鉴“向系统广播已有播放状态、系统按钮回调既有播放器”的职责。PiliPlus 使用其自有 audio_service／audio_session Git 分支，本项目未采用这些浮动 ref。PiliPlus 应用源码为 GPLv3；本轮独立实现 Dart、Kotlin 配置和 C++，未复制其应用源码或资源、未修改相邻仓库。

## 验证

- 根检查的格式、静态分析、五份锁文件可复现解析和打包边界检查通过。主工作区进入测试时被同期进程占用的 `build/native_assets/windows/sqlite3.dll` 阻挡，因此在 `build/system-media-validation-workspace` 的独立源码快照补齐根测试；最终 3499 项通过、13 项既有跳过。日志：`build/system-media-check.log`、`build/system-media-root-tests-final.log`。
- 四个包通过：bili_api 496、bili_player 96、bili_danmaku 118、bili_mux 5；10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生覆盖。日志：`build/system-media-packages.log`。
- 新增 14 项平台适配／会话行为测试覆盖元数据、幂等命令、失败重试、源和账号 epoch 隔离、多标签目标、停止／任务移除、直播能力、更新去重和原生通道顺序，包含在完整根测试中。
- Windows Debug 构建通过。独立快照中本地 DASH 音视频均确认解码；通过 Windows 全局媒体 API 完成读取元数据、暂停、seek、播放、停止和系统条目清理，整个过程保留同一 engine generation。最终原生回归 1 项通过，日志：`build/system-media-native-final.log`。没有操作其他应用的媒体会话，也未使用公网媒体或真实账号。
- Android arm64 mux 组件与普通入口开发 Release／AOT APK 构建通过，包名 `dev.bilisail.bilisail.test`、名称 `BiliSail 测试版`、版本 `1.2.5+0`／12500；沿用本机开发证书并校验不可调试。产物 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，SHA-256 为 `aa49b279b8b8fbe919f596af125a8d18f5d304c38b637e50f769203087f67ec5`，元信息和校验文件位于同目录；日志：`build/system-media-android-build-delivery.log`。未连接设备、未安装或清理任何已有包。
- 本轮文档 211 个本地链接与 `git diff --check` 通过。未进行性能测量，未构建 Apple／Linux 目标。
- 独立 Windows 调试探针连接 DTD 并热重载成功（`Success`）；探针只挂载本轮平台适配器，不恢复真实账号或打开用户数据库，完成后已退出。

Windows 原生回归已接入 `tool/test-windows-media.ps1`，也可单独使用本地 DASH 音视频 fixture 运行：

```powershell
$env:BILI_TEST_MEDIA_DIR = (Resolve-Path test/fixtures/media).Path
$env:BILI_TEST_SYSTEM_MEDIA_SCRIPT = (Resolve-Path tool/windows-system-media-command.ps1).Path
flutter test integration_test/windows_system_media_test.dart -d windows
```

`windows-system-media-command.ps1` 仅匹配标题为 `BiliSail system media fixture` 的测试会话，通过 Windows 全局媒体 API 读取元信息、请求暂停／seek／播放／停止，并检查系统会话移除。不会控制其他应用的会话。

待设备验收：Android 通知栏／锁屏按钮、通知滑除、最近任务移除、后台暂停后恢复、通知点击回到应用；iOS 控制中心／锁屏与系统中断；macOS 双窗口／控制中心；Linux GNOME／KDE、Flatpak 与 D-Bus 断开恢复。尚无 Android 设备连接，Apple／Linux 工具链不在当前 Windows 主机上。

## Android Release 通知缺失修复（2026-10-31）

定位到 Release 资源压缩丢失动态图标的问题。修复前可用的开发 Release APK（1.2.5+1，SHA-256 `776c9f6db9804831d27e4c5ffcda33a31670f9d665e0064e027a3b02885522dd`）中，`aapt2 dump resources` 仅能找到 `ic_media_notification`，找不到 `audio_service_play_arrow`、`audio_service_pause`、`audio_service_stop`；构建的 `resources.txt` 也把三者标为不可达。基线证据保存在 `build/android-media-notification-baseline.log`。

`audio_service` 0.18.19 的 `AudioService.getResourceId` 用 `Resources.getIdentifier` 按 Dart 传来的名称查图标，Android 资源压缩器无法据此识别 Dart 的引用。Android 13+ 的 `createCustomAction` 会为停止按钮创建 `PlaybackStateCompat.CustomAction.Builder`，而实际解析到的 androidx.media 1.7.0 要求图标 ID 非零；该构造器在图标缺失时抛出异常，发生在 `enterPlayingState` 和通知创建之前。通过本机固定依赖的原生源码及 AAR 字节码核对了这条失败路径，未将缺图误判为缺少通知运行时权限。

- [资源保留规则](../../android/app/src/main/res/raw/keep.xml) 明确保留小图标与三种实际使用的媒体按钮图标，继续开启 Release 代码／资源压缩，不扩大为保留所有 drawable。依据为 [Android 动态资源保留说明](https://developer.android.com/topic/performance/app-optimization/customize-which-resources-to-keep)。
- [APK 媒体资源检查](../../tool/android-media-notification.ps1) 读取实际编译后的资源表，要求四个 drawable 都具有非零资源 ID 和文件资源值；仅有名称、空资源或相似名称均拒绝。开发构建和正式／CI 打包在产物校验阶段调用它，缺图时停止，不进入安装／分发流程。
- [离线边界检查](../../tool/test-android-media-notification.ps1) 已接入根检查，21 项通过；覆盖正式与测试包名、LF／CRLF、逐个缺图、仅 spec、空值、零 ID 和相似名称。新检查也成功拒绝修复前的实际 APK。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、打包边界检查通过；根应用 3649 项通过、13 项既有跳过，bili_api 497、bili_player 101、bili_danmaku 136、bili_mux 5 项通过。mux 另有 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。日志：`build/android-media-notification-check.log`。
- 普通入口开发 Release／AOT APK 构建通过，并通过新增的实际资源检查；`aapt2` 确认四个 drawable 均存在，资源压缩报告明确按 keep 规则保留媒体按钮。产物为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，包名 `dev.bilisail.bilisail.test`，版本 `1.2.5+1`／12501，沿用原开发签名、不可调试；SHA-256 `6c160f047c039a04b5605218d2c98f38a41678e2a100a06de8fee1297e714174`。日志：`build/android-media-notification-release.log`、`build/android-media-notification-fixed.log`。构建复用本机已有 arm64 mux 资产，没有执行安装或清理数据。
- 本轮不修改播放状态、后台策略、凭据、SDK、依赖或安全存储；没有修改 Pub 缓存。未连接 Android 设备，通知栏实际操作仍需设备验收。

## 播放通知样式与完播清理（2026-10-31）

- 对照本机 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/services/audio_handler.dart`，点播系统媒体卡片提供后退 10 秒、播放／暂停、前进 10 秒；直播不提供跳转。Android 系统版本和厂商决定最终卡片布局及按钮位置。按钮调用现有会话并按实时位置和时长限制，保留系统停止命令；图标由本项目独立绘制，未复制 GPL 应用源码或资源。
- 自然完播后该会话退出系统媒体目标；没有其他可用会话时清除媒体条目与通知，多标签时回退到其他未结束会话。重播或连播新源重新发布；暂停与缓冲不清除。账号、source generation 和旧指令隔离仍然适用。
- 新增 Android 两个动态引用图标的资源保留和 APK 检查，防止 Release 压缩导致媒体按钮不可用。具体设备的通知栏、锁屏样式、按钮与完播清除仍需 Android 实机验收。
- 定向系统媒体测试 17 项及 Android 通知资源边界检查 25 项通过；独立包测试 bili_api 497、bili_player 101、bili_danmaku 136、bili_mux 5 项通过，mux 另有 10 项因未设置 `BILI_MUX_LIBRARY` 跳过。`flutter analyze --no-pub` 通过。初次根检查在同期临时集成探针的格式检查处中断；该探针移除后分别运行检查脚本 Lint、RootTests 和 PackageTests 阶段，均通过。根测试 3697 项通过、13 项跳过。
- Android 普通入口开发 Release 构建及 APK 资源检查通过，复用既有 mux 资产；构建时工作区存在同期修改，产物并非只含本轮变更。未连接设备，未安装；未验证通知栏／锁屏的实际按钮、自动连播衔接与清除。
