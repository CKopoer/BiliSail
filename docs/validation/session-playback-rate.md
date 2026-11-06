# 应用会话内继承播放倍速与音量

日期：2026-10-06。

## 自定义倍速选项（2026-11-06）

“设置 → 播放”和“播放器设置 → 播放”共用倍速编辑器：显示当前数量、添加按钮和可删除的选项；0.5x、1.0x、2.0x 显示锁定标记，不可删除。列表最少三项、最多九项，自动升序排列。新增值支持 0.25x～5.0x、最多两位小数，拒绝重复、非有限值、越界值和多余精度；满九项时禁用添加，窄屏自动换行。

- 默认保持原七档：0.5、0.75、1.0、1.25、1.5、2.0、3.0。视频／影视／离线的普通与全屏倍速菜单、小窗更多菜单、听视频菜单，以及加减速快捷键统一读取会话当前配置。直播继续不提供倍速。
- 删除当前默认档位时，将持久化默认倍速重置为 1.0x。已有播放源及运行内最近手动选择仍遵循原有记忆规则；仅编辑列表不会清除手动播放意图。长按临时加速的独立设置和松手恢复逻辑沿用原实现。
- `AppSettings.playbackRates` 是不可变列表。`preferences.v1` 快照版本升至 40，SQLite 表结构仍为 3；旧快照缺失列表或字段类型错误时使用原七档，列表内部过滤非法／重复项、补齐必选值并限制九项。旧连续默认值继续就近迁移到可选档位；有效自定义默认值保持原值。
- 保存沿用设置控制器的串行持久化与失败回退；编辑器显示失败提示并允许重试。恢复默认同时还原原七档及 1.0x 默认倍速。

自动回归覆盖领域校验、不可变性、兼容读取／持久化／重置、失败回退、320／960 像素布局、添加／删除／输入校验／数量上限、两处设置入口、视频／听视频菜单及加减速快捷键。

本轮验证：

- 新增／相关定向回归 15 项通过，见[定向日志](../../artifacts/custom-playback-rates-targeted-tests.log)。
- `tool/check.ps1 -SkipPub` 完整通过：格式、静态分析和打包边界检查通过；根应用 **4516**、`bili_api` **677**、`bili_player` **170**、`bili_danmaku` **161**、`bili_mux` **5** 项通过，见[完整日志](../../artifacts/custom-playback-rates-check.log)。13 项 Windows 符号链接用例因权限条件跳过；10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。
- Windows Debug 独立内存设置预览完成构建、启动、添加／删除 1.75x、列表与默认选项同步、热重载及应用运行时错误检查。预览不读取正式版的账号或设置，测试后关闭，并重新构建普通 `lib/main.dart` 入口，见[普通入口 Debug 构建日志](../../artifacts/custom-playback-rates-windows-build.log)；持久化和重新加载由真实 SQLite 离线回归验证。
- 本轮未修改原生播放器适配器，未构建 Release 安装包或进行 Android／macOS 实机、原生新倍速音画质量与性能验收。

## 倍速记忆开关（2026-11-05）

针对 [Issue #65](https://github.com/CKopoer/BiliSail/issues/65)，在“设置 → 播放 → 记忆播放倍速”增加默认开启的开关，保留既有运行内继承行为。

- 关闭后，新打开的视频、分 P、影视剧集和离线内容使用“默认播放倍速”，手动调速仅影响当前源。已有源返回、换清晰度及重试保留原源的倍速；直播仍为 1x，长按临时倍速沿用原有恢复语义。
- 切换开关不改变当前播放速度。关闭时清除运行内记忆并使旧调速 revision 失效；重新开启后，从下一次成功手动调速开始记忆。全部播放页关闭时，根应用仍同步开关，避免重新打开时恢复已丢弃的记录。
- `AppSettings.rememberPlaybackRate` 随 `preferences.v1` 保存；缺失或非法字段回退为开启，显式关闭跨启动保留，恢复默认重新开启。最近倍速仍只在内存保存，重启使用默认倍速；未增加独立倍速存储或更改 SQLite 表结构。
- 设置保存和失败回退复用现有设置控制器。默认倍速仍可编辑，关闭记忆后各新源都采用该值。

自动回归覆盖设置默认值／兼容读取／持久化／重置、开关交互和保存失败回退、单／并发会话的新视频与分 P、影视／离线／直播边界、当前源恢复与清晰度保留、开关切换及迟到命令隔离。本次未修改原生播放器适配器。

验证结果：

- 定向设置／播放测试 **323 项通过**，见[定向日志](../../artifacts/issue65-isolated-targeted-tests.log)。
- 主工作区首轮 `tool/check.ps1 -SkipPub` 被同期视频卡菜单改动中的空值调用等 12 项分析诊断阻塞，未改动这些非本任务文件。随后基于 `7b4ff03` 与本任务补丁创建隔离工作区，完整检查通过：格式、静态分析与打包边界检查通过；根应用 **4122**、`bili_api` **586**、`bili_player` **148**、`bili_danmaku` **161**、`bili_mux` **5** 项通过，见[完整日志](../../artifacts/issue65-isolated-check.log)。
- 根应用 13 项 Windows 符号链接用例按权限条件跳过；mux 10 项原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，不作为原生集成通过。`git diff --check` 通过。
- 本轮未构建安装包或进行 Windows／Android／macOS 实机播放验收。未发现可连接的 DTD／Debug 应用，热重载未能执行；运行内状态和重启后的设置读取由 fake engine 与 SQLite 自动回归验证。

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

## 音量继承（2026-10-11）

- 播放页音量滑条和快捷键调节成功后，本次应用运行中后续打开的普通视频、分 P、影视、直播与离线播放继承最近选择，包含 0% 静音、小数音量及 100%。
- 记录只存内存，关闭全部播放页或停止播放后仍保留；重新启动应用后使用设置中的默认音量。播放页调节不改写持久化默认值。
- 已有播放页保持自己的音量；原源恢复、换清晰度、重试沿用源快照。切换到新视频或分 P 时读取共享记录。
- 未手动调节时，修改默认音量作用于当前和后续播放，且不建立临时记录；已有手动选择时，后续播放继续使用本次运行的选择，新的默认值用于下次启动。

[PlaybackVolumeMemory](../../lib/features/playback/application/playback_volume_memory.dart) 由 [app/dependencies.dart](../../lib/app/dependencies.dart) 创建并注入所有正式播放会话，与倍速记录分别维护 revision。只有当前源成功完成的手动音量命令写入记录；失败、已关闭会话、旧源和较早动作的迟到完成不能覆盖新选择。默认设置应用走独立路径，不写入记录。继续复用既有的音量命令合并机制；静音悬停预览不参与正式播放会话，也不更新这份记录。

本次未修改原生适配器、持久化设置格式或数据库结构。

验证：

- 播放会话测试 **137 项通过**，其中新增 9 项覆盖单／多标签、新分 P、清晰度／重试／原源恢复、静音、小数音量、关闭所有标签、模拟重启、命令合并、乱序／失败／旧源／关闭隔离、影视与直播及默认值更新。日志：[会话测试](../../artifacts/session-playback-volume-unit.log)。
- `tool/check.ps1 -SkipPub` 通过：根应用 1810、`bili_api` 388、`bili_player` 35、`bili_danmaku` 86、`bili_mux` 2，共 **2321 项通过**；根应用及四个包的格式和静态分析通过。`bili_mux` 的 7 项原生封装测试因未配置 `BILI_MUX_LIBRARY` 按原有条件跳过。日志：[全量检查](../../artifacts/session-playback-volume-check.log)。
- Windows 真实 `MediaKitEngine` 专项通过：默认 60% → 手动 32.5% → 新页继承 32.5% → 新页静音，旧页仍为 32.5% → 关闭全部页后继承 0% → 重建应用运行状态后恢复 60%。既有倍速和长按隔离断言同测通过。使用本地音视频分轨 fixture、暂停打开，验证了引擎音量状态；不作为主观响度或系统音量验证。命令为设置 `BILI_TEST_MEDIA_DIR=test/fixtures/media` 后运行 `flutter test integration_test/windows_playback_test.dart -d windows --plain-name "Windows native playback inherits run rate and volume and a new run restores defaults"`；Windows Debug 测试入口构建成功，仅运行此专项，未复跑整套原生测试。日志：[Windows 原生专项](../../artifacts/session-playback-volume-windows.log)。

Android/macOS 原生运行、跨进程真实退出重启及 Release 构建本轮未测；重启语义通过重建共享内存状态验证。本轮无在线账户请求。

## 全局音量记忆（2026-10-27）

- “设置 → 播放 → 全局音量记忆”默认关闭；旧配置缺失或字段非法时仍关闭，保留有效选择。开启后默认音量滑条禁用，原值保留；关闭后恢复编辑，下一次应用启动使用默认音量。本次运行内已有的手动音量继承保持不变。
- 开启时使用本次运行最近成功的手动音量；尚未调节时优先恢复已记忆的值，首次没有记录才以当前默认音量初始化。此后成功调节音量会更新独立记录，包含静音、小数值和 100%；默认音量修改不覆盖记忆。
- 视频、分 P、影视、直播和离线播放共用原有 `PlaybackVolumeMemory`，普通／全屏、滑条、手势和快捷键走同一 `PlaybackSession.setVolume`。悬停预览不参与记录。已有播放页、同源恢复、清晰度切换和重试继续使用各自源快照，不广播改变其他页面音量。
- `AppSettings.rememberVolumeGlobally` 保存在 `preferences.v1`，快照版本 26 → 27；最近音量通过 `SqliteSettingsRepository` 独立存入 `playback.volume.v1`，避免并发保存偏好覆盖播放器的新值。SQLite schema 仍为 3，无需改表。非法、非有限或超出 0–100 的已存音量忽略。
- `AppDependencies` 启动时读取音量并注入所有会话，根应用同步开关，关闭全部播放页后仍可启停记忆。存储最多保留一个进行中的写入和一个最新待写值；应用退出等待写入完成后关闭数据库。失败保留本次运行的音量，通过错误回调报告，后续成功写入可恢复；不把保存失败伪装为持久化成功。

自动回归覆盖新运行读取独立 SQLite 记录、关闭后的默认值、重新开启、静音与小数值、与偏好保存交错、写入合并和迟到 revision、保存失败及恢复、已有源保留、设置控件禁用和保存失败回退。本轮未修改原生播放器适配器；Windows／Android／macOS 安装运行、跨进程退出重启和实际听感尚未验证。

本轮验证：

- 定向设置／播放回归 **292 项通过**，见[定向日志](../../artifacts/global-volume-targeted-tests.log)。`flutter analyze --no-pub` 无问题，本任务文件、四个包及 Linux 插件格式检查通过；Linux 插件单独分析通过。见[静态分析日志](../../artifacts/global-volume-analysis.log)。文档新增相对链接和 `git diff --check` 通过。
- `tool/check.ps1 -SkipPub -Stage RootTests`：根应用 **3076 项通过**，13 项 Windows 符号链接用例因权限条件跳过，见[根应用日志](../../artifacts/global-volume-root-tests.log)。
- `tool/check.ps1 -SkipPub -Stage PackageTests`：`bili_api` **478**、`bili_player` **83**、`bili_danmaku` **93**、`bili_mux` **5** 项通过。mux 的 **10** 项原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，见[包测试日志](../../artifacts/global-volume-package-tests.log)。
- 完整 `tool/check.ps1 -SkipPub` 在格式阶段被同期修改的 `lib/app/shell.dart` 阻塞；末次独立 Lint 阶段复查被同期修改的 `lib/features/playback/presentation/playback_timeline_bar.dart` 格式差异阻塞。保留这些非本任务修改，未为通过全量检查重排它们；完整检查未标为通过。打包／签名边界脚本均已通过，见[末次 Lint 日志](../../artifacts/global-volume-lint.log)。
