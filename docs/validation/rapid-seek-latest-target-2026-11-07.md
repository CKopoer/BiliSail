# 连续跳转只保留最新目标

## 2026-11-08：方向键连续回退

点击进度条按指针位置提交绝对时间；方向键原先每次都从
`session.snapshots.value.position` 加减步长。音视频准备期间，后端位置仍可能
停在上一次已确认的画面，因此连续回退会反复请求同一个目标，取消并重启
正在进行的准备。已有的后端“仅保留最新目标”不能替调用方计算累计目标。

[会话](../../lib/features/playback/application/playback_session.dart) 现增加
`seekBy`：同一源有待完成的 seek 时从其目标继续累加；确认完成或失败后恢复
使用真实播放位置。绝对跳转也更新待完成目标，进度条与方向键交替使用时沿用
最新意图；请求代次与源代次使旧完成不能清除新目标。相对跳转限制在零至已知
时长之间，到达边界后重复按键不再取消、重启准备。该目标仅用于命令计算，
不会作为已确认位置驱动弹幕或进度上报。

[快捷键控制器](../../lib/features/playback/application/playback_shortcut_controller.dart)
的回退、短按前进、重绑前进和前进 90 秒均通过这个会话入口；右方向键长按
临时倍速沿用原有语义。普通／全屏及视频／PGC／离线仍共享原会话。

[会话回归](../../test/features/playback/playback_session_test.dart) 新增 9 项：
连续回退、短按前进、90 秒前进、片头／片尾、绝对与相对跳转混用及反向、
换源与旧完成、播放器失败和其他异常后的目标清理。修复前三组分别重复
57、63、150 秒；修复后分别为 57／54／51、63／66／69、150／240／330 秒，
三组及其余边界回归通过。按用户要求，本轮不构建、不做原生或设备验收；
后续由用户自行构建并确认实际连续回退与准备提示。

本轮 `tool/check.ps1 -SkipPub` 的打包边界及全目录格式检查通过；静态分析因
工作区同期重构文件 `packages/bili_player/lib/src/shared_player_engine.dart:504`
的 `curly_braces_in_flow_control_structures` 提示停止，未修改该文件。
本任务三个 Dart 文件定向分析及 Linux 本地适配器分析通过。分别续跑
`-Stage RootTests` 和 `-Stage PackageTests`：根应用 4718、API 719、播放器 317、
弹幕 161、mux 5 项通过，共 5920 项；根应用另有 13 项环境跳过，mux 的 10 项
原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。日志保存在忽略目录
`build/validation/keyboard-seek-*-2026-11-08.log`。文档本地链接及
`git diff --check` 通过；未发现运行中的 Flutter 调试实例，未执行热重载。

日期：2026-11-07。用户反馈 fvp 快速来回点击进度条时，逐个加载中间位置，偶尔出现画面快速追赶。范围为应用共用的播放后端包装层及两后端的受控跳转回归。

## 原因与修复

组合根为所有播放会话创建 [ConfigurablePlayerEngine](../../packages/bili_player/lib/src/configurable_player_engine.dart)。media_kit 和 fvp 已有取消旧目标的实现，但包装层仍等待上一个 `seek` 的完整加载 Future，之后才下发下一个目标。新点击因此无法及时进入后端的取消路径；其间的音量、倍速和暂停完成等待也可能继续阻塞分发。此前两组原生专项直接创建具体后端，未覆盖实际应用多出来的这层队列。

现在包装层按调用顺序下发控制命令，把每个命令的完成／错误分别返回调用方，不再用原生准备时间阻塞后续命令下发。后端继续持有自身的原生命令队列与取消状态；包装层增加 seek 请求代次，尚未下发的过期目标直接跳过。打开媒体仍完成后才下发控制，换源／停止／释放仍先取消旧源并等待原生释放，旧命令不能跨源执行。暂停继续立即撤销原生播放意图，其完成 Future 不阻塞下一次跳转。

- media_kit 继续使用同一 player 的目标替换及 load／restart、视频位置确认，详见[同步恢复](seek-av-synchronization-2026-11-07.md)。
- fvp 继续取消旧读取、退役回调槽，在同一 player／纹理上重新准备最新目标，详见[fvp 同步恢复](fvp-seek-synchronization-2026-11-07.md)。Android 隔离进程的取消命令沿用既有端口。
- 两后端在目标画面准备期间暂停两轨，只在最新目标就绪后恢复用户意图。保留原倍速、音量、解码与输出偏好；不通过临时提高倍速追赶目标。
- 进度条、触摸、快捷键、章节、歌词、系统媒体等入口共用同一 engine。普通／全屏沿用原会话；直播保持禁用跳转。

## 回归入口

[包装层行为测试](../../packages/bili_player/test/configurable_player_engine_test.dart) 覆盖打开期间仅执行最新目标、跨源隔离和同步／异步错误传播。[fvp 行为测试](../../packages/bili_player/test/fvp_engine_test.dart) 通过真实 FvpEngine 和 fake 原生端口覆盖兼容／直出选项、播放／暂停／跳转中暂停，并在旧跳转与最新目标之间插入音量和倍速命令。新增六组在修复前均仅收到第一个目标，修复后均收到首个和最终目标，中间目标不执行。

两组既有 Windows 专项现均通过应用包装层执行。受控 HTTP fixture 保持旧 Range 请求不返回，只放行最新请求，检查旧 Future 取消、最新目标完成、连续第三次改目标、暂停／停止、同一源及非黑目标帧。media_kit 还核对恢复后的原生 avsync；fvp 检查原生时钟不包含等待视频的时间，并保持同一纹理只创建一次。

```powershell
$env:BILI_TEST_MEDIA_DIR = (Resolve-Path test/fixtures/media).Path
flutter test integration_test/windows_seek_synchronization_test.dart -d windows
flutter test integration_test/windows_fvp_seek_synchronization_test.dart -d windows

# 使用现有开发签名与独立测试身份；finally 恢复普通入口 Release 和常亮设置。
./tool/test-android-seek.ps1 -DeviceId <device>
```

[Android 入口](../../integration_test/android_seek_synchronization_test.dart) 复用两组原生专项，并分别设置 `renderedTexture`（兼容）和 `directTexture`（直出）。[脚本](../../tool/test-android-seek.ps1) 先保留普通入口 Release，核对测试身份、版本码和签名后覆盖安装 Profile fixture，通过 `flutter drive --keep-app-running` 执行；结束清理自己的两份临时样片并覆盖恢复普通入口，不卸载或清数据。

Android 的 377 KiB 原样片曾被提前完整读入，不能触发受控的 Range 阻塞。脚本用 x264 CBR filler 生成约 95 MB 的相同内容视频，把 9 秒目标放到 32 MiB 读取窗口外；不下载新媒体，不把填充码率当作真实视频性能测试。可用 `-Backend fvp -Output directTexture` 单独重跑某个组合。

Android worker 的位置由异步消息上报，取样窗口可能先收到旧位置，再一次跳到 9375ms。暂停等待断言允许这一次目标位置跳变，仍不允许继续播放越过目标；最终位置、原生暂停意图和恢复后的时钟断言保持。没有 MDK 独立外部音轨时钟，因此不将该读数称作两轨偏差测量。

Android 重准备期间的截图可能为黑；Windows 保留旧帧的中间截图断言不作为 Android 保证，所有平台仍检查初始画面和最终目标帧。不同播放源的夹具之间留出 2 秒释放间隔，同一源内的连续跳转没有间隔或重试。首轮无间隔换源时出现过 fvp worker 退出，保持该生命周期限制，不将其算作连续换源稳定性通过。

## 本轮结果

| 后端 | Windows 默认输出 | Xiaomi 13 兼容纹理 | Xiaomi 13 直出纹理 |
| --- | --- | --- | --- |
| media_kit | 9／9 | 9／9 | 9／9 |
| fvp | 9／9 | 9／9 | 最后一次 8／9；另一项在打开源时 worker 崩溃，未进入 seek |

Android 使用 Profile/AOT、Android 16 和实际隔离 worker。最后一次 fvp 直出重跑中，连续第三次改目标、准备中暂停和停止均通过；单次替换目标在前一轮也有通过记录，但最后一轮在该场景的 `open` 阶段遇到 `mdk.read` 线程 SIGSEGV，不能将整次脚本记为通过，也不能将 2 秒换源间隔表述为解决了启动崩溃。失败记录保留在 `build/validation/rapid-seek-android-fvp-direct-final.log` 和 `rapid-seek-android-fvp-open-crash.log`。

工作区同期接入其他历史／播放后端功能，期间出现历史 API 测试失败及新后端导出文件尚未写入的编译失败。本项未修改这些业务实现。完整检查在 `1765e2d367dcaaca2df34cbbf156e936cd36a1a1` 加本次补丁的隔离源码执行；普通入口开发 APK 只在该目录使用 `1.2.8+1`，与设备已有版本码 12801 保持覆盖兼容，主工作区版本未由本项调整。锁文件严格解析、格式及全目录静态分析通过，根应用 4607、API 678、播放器 245、弹幕 161、mux 5 项通过；根测试 13 项环境跳过，未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过。日志为 `build/validation/rapid-seek-isolated-check-final.log`。SQLite 首次资产下载遇到 TLS 握手失败；复用本机已有 DLL，完整 SHA-256 与 sqlite3 3.7.0 自带资产清单一致后重跑，没有关闭 TLS 或修改依赖缓存源码。

按用户后续要求全局格式化维护的 Dart 源码／测试，修复 `mini_player_window_service_test.dart` 格式，并格式化期间新出现的其他源码。未以格式化为由修改其他任务的业务逻辑。本项定向静态分析及 `git diff --check` 通过。

Windows 暂停状态的普通 Flutter Debug 探针完成热重载、连续跳转到 2000ms、无 Dart 运行时错误，并确认 native 释放后退出；这一结果与下述 EOF 异常分别记录。

Android 普通入口 Release 构建通过，测试结束覆盖恢复 `dev.bilisail.bilisail.test`，不可调试，保留本机开发签名与数据。拉回已安装 APK 的 SHA-256 与恢复包一致：`a6099f74d0ff2a05b178f51a252f85e78981f73c339cb78a3d932375598ec1bb`。可复查包及摘要／元信息保存在 `build/development/android-arm64/rapid-seek/`，测试 fixture 未留作日常入口；常亮设置由 finally 恢复，结束复核值为 2。

## 验证边界

本轮为功能与竞态验证，不以 Debug 测试耗时作性能结论。原生测试静音，时钟和画面断言不替代人工可听同步、真实账号 CDN、长视频、HDR、其他机型或 Apple 平台验收。用户报告的极高倍速追赶未单独量化，不能仅凭队列修复宣称所有底层时钟异常已消失。

额外的 Windows Debug 调试探针在完整播放至 EOF 后执行跳转时出现一次 `mdk.dll` 原生访问冲突（0xc0000005，模块偏移 0x8590）。同次热重载本身成功、未报告 Dart 运行时错误；该后续跳转不能记为调试烟测通过。转储保留在忽略目录 `build/validation/rapid-seek-eof-mdk.dmp`。绕过包装层的另一轮完播跳转也未正确到达请求目标，但不足以证明与该崩溃具有同一根因。该完播边界尚未定位，本次不修改 MDK ABI 或完播重准备实现。
