# 第三方来源与分发检查

记录日期：2026-10-05。本文件用于本地 0.1.0 预览的来源追踪，不表示已经完成对外发行所需的全部原生许可证归档。项目尚未确定自己的开源许可证。

## 工程与参考

- Flutter 工程由本机 Flutter 3.47.6 模板生成；Dart 3.13.5。直接版本写入各 `pubspec.yaml`，实际完整依赖保留在根及三个包的 `pubspec.lock`。
- `../biliuwp-lite` 作为功能、布局和交互参考，并按用户明确要求采用部分图标字体与 PNG 资源；`../bili-kernel` 仅作为协议/职责参考。没有复制它们的 C#、XAML 或 schema，也没有运行时依赖这两个仓库。图标具体路径、来源提交、SHA-256 与派生启动图标命令见 [资源来源](assets/README.md)。本地尚未找到覆盖这些资源的明确许可，本次采用范围为用户本机预览，不代表已获开源或对外再分发授权；发行前需核实资源权利和品牌使用范围。
- Bilibili 标题、封面、弹幕和媒体由服务端动态取得，未作为应用素材内置。测试的音视频由 FFmpeg 合成，生成命令见 [测试媒体说明](test/fixtures/media/README.md)。
- 界面业务图标采用上述 Bili 图标字体，通用操作保留 Flutter Material 图标；构建产物 `data/flutter_assets/NOTICES.Z` 包含 Flutter 工具收集的包许可文本，但不能替代手动记录的 UWP 资源许可审查。用户界面“关于”提供 Flutter 的许可证页。

2026-10-07 应用启动图标已改为按“BiliSail / 哔帆”设计的帆船标识，由内置 `image_gen` 辅助生成，替代原 UWP 启动图标。Bilibili 官网及其下载中心的小电视仅作为视觉参考，官网原图未打包；具体 URL、提示词、SHA-256 和采用边界见 [品牌资源说明](assets/branding/README.md)。本应用仍为独立第三方客户端，品牌参考不构成官方授权、合作或背书；业务图标的既有来源登记不变。

空降助手可选访问 [BilibiliSponsorBlock API](https://github.com/hanydd/BilibiliSponsorBlock/wiki/API) 的 `bsbsb.top` 服务，默认关闭。客户端按公开协议独立实现，无第三方源码或资源复制；只读查询不携带 Bilibili 凭据。服务范围、字段与未在线验证项见 [验证记录](docs/validation/ui-controls.md)。

## 直接组件

内嵌官网登录使用 [flutter_inappwebview 6.2.0-beta.3](https://pub.dev/packages/flutter_inappwebview/versions/6.2.0-beta.3)，Apache-2.0；选此固定预览版是因为工程 AGP 9 与其稳定版不兼容。官网页面与验证码按需通过 HTTPS 加载，未复制到应用资产。Windows 的 WebView2 SDK／Loader 使用 NuGet 包内 Microsoft BSD 类许可，WIL、CppWinRT 与 nlohmann.json 使用 MIT；这些原生许可另随 Windows 产物置于 `data/licenses/webview`。nlohmann.json 3.12.0 的 [原始许可](https://github.com/nlohmann/json/blob/v3.12.0/LICENSE.MIT)保留于 [本地许可](windows/licenses/nlohmann-json-LICENSE.txt)。平台 SDK 来源、锁定版本和实测边界见 [登录验证](docs/validation/password-sms-login.md)。

应用默认内置 HarmonyOS Sans（简体中文 Regular/Medium/Bold），来源为用户提供的本机字体目录，文件未修改。随字体提供的 HarmonyOS Sans Fonts License Agreement、版权通知与 SHA-256 见 [资源来源](assets/README.md#harmonyos-sans)。完整许可证打包到应用，并通过“关于”中的许可证页展示；设置中可切换为系统默认字体。

固定组合：Flutter 3.47.6、Riverpod 3.4.3、go_router 18.0.2、Dio 5.11.1、crypto 3.0.7、Drift 2.35.1、path 1.9.1、path_provider 2.1.6、flutter_secure_storage 11.2.0、qr_flutter 4.1.0、window_manager 0.5.2、media_kit 1.2.6、media_kit_video 2.0.1、media_kit_libs_video 1.0.7。各包的许可证以锁定版本包内 `LICENSE` 和生成的 notices 为准。

依赖维护方入口：[Flutter](https://github.com/flutter/flutter)、[Riverpod](https://github.com/rrousselGit/riverpod)、[go_router](https://pub.dev/packages/go_router/versions/18.0.2)、[Dio](https://github.com/cfug/dio)、[Drift](https://github.com/simolus3/drift)、[flutter_secure_storage](https://github.com/juliansteenbakker/flutter_secure_storage)、[media_kit](https://github.com/media-kit/media-kit)。

关于页与更新检查使用 [package_info_plus 10.2.2](https://pub.dev/packages/package_info_plus/versions/10.2.2) 读取平台包版本，BSD-3-Clause；本轮将已有锁定的传递依赖提升为直接依赖，没有改变包版本或新增下载的二进制来源。GitHub 更新请求自行实现，只参考 UWP 交互职责，未复制源码或版本 schema，见 [更新验证](docs/validation/app-updates.md)。系统浏览器入口沿用 url_launcher，仅开放本项目 GitHub 仓库与 Release 路径，不传账号凭据。

## Windows 原生播放器资产

图片缓存直接使用现有锁定的 [crypto 3.0.7](https://pub.dev/packages/crypto/versions/3.0.7) 计算 SHA-256 文件键和内容校验，BSD-3-Clause；它此前已由 API 包引入，本次没有增加新的解析版本或原生二进制。

新增外部内容入口采用固定的 [url_launcher 6.3.2](https://pub.dev/packages/url_launcher/versions/6.3.2)，由 Flutter 团队维护，BSD-3-Clause。Android、Windows、macOS 的平台实现随根锁文件固定；插件调用系统 URL 打开能力，不增加媒体解码二进制。仅在用户点击明确的“在浏览器打开”内容入口后打开 Bilibili HTTPS 页面，不向外部浏览器传递应用 Cookie。

当前锁文件解析 `media_kit_libs_windows_video 1.0.11`。本机成功下载并校验：

| 资产 | 固定来源 | 已核对 MD5 |
| --- | --- | --- |
| mpv/FFmpeg 组合 DLL | [libmpv-win32-video-build 2023-09-24](https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24)，`mpv-dev-x86_64-20230924-git-652a1dd.7z` | `a832ef24b3a6ff97cd2560b5b9d04cd8` |
| ANGLE DLL | [flutter-windows-ANGLE-OpenGL-ES v1.0.1](https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v1.0.1)，`ANGLE.7z` | `e866f13e8d552348058afaafe869b1ed` |

校验值来自插件构建脚本，并与本地下载文件重新计算结果一致；它们用于记录上游固定资产的一致性。当前 Windows native 资产较旧，对外发行前需要重新评估维护状态、编解码组件、修复版本以及相应源码/许可材料。

media_kit 的 Dart 包许可不能替代 mpv、FFmpeg、ANGLE 和其子依赖的分发条件。当前仅生成用户本机可运行预览，尚未对外发布、签名或宣称许可审核完成。Android/macOS 原生来源及预期校验在 [媒体包验证](docs/validation/media-packages.md)；未构建下载的资产不能记为已校验。
