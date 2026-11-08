# 播放后端清理

日期：2026-11-08。按用户要求完整移除 fsplayer，仅保留默认 media_kit 与可选 fvp／MDK，并保留二者既有的会话、起播同步和视频输出契约。

## 清理范围

- 删除引擎、DASH 输入构造、本地请求转发租约及对应专属测试，移除公共导出、组合根分支、设置枚举和 Android 输出限制文案。
- 删除 Android Java 桥、Gradle AAR 下载／校验逻辑、插件 manifest，以及 Apple Objective-C 桥、podspec 和两端 Podfile 依赖。
- 删除原生资产锁、许可／来源资源、根应用资产声明、Apple 专属验证 workflow、烟测入口和专属性能数据／说明；更新共享探针和文档引用。
- `bili_player` 不再声明 Android／iOS／macOS 本地插件。Flutter 重新生成的 macOS 注册器移除该插件；fvp 的 Native Assets hook 与原生音频活动采样继续保留。根应用和四包的锁文件经固定版本解析，不需改写。

## 旧设置兼容

`SqliteSettingsRepository` 已按枚举名称读取后端，未知值回退 media_kit。删除枚举后，旧 `playbackBackend: fsplayer` 沿用同一规则，下次成功保存写回 `mediaKit`；不增加迁移分支，不修改 SQLite 表或偏好快照版本。

[设置回归](../../test/features/settings/playback_backend_test.dart)覆盖旧值加载、保存及重载时音量、默认倍速、自动播放、软硬解和 Android 输出偏好保留，以及 media_kit／fvp 来回切换、保存失败回退和恢复默认。源码中保留的旧后端名称只用于这一兼容 fixture；文档中的名称用于说明移除决定。

## 本轮验证

日志位于忽略目录 `build/validation/playback-backend-cleanup/`。测试基于共同工作区运行，其中已有独立 fvp 连续跳转修复；本次提交只包含后端清理。

- `tool/check.ps1 -EnforceLockfile` 完成五份锁文件复现解析、根应用／四包格式及打包边界检查。首次全仓分析被已有的 `packages/bili_player/test/android_fvp_player_test.dart:112` 的 `use_null_aware_elements` 提示阻塞；同期修复更新后，补跑全仓 `flutter analyze --no-pub` 和 Linux 适配器 `dart analyze` 均通过，见 `analyze-final.log`。本次未改动该 fvp 测试。
- 本次涉及的 7 个 Dart 文件定向静态分析通过，见 `targeted-analyze.log`；`git diff --check` 与修改文档的 500 条本地相对链接检查通过。
- `tool/check.ps1 -SkipPub -Stage RootTests`：4697 项通过，13 项按既有 Windows 符号链接权限条件跳过，见 `root-tests.log`。
- `tool/check.ps1 -SkipPub -Stage PackageTests`：API 719、播放器 289、弹幕 161、mux 5 项通过；mux 另有 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生集成通过。
- Windows x64 mux 组件构建及 `integration_test/windows_playback_startup_test.dart` 的 9 项原生回归通过，覆盖保留的 media_kit／fvp 延迟双轨起播及取消／超时／释放边界，见 `windows-native.log`。沿用 WebView 插件已有的 CMake CMP0175 开发警告。
- 使用内存设置仓储的独立 Windows Debug 设置页构建、启动与 DTD 热重载通过，运行时错误采样为空，随后退出；未读取或修改用户设置，见 `settings-preview.log`。
- `tool/build-android-development.ps1 -Mode Release` 构建普通入口 arm64 开发 APK，通过脚本的包名、测试版名称、版本、原开发证书、不可调试及 AOT 检查；未安装或改动设备数据。产物为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`，见 `android-release.log`。反查 APK 无已删除的桥接类、上游 Java 包与资产路径；Flutter 生成的 Android／iOS／macOS 插件元数据均不再注册该桥。

Android／Apple 的设备播放与长期稳定性需分别验证，Windows 主机不能执行 Apple 构建；历史设备或 CI 记录不作为本次清理的验收结果。
