# 移除 fvp 播放后端

日期：2026-11-12（Asia/Shanghai）。按用户要求不再使用 fvp／MDK，当前唯一播放后端为 media_kit。

## 实现范围

- 删除 `FvpEngine`、原生播放器／输出适配、分轨同步、HTTP 续读参数、缓冲显示、暂停准备、解码器选择及 Android worker 实现和公开导出。
- 删除 Android 播放子进程、Service／Surface 桥、Manifest 注册和 Gradle 补丁；保留 media_kit 的 SurfaceView 测量原型。
- 删除 Windows SDK／纹理补丁、Apple Podfile 的 MDK pod 和渲染准备脚本、Linux MDK 配置及各平台资产、许可副本和锁定清单；media_kit 的固定 Git ref 和 SDK 来源保持。
- 删除 bili_player 的 MDK C API 头文件、音频探针、生成绑定、FFI 构建 hook 及仅供它们使用的依赖；重新解析根应用和播放器包锁文件，由 Flutter 重新生成插件注册。
- 删除 fvp 专属单元／集成／原生测试和入口，共享播放回归只覆盖 media_kit，保留解码、Android 输出、听视频、无音轨、DASH、缓冲、连续 seek、重播和实例复用场景。
- 共享层移除仅供 fvp 使用的暂停后重新 seek 接口、周期原生健康采样、进程退出分支及 MDK 读端点诊断；保留 media_kit SDK 事件、原生日志宽限、暂停意图、源代次、取消与释放保护。网络超时及日志错误宽限仍为原值。

## 历史设置兼容

`PlaybackBackendPreference` 仅保留 `mediaKit`，`SqliteSettingsRepository` 沿用按名称解析并对未识别值回退的规则。历史 `playbackBackend: fvp`、`fsplayer`、未知字符串、空值及非法类型均加载为 media_kit，后续成功保存写回 `playbackBackend: mediaKit`。旧 GPU 字段继续忽略并在保存时移除。

移除后端选择 UI 与控制命令，保留内部兼容字段。不清空或重置设置，不修改数据库 schema、登录、导航和离线数据。回归覆盖音量、倍速、自动播放、软解、Android 输出及其他设置修改后的读写恢复；仍可选择硬件／软件解码和 Android 兼容渲染／直出纹理。

## 验证

- `tool/check.ps1 -EnforceLockfile` 通过：根应用及四个包格式、静态分析、锁文件复现和离线测试均通过，共 6,532 项测试通过，24 项环境用例跳过。其中 mux 原生 10 项因未设置 `BILI_MUX_LIBRARY` 跳过，不能计为原生通过。
- 设置兼容与播放信息定向回归 18 项通过；fvp 专属测试全部删除，仅保留历史设置兼容测试。
- Windows 原生释放／渲染队列／尺寸回归 9 项通过；受控原生纹理交接 3 项通过。
- Windows 受控媒体最终结果为 50 项通过、8 项未通过、2 项环境跳过。已通过基础分轨、请求头、工作区会话、重播、共享契约、错误脱敏、起播、首帧、听视频、系统控制、临时缓冲恢复、seek 同步、音频增益、无音轨、缓存 seek 和 HTTP 连续 seek。
- 未通过项保留原有断言：`windows_video_stall_test.dart` 的截断音／视频 4 项和静默停滞夹具 2 项（在缓存时长前置断言失败，尚未进入故障注入）、`windows_preview_buffer_test.dart` 的预览切回普通缓冲 1 项，以及 `windows_buffer_ahead_test.dart` 的两分钟缓冲推进 1 项。预览的 5 秒初始／推进／seek 窗口已到达，失败发生在普通源重新打开后的缓冲；两分钟用例的初始、暂停、推进和 seek 窗口均达标，失败发生在重新打开短视频后的缓冲刷新。完整媒体脚本不能表述为全通过。
- 移除前基线 `f4369b8b` 在独立 worktree 对照运行两个 media_kit 场景，同样失败：截断视频未报告失败事件，以及静默停滞夹具的前置缓存时长为 0。两项失败位置与本次相同；其余未通过项未逐项做基线复跑，不据此宣称全部属于既有问题。基线未运行 fvp 专属测试。
- `tool/build-download-mux.ps1 -Target windows-x64` 与普通入口 `flutter build windows --release -t lib/main.dart` 均通过。构建使用仅包含本次暂存改动的独立工作区，避免混入同期动态功能修改。
- 新 Release 完整目录位于 `build/fvp-removal/windows-release/`；当前正在运行的旧 Release 不覆盖。产物核对未包含 fvp／MDK、音频探针、旧资产或外部 FFmpeg／libass DLL；libmpv 仍通过固定 SDK 摘要和能力校验。新 EXE SHA-256 为 `8b41154e08b7ec21c77d606609a4db41a2960c2db41cda79406f30171564c5b7`。
- 独立无账号、静音 DASH fixture 成功播放并热重启，原生旧实例被找回并释放，新实例重新就绪；最后等待播放器释放并关闭 fixture。
- PowerShell／Python 语法、当前文档相对链接、`git diff --check` 与全仓引用检查通过。除历史说明与兼容性测试外，当前代码、依赖、插件注册和构建配置均无 fvp／MDK 引用。

本机原始日志保存在忽略目录 `build/fvp-removal/`。Windows 受控播放为 Debug 功能验证，Release 结果为普通入口编译和资产核对；未作性能结论。

## 文档与平台边界

保留历史调查和已发生的测试事实，fvp 专项及旧后端设计标记为历史；旧源码路径、SDK 和命令不再作为现行操作入口。当前依赖以两份媒体锁文件及源码为准。

本机为 Windows。Android、Apple、Linux 的移除后完整应用构建和设备验收需对应平台验证，不能从插件注册重新生成或 Windows 回归推导通过。
