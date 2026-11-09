# 第三方来源与分发检查

## 2026-11-07 可选 fvp 后端

音频健康采样桥接使用 MDK 0.39 的三个未修改 C API 头文件；来源、摘要和许可范围见 [头文件来源](packages/bili_player/third_party/mdk/SOURCE.md)，原许可通知随 `native/fvp/NOTICE.md` 分发。桥接只统计音频解码活动，不额外链接 MDK／FFmpeg。

实验后端新增 BSD-3-Clause 的 [wang-bin/fvp](https://github.com/wang-bin/fvp/tree/e81637411c58a9ae28de246ee73ad06e3418f10e)，固定完整提交 `e81637411c58a9ae28de246ee73ad06e3418f10e`；其 MDK 核心固定官方 v0.39.0，逐平台 URL／SHA-256 见 `native/fvp/assets.lock.json`。MDK 的 SDK 授权与 Flutter 插件分别处理，官方说明 Flutter 用户可免费商用；原 SDK 许可保留在 `native/fvp/mdk.podspec`，SDK 附带 FFmpeg、libass 和可选专业解码插件的许可不能被插件 BSD 许可覆盖。接入方式、验证与分发边界见[可选 fvp 记录](docs/validation/fvp-backend-2026-11-07.md)。media_kit 和 bili_mux 的既有来源及许可继续独立保留。

## 2026-11-07 Windows x64 硬解边缘修复

Windows x64 改用个人 mpv `afd6da8843a07f463ba4c736a2ea636b1a92e23e` 重建的 SDK；固定 [原生资产](https://github.com/CKopoer/media-kit/releases/tag/native-windows-hwdec-edges-2026-11-07)、源码、构建容器和完整摘要见 [Windows 来源](windows/native/mpv/SOURCE.md)。mpv 为 LGPL-2.1-or-later，本次 FFmpeg 为 LGPL-3.0-or-later；LuaJIT／libsixel 的 MIT 和 subrandr 的 MPL-2.0 原始文本、容器附带的子依赖通知随 SDK 的 `provenance/` 分发。补充许可的打包脚本逐项验证原生 DLL、import library、头文件和 JAR 与 CI 产物内容不变。应用动态加载 DLL，保留替换和对应源码／构建材料；MIT 包装许可不覆盖静态子依赖许可。ARM64 和其他平台保留既有原生资产。

## 2026-11-09 Windows ARM64 OpenGL SDK

Windows ARM64 的 libmpv 改用 [Carapacik/libmpv-win32-video-cmake 20261031](https://github.com/Carapacik/libmpv-win32-video-cmake/releases/tag/20261031) 的原始 LGPL SDK，归档 SHA-256 为 `497841ee27697d816ff3aa14a0e1cce0ce639b593d28b53fb4e06e4410c37df6`，逐字节镜像由个人 media-kit fork 分发。mpv 来源为 `41f6a645068483470267271e1d09966ca3b9f413`，构建材料和补丁固定为 `6b921819019b11a84554e4c65c280d2676a15dd8`；`gpl=false`，FFmpeg n9.0.2 禁用 GPL／nonfree 并开启 version3。mpv 适用 LGPL-2.1-or-later；组合 DLL 的 FFmpeg 适用 LGPL-3.0-or-later，其他子依赖许可单独保留。SDK 来源与 LGPL 文本随 Windows 包分发；ANGLE 仍使用原固定 BSD-3-Clause 资产。新 SDK 没有 Vulkan loader 硬导入，ARM64 不再分发该 loader。详情见 [修复记录](docs/validation/windows-arm64-preview-crash-2026-11-09.md)。下方初版 ARM64 SDK 与 loader 说明保留为历史。

## 2026-11-07 个人媒体 fork

当前核心、视频和全部平台库插件统一来自 MIT 的 [CKopoer/media-kit](https://github.com/CKopoer/media-kit/tree/9858a8db83faf8bcfa39a8bfbc02dde9a2e92572)，官方基线为 `c533e446755f51cf53c7e57aea873f2aa5355f81`。mpv 源码由 [CKopoer/mpv](https://github.com/CKopoer/mpv) 维护；固定资产与原来源见 [native-2026-11-07](https://github.com/CKopoer/media-kit/releases/tag/native-2026-11-07)。Windows、Android、Apple 的首批资产为原摘要不变的上游镜像；Linux 从个人固定源码构建，子依赖继续记录发行版来源。MIT 不替代 mpv、FFmpeg、ANGLE 或其他子依赖的许可。当前入口及验证见[实施记录](docs/validation/media-kit-personal-fork-2026-11-07.md)；下列各次切换记录保留为历史。



记录日期：2026-10-05。本文件用于本地 0.1.0 预览的来源追踪，不表示已经完成对外发行所需的全部原生许可证归档。项目尚未确定自己的开源许可证。

## 2026-11-01 Windows ANGLE 硬解回退修复

2026-11-07 新增 Windows ARM64：libmpv 使用同一 `88eb9f2e73945d8bc9c133a2f67babaa9af34680` 的 LGPL aarch64 SDK；ANGLE 使用 BSD-3-Clause 的 `a96fca8d5ee2ca61e8de419e38cd577579281c9e`，构建材料为 [yorickreum/angle-libs](https://github.com/yorickreum/angle-libs/tree/485758dd4baf87570c2aac3cc47577a9514d3429)。两份原始归档逐字节镜像到个人媒体 fork；摘要、对应源码与分发许可见 [Windows 来源](windows/native/mpv/SOURCE.md)。ARM64 包附原始 ANGLE LICENSE 与来源记录，MIT 包装许可不替代其子依赖许可。

Windows 保留以下 PiliPlus 核心／视频／库插件和 ANGLE 来源，完整 libmpv SDK 改用固定的 [zhongfly LGPL x86_64 构建 88eb9f2e73](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-10-12-88eb9f2e73)，包含 mpv 的 EGL device-query 修复。当前清单为 [media-assets.cmake](windows/native/media-assets.cmake)，归档、SDK 逐文件摘要、源码、构建记录及许可边界见 [SOURCE.md](windows/native/mpv/SOURCE.md)。许可、来源与清单随 Windows bundle 一并保留，动态链接方式不变。没有采用 DXGI 扩展、修改 Pub 缓存或切换其他平台。LGPL 标签不代替静态子依赖各自的许可与对应源码分发要求。

## 2026-11-01 与 PiliPlus 锁文件对齐

按用户要求，采用与 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 锁文件相同的 MIT 依赖：

| 组件 | 固定来源 |
| --- | --- |
| canvas_danmaku 0.2.6 | [bggRGjQaUbCoE/canvas_danmaku](https://github.com/bggRGjQaUbCoE/canvas_danmaku/tree/275046d8647a6a26cba1d0dadb9e28688cb3dbf1)，`275046d8647a6a26cba1d0dadb9e28688cb3dbf1` |
| media_kit 1.1.11、原生库插件与事件桥 | [My-Responsitories/media-kit](https://github.com/My-Responsitories/media-kit/tree/73771ec38176be2d984a3049c28177bce23b54a0)，`73771ec38176be2d984a3049c28177bce23b54a0` |
| media_kit_video 1.2.5 | [bggRGjQaUbCoE/media-kit](https://github.com/bggRGjQaUbCoE/media-kit/tree/fd8421d21eade4d6d12de137fa7df902fec20292)，`fd8421d21eade4d6d12de137fa7df902fec20292` |
| macOS／Linux 库插件 | PiliPlus 锁文件的 hosted `media_kit_libs_macos_video 1.1.4`／`media_kit_libs_linux 1.2.1` |

该次对齐的 Windows 基线使用库插件指定的 libmpv／ANGLE，归档与 DLL 摘要见[基线来源](windows/native/PILIPLUS_SOURCE.md)；Windows 后续差异见上节。Android 使用该提交指定、逐 ABI SHA-256 校验的 20260906 jar；Apple 使用匹配库插件的 framework 和 CocoaPods，Linux 使用发行版 libmpv 并保留 distro notices。移除当前构建对 Predidit Native Assets 的依赖；本文件以下相关描述是历史。

弹幕保留有界媒体／到达时钟、布局、字体效果、分层与缓存，实际图片采样调用所锁定库的公开 painter。Windows 构建副本补丁继续保留上游版权和 MIT 许可。未复制 GPLv3 的 PiliPlus 应用源码或修改相邻仓库。MIT 不替代原生二进制及子依赖的许可；本轮二进制不沿用历史 LGPL-only 声明。适配、验证及未测项见[依赖切换](docs/validation/piliplus-dependencies-2026-11-01.md)。

## 2026-10-29 弹幕与播放器切换

`bili_danmaku` 依赖 MIT 的 [Predidit/canvas_danmaku](https://github.com/Predidit/canvas_danmaku/tree/401915a11ae113cddb5409632cd99729f4b0a301)，固定完整提交 `401915a11ae113cddb5409632cd99729f4b0a301`（0.3.3），使用其公开 Canvas 批量绘制和图像合成管线；包内保留媒体／到达时钟、布局、字体效果与缓存预算适配，没有复制 PiliPlus 应用代码。

播放器核心及视频插件切换为 MIT 的 [Predidit/media-kit](https://github.com/Predidit/media-kit/tree/83b7ca63772856e1ea0158916177e136f7b7b0be)，固定完整提交 `83b7ca63772856e1ea0158916177e136f7b7b0be`。其包内版本分别是 1.1.11 / 1.2.5，版本数字较旧不表示解析回到官方 hosted 实现。所有 `media_kit_libs_*` 已由 Native Assets 替代；原生资产逐目标 URL、SHA-256 及解包规则以该提交的 `media_kit/hook/native_bundles.json` 为准。Windows 使用 D3D11/DXGI，Linux 打包消费构建产物中的原生库，不再从系统软件包加入另一份 mpv；其余 Ubuntu 运行库仍保留 distro notices。

新 Windows 来源及分发边界见 [Native Assets 来源](windows/native/PREDIDIT_SOURCE.md)。下文 2026-10-16 自有 fork、旧 Android 资产与 Windows ANGLE/LGPL DLL 的描述属于历史实现，不能作为新二进制的许可或性能证明。目标 fork 的 MIT 只覆盖其源码；mpv、FFmpeg 和子依赖仍须保留各自许可、源码与重建材料。迁移方案与实际验证见[切换记录](docs/predidit-media-migration.md)。

## 2026-10-26 iOS 与 Linux 预览包

iOS 原生播放器沿用锁定 media-kit 依赖，独立 bili_mux 继续从固定 FFmpeg 源码构建，原始归档与构建材料随 `.mux-source.zip` 提供。Linux 从 Ubuntu 24.04 软件源安装 libmpv，使用 linuxdeploy 收集运行依赖；这些二进制不沿用 Windows LGPL 资产的配置声明，各自许可以包内 `usr/share/doc/bilisail/dependencies/*.copyright` 为准，`packages.tsv` 记录实际 binary/source 名称与版本。正式分发仍需归档实际子依赖的对应源码和许可材料。

打包工具 [linuxdeploy 1-alpha-20251107-1](https://github.com/linuxdeploy/linuxdeploy/releases/tag/1-alpha-20251107-1) 及 [GTK 部署 hook](https://github.com/linuxdeploy/linuxdeploy-plugin-gtk/tree/7a3fbc31a9e5075073ff8790f26effbac5f84453) 固定版本／提交和 SHA-256。GTK hook 的运行时脚本随包保留其来源许可，工具许可不替代所打包库的许可。Linux 禁用 WebView 的适配为本项目独立编写，没有复制上游或 PiliPlus 应用源码。平台与验收边界见[iOS／Linux 记录](docs/validation/ios-linux.md)。

## 工程与参考

- Flutter 工程由本机 Flutter 3.47.6 模板生成；Dart 3.13.5。直接版本写入各 `pubspec.yaml`，实际完整依赖保留在根及四个包的 `pubspec.lock`。
- `../biliuwp-lite` 作为功能、布局和交互参考，并按用户明确要求采用部分图标字体与 PNG 资源；`../bili-kernel` 仅作为协议/职责参考。没有复制它们的 C#、XAML 或 schema，也没有运行时依赖这两个仓库。图标具体路径、来源提交、SHA-256 与派生启动图标命令见 [资源来源](assets/README.md)。本地尚未找到覆盖这些资源的明确许可，本次采用范围为用户本机预览，不代表已获开源或对外再分发授权；发行前需核实资源权利和品牌使用范围。
- Bilibili 标题、封面、弹幕和媒体由服务端动态取得，未作为应用素材内置。测试的音视频由 FFmpeg 合成，生成命令见 [测试媒体说明](test/fixtures/media/README.md)。
- 界面业务图标采用上述 Bili 图标字体，通用操作保留 Flutter Material 图标；构建产物 `data/flutter_assets/NOTICES.Z` 包含 Flutter 工具收集的包许可文本，但不能替代手动记录的 UWP 资源许可审查。用户界面“关于”提供 Flutter 的许可证页。

2026-10-07 应用启动图标已改为按“BiliSail / 哔帆”设计的小电视与船帆角标，由内置 `image_gen` 辅助生成，替代原 UWP 启动图标。当前默认采用第二轮 C 版，保留三个候选方案和第一版帆船方案。2026-10-30 按用户要求另加入可选粉红小电视，矢量取自 Simple Icons 固定提交 `90646e4bf7f3b89df6c37e65baf3e7bc759a517c` 的 `icons/bilibili.svg`，按源项目 CC0 使用，保留[许可原文](assets/branding/bilibili_LICENSE.md)并在“关于 → 许可证”展示；仅改变填色、边距和输出尺寸，不打包蓝色版本。具体来源、摘要和采用边界见[品牌资源说明](assets/branding/README.md)。CC0 不授予商标权，Bilibili 标识权利仍归其权利人；本应用仍为独立第三方客户端，不构成官方授权、合作或背书。业务图标的既有来源登记不变。

空降助手可选访问 [BilibiliSponsorBlock API](https://github.com/hanydd/BilibiliSponsorBlock/wiki/API) 的 `bsbsb.top` 服务，默认关闭。客户端按公开协议独立实现，无第三方源码或资源复制；只读查询不携带 Bilibili 凭据。服务范围、字段与未在线验证项见 [验证记录](docs/validation/ui-controls.md)。

## 直接组件

2026-10-09 下载可选合并引入独立 `bili_mux`：固定 FFmpeg [`n9.0.2`](https://github.com/FFmpeg/FFmpeg/tree/n9.0.2) 源码，归档 SHA-256 为 `6e374ed621e48faa40639307dff48ba6fe574a509977956d2cce9669b7cc27e9`。裁剪为本地 MP4 读取/写入和必要的码流处理，构建报告 LGPL 2.1 or later，没有启用 GPL / nonfree 组件或外部编解码库。原文、三端打包、构建配置和测试边界见 [组件说明](packages/bili_mux/README.md)与[原始许可](packages/bili_mux/LICENSE-FFmpeg.txt)。`tool/build-release.ps1` 在应用安装包旁保存对应源码归档、本项目原生包装源码和构建说明；包装接口独立编写，不修改或复用播放器内部 ABI。新增 Dart 绑定使用固定 `ffi 2.2.0`（BSD-3-Clause，已有解析版本），不是额外媒体引擎。

Windows MSI/EXE 打包使用固定 [WiX Toolset 6.0.2](https://github.com/wixtoolset/wix/releases/tag/v6.0.2) 与同版本 `WixToolset.BootstrapperApplications.wixext`、`WixToolset.UI.wixext`、`WixToolset.Util.wixext`，来源为 NuGet 官方包；UI 扩展提供 MSI 辅助对话框，Util 扩展用于 EXE 读取先前安装目录。源码采用 [Microsoft Reciprocal License（MS-RL）](https://github.com/wixtoolset/wix/blob/v6.0.2/LICENSE.TXT)，二进制使用另适用 [Open Source Maintenance Fee](https://docs.firegiant.com/wix/osmf/)；没有采用 FireGiant 商业扩展。WiX CLI 和 .NET 仅用于构建，EXE 安装器内嵌原生 Burn 引擎与 Bootstrapper UI，用户机器无需 .NET。[原始许可](windows/licenses/wix/LICENSE.TXT) 与 [二进制条款](windows/licenses/wix/OSMFEULA.txt) 随 Windows 安装包一并保留于 `data/licenses/wix`。品牌 UI 的三个改编文件单独沿用 MS-RL，来源和文件范围见 [界面说明](windows/packaging/README.md)，完整 UI 源码与许可证另随包保留于 `data/licenses/wix/installer-ui`。

Windows 安装器的现代文件夹选择器另使用同版本的 `WixToolset.BootstrapperApplicationApi` 与 `WixToolset.WixStandardBootstrapperApplicationFunctionApi` 接口头文件；不链接新增 WiX 库。NuGet 归档 SHA-256 固定于[构建脚本](tool/windows-installer-native.ps1)，头文件保留 MS-RL 通知并连同辅助源码随 `data/licenses/wix/installer-ui` 分发；静态 CRT 的原生辅助 DLL 仅用于安装 UI。

内嵌官网登录使用 [flutter_inappwebview 6.2.0-beta.3](https://pub.dev/packages/flutter_inappwebview/versions/6.2.0-beta.3)，Apache-2.0；选此固定预览版是因为工程 AGP 9 与其稳定版不兼容。官网页面与验证码按需通过 HTTPS 加载，未复制到应用资产。Windows 的 WebView2 SDK／Loader 使用 NuGet 包内 Microsoft BSD 类许可，WIL、CppWinRT 与 nlohmann.json 使用 MIT；这些原生许可另随 Windows 产物置于 `data/licenses/webview`。nlohmann.json 3.12.0 的 [原始许可](https://github.com/nlohmann/json/blob/v3.12.0/LICENSE.MIT)保留于 [本地许可](windows/licenses/nlohmann-json-LICENSE.txt)。平台 SDK 来源、锁定版本和实测边界见 [登录验证](docs/validation/password-sms-login.md)。

应用默认内置 HarmonyOS Sans（简体中文 Regular/Medium/Bold），来源为用户提供的本机字体目录，文件未修改。随字体提供的 HarmonyOS Sans Fonts License Agreement、版权通知与 SHA-256 见 [资源来源](assets/README.md#harmonyos-sans)。完整许可证打包到应用，并通过“关于”中的许可证页展示；设置中可切换为系统默认字体。

固定组合：Flutter 3.47.6、Riverpod 3.4.3、go_router 18.0.2、Dio 5.11.1、crypto 3.0.7、Drift 2.35.1、path 1.9.1、path_provider 2.1.6、flutter_secure_storage 11.2.0、qr_flutter 4.1.0、window_manager 0.5.2、canvas_danmaku 0.2.6、media_kit 1.1.11、media_kit_video 1.2.5（上述固定 PiliPlus Git 来源）。各包的许可证以锁定版本包内 `LICENSE` 和生成的 notices 为准。

依赖维护方入口：[Flutter](https://github.com/flutter/flutter)、[Riverpod](https://github.com/rrousselGit/riverpod)、[go_router](https://pub.dev/packages/go_router/versions/18.0.2)、[Dio](https://github.com/cfug/dio)、[Drift](https://github.com/simolus3/drift)、[flutter_secure_storage](https://github.com/juliansteenbakker/flutter_secure_storage)、[media_kit](https://github.com/media-kit/media-kit)。

关于页与更新检查使用 [package_info_plus 10.2.2](https://pub.dev/packages/package_info_plus/versions/10.2.2) 读取平台包版本，BSD-3-Clause；本轮将已有锁定的传递依赖提升为直接依赖，没有改变包版本或新增下载的二进制来源。GitHub 更新请求自行实现，只参考 UWP 交互职责，未复制源码或版本 schema，见 [更新验证](docs/validation/app-updates.md)。系统浏览器入口沿用 url_launcher，仅开放本项目 GitHub 仓库与 Release 路径，不传账号凭据。

## 2026-10-16 media-kit fork 与 Android 原生资产

播放器核心、视频输出、聚合库及 Android video 库固定为用户 [CKopoer/media-kit](https://github.com/CKopoer/media-kit/commit/63b7ea7dd95fc348cecf250df5f54ff87d69d8a9) 的 Git 提交。基于官方当前代码，兼容移植 PiliPlus 实际使用的两个 MIT fork；保留 MIT 版权头。mpv v0.41.0 client 头文件另保留 ISC 声明，FFI 使用固定版本工具真实重生成。

Android 使用 [20260906 default](https://github.com/My-Responsitories/libmpv-android-video-build/releases/tag/20260906) 原生资产，逐 ABI 校验 SHA-256；源码版本、构建选项、依赖许可与摘要见 fork 的 [NATIVE_LIBRARIES.md](https://github.com/CKopoer/media-kit/blob/63b7ea7dd95fc348cecf250df5f54ff87d69d8a9/libs/android/media_kit_libs_android_video/NATIVE_LIBRARIES.md)。构建脚本的 MIT 不替代原生依赖各自的许可。

PiliPlus 应用为 GPLv3，本次仅参考其配置与职责，未复制应用代码。弹幕参考分支 canvas_danmaku 为 MIT，未新增依赖或复制源码。精确来源、采用边界与验证见 [移植记录](docs/validation/piliplus-media-kit-port.md)。

## Windows 原生播放器资产

图片缓存直接使用现有锁定的 [crypto 3.0.7](https://pub.dev/packages/crypto/versions/3.0.7) 计算 SHA-256 文件键和内容校验，BSD-3-Clause；它此前已由 API 包引入，本次没有增加新的解析版本或原生二进制。

新增外部内容入口采用固定的 [url_launcher 6.3.2](https://pub.dev/packages/url_launcher/versions/6.3.2)，由 Flutter 团队维护，BSD-3-Clause。Android、Windows、macOS 的平台实现随根锁文件固定；插件调用系统 URL 打开能力，不增加媒体解码二进制。仅在用户点击明确的“在浏览器打开”内容入口后打开 Bilibili HTTPS 页面，不向外部浏览器传递应用 Cookie。

迁移前锁文件曾解析 `media_kit_libs_windows_video 1.0.11`。旧 SDK 默认资产的历史下载校验如下；当前实现以本文件开头的 2026-10-29 记录为准：

| 资产 | 固定来源 | 已核对 MD5 |
| --- | --- | --- |
| mpv/FFmpeg 组合 DLL | [libmpv-win32-video-build 2023-09-24](https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24)，`mpv-dev-x86_64-20230924-git-652a1dd.7z` | `a832ef24b3a6ff97cd2560b5b9d04cd8` |
| ANGLE DLL | [flutter-windows-ANGLE-OpenGL-ES v1.0.1](https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v1.0.1)，`ANGLE.7z` | `e866f13e8d552348058afaafe869b1ed` |

上述 MD5 记录 SDK 默认下载内容的一致性。2026-10-13 Windows x64 的实际 bundle 改用固定 LGPL 构建 `mpv-dev-lgpl-x86_64-20261012-git-88eb9f2e73.7z`，修复旧版 ANGLE 硬解扩展检查并避免回读；ANGLE 默认资产保持。归档 SHA-256 为 `d1a3f57dfb3c7f07e5456e32e9ecc9e406f6457f2560ff5801c9b37a8036f507`，DLL SHA-256 为 `222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`，构建时分别校验。来源、实际 `gpl=false` 配置、对应 mpv 源码/构建记录及 LGPL-2.1-or-later 许可见 [Windows 原生资产](windows/native/mpv/SOURCE.md)，许可和来源说明随 bundle 保留于 `data/licenses/mpv`。公开发行仍需完整归档其子依赖的源码与许可材料。

media_kit 的 Dart 包许可不能替代 mpv、FFmpeg、ANGLE 和其子依赖的分发条件。当前仅生成用户本机可运行预览，尚未对外发布、签名或宣称许可审核完成。Android/macOS 原生来源及预期校验在 [媒体包验证](docs/validation/media-packages.md)；未构建下载的资产不能记为已校验。
