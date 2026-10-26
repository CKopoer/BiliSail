# iOS 与 Linux 工程、CI 和预览包

日期：2026-10-26。按用户要求增加平台工程及 GitHub Actions；首次接入时未在本地构建 iOS／Linux 应用或安装包。后续 Linux 远端首次失败及修复见文末，构建和设备验收分别记录。

## 平台与产物

| 目标 | 主机 | 最低范围 | 产物 |
| --- | --- | --- | --- |
| `ios-arm64` | `macos-15` / Apple Silicon / Xcode / CocoaPods | iOS 15，iPhoneOS arm64 | `BiliSail-<version>-ios-arm64-unsigned.ipa` |
| `linux-x64` | `ubuntu-24.04` / GTK 3 / libsecret / libmpv | AppImage 基线 Ubuntu 24.04；Flatpak Freedesktop 25.08；X11／XWayland | `BiliSail-<version>-linux-x64.AppImage` 与 `.flatpak` |

两个平台均复用 [CI](../../.github/workflows/ci.yml) 的并行检查、原生 mux 回归及 [build-release.ps1](../../tool/build-release.ps1)。push／PR 默认构建全部五个平台，手动 CI 和 [Release preview](../../.github/workflows/release.yml) 通过 `enable_ios`、`enable_linux` 分别选择。构建在检查成功后启动，所选目标全部成功才创建 Release 草稿；继续使用 `github.token`，无需增加 GitHub secret。原有 Android、Windows 和 macOS 签名方式沿用现有配置。

每个目标保留 `.build-info.json`、SHA-256 文件和 `.mux-source.zip`；Actions artifact 保留 14 天。Release 不自动公开，旧 Release 不会自动补上新增包。

## iOS

全能签 BiliMux Info.plist 校验失败的原包证据、兼容性处理与验证限制见 [重签名排查](ios-resigning.md)。

- [工程](../../ios/Runner.xcodeproj/project.pbxproj) 与 Linux runner 均由固定 Flutter 3.47.6 模板生成。iOS bundle ID 为 `dev.bilisail.bilisail`，显示名 BiliSail；Swift 入口注册原生插件，使用 CocoaPods，与根配置的禁用 SwiftPM 保持一致。
- `flutter build ios --release --no-codesign` 构建真实设备 arm64 应用，再将 `Runner.app` 按 `Payload/Runner.app` 布局压缩。脚本核对版本名、构建号、bundle ID、主程序和必需 framework 的 arm64 架构，以及压缩包内的实际布局。
- [bili_mux](../../packages/bili_mux/README.md) 从已有固定 FFmpeg 源码构建独立的 iOS 动态 framework；通过 CocoaPods 嵌入，不借用播放器 FFmpeg。最低 iOS 15，暂不提供 simulator slice。媒体/CDN 可能提供 HTTP 地址，Info.plist 允许 ATS 非 HTTPS 请求，仍保留系统 TLS 证书校验。
- 安全存储继续使用系统 Keychain；[entitlements](../../ios/Runner/Runner.entitlements) 声明空的 Keychain access groups，不添加团队或共享组标识。后续安装签名须结合实际 provisioning profile 重新生成应用及 framework 签名和最终 entitlement。
- **GitHub Actions token 不能替代 Apple 开发者证书或 provisioning profile**。未签名 IPA 需自行签署才能安装；本轮没有配置 Apple 账号、上传 App Store 或承诺商店审核。[Flutter iOS 发布说明](https://docs.flutter.dev/deployment/ios)

## Linux

[GTK runner](../../linux/runner/my_application.cc) 使用系统原生标题栏。桌面窗口、全屏、快捷键、音视频和弹幕沿用共享能力；独立播放窗口目前仅在 Windows／macOS 开放，Linux 双标签在同一应用窗口中显示。

[package-linux.sh](../../tool/package-linux.sh) 处理 Flutter 已生成的完整 bundle：

1. 保留可执行文件相邻的 `lib/` 和 `data/`，显式添加由播放器 `dlopen` 的 `libmpv.so.2`；linuxdeploy 收集动态依赖，GTK hook 收集其资源及加载器。不把宿主 GPU 驱动目录作为应用资产。
2. linuxdeploy 固定 `1-alpha-20251107-1`，GTK 部署脚本固定提交 `7a3fbc31a9e5075073ff8790f26effbac5f84453`；两者下载后校验 SHA-256 才执行。`APPIMAGE_EXTRACT_AND_RUN=1` 使 CI 不依赖 FUSE 挂载。
3. [校验脚本](../../tool/linux-package-validation.py) 核对应用版本、`libmpv.so.2` 和动态依赖，并保留 Ubuntu binary／source 包版本及版权文本。再从同一 AppDir 生成 AppImage 和 Flatpak，在临时 CI runner 安装导出的 Flatpak 后，使用实际 Runtime 另运行一遍动态依赖校验，缺库即失败，避免 SDK 的额外库掩盖问题。该检查不等于真实播放或启动通过。
4. [Flatpak manifest](../../linux/packaging/dev.bilisail.bilisail.json) 使用 Freedesktop 25.08 Runtime／SDK。只开放网络、X11、IPC、PulseAudio、DRI 和 Secret Service，不授予宿主文件目录权限。Linux 默认离线目录为应用支持目录下的 `offline/`，数据库、缓存与下载均可在沙盒内持久保存；其他平台的默认下载位置沿用原值。

AppImage 的宿主要求由 Ubuntu 24.04 构建基线决定，不能保证旧发行版运行。图形暂按 X11／XWayland 打包，未承诺纯 Wayland、Linux arm64 或所有 GPU 的硬件解码。[linuxdeploy 文档](https://docs.appimage.org/packaging-guide/from-source/linuxdeploy-user-guide.html)

Flatpak 单文件不携带 Runtime。本地需先安装 Flatpak，并确保存在 Flathub remote；包内指定 runtime 仓库供解析依赖：[Flatpak 单文件说明](https://docs.flatpak.org/en/latest/single-file-bundles.html)。

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./BiliSail-<version>-linux-x64.flatpak
flatpak run dev.bilisail.bilisail

chmod +x ./BiliSail-<version>-linux-x64.AppImage
./BiliSail-<version>-linux-x64.AppImage
# 缺少 FUSE 时可用 --appimage-extract 后运行 squashfs-root/AppRun。
```

登录持久化要求桌面具有已解锁的 `org.freedesktop.secrets` 服务，例如 GNOME Keyring 或兼容的 KWallet。服务不可用或保存失败不能退回明文。Flatpak 与 AppImage 的数据目录可能不同，不自动迁移账号或下载文件。

## Linux 网页登录的明确降级

当前锁定 `flutter_inappwebview_linux 0.1.0-beta.1` 的上游实验实现依赖 WPE WebKit 和相应 backend，不是只安装 GTK 即可分发。本轮不引入该浏览器引擎及独立的 helper 进程打包链。

根应用使用显式的 [Dart 平台适配](../../linux/plugins/flutter_inappwebview_linux/lib/flutter_inappwebview_linux.dart) 覆盖该实现，没有复制上游代码或修改 Pub 缓存；Flutter 的生成器因此不注册其原生 CMake 插件。登录页面通过平台能力隐藏密码／短信入口，保留扫码和既有会话验证。其他平台继续使用上游 WebView；恢复 Linux 网页登录前须一起验证引擎、TLS、Cookie 元数据、账号隔离、helper 路径与沙盒权限。

## 验证边界

Windows x64／Flutter 3.47.6 本轮验证：

- `tool/check.ps1 -EnforceLockfile` 完整通过格式、统一分析、打包边界检查及 3357 项离线测试（根应用 2718、API 460、播放器 81、弹幕 93、mux 5）；10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。
- 随后调整 Linux 默认下载位置并增加平台适配检查后，`tool/check.ps1 -Stage Lint -EnforceLockfile` 及登录／下载目录的 24 项定向测试通过。下载目录测试在 Windows 验证原位置，在 Ubuntu CI 会检查应用支持目录分支。
- actionlint 1.7.12、PowerShell／Bash 解析、Python 编译检查、全部 32 种平台选择组合、两个新目标的错误主机拒绝、19 条 iOS 图标尺寸／RGB 配置、plist／entitlement／生成插件选择、Flatpak 权限、文档链接与 `git diff --check` 通过。根锁文件只替换 Linux WebView 平台适配来源，依赖版本及其他四份锁文件保持。
- 没有可连接的 DTD／调试应用，未执行热重载。

上述首次接入验证未执行 iOS／Linux 本地构建、远端新工作流、签名安装、图形启动、DASH 双轨、PGC／直播、下载封装、账号恢复、退出释放、硬解或性能验收。两个新平台的工程／CI 接入不代表这些设备能力已通过。

## 2026-10-26：Linux 许可证归属误匹配与依赖缓存

[CI 40214248464 的 Linux job](https://github.com/CKopoer/BiliSail/actions/runs/40214248464/job/121233229596) 在提交 `db982b7aaa545506e5484fae03f0ddef07778b01` 上完成 Flutter Release 编译，随后公共 AppDir 的许可证收集报错：`Distro license text missing: google-chrome-stable`。失败前约 5 分 21 秒，不是两个安装包构建成功的耗时，也不是 Flutter 编译失败。

原脚本按 `*/<库文件名>` 查询 dpkg 归属，同名库会把 runner 预装应用的私有副本也算入依赖，例如 `/opt/google/chrome/` 中的库。修复将归属查询限制为 Ubuntu x64 的 `/usr/lib/x86_64-linux-gnu/`、`/lib/x86_64-linux-gnu/`，再匹配包中实际库名；保留嵌套 GTK 模块和多归属解析，忽略 diversion 说明行。真实系统依赖仍必须附版权文本、binary/source 包名及版本，缺失时继续失败；没有通过忽略 Chrome 错误或关闭许可证校验放行。

[依赖安装脚本](../../tool/setup-linux-build.sh) 将 apt 包列表与网络重试／连接超时集中管理，从 Flatpak manifest 读取 Runtime／SDK 分支。[下载辅助脚本](../../tool/linux-downloads.sh) 保留原有固定版本及哈希，缓存命中重新校验，损坏条目重新下载，错误下载不发布为缓存。CI 对 `.deb`、固定打包工具和 Flatpak Runtime／SDK 分别恢复并在应用构建前保存；每周生成新键并允许同配置回退，缓存恢复后仍核对上游包和 Runtime 更新。缓存范围与失效条件见 [CI/CD](ci-cd.md)。

离线回归包含 Chrome／其他应用同名库排除、usrmerge 路径、嵌套模块、多归属、查询失败、真实许可证缺失，以及工具缓存首次下载、命中、损坏重下和哈希错误拒绝；已加入 CI 的 Lint job。

本轮验证：

- Windows 与 WSL 内实际 Ubuntu 24.04.4 的 12 项 Python 回归、4 项本地文件下载／缓存回归通过；Python 标准库 trace 统计校验脚本行覆盖率 93%。Ubuntu 真实 dpkg 查询和 Vulkan 版权文本／source 版本收集通过。
- 固定 linuxdeploy 下载通过，三份固定资源的 SHA-256 和缓存读取通过。WSL／Windows 直连 `raw.githubusercontent.com` 的文本下载遇到 TLS 连接中断，文本改由 GitHub 只读连接取得后核对既有固定哈希，没有关闭 TLS 或修改哈希。
- actionlint 1.7.12、Bash 语法、Python 编译、40 条相对文档链接与 `git diff --check` 通过。
- `tool/check.ps1 -SkipPub` 重跑完整通过格式、分析、打包边界脚本和 3430 项测试（根应用 2791、API 460、播放器 81、弹幕 93、mux 5）；10 项 mux 原生测试因未配置 `BILI_MUX_LIBRARY` 跳过。首轮根检查曾因 `build/native_assets/windows/sqlite3.dll` 缺失产生 46 项数据库测试失败；随后设置仓储文件的 42 项定向复测及全套重跑通过，没有为此修改应用或 SQLite 源码。

尚未复跑修复后的远端 CI、完整 AppImage／Flatpak 构建及设备启动；apt／Flatpak 缓存上传、命中和实际提速需新 CI 验证。本地脚本回归不替代这些验收。

## 同日补查：Linux 依赖下载偶发长时间低速

对照同一源码提交的两条运行：

- [push CI 的 Linux job](https://github.com/CKopoer/BiliSail/actions/runs/40214248464/job/121233229596)：apt 共新增 335 个包、升级 18 个包，175 MB 的 `.deb` 在 14 秒内下载完成（日志约 12.3 MB/s）；随后完成解包／配置。Flatpak Runtime、GL／Locale 扩展及 SDK 安装约 45 秒；依赖整个步骤从 UTC 17:05:12 到 17:06:54，约 1 分 42 秒。
- [Release 的 Linux job](https://github.com/CKopoer/BiliSail/actions/runs/40214401648/job/121233826103)：该依赖步骤从北京时间 01:07:42 到 01:37:43，实际耗时 30 分 1 秒。任务后续取消，日志归档后确认 apt 明确报告 `Fetched 173 MB in 28min 32s (101 kB/s)`；下载源为 `http://azure.archive.ubuntu.com/ubuntu`，`libsystemd-shared` 出现重试。其后 Flatpak 安装仍只约 45 秒，耗时差异几乎全在 apt 下载链路。28 分 32 秒中持续有包下载进度：例如 11.2 MB 的 cmake 相邻下载记录间隔约 141 秒，13.6 MB 的 libflite1 间隔约 186 秒。日志能确认低吞吐，不能进一步区分镜像节点与具体 runner 网络路由。

主要问题落在 apt 到 Azure 镜像的下载链路，额外的重复下载由此前缺失 Linux 依赖缓存放大。GitHub runner-images 维护者在 [issue 12949](https://github.com/actions/runner-images/issues/12949) 中确认过该镜像偶发低速；[官方 runner 配置](https://github.com/actions/runner-images/blob/main/images/ubuntu/scripts/build/configure-apt-sources.sh) 将 Azure 设为 priority 1、Ubuntu archive 为 2、security 为 3。[APT 镜像选择](https://manpages.ubuntu.com/manpages/noble/man1/apt-transport-mirror.1.html) 优先数值较低的条目，[HTTP 超时](https://manpages.ubuntu.com/manpages/noble/man1/apt-transport-http.1.html) 是连接／数据超时，不能作为整个下载的总时限。

因此在刚增加的缓存之外，加入 [镜像优先级调整](../../tool/linux-apt-mirrors.py)：仅在 hosted CI 的既有镜像列表上将官方 archive／security 提前、Azure 后移，保留签名验证、其他镜像和元数据，不安装额外第三方 Action。安装脚本增加四个阶段的分组和耗时输出。新增 6 项镜像优先级回归，与原有 12 项 Python 和 4 项下载缓存回归在 Windows／Ubuntu 24.04 均通过；actionlint、Python 编译、Bash 语法和更新后的 41 条相对文档链接通过。`tool/check.ps1 -SkipPub` 再次完整通过 3430 项测试，10 项 mux 原生测试按配置跳过。实际新镜像链路及缓存提速仍须新 CI 验证。

提交前另运行 `tool/check.ps1 -Stage Lint -EnforceLockfile`，五份锁文件的解析、格式、静态分析和打包边界检查通过。按用户后续要求，本次以源码版本 `1.2.1+3` 触发 Release，仅选择 Android、Windows、macOS、iOS，明确关闭 Linux；Linux 修复的远端完整打包与缓存命中继续保留为未验项。本次提交跳过重复的 push 矩阵，由手动 Release 运行全部检查及选中的四端构建，不修改工作流的平台默认值。

## 同日补查：Flatpak Runtime 校验静默失败

[CI #147 的 Linux job](https://github.com/CKopoer/BiliSail/actions/runs/40220618910/job/121252679168) 对应 `687a046bc3e01e09815fcafe1512c89a212328f7`。原始日志确认 Flutter Release 编译、AppImage 生成及 Flatpak 仓库导出完成，随后在安装及 Runtime 校验阶段仅报告 `bash failed: 1`。依赖缓存已命中，APT 安装耗时 35 秒；本次没有再出现旧的 Chrome 许可证错误。

原 Runtime 检查在 `sh -e` 中将 `ldd` 的输出捕获到变量；命令返回非零时，shell 会在打印错误之前退出。主程序的依赖输出又被写入沙盒临时文件，未传回日志。因此现有日志不能确定具体失败库或 ABI，不能据此宣称依赖问题已修复。

[Runtime 检查脚本](../../tool/linux-runtime-validation.sh) 现在通过标准输入在已安装应用的 Runtime 中执行，统一检查主程序和共享库，打印失败路径、退出码及完整输出。非零退出和 `not found` 都继续使任务失败；未跳过库文件或放宽依赖要求。检查回归沿用 CI 的 `test_linux_*.py` 入口。

本地 Debian 13 的 23 项 Python 回归及 4 项下载缓存检查通过；真实 GCC/ELF/ldd 探针验证完整依赖通过、移除共享库失败且显示缺失 SONAME。Shell 语法与 `git diff --check` 通过。本机没有 Flutter、PowerShell 和 Flatpak，未运行根检查脚本或完整 Linux 打包。具体 Runtime 失败原因仍待带诊断的新 CI 确认；这些检查不代表图形启动或实机播放验收。

### 诊断 CI 确认的两个根因

[诊断提交 5769b3f 的 Linux job](https://github.com/CKopoer/BiliSail/actions/runs/40257170639/job/121362968972) 明确报告：

- `org.gnome.desktop.sound.gschema.xml` 被 `*.so*` 匹配，`ldd` 返回 `not a dynamic executable`。Runtime 检查原先缺少宿主 AppDir 校验已有的 ELF 文件头筛选，数据文件导致误报。现仅对 ELF 运行依赖检查，主程序缺失或不是 ELF 仍报错。
- `/app/usr/bin/lib/libdartjni.so` 的 `libjvm.so => not found` 是真实缺依赖。锁定的 `path_provider_android 2.3.1` 传递引入 `jni 1.1.0`；后者作为桌面 FFI 插件，仅在发现 JDK 时生成 JNI 库并链接该 JDK。runner 安装了 JDK，宿主检查因而通过，但 Flatpak Runtime 不提供该 JVM。Linux 应用实际使用 `path_provider_linux`，源码没有 JVM 集成；在 Linux CMake 引入生成插件规则前设置 `CMAKE_DISABLE_FIND_PACKAGE_JNI`，使用上游支持的可选探测路径，不构建或分发这份 Android 传递依赖的桌面 JNI 库。Android 和其他平台配置不变，未修改 Pub 缓存、生成插件清单或锁文件，也未添加 JVM 运行时。

两份上游包归档的 SHA-256 均与 `pubspec.lock` 一致。本地用锁定 JNI 源码、系统 JDK 与 CMake 3.31.6 对照验证：默认配置生成 `libdartjni.so` 并链接 `libjvm.so`；禁用 JNI 探测后配置和构建成功，不生成该库。更新后 25 项 Python 回归通过，新增精确 XML 文件名误匹配及非 ELF 主程序拒绝用例；真实缺库和 `ldd` 非零返回仍失败。最终应用构建、Flatpak Runtime 检查和产物上传以修复提交的后续 CI 结果为准。
