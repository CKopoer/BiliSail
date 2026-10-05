# BiliSail（哔帆）项目更名

日期：2026-10-06。项目原名 Bili Lite，本轮按用户要求更新名称与描述；应用尚未发布，直接重构内部标识，不保留旧版数据兼容层。

## 命名范围

- 产品英文名：**BiliSail**；中文昵称：**哔帆**。
- 项目描述：**一个专注观看体验的跨平台 Bilibili 第三方客户端**。
- 根 Dart 工程：`bilisail`，测试、工具和集成测试同步更新 `package:bilisail/` 导入。
- Flutter／桌面窗口／Android 启动名称：`BiliSail`；设置关于页与字体预览同时展示中文昵称。
- Windows 构建入口：`build/windows/x64/runner/Release/bilisail.exe`，版本资源的文件描述、产品名称和内部文件名同步更新。
- macOS 产品名称：`BiliSail.app`，Xcode product reference、scheme 与测试宿主路径同步更新。
- 项目 HTTP／WebSocket User-Agent 与空降助手 origin 同步更新；API 端点和鉴权策略沿用既有方案。
- 三个独立包仍为 `bili_api`、`bili_player`、`bili_danmaku`，包描述更新为 BiliSail。
- 本地检出目录仍为 `bili-lite`；VS Code CMake 配置使用 `${workspaceFolder}/windows`，不再绑定机器上的绝对路径。

## 安装与存储标识

| 标识 | 新值 |
| --- | --- |
| Android namespace／application ID | `dev.bilisail.bilisail` |
| Android Activity 包路径 | `android/app/src/main/kotlin/dev/bilisail/bilisail/MainActivity.kt` |
| macOS bundle ID | `dev.bilisail.bilisail` |
| macOS RunnerTests bundle ID | `dev.bilisail.bilisail.RunnerTests` |
| Windows `CompanyName`／`ProductName` | `dev.bilisail`／`BiliSail` |
| 数据库文件 | `bilisail.sqlite` |
| 安全存储 key prefix | `bilisail.web_session.v1` |

Windows 的 `path_provider_windows 2.3.0` 和 `flutter_secure_storage_windows 4.2.2` 均读取 EXE 版本资源中的 `CompanyName`／`ProductName`。新应用数据和安全存储目录为 `%APPDATA%\dev.bilisail\BiliSail`，图片缓存位于对应的 `%LOCALAPPDATA%` 目录，诊断日志位于应用数据目录下的 `logs`。Android／macOS 通过新安装标识使用独立应用数据空间。

数据库结构仍为 v2；改名版本从新的数据空间开始，旧开发版登录、设置与历史不自动迁移。保留原开发版数据文件，不执行删除或搬移。

相邻参考仓库、`BiliLite.UWP` 源码路径和许可来源保持原名。此前验收文档中的旧可执行文件、交付目录、压缩包名称与哈希是历史记录，保留原值；当前构建入口以根 README 为准。

## 验证

固定工具链仍为 Flutter 3.47.6／Dart 3.13.5，直接依赖与锁文件未改版本。

| 检查 | 结果 |
| --- | --- |
| `tool/check.ps1 -SkipPub` | 根应用与三个包格式、分析全部通过；根应用 597、API 206、播放器 16、弹幕 19，共 838 项测试通过 |
| `tool/test-windows-media.ps1` | 5 项本地媒体／安全存储测试与 1 项原生错误诊断测试通过；未启用在线烟测 |
| `flutter build windows --release --no-pub --target lib/main.dart` | 通过；在独立源码副本构建，源码与当前工作区一致，完整产物复制至 `artifacts/BiliSail-0.1.0-windows-x64/` |
| `flutter build apk --release --target-platform android-arm64 --target lib/main.dart` | 通过；使用相同源码副本，产物复制为 `artifacts/BiliSail-0.1.0-android-arm64.apk` |
| Windows 成品版本资源 | `FileDescription`／`ProductName` 为 `BiliSail`，`CompanyName` 为 `dev.bilisail`，`InternalName`／`OriginalFilename` 为 `bilisail`／`bilisail.exe` |
| Android 成品 `aapt2 dump badging` | 应用名 `BiliSail`，application ID 为 `dev.bilisail.bilisail`，启动入口为 `dev.bilisail.bilisail.MainActivity` |
| 文档／配置静态检查 | 修改文档的相对链接、差异空白检查、Android manifest 与 macOS plist／scheme 语法通过；应用源码、测试、工具和平台配置无本项目旧名称残留 |

日志位于 `build/project-renaming/`；构建源码副本及哈希清单位于该目录下的 `source/` 和 `source-hashes.json`，均为忽略的本地验证产物。Android 发布构建通过 Flutter 重新生成插件注册文件，不手改生成文件，避免复用集成测试注册状态。

Android 的 Flutter 构建目标为 arm64；APK 内仍包含媒体插件附带的其他 ABI 原生库，这不代表其他 ABI 的完整运行支持已验证。构建输出中的第三方 CMake、Java 编译级别与可选 CupertinoIcons 字体提示未阻断构建，本次未扩展依赖或播放能力。

未进行 Android 真机安装／播放、macOS 构建／运行或真实账号在线恢复与写操作验证。更名与构建通过不代表三端 M0 验收完成。
