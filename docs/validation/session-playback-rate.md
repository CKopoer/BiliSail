# 应用会话内继承播放倍速

日期：2026-10-06。

## 行为与状态归属

- 应用启动后，首个点播使用设置中的默认播放倍速。用户通过播放页菜单或加减速快捷键修改倍速后，后续打开的普通视频、分 P、影视剧集继承本次运行中最近成功选择的倍速。
- 倍速只保存在内存；关闭所有播放页、切换导航模式或停止会话不会清除这份记录。退出应用后重新启动，重新使用设置中的默认倍速。播放页调速不修改持久化设置。
- 已打开的其他播放页保留各自的速度；返回原播放源、换清晰度或重试保留该源的速度。每个标签继续拥有独立 engine，不广播修改其他标签的播放速度。
- 长按临时加速与松开恢复不更新共享记录；直播保持 1x，不参与点播倍速继承。菜单与快捷键继续使用已有档位。
- 未手动调速时，修改默认倍速仍应用到当前点播及后续视频。已有会话倍速时，本次运行继续使用会话选择，修改后的默认值用于下次启动。

[app/dependencies.dart](../../lib/app/dependencies.dart) 每次启动创建一份 [PlaybackRateMemory](../../lib/features/playback/application/playback_rate_memory.dart)，通过构造器注入各 [PlaybackSession](../../lib/features/playback/application/playback_session.dart)。新源打开时读取内存记录，缺失时使用当前默认值；原源恢复继续使用本地快照。更新按用户动作顺序登记 revision，只有当前源的成功调速可以提交，旧源、已关闭会话及迟到的前序命令不能覆盖较新的选择。默认设置应用、临时加速恢复使用独立命令路径，不写入会话记录。

没有新增依赖、数据库字段或迁移，也没有改变 `bili_player` 的公共契约及原生适配器。

## 验证

播放会话针对性测试 74 项通过，新增 8 项回归覆盖单/多标签继承、已创建但未打开的页面、换分 P、清晰度保留、全部标签关闭后继承、模拟重启、长按临时加速、乱序完成、失败/旧源隔离、影视/直播边界及默认值修改。

- 最终执行 `tool/check.ps1 -SkipPub` 通过：根应用 837、`bili_api` 266、`bili_player` 16、`bili_danmaku` 32 项，共 **1151 项测试通过**；根应用和三个包的格式、静态分析均通过。日志：[最终全量检查](../../artifacts/session-playback-rate-check-final.log)。首轮检查遇到的工作区其他 API 测试格式问题在复验时已消失，本轮没有改写该文件。
- 两次运行 `tool/test-windows-media.ps1`，新增原生倍速回归均通过：默认 1.25x → 手动 2x → 长按 3x，新播放页继承 2x；另一页改为 1.5x、原页恢复 2x 后，新页仍继承 1.5x；全部页面关闭后仍继承，重建应用运行状态恢复默认 1.25x。媒体为本地分轨 fixture，使用真实 Windows `MediaKitEngine`。日志：[首次](../../artifacts/session-playback-rate-windows.log)、[复跑](../../artifacts/session-playback-rate-windows-retry.log)。
- 同一原生套件的既有 `Windows native responsive controls, fullscreen and Esc preserve one playback source` 在两次运行中均失败：其弹幕准备阶段预期活动项 `visible`，实际为 `warmup`。失败发生在全屏循环前；本轮没有改动该断言、弹幕实现或原生适配器，未把整套原生测试标为通过。未启用公网媒体分支。
- 单独执行 `integration_test/windows_playback_diagnostics_test.dart -d windows`，原生 403 错误分类和本地脱敏诊断通过，见 [诊断日志](../../artifacts/session-playback-rate-windows-diagnostics.log)。
- `flutter build windows --release --no-pub -t lib/main.dart` 成功，入口为 `build/windows/x64/runner/Release/bilisail.exe`，见 [Windows 构建日志](../../artifacts/session-playback-rate-build-windows.log)。
- `flutter build apk --debug --target-platform android-arm64 --no-pub -t lib/main.dart` 成功，产物为 `build/app/outputs/flutter-apk/app-debug.apk`，见 [Android 构建日志](../../artifacts/session-playback-rate-build-android.log)。

Android/macOS 原生运行未测，当前 Windows 主机不构建 macOS。本轮不使用真实账号，不发 Bilibili 在线请求，不作性能结论。
