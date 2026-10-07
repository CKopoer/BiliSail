<p align="center">
  <img src="assets/branding/app_icon.png" width="144" height="144" alt="BiliSail 哔帆应用图标">
</p>

<h1 align="center">BiliSail · 哔帆</h1>

<p align="center">
  专注观看体验的跨平台 Bilibili 第三方客户端<br>
  基于 Flutter 与 Dart，面向 Windows、Android 和 macOS
</p>

<p align="center">
  <a href="https://github.com/CKopoer/BiliSail/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/CKopoer/BiliSail/ci.yml?label=CI" alt="CI 状态"></a>
  <a href="pubspec.yaml"><img src="https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fraw.githubusercontent.com%2FCKopoer%2FBiliSail%2Fmaster%2Fpubspec.yaml&amp;query=%24.version&amp;label=version&amp;color=fb7299" alt="源码版本（pubspec.yaml）"></a>
  <a href="https://github.com/CKopoer/BiliSail/releases"><img src="https://img.shields.io/github/v/release/CKopoer/BiliSail?include_prereleases&amp;sort=date&amp;label=release&amp;color=fb7299" alt="最新公开发布版本（含预发布）"></a>
  <a href="docs/validation/ci-cd.md"><img src="https://img.shields.io/badge/Flutter-3.47.6-02569B?logo=flutter&amp;logoColor=white" alt="Flutter 3.47.6"></a>
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

BiliSail（哔帆）以视频、影视和直播观看为核心，提供单／多标签浏览、原生播放、弹幕、云端观看历史与本地续播，以及下载队列和离线播放。界面借鉴 BiliLite 的轻量桌面布局，结合自适应网格、视频卡片悬停预览、播放详情分栏和可配置快捷键。

当前处于预览阶段，源码版本以 [pubspec.yaml](pubspec.yaml) 为准，最新公开发布版本见 [GitHub Releases](https://github.com/CKopoer/BiliSail/releases)。截至 **2026-10-07**，已公开提供 Windows x64、Android arm64 和 macOS arm64 预览包，三端 CI 构建与打包已有通过记录；运行与功能实测主要在 Windows 上进行，完整三端验收仍在推进。具体状态见下方平台表及[验证文档](docs/README.md)。本项目为独立的第三方客户端，与哔哩哔哩官方无隶属关系。

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
| 内容浏览 | 推荐、热门、分区、排行榜；动态、视频动态、番剧、国创、放映厅和直播；自适应卡片网格、自动分页与列表位置保留 |
| 视频卡片 | 悬停封面放大与静音视频预览、添加稍后再看、操作菜单；推荐反馈保留原卡片位置并支持撤销 |
| 搜索 | 综合、视频、番剧、影视、直播、专栏和用户七类搜索，支持对应排序、筛选与自动分页 |
| 视频与影视 | DASH 音视频分轨播放，分 P、合集与选集、合集订阅、稍后再看队列；清晰度、编码与 CDN 偏好、倍速、音量、全屏、章节与进度条缩略图 |
| 直播 | HLS / FLV、可用清晰度、实时聊天与表情、画面弹幕、Super Chat 展示、用户主页跳转及弹幕发送入口 |
| 弹幕与字幕 | 滚动、顶部、底部弹幕，暂停与缓冲冻结、seek 重定位；样式、密度与本地过滤配置，字幕 cue 显示 |
| 账号与个人空间 | 扫码登录、内嵌官方网页密码／短信登录、系统安全存储；用户主页、关注分组、收藏夹查看与编辑、追番、追剧、稍后再看及消息／私信 |
| 评论与动态互动 | 最热／最新评论、楼中楼、表情与图片、作者装扮、服务端提供的 IP 属地、正文链接与时间点跳转；视频点赞／投币／收藏，动态点赞、评论、复制链接与转发 |
| 导航与界面 | 单／多标签模式与平台默认值、独立播放标签及可选并发播放、访问顺序回退、顶部分类横向滚轮、紧凑播放布局、桌面平滑滚动、键盘与鼠标侧键配置、图片缓存 |
| 历史与续播 | 当前账号云端观看历史分页；登录点播上报云端进度，记住进度开启时本地优先、云端补充；新点播继承本次运行中最近选择的倍速 |
| 下载与离线 | 分 P／剧集多选、画质与编码、队列暂停/继续/重试、断点和重启恢复、文件校验；本地音视频分轨、弹幕与字幕播放 |
| 个性化 | 明暗主题、内置／系统字体、播放、弹幕、字幕和下载设置；手动及每日首次启动更新检查；可选空降助手，默认关闭 |

上表描述已接入的功能，在线和平台验证范围见[文档索引](docs/README.md)。部分能力仍需进一步验收：

- Windows 官方登录窗口打开及关闭重开、现有登录会话的动态／评论只读请求已有验证；三种登录方式的完整账号闭环、部分私有列表在线分页，以及投币、收藏、评论／私信／动态转发等真实写操作仍需逐项验收。互动写请求只由明确的用户操作触发，不自动重试。详见[登录验证](docs/validation/password-sms-login.md)与[动态互动验证](docs/validation/dynamic-interactions.md)。
- 云端观看历史列表和云端进度读写仍需真实账号验收；云端进度由用户播放动作及周期观察触发，具体边界见[云端观看历史](docs/validation/cloud-watch-history.md)和[云端进度验证](docs/validation/cloud-playback-progress.md)。
- Windows 已验证游客公开视频下载与本地分轨离线播放；会员影视下载、长视频断网／休眠恢复和 Android/macOS 设备离线播放待验。Android 退入后台会主动暂停下载，尚未实现系统后台下载服务。详见[下载与离线播放](docs/downloads.md)。
- 字幕正文与离线字幕显示已通过合成 fixture 验证，在线样本尚未取得可用字幕；Windows 悬停预览已验证首帧与 5 秒向前预读窗口，Android/macOS 原生预览仍待验。详见[悬停预览验证](docs/validation/video-preview-loading.md)。
- 部分公开视频准备时间较长，排行榜可能受到服务端风控；Windows 辅助功能场景的原生崩溃防护仍需持续回归。详见[首版记录](docs/validation/m0-results.md)和[播放错误排查](docs/validation/native-playback-errors.md)。

应用默认不添加自动遥测。空降助手启用后会查询独立第三方服务，不携带 Bilibili 账号凭据，也不自动上报。

## 平台与开发状态

| 平台 | 目标架构 / 系统 | 仓库记录的验证状态 |
| --- | --- | --- |
| Windows | x64 / Windows 10 1809 及以上 | 本地与 CI 构建、MSIX 打包／测试签名通过；游客视频／影视／直播、受控多标签并发和离线分轨播放已有原生验证，本机已有 MSIX 安装运行记录；新版安装、卸载和升级待完整回归 |
| Android | arm64 / Android 7.0（API 24）及以上 | 本地与 CI 构建 APK 通过，固定 release 签名与单 arm64 ABI 校验通过；真机运行、播放、离线下载和覆盖升级待验 |
| macOS | arm64 / macOS 12.0 及以上 | CI 的 arm64 构建、架构校验和 DMG 打包通过；设备启动、原生播放、安装及 Gatekeeper 验收待验 |

2026-10-07 的 [CI 通过记录（提交 `3b8ed05`）](https://github.com/CKopoer/BiliSail/actions/runs/37591479657)覆盖根应用与三个包的检查及三端构建／打包。各项运行证据见[首版实测](docs/validation/m0-results.md)、[影视与直播播放](docs/validation/content-playback.md)、[多标签并发播放](docs/validation/multi-tab-playback.md)、[下载与离线播放](docs/downloads.md)和[构建打包记录](docs/validation/ci-cd.md)。首版记录保留历史快照，后续专项记录补充当前能力；构建成功与实机验收分别记录，预览版尚未完成 M0 三端验收。

后续重点：

- 补齐三端原生播放、扫码／密码／短信登录、安全存储和安装升级验收。
- 验收真实账号下载、Android/macOS 离线播放与系统后台边界；验证云端观看历史列表及云端进度真实账号读写。
- 逐平台接入并验证后台音频、媒体键和画中画（PiP）。

完整阶段安排见[实施与验收](docs/implementation-plan.md)。

## 下载与安装

安装包入口：[GitHub Releases](https://github.com/CKopoer/BiliSail/releases)。

提供三个平台的安装包、构建信息及 SHA-256 校验文件。也可按[源码运行说明](#从源码运行)自行构建。

| 平台 | 预览包格式 | 安装说明 |
| --- | --- | --- |
| Windows x64 | `.msix`/`.msi`/`.exe`，附签名公钥证书 `.cer` | 使用测试签名时，需要先信任对应证书；具体步骤见 [MSIX 签名与安装](docs/validation/ci-cd.md#windows-msix-签名与安装) |
| Android arm64 | `.apk` | 旧版 0.3.0+1 包使用临时 debug 签名；后续非 PR 构建已改用固定 release 密钥，跨签名切换与覆盖升级说明见 [Android 签名](docs/validation/ci-cd.md#android-固定签名与覆盖升级) |
| macOS arm64 | `.dmg` | 打开后将 `BiliSail.app` 拖到 `Applications`；当前配置使用 ad-hoc 签名，尚未完成 Developer ID 签名与公证 |

GitHub Actions 的 **CI** 执行根应用和三个包的检查，并按平台构建预览产物；维护者可手动运行 **Release preview** 创建预览 Release 草稿，再公开发布。Release 和 CI 构建包的签名种类以各自的 `build-info.json` 为准。触发方式、产物校验与签名配置见 [CI/CD 说明](docs/validation/ci-cd.md)。

CI 和 Release 构建的 Windows 产物同时包含 `.msix`、`.msi` 和 `.exe` 安装包，均附 SHA-256；MSI 与 EXE 使用同一安装链，任选一种安装。MSI 向导提供安装目录页，EXE 可通过 **Options → Browse** 选择目录，后续升级默认沿用原目录，详见 [Windows MSI 与 EXE](docs/validation/ci-cd.md#windows-msi-与-exe)。已发布版本的文件不会因工作流修改而自动补齐。

## 从源码运行

### 环境要求

项目固定使用 **Flutter 3.47.6 stable / Dart 3.13.5**。直接依赖采用精确版本，根应用和各包均保留锁文件。

Windows 开发还需安装 **Visual Studio 2022** 的“使用 C++ 的桌面开发”工作负载及 Windows SDK，并将 NuGet CLI 加入 `PATH`（内嵌网页插件构建使用）。Windows 密码／短信登录需要 WebView2 Runtime；来源与平台边界见[登录验证](docs/validation/password-sms-login.md)。Android 和 macOS 的构建需各自的工具链，macOS 构建需在 macOS 主机上执行。

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

设置“关于”提供项目 GitHub 地址和“检查更新”。每天首次打开应用时会自动检查已发布版本（包含预览版）；发现新版本后弹窗提示，点击“前往 Release”可查看说明并下载。自动检查失败时保持安静，可随时手动重试；应用不会自动下载或安装更新。

桌面工作区支持同时打开首页、搜索、视频、影视、直播、用户、历史、消息、下载和设置等标签。首页固定，最多打开 16 个标签；标签状态保留至本次运行结束。每个播放标签拥有独立播放器，切换到普通页面时媒体继续播放；是否允许不同播放标签同时播放由下方设置控制。关闭播放标签只停止并释放该标签的播放器。

### 常用快捷键

| 操作 | 默认快捷键 |
| --- | --- |
| 播放 / 暂停 | `Space` |
| 前进 / 后退 | `→` / `←`，默认 3 秒 |
| 临时加速 | 长按 `→`，默认 3 倍速 |
| 提高 / 降低音量 | `↑` / `↓` |
| 切换 / 退出全屏 | `F`、`F11` 或 `Enter` / `Esc` |
| 收起 / 展开视频信息 | `W` 或 `F12` |
| 开关弹幕 / 字幕 | `D` 或 `F9` / `F6` |
| 降低 / 提高倍速 | `F1` 或 `;` / `F2` 或 `'` |
| 切换 1 / 2 倍速 | `Ctrl+1` |
| 上一 / 下一分 P | `Z`、`N` 或 `,` / `X`、`M` 或 `.` |
| 刷新当前页面 | `Ctrl+R` 或 `F5` |
| 新建 / 关闭标签 | `Ctrl+T` / `Ctrl+W` |
| 下一个 / 上一个标签 | `Ctrl+Tab` / `Ctrl+Shift+Tab` |

设置 → 外观 → 页面导航模式可选择“单标签页、多标签页”。Windows 和 macOS 默认多标签页，Android 默认单标签页；手动选择会保存，调整窗口大小不会切换模式。Android/iOS 隐藏顶部工作区横条及返回／首页图标，使用系统返回；Windows/macOS 保留横条，单页显示返回、标题和首页入口，多页显示标签栏。返回按访问顺序回退；`Ctrl+W` 在单标签页中返回上一页。首页频道、子标签和设置分类超出宽度时，可触摸横向滑动或在栏内使用鼠标滚轮查看后面的入口。详见[单标签导航与顶部滚动](docs/validation/single-page-navigation.md)。

设置 → 播放 → “允许多个标签页同时播放”默认开启，仅在多标签页模式下生效。开启时，不同视频、影视或直播标签可同时播放，打开新播放标签不会中止旧媒体流；每个标签内仍只有一个播放器。关闭开关或使用单标签模式时只允许一个会话播放，进入另一播放页会暂停旧会话并保留进度和播放意图。开关立即生效，恢复允许并发时继续被导航暂停的会话，手动暂停的会话保持暂停；单标签模式禁用开关并保留选择，关闭标签只释放该标签的播放器。详见[多标签并发播放](docs/validation/multi-tab-playback.md)。

单击视频画面切换控制栏，双击切换全屏。快捷键可在设置中修改、停用或恢复默认，支持组合键和鼠标侧键。输入时保留编辑，明确绑定的侧键或 Ctrl／Meta 关闭组合仍可关闭当前标签；普通弹窗隔离底层，全屏播放保留当前标签命令。固定标签循环和图片查看器操作不受快捷键总开关影响。设置中的本次运行诊断可查看输入匹配与拦截结果，关闭即清空。当前结构与验证边界见[快捷键重构实施记录](docs/shortcut-system/implementation-results.md)。历史操作见[快捷键与富评论](docs/validation/shortcuts-rich-comments.md)、[设置与侧键](docs/validation/settings-tabs-fonts.md)和[标签播放行为](docs/validation/profile-playback-rates.md)。

视频卡片悬停时放大封面并静音预览，移开后停止；预览持续播放，并维持当前位置之后约 5 秒的向前预读窗口。稍后再看页面通过菜单管理条目，从该列表开始播放会保留可折叠队列。点播中选择的新倍速会由后续视频／分 P／影视剧集继承，重启应用后使用设置中的默认值；长按临时加速不改变这份选择。

视频与影视播放页可按分 P／剧集多选下载，选择当前账号可用的画质与编码，在下载中心暂停、继续、重试或打开已完成项。重启后保留任务并等待手动继续；离线文件与普通图片缓存分开，清理图片缓存不会删除离线媒体。完整使用与验收边界见[下载与离线播放](docs/downloads.md)。

## 开发与文档

### 工程结构

```text
lib/
├── app/                  # 组合根、路由、主题与工作区
├── core/                 # 存储、安全凭据、取消与平台能力
├── domain/               # 共享领域类型
├── features/             # 按 domain / data / application / presentation 分层
└── shared/               # 共用数据映射与 ui 组件
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
| [下载与离线播放](docs/downloads.md) | 下载队列、断点恢复、文件校验与离线播放边界 |
| [快捷键实施记录](docs/shortcut-system/implementation-results.md) | 输入作用域、页面刷新、键位录制与验证 |
| [CI/CD 与安装包](docs/validation/ci-cd.md) | 三端构建、MSIX／APK／DMG、签名与安装说明 |
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
