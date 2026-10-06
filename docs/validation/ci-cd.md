# GitHub Actions CI/CD 与 MSIX

日期：2026-10-06。配置覆盖 Android arm64、Windows x64、macOS arm64；本地验证结果与远端、设备未测项分别记录。此流程交付预览构建，不表示 M0 三端验收或 M5 正式发行完成。

## 入口与分工

- [CI](../../.github/workflows/ci.yml)：替换原来的 `windows.yml`；分支 push、PR、手动运行时执行检查及构建，也供 Release 复用。
- [Release preview](../../.github/workflows/release.yml)：在 Actions 页面手动运行；可选择三个平台，全部所选构建通过后创建 **draft + prerelease** 并上传包、签名公钥证书、校验文件与第三方说明。不会自动公开发布。
- [检查脚本](../../tool/check.ps1)：CI 在 Ubuntu 使用 PowerShell 7 执行，先安装根应用和三个独立包的依赖，再分别运行格式、分析和离线测试。根分析会扫描子包，故子包开发依赖也须先安装。`-EnforceLockfile` 要求 pub 使用提交的锁文件及内容哈希。
- [构建打包脚本](../../tool/build-release.ps1)：各平台使用对应主机生成预览包，缺文件、原生命令失败、签名失败立即停止。已有同目标输出目录时拒绝覆盖，重新本地构建前先将其移走。

| 任务 | Runner | 产物与边界 |
| --- | --- | --- |
| 版本解析、根与三个包检查 | `ubuntu-24.04` | 无需真实账号，不自动运行在线或原生播放集成测试 |
| Android | `ubuntu-24.04`，Temurin JDK 17 | 仅 arm64 的 release APK；沿用工程临时 debug key，无正式签名 |
| Windows | `windows-2022`，Visual Studio C++ / Windows SDK | x64 MSIX，包含 EXE、全部原生 DLL/data 及 VC++ runtime；无需 MSI 或安装 EXE |
| macOS | `macos-15`，Apple Silicon / Xcode | arm64 `.app` ZIP，`ditto` 保留权限与链接；仅 ad-hoc 签名，未 notarize |
| Release 上传 | `ubuntu-24.04` | 合并本次所选平台的 Actions artifacts 后创建草稿 |

PowerShell 7 是跨平台 shell；Ubuntu 上复用 `.ps1` 不要求 Windows。Windows 原生构建需要 Windows 主机与 Visual Studio 工具链，macOS 原生构建需要 macOS/Xcode。macOS 在固定 SDK 中显式启用 `--enable-macos-arm64-only`，避免默认 universal 构建引入未承诺的 Intel 目标。参见 [Flutter Windows 构建](https://docs.flutter.dev/platform-integration/windows/building)、[GitHub runner 范围](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

Flutter 固定 **3.47.6 stable / Dart 3.13.5**；升级需同时调整工作流、检查/构建脚本并重新验证。根及各包保留各自 `pubspec.lock`，pub 缓存键包含锁文件哈希。Actions 使用已查询的提交 SHA，并以注释标明主版本。Android SDK/NDK 由该 SDK 的 Flutter Gradle 配置选择，AGP/Gradle 版本沿用工程；Xcode/系统映像仍由对应 runner 提供，不能据此宣称完全可重现的原生工具链。

CI 在工作流顶层固定 `PUB_HOSTED_URL=https://pub.flutter-io.cn`，与根应用及三个包锁文件中的 hosted URL 一致；检查、三端构建和 Release 复用流程均使用此包源。切换包源时须在同一包源下重新生成并验证四份锁文件，继续保留 `--enforce-lockfile`。

## 版本与产物

手动输入版本使用 Flutter 的 `x.y.z+N`，例如 `0.1.0+1`；留空取根 `pubspec.yaml`。脚本通过 `--build-name` 和 `--build-number` 传入，不改源码版本或锁文件。Windows MSIX 映射为 `x.y.z.N`，四段均不超过 65535。Android 使用 arm64 split APK，Flutter 自动将 versionCode 设为 `N + 2000`，因此 `N` 不超过 2099998000；实际 versionCode 同时写入 metadata。MSIX 升级要求递增包版本并保持 identity/publisher。当前草稿 tag 为 `v0.1.0+1`；已有同名 tag 时拒绝附加新构建，重跑草稿遇到冲突时也需使用新版本或显式处理旧草稿。

每个平台的 `artifacts/<target>/release/` 中包含：

- `BiliSail-<version>-<target>.apk`、`.msix` 或 `.zip`。
- Windows 包旁的 `.cer`，只含签名证书公钥。
- `.build-info.json`：源码 revision 与 `sourceDirty`、Flutter/engine/Dart 版本、目标、签名类型、runner image、根锁文件 SHA-256。
- 每个上述文件对应的 `.sha256`，格式兼容 `sha256sum -c`。

CI 的 artifacts 保留 14 天；Release 从同一运行下载，所选平台失败时不创建新草稿。不使用参考仓库的 WebDAV、NuGet ZIP、UWP manifest、Chocolatey 或 TLS 验证绕过逻辑。

构建前先 `pub get --enforce-lockfile`，随后保留 Flutter build 默认的 pub 阶段，并检查构建后锁文件哈希不变。在 Flutter 3.47.6 中，`--no-pub` 还会跳过 release 原生插件注册文件的重生成：本轮 Android 初次构建因此错误引用 dev-only `integration_test`。修正采用 SDK 自身的重生成流程，不手改 `GeneratedPluginRegistrant.java`。

仅指定 `--target-platform android-arm64` 时，该 SDK 仍会把插件的其他 ABI 库装入非 split APK。本轮检查发现 armeabi-v7a/x86_64 的 mpv/JNI 库，已增加 `--split-per-abi` 并在脚本中校验 APK 内只存在 `arm64-v8a`。

## Windows MSIX 签名与安装

[AppxManifest.xml](../../windows/packaging/AppxManifest.xml) 的 identity 为 `dev.bilisail.bilisail`，默认 publisher 为 `CN=BiliSail`；Windows 安装下限为 Windows 10 1809（build 17763）。`MakeAppx` 打包完整 Flutter Release 目录，`SignTool` 使用 SHA-256 签名。MSIX 图标在构建时从已有品牌 PNG 派生，不引入新资源或 Dart 依赖。

无签名 Secrets 时生成一年有效的临时自签证书，产物标记 `self-signed-preview`。安装前需要在测试机器上把对应 `.cer` 信任到 **本地计算机 → 受信任人**，再打开 `.msix`；这一步需要管理员权限。工作流只导出公钥，不上传 PFX、私钥或密码，打包结束后清理本次临时证书/私钥。每次运行的测试证书不同，不能视为长期可升级的正式发行链路。

使用固定签名证书时，在仓库 Actions Secrets 配置：

| 名称 | 内容 |
| --- | --- |
| `MSIX_CERTIFICATE_BASE64` | 带私钥的代码签名 PFX 的 Base64 |
| `MSIX_CERTIFICATE_PASSWORD` | 该 PFX 的密码；无密码 PFX 可留空 |

仓库 Actions Variable `MSIX_PUBLISHER` 可指定证书的完整 Subject，缺省为 `CN=BiliSail`；manifest Publisher 必须与证书 Subject 匹配。PR 构建始终使用临时测试证书，避免向 PR 提供正式私钥。已配置 PFX 无效、密码错误、证书过期或 publisher 不匹配时失败，不降级成测试签名。当前未接入可信时间戳；正式发行还需完善时间戳、证书续期与升级验证。参见 [Microsoft MSIX 证书](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)、[SignTool 签名](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool)。

Android 仍使用 runner 上自动生成的 debug keystore，多次运行不能保证相同签名或覆盖升级；macOS ad-hoc 签名不能替代 Developer ID / notarization。资源许可范围沿用 [第三方说明](../../THIRD_PARTY_NOTICES.md)，公开发布前仍需完成其待核实项。

## 验证记录

在本机 Windows 使用 Flutter 3.47.6 / Dart 3.13.5 完成；源码 HEAD 为 `4bcbfb0fe03315543b3dcc18730fed051af0cdbb`，含用户原有修改与本轮配置，metadata 的 `sourceDirty=true`，不能仅凭 HEAD 复现这份本地包。

| 检查 | 结果 |
| --- | --- |
| `tool/check.ps1 -EnforceLockfile` | 根应用与三个包的依赖、格式、分析和全部离线测试通过；锁文件无差异 |
| actionlint 1.7.12 / PowerShell parser | 两个工作流与两个脚本通过；actionlint 下载包按维护方 SHA-256 验证 |
| CI plan | 全平台、单平台选择通过；全关闭、错误版本格式、MSIX 数字溢出拒绝 |
| Markdown | 变更文档的 222 条本地链接有效；`git diff --check` 通过 |
| Windows release → MSIX | 最终构建、MakeAppx 验证/打包、SignTool 测试签名通过；包含完整原生运行目录与三个 VC++ runtime DLL，去除本地构建遗留的旧名称 EXE |
| MSIX 内容与签名 | manifest identity/version、58 个包条目、播放器库、CMS 数学签名、公钥证书匹配及 SHA-256 通过；无 PFX/私钥，临时签名证书清理通过。未向系统信任区安装证书，不代表已通过受信任发行证书链验证 |
| Android arm64 release | 最终 split APK 构建、包内 ABI 断言和 metadata 输出通过；初次 `--no-pub` 失败及非 split APK 包含额外 ABI 的修正见上文 |

本地产物位于 `artifacts/windows-x64/release/` 和 `artifacts/android-arm64/release/`，由 Git 忽略；前序尝试另行保留，工作流只上传最终 `release/` 文件。没有执行在线账号操作，没有修改相邻参考仓库或新增 Dart 依赖。

### 首次远端运行的包源修复

[CI #1](https://github.com/CKopoer/BiliSail/actions/runs/37405976185) 使用提交 `415b054698f3a0357b90c4498ef4d4c8d70a2e3c`，版本与平台解析通过；Ubuntu 的 `Analyze and test` 在根应用 `flutter pub get --enforce-lockfile` 阶段以退出码 65 失败，分析、测试及三端构建尚未执行。

根锁文件的 119 个 hosted 依赖均来自 `pub.flutter-io.cn`，三个包锁文件也使用此镜像；本机设置了 `PUB_HOSTED_URL`，初版 CI 未设置，因而使用默认 `pub.dev`。包源身份变化使 pub 重新解析依赖，日志出现 `Would change 119 dependencies` 和 `Unable to satisfy pubspec.yaml using pubspec.lock`。修复在 CI 工作流顶层显式设置相同包源，覆盖检查与构建任务；沿用已验证的锁定版本和内容哈希。

本轮修复在 Windows / Flutter 3.47.6 下运行 `tool/check.ps1 -EnforceLockfile`：根应用 597、`bili_api` 206、`bili_player` 16、`bili_danmaku` 19 项测试全部通过，各目录格式及静态分析通过，四份锁文件 SHA-256 均未变化。两个工作流通过 actionlint 1.7.12；本文件 6 条本地链接及 `git diff --check` 通过。此结果不代表修复后的远端运行或三端构建已通过。

### 干净检出时的子包依赖初始化修复

[CI #2](https://github.com/CKopoer/BiliSail/actions/runs/37407053988/job/112086879462) 使用提交 `8b120ebccee92dccfbf27bc0c4371c92113cfd37`，镜像配置已生效，根依赖安装和格式检查通过；根 `flutter analyze` 在 `packages/bili_api/test` 中找不到 `package:test/test.dart`，产生 1304 条连带诊断，测试及构建尚未执行。

根应用的 `pub get` 不会安装 path 依赖包的 `dev_dependencies`，参见 [Dart 开发依赖说明](https://dart.dev/tools/pub/dependencies#dev-dependencies)。原脚本在根分析后才逐个安装子包依赖；本机已有的子包 `.dart_tool/package_config.json` 掩盖了此问题。修复将根及三个包的依赖安装全部放到任何分析和测试之前，再分别执行完整检查；四次安装均保留锁文件强校验，`-SkipPub` 仍只跳过安装阶段。

在 Windows / Flutter 3.47.6 下，从提交 `8b120eb` 导出两份不含生成配置的源码副本：旧顺序复现相同的 1304 条诊断；替换修复脚本后，先安装全部依赖的根分析通过。隔离副本中 `tool/check.ps1 -EnforceLockfile` 最终通过全部格式、分析及 838 项测试，四份锁文件 SHA-256 均未变化；PowerShell parser、6 条本地文档链接和 `git diff --check` 通过。

完整测试初次因本机下载 SQLite 3.5.2 Windows 原生库连接中断而停止，随后复用本机已下载的同版本库，其 SHA-256 与包内 `asset_hashes.dart` 一致；没有复制任何已有包解析配置。此验证覆盖干净检出的依赖初始化，不表示本机原生库下载或 Ubuntu 远端运行已通过。

**未测**：子包依赖初始化修复后的 GitHub Actions 运行、Ubuntu runner 完整检查/构建、macOS 构建/启动、MSIX 安装/卸载/升级、正式 PFX 签名、Android 真机播放与签名升级。未创建或公开远端 Release；需将修复提交并推送到 GitHub 后运行 Actions。本机 Windows 成功不能代替这些结果。
