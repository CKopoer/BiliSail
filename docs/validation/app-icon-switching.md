# 应用图标切换

日期：2026-10-30；2026-10-31 补充 Dock 尺寸、侧边栏与 Windows Shell 同步。

## 行为与边界

设置外观分类仅提供“哔帆”和“粉红小电视”，默认哔帆，不提供蓝色选项或蓝色素材。小电视使用独立 [SVG](../../assets/branding/bilibili_source.svg) 与 [1254px 渲染图](../../assets/branding/bilibili_pink.png)，来源、摘要和权利边界见[品牌说明](../../assets/branding/README.md#可选图标2026-10-30)。

| 平台 | 生效范围 | 保留的安装资源 |
| --- | --- | --- |
| Android | 两个 activity-alias 的桌面启动图标；API 33 起原子切换，旧系统先启用目标再禁用旧别名，主 Activity 不禁用 | 包管理器中的应用图标、旧手动固定入口可能仍使用安装图标；桌面可能延迟刷新 |
| iOS/iPadOS | 通过 `setAlternateIconName` 切换主屏幕图标，Xcode 为 iPhone/iPad 打包备用图标 | 系统负责提示及刷新 |
| Windows | 运行窗口及任务栏的 Shell 图标属性，新播放窗口沿用；EXE/MSI 同步当前用户的已有开始菜单入口 | EXE、安装包、MSIX 的开始菜单资源、已有固定任务栏入口及其他快捷方式；Shell 最终显示仍需逐安装类型验收 |
| macOS | 运行中的 Dock 图标；哔帆恢复系统默认，粉红小电视按专用 ICNS 和留白应用 | 应用 bundle、访达、启动台 |
| Linux | GTK 窗口图标与随后新建窗口的默认图标 | 应用菜单与 `.desktop` 图标；Wayland/桌面环境可忽略窗口图标 |

不修改已安装二进制或应用 bundle。Windows 仅处理本应用约定路径、指向当前 EXE 的开始菜单入口，不扫描或修改其他用户快捷方式。沿用根应用 MethodChannel，未增加 Pub 依赖，四个独立包不感知业务图标。

纯 Dart 契约为 `lib/domain/app_icon.dart`，平台适配为 `lib/core/platform/app_icon_service.dart`，由 app 组合根注入设置控制器。`AppSettings.appIcon` 存入 `preferences.v1`，快照 schema 递增到 34，SQLite 表结构及数据库版本保持不变。缺失/非法值回退哔帆，恢复默认也恢复图标。

图标变更串行完成系统应用与设置保存后才发布选中值；失败时尝试恢复原生图标，后续主题等设置写入只合并已提交的图标，避免重新写入失败选择。移动端启动读取操作系统实际保留的选择并同步快照，避免 iOS 重复改图标提示，也修复原生完成而 SQLite 提交中断的状态；桌面启动按保存值重新应用。图标恢复失败保留其他设置并在选项中提示重试。

Android 正式包与 `.test` 开发包使用各自 packageName，别名类名固定在生产 namespace；不访问其他包。首次从旧版本升级时，桌面对旧 MainActivity 固定入口的处理及位置保留需实机验收。

## Windows Shell 同步（2026-10-31）

此前仅发送 `WM_SETICON`，没有向 Shell 指定任务栏分组图标。现在 [Shell 适配器](../../windows/runner/shell_app_icon.cpp) 通过 `SHGetPropertyStoreForWindow` 设置 `System.AppUserModel.RelaunchIconResource`，普通 EXE 同时设置重启命令和显示名，最后设置 `System.AppUserModel.ID`。微软明确说明[提交 ID 会通知任务栏刷新，其他属性须先设置](https://learn.microsoft.com/en-us/windows/win32/properties/props-system-appusermodel-id)。图标直接引用 EXE 中已有的 `101/102` 资源，无需覆盖 EXE 或额外导出 ICO。

- 普通 EXE 的 ID 按安装路径保持稳定，同一安装往返换图标不改变身份，原地升级保留分组；不同开发/安装目录互不合并。MSIX 通过 `GetCurrentApplicationUserModelId` 保留系统包身份，避免破坏启动和分组。包的任务栏最终显示可能仍由注册图标决定，不能把属性提交成功当作 MSIX 视觉验收通过。
- 开始菜单只检查 `FOLDERID_Programs` 与 `FOLDERID_CommonPrograms` 下的 `BiliSail/BiliSail.lnk`，并核对目标文件身份。没有入口则不新建；入口指向另一安装或开发构建则跳过，不修改其目标。用户自行改名、移动的入口不在此次范围。
- 个人偏好写入当前用户入口。全用户入口通过标准 `IPersistStream` 克隆为同相对位置的当前用户入口，保留参数、工作目录和其他属性；全用户原件不写入，不提权、不影响其他用户。当前用户副本属于快捷方式，卸载另一安装后可能需要用户手动清理；本轮未扩大 MSI 卸载逻辑去删除用户副本。
- 使用 [`IShellLink::SetIconLocation`](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ishelllinkw-seticonlocation) 与属性存储更新当前用户入口，经临时文件保存、原子替换后发送定向 [`SHChangeNotify`](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shchangenotify)。保存失败保留原入口并回报失败，沿用设置控制器的原生/SQLite 保存失败回退。
- MSIX 的开始菜单图片来自签名包清单。[包内资源不允许运行时写入](https://learn.microsoft.com/en-us/windows/uwp/porting/desktop-to-uwp-behind-the-scenes)，本轮不篡改包、不创建伪装的额外入口。已有固定任务栏快捷方式也不修改，不调用未公开的固定接口、删除图标缓存或重启 Explorer。

原生回归入口为 [tool/test-windows-app-icon.ps1](../../tool/test-windows-app-icon.ps1)，使用隔离的临时目录和真实 Shell COM 接口，覆盖缺失入口、只读全用户入口、当前用户副本、参数保留、恢复默认、目标锁定时保留原件与临时文件清理、其他安装隔离、MSIX 跳过，以及真实窗口属性和稳定 ID 的反复切换。它不写真实开始菜单或用户设置；不能代替 Shell 视觉验收。

本轮验证：原生 Shell 回归、Windows `desktop_app_icon_test` 集成测试及调试热重载通过，未发现运行时错误。另在已开启开发者模式的本机注册独立全信任测试包，确认实际包身份识别及三次图标属性提交成功，随后注销该测试包，没有修改正式 MSIX 的安装、凭据或设置。该探针仅验证包环境下的 API，不代表任务栏/开始菜单最终图像已验收。

`tool/check.ps1 -SkipPub` 通过：根应用 3716 项通过、13 项 Windows 符号链接权限跳过；`bili_api` 498、`bili_player` 105、`bili_danmaku` 145、`bili_mux` 5 项通过。mux 另有 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计原生覆盖；格式、静态分析与打包边界检查通过。日志为 `build/app-icon-shell-check.log`。当前工作区含其他同期修改，本轮只调整图标适配器、原生回归、外观说明和本文。

普通 `lib/main.dart` 的 Windows Release 构建通过，产物为 `build/windows/x64/runner/Release/bilisail.exe`；日志 `build/app-icon-shell-release.log`。普通入口 Debug 构建、启动及最终热重载通过，未发现运行时错误，已通过 Flutter daemon 正常退出本轮调试进程；日志 `build/app-icon-shell-final-run.log`。未重新制作或安装正式安装包。

未验证：新正式 MSIX、EXE/MSI 的实际 Shell 图像、已固定入口、全用户/当前用户菜单合并显示、卸载与安装目录迁移。其他四个平台的运行行为未改动，本轮未进行其构建和设备验证。

## Dock 尺寸与侧边栏同步（2026-10-31）

用户反馈重新应用后图标偏大，粉红小电视切回哔帆时 Dock 中的哔帆也变大。原代码对两种图标都直接设置 1254px PNG，未恢复安装时的图标路径。现在哔帆改为设置 `NSApp.applicationIconImage = nil`，遵循 [AppKit 的恢复语义](https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage)，启动恢复、显式切回与保存失败回退共用此行为，不再传输默认 PNG。

粉红小电视改为 [macOS 专用 ICNS](../../assets/branding/bilibili_pink_macos.icns)：1024px 透明画布居中绘制 820px 图稿，各边留 102px，包含 16/32/64/128/256/512/1024px 七种像素尺寸及 11 个 1×/2× 表示，原生固定 512pt 逻辑尺寸。ICNS 中各表示从同一画布独立缩放，不从上次 Dock 图像重采样，重复切换不会累计缩放。其他平台及已安装的默认图标资源保持原样。

侧边栏由 app 组合根把 `AppSettings.appIcon` 传给 `BiliAppShell`，顶部标识复用枚举的图片路径。仅在系统切换和持久化都成功后跟随设置更新，启动恢复与恢复默认同步生效；图标框保持 36 × 36，工作区页面和导航状态保留。

本轮已通过：资源检查共 77 项（增加 ICNS 七种像素尺寸、全部表示与带留白源图的像素核对）；紧凑/展开侧栏两项组件回归覆盖已保存粉红图标、反复切回哔帆与再切换、固定尺寸和页面元素保留；原生通道测试增加 macOS 默认恢复不传 PNG 的重复切换用例。

`tool/check.ps1 -SkipPub` 通过：根应用 3641 项通过（13 项 Windows 符号链接权限跳过），`bili_api` 497、`bili_player` 99、`bili_danmaku` 136、`bili_mux` 5 项通过。mux 另有 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过；格式、静态分析和打包边界检查通过。已检查两份更新文档的 23 个本地链接与 `git diff --check`。

Windows 普通入口 Debug 构建通过，随后用同一产物启动并热重载成功，未发现运行时错误；检查后正常退出本轮启动的进程。首次调试进程在热重载前断开，后一次运行完成验证，不将首次断开算作通过。

当前主机为 Windows，无法执行 AppKit 原生构建或实测 Dock 尺寸；需要用新 macOS 构建复核启动、两种图标往返切换及不同 Dock 大小/Retina 显示。

## 首轮验证（2026-10-30）

- `uv run --with pillow==12.3.0 python tool/check_app_icons.py` 通过：共 70 项资源检查，包含两套 Android 五密度、两套 ICO 的 16/24/32/48/64/128/256px、两套 iPhone/iPad 全部声明尺寸，以及默认 macOS 七尺寸和 Linux 256px；PNG 像素与源图缩放一致，iOS 为白底不透明 RGB。运行时两张原图均为 1254px RGBA。蓝色文件已移除。
- `tool/check.ps1 -SkipPub` 通过：格式、静态分析、打包边界脚本；根应用 3633 项通过、13 项因 Windows 符号链接权限跳过；`bili_api` 496、`bili_player` 99、`bili_danmaku` 118、`bili_mux` 5 项通过。mux 的 10 项原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。
- 新增 11 项定向测试覆盖旧快照和非法值、系统保留状态恢复、图标初始化失败隔离、原生切换失败、保存失败回退、并发主题保存与恢复默认；原生通道测试覆盖五个平台的方法和图像参数。
- Windows Debug 构建、`flutter test integration_test/desktop_app_icon_test.dart -d windows` 通过：点击粉红小电视、原生调用、数据库持久化、控制器重新加载及恢复默认；测试数据库使用内存，不写用户设置。普通 `lib/main.dart` 入口重新构建启动、热重载成功，未发现运行时错误。
- Android arm64 开发 Release 构建通过，产物为 `build/development/android-arm64/BiliSail-test-arm64-release.apk`（普通 `lib/main.dart`、AOT、`dev.bilisail.bilisail.test`、BiliSail 测试版、不可调试、本机开发签名），脚本已核验包名、版本、签名及 SHA-256，未连接设备、未安装。首次构建期间同时进行 Windows Debug 构建，触发 dev-only `integration_test` 插件注册干扰；随后顺序执行 `tool/build-android-development.ps1 -Mode Release -SkipMuxBuild`，由 Flutter 自身重新生成注册文件后通过，未手改生成物。Android mux 资产已由本轮第一次构建脚本准备。
- 已检查相关文档的 206 个本地链接与 `git diff --check`。
- 对最终开发 Release APK 另用 `aapt dump xmltree/resources` 检查两个别名、默认启用状态和目标 Activity；从 APK 解码两套共 10 张原生图标，48/72/96/144/192px 均保留，alpha 与浅/深背景上的可见像素均与各自源图缩放一致（打包工具会归零少数全透明像素的隐藏 RGB），确认资源压缩没有移除备选尺寸。

未验证：Android 实机桌面切换、旧版覆盖升级后的固定图标和位置；iPhone/iPad、macOS、Linux 的原生构建与设备显示；Windows 固定任务栏/桌面快捷方式缓存和跨 DPI 显示。Windows 集成测试证明原生调用和选择状态闭环，不能代替各系统 Shell 视觉验收。没有修改播放输出或测量播放性能。
