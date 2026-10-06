<h1 align="center">BiliSail · 哔帆</h1>

<p align="center">
  专注观看体验的跨平台 Bilibili 第三方客户端<br>
  基于 Flutter 与 Dart，面向 Windows、Android 和 macOS
</p>

<p align="center">
  <a href="https://github.com/CKopoer/BiliSail/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/CKopoer/BiliSail/ci.yml?label=CI" alt="CI 状态"></a>
  <a href="pubspec.yaml"><img src="https://img.shields.io/badge/version-0.1.0%20preview-fb7299" alt="版本：0.1.0 预览"></a>
  <a href="docs/validation/m0-results.md"><img src="https://img.shields.io/badge/Flutter-3.47.6-02569B?logo=flutter&amp;logoColor=white" alt="Flutter 3.47.6"></a>
  <a href="https://github.com/CKopoer/BiliSail/stargazers"><img src="https://img.shields.io/github/stars/CKopoer/BiliSail?style=flat" alt="GitHub Stars"></a>
  <a href="https://github.com/CKopoer/BiliSail/forks"><img src="https://img.shields.io/github/forks/CKopoer/BiliSail?style=flat" alt="GitHub Forks"></a>
</p>

<p align="center">
  <a href="#下载与安装">下载与安装</a> ·
  <a href="docs/README.md">项目文档</a> ·
  <a href="https://github.com/CKopoer/BiliSail/issues">问题反馈</a> ·
  <a href="#参与贡献">参与贡献</a>
</p>

---

BiliSail（哔帆）以视频、影视和直播观看为核心，提供多标签浏览、原生播放、弹幕与本地续播。界面借鉴 BiliLite 的轻量桌面布局，结合自适应网格、播放详情分栏和可配置快捷键。

当前开发版本为 **0.1.0 预览版**，主要在 Windows 上调试和验证。Android 与 macOS 为首批目标平台，完整三端验收仍在推进；具体状态见下方平台表及[验证文档](docs/README.md)。本项目为独立的第三方客户端，与哔哩哔哩官方无隶属关系。

## 使用声明

本应用是哔哩哔哩第三方客户端，视频、影视、直播及相关内容均来自哔哩哔哩，与官方无隶属关系。

本程序仅供学习交流与编程技术研究使用。

如果侵犯了您的合法权益，请及时联系开发者，我们会第一时间处理并删除相关内容。可通过[项目问题反馈](https://github.com/CKopoer/BiliSail/issues)联系我们。

## 目录

- [使用声明](#使用声明)
- [功能概览](#功能概览)
- [平台与开发状态](#平台与开发状态)
- [下载与安装](#下载与安装)
- [从源码运行](#从源码运行)
- [使用说明](#使用说明)
- [开发与文档](#开发与文档)
- [参与贡献](#参与贡献)
- [贡献者](#贡献者)
- [致谢](#致谢)
- [Star 趋势](#star-趋势)
- [许可与第三方资源](#许可与第三方资源)

## 功能概览

| 模块 | 当前能力 |
| --- | --- |
| 内容浏览 | 推荐、热门、分区、排行榜；动态、视频动态、番剧、国创、放映厅和直播入口 |
| 搜索 | 综合、视频、番剧、影视、直播、专栏和用户七类搜索，支持对应排序、筛选与自动分页 |
| 视频与影视 | DASH 音视频分轨播放，分 P、合集与选集，清晰度、倍速、音量、全屏、章节与缩略图预览 |
| 直播 | HLS / FLV、可用清晰度、实时聊天、画面弹幕、Super Chat 展示及发送入口 |
| 弹幕与字幕 | 滚动、顶部、底部弹幕，暂停与缓冲冻结、seek 重定位；样式、密度与本地过滤配置，字幕 cue 显示 |
| 账号与互动 | Web 扫码登录流程、系统安全存储、用户主页、收藏、追番、追剧、稍后再看、评论与消息；用户主动触发的点赞、投币、收藏和发送 |
| 桌面体验 | 多标签工作区、自适应视频卡片、紧凑播放布局、键盘与鼠标侧键配置、图片缓存、账号隔离的本地历史与续播 |
| 个性化 | 外观、字体、播放、弹幕和字幕设置；可选空降助手，默认关闭 |

上表描述已接入的功能，在线和平台验证范围见[文档索引](docs/README.md)。部分能力仍需进一步验收：

- 完整的真实扫码登录、部分私有列表的在线分页，以及真实账号的投币、收藏、发送等写操作仍待验证；写请求只由明确的用户操作触发，不自动重试。
- 字幕正文目前仅通过 fixture 验证，在线样本未取得可用字幕。
- 部分公开视频准备时间较长，排行榜可能受到服务端风控；Windows 辅助功能场景的原生崩溃防护仍需持续回归。详见[首版记录](docs/validation/m0-results.md)和[播放错误排查](docs/validation/native-playback-errors.md)。

应用默认不添加自动遥测。空降助手启用后会查询独立第三方服务，不携带 Bilibili 账号凭据，也不自动上报。

## 平台与开发状态

| 平台 | 目标架构 / 系统 | 仓库记录的验证状态 |
| --- | --- | --- |
| Windows | x64 / Windows 10 1809 及以上 | 已本地构建并运行，验证游客视频、影视和直播原生播放；MSIX 打包与测试签名通过，安装、卸载和升级待验 |
| Android | arm64 / Android 7.0（API 24）及以上 | 已本地构建 APK；真机运行、播放与签名升级待验 |
| macOS | arm64 / macOS 12.0 及以上 | 已创建平台入口与 CI 配置；构建、启动和原生播放待验 |

平台状态以[首版实测](docs/validation/m0-results.md)、[影视与直播播放验证](docs/validation/content-playback.md)和[构建打包记录](docs/validation/ci-cd.md)为准。构建成功与实机验收分别记录，当前预览版尚未完成 M0 三端验收。

后续重点：

- 补齐三端原生播放、扫码登录、安全存储和安装升级验收。
- 实现下载与离线播放、UGC 云历史。
- 逐平台接入并验证后台音频、媒体键和画中画（PiP）。

完整阶段安排见[实施与验收](docs/implementation-plan.md)。

## 下载与安装

安装包入口：[GitHub Releases](https://github.com/CKopoer/BiliSail/releases)。

**目前尚无公开 Release**，可按[源码运行说明](#从源码运行)在 Windows 上构建预览版。后续发布的包格式如下：

| 平台 | 预览包格式 | 安装说明 |
| --- | --- | --- |
| Windows x64 | `.msix`，附签名公钥证书 `.cer` | 使用测试签名时，需要先信任对应证书；具体步骤见 [MSIX 签名与安装](docs/validation/ci-cd.md#windows-msix-签名与安装) |
| Android arm64 | `.apk` | 当前构建使用临时 debug 签名，尚未建立正式签名与升级链路 |
| macOS arm64 | `.app.zip` | 当前配置使用 ad-hoc 签名，尚未完成 Developer ID 签名与公证 |

GitHub Actions 的 **CI** 执行根应用和三个包的检查，并按平台构建预览产物；维护者可手动运行 **Release preview** 创建预览 Release 草稿。触发方式、产物校验与签名配置见 [CI/CD 说明](docs/validation/ci-cd.md)。

## 从源码运行

### 环境要求

项目固定使用 **Flutter 3.47.6 stable / Dart 3.13.5**。直接依赖采用精确版本，根应用和各包均保留锁文件。

Windows 开发还需安装 **Visual Studio 2022** 的“使用 C++ 的桌面开发”工作负载及 Windows SDK。Android 和 macOS 的构建需各自的工具链，macOS 构建需在 macOS 主机上执行。

### Windows 调试

在 PowerShell 中执行：

```powershell
git clone https://github.com/CKopoer/BiliSail.git
cd BiliSail
flutter pub get
flutter run -d windows
```

### Windows Release 构建

```powershell
flutter build windows --release
.\build\windows\x64\runner\Release\bilisail.exe
```

移动或分发便携构建时，需保留整个 `Release` 目录，包括原生 DLL 和 `data`。播放器原生库由插件从固定来源下载，首次构建需能访问 GitHub。**运行应用无需另行安装 FFmpeg**；测试媒体的生成才使用本机 FFmpeg。

## 使用说明

桌面工作区支持同时打开首页、搜索、视频、用户、历史和设置等标签。首页固定，最多打开 16 个标签；标签状态保留至本次运行结束。切换到普通标签时，当前视频继续播放；切换到另一个视频时复用单一播放器，保留各视频的进度与播放选项。关闭当前播放标签会停止播放。

### 常用快捷键

| 操作 | 默认快捷键 |
| --- | --- |
| 播放 / 暂停 | `Space` |
| 前进 / 后退 | `→` / `←`，默认 3 秒 |
| 临时加速 | 长按 `→`，默认 3 倍速 |
| 切换 / 退出全屏 | `F`、`F11` 或 `Enter` / `Esc` |
| 收起 / 展开视频信息 | `W` 或 `F12` |
| 开关弹幕 / 字幕 | `D` 或 `F9` / `F6` |
| 降低 / 提高倍速 | `F1` 或 `;` / `F2` 或 `'` |
| 切换 1 / 2 倍速 | `Ctrl+1` |
| 新建 / 关闭标签 | `Ctrl+T` / `Ctrl+W` |
| 下一个 / 上一个标签 | `Ctrl+Tab` / `Ctrl+Shift+Tab` |

单击视频画面切换控制栏，双击切换全屏。快捷键可在设置中修改、停用或恢复默认；文本输入和模态弹窗期间不触发播放快捷键。更多操作见[快捷键与富评论](docs/validation/shortcuts-rich-comments.md)、[设置与侧键](docs/validation/settings-tabs-fonts.md)和[标签播放行为](docs/validation/profile-playback-rates.md)。

## 开发与文档

### 工程结构

```text
lib/
├── app/                  # 组合根、路由、主题与工作区
├── core/                 # 存储、安全凭据、取消与平台能力
├── domain/               # 共享领域类型
├── features/             # 按 domain / data / application / presentation 分层
└── shared/ui/            # 通用界面组件
packages/
├── bili_api/             # 纯 Dart 协议与 API 包
├── bili_player/          # 通用播放器契约、media_kit 适配与 VideoSurface
└── bili_danmaku/         # 无网络的有界弹幕调度与绘制
docs/                     # 设计、决策与验证记录
tool/                     # 检查、原生测试与构建打包脚本
```

### 检查与调试

根应用与三个包的格式、静态分析和离线测试：

```powershell
.\tool\check.ps1
```

Windows 原生受控媒体与安全存储测试：

```powershell
.\tool\test-windows-media.ps1
```

显式运行游客公开 API 与媒体 CDN 烟测：

```powershell
.\tool\test-windows-media.ps1 -Online

# 纯 Dart API 只读烟测
Push-Location packages\bili_api
dart run tool\live_smoke.dart
Pop-Location
```

正常测试使用 fake transport、repository、player 和人工生成的媒体，无需真实账号。播放诊断保存在本机应用数据目录的 `logs` 下，限制容量并过滤账号、请求头和媒体 URL，不自动上传；路径与排查方法见[播放错误排查](docs/validation/native-playback-errors.md)。

### 文档入口

| 文档 | 内容 |
| --- | --- |
| [文档索引](docs/README.md) | 全部设计与功能验证记录 |
| [整体架构](docs/architecture.md) | 功能分层、独立包、状态与生命周期 |
| [API 与会话](docs/api-design.md) | 接口、鉴权、错误处理与账号隔离 |
| [播放、直播与弹幕](docs/playback-and-danmaku.md) | 播放会话、媒体请求与弹幕时钟 |
| [实施与验收](docs/implementation-plan.md) | 开发阶段与平台验收要求 |
| [架构决策](docs/decisions.md) | 重要技术选择及其依据 |
| [开发约定](AGENTS.md) | 代码、文档、测试与交付规则 |
| [第三方说明](THIRD_PARTY_NOTICES.md) | 依赖、原生二进制与资源来源 |

项目原名 Bili Lite，当前工程名为 `bilisail`。更名后的安装与数据标识以及数据空间变化见[项目更名记录](docs/validation/project-renaming.md)。

## 参与贡献

欢迎通过 [Issues](https://github.com/CKopoer/BiliSail/issues) 反馈问题、提出建议，通过 [Pull Requests](https://github.com/CKopoer/BiliSail/pulls) 改进代码、文档和平台适配。

- **反馈问题**：附上应用版本、操作系统、复现步骤、预期与实际结果；播放问题可提供公开视频 BV 号及脱敏诊断。请勿提交 Cookie、token、二维码 key 或带签名参数的媒体 URL。
- **提出改进**：说明使用场景与预期行为。较大的功能或架构调整建议先通过 Issue 讨论。
- **提交修改**：先阅读[文档索引](docs/README.md)与 [AGENTS.md](AGENTS.md)，保持改动聚焦，并在 PR 中说明变更、验证结果和未测项。代码改动运行 `tool/check.ps1`；原生播放改动补充受影响平台的构建与实机验证。纯文档改动检查链接、路径和内容一致性即可。

## 贡献者

感谢所有参与代码、文档、测试和问题反馈的贡献者。

<a href="https://github.com/CKopoer/BiliSail/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=CKopoer/BiliSail" alt="BiliSail 代码贡献者头像">
</a>

头像由 [contrib.rocks](https://contrib.rocks) 根据 GitHub 提交贡献生成；完整提交贡献见[贡献者列表](https://github.com/CKopoer/BiliSail/graphs/contributors)。

## 致谢

感谢以下项目及其维护者提供的参考与基础能力：

| 项目 | 与 BiliSail 的关系 |
| --- | --- |
| [biliuwp-lite（原项目）](https://github.com/xiaoyaocz/biliuwp-lite) / [ywmoyue 维护分支](https://github.com/ywmoyue/biliuwp-lite) | 功能、桌面布局与交互参考；部分图标资源来源见[资源记录](assets/README.md) |
| [bili-kernel](https://github.com/Richasy/bili-kernel) | C# / .NET API 项目，为协议模型、鉴权与职责划分提供参考 |
| [Flutter](https://github.com/flutter/flutter) / [Dart](https://github.com/dart-lang/sdk) | 跨平台界面与语言运行时 |
| [Riverpod](https://github.com/rrousselGit/riverpod) / [go_router](https://pub.dev/packages/go_router) | 应用状态、依赖注入与路由 |
| [media_kit](https://github.com/media-kit/media-kit) / [mpv](https://github.com/mpv-player/mpv) / [FFmpeg](https://ffmpeg.org) | 播放适配与原生媒体解码基础 |
| [Dio](https://github.com/cfug/dio) / [Drift](https://github.com/simolus3/drift) / [flutter_secure_storage](https://github.com/juliansteenbakker/flutter_secure_storage) | 网络、结构化存储与系统安全凭据 |
| [BilibiliSponsorBlock](https://github.com/hanydd/BilibiliSponsorBlock) | 可选空降助手的公开查询协议与服务 |
| [Star History](https://github.com/star-history/star-history) / [contributors-img](https://github.com/lacolaco/contributors-img) | README 的 Star 趋势与贡献者展示 |

参考项目的具体采用范围见[参考文档](docs/references.md)，资源、字体和原生组件的来源及许可范围见[第三方说明](THIRD_PARTY_NOTICES.md)。

## Star 趋势

如果 BiliSail 对你有帮助，欢迎点亮 Star，支持项目持续完善。

<a href="https://www.star-history.com/?repos=CKopoer%2FBiliSail&amp;type=date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=CKopoer/BiliSail&amp;type=date&amp;theme=dark">
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=CKopoer/BiliSail&amp;type=date">
    <img src="https://api.star-history.com/chart?repos=CKopoer/BiliSail&amp;type=date" alt="BiliSail Star 数量随时间的变化趋势">
  </picture>
</a>

## 许可与第三方资源

本项目尚未确定开源许可证。第三方依赖与素材保留各自许可和权利范围，公开源码不代表所有资源均已取得再分发授权。

部分参考图标目前仅记录了本机预览的采用范围，对外发行前仍需核实；原生播放器及其子依赖的许可材料也需单独归档。详见[第三方来源与分发检查](THIRD_PARTY_NOTICES.md)及[资源来源](assets/README.md)。
