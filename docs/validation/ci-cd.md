# GitHub Actions CI/CD 与安装包

更新日期：2026-10-07。配置覆盖 Android arm64、Windows x64、macOS arm64；本地验证结果与远端、设备未测项分别记录。此流程交付预览构建，不表示 M0 三端验收或 M5 正式发行完成。

## 入口与分工

- [CI](../../.github/workflows/ci.yml)：替换原来的 `windows.yml`；分支 push、PR、手动运行时执行检查及构建，也供 Release 复用。
- [Release preview](../../.github/workflows/release.yml)：在 Actions 页面手动运行；可选择三个平台，全部所选构建通过后创建 **draft + prerelease** 并上传包、签名公钥证书、校验文件与第三方说明。不会自动公开发布。
- [检查脚本](../../tool/check.ps1)：CI 在 Ubuntu 使用 PowerShell 7 执行，先安装根应用和三个独立包的依赖，再分别运行格式、分析和离线测试。根分析会扫描子包，故子包开发依赖也须先安装。`-EnforceLockfile` 要求 pub 使用提交的锁文件及内容哈希。
- [构建打包脚本](../../tool/build-release.ps1)：各平台使用对应主机生成预览包，缺文件、原生命令失败、签名失败立即停止。已有同目标输出目录时拒绝覆盖，重新本地构建前先将其移走。

| 任务 | Runner | 产物与边界 |
| --- | --- | --- |
| 版本解析、根与三个包检查 | `ubuntu-24.04` | 无需真实账号，不自动运行在线或原生播放集成测试 |
| Android | `ubuntu-24.04`，Temurin JDK 17 | 仅 arm64 的 release APK；正常构建复用固定 keystore，PR 使用临时预览签名 |
| Windows | `windows-2022`，Visual Studio C++ / Windows SDK / .NET 8 / WiX 6.0.2 | 同时提供 x64 MSIX、MSI 和 EXE 安装包；全部包含完整原生 DLL/data 及 VC++ runtime |
| macOS | `macos-15`，Apple Silicon / Xcode | arm64 DMG，`ditto` 保留应用权限与链接，`hdiutil` 打包并校验镜像；仅 ad-hoc 签名，未 notarize |
| Release 上传 | `ubuntu-24.04` | 合并本次所选平台的 Actions artifacts 后创建草稿 |

PowerShell 7 是跨平台 shell；Ubuntu 上复用 `.ps1` 不要求 Windows。Windows 原生构建需要 Windows 主机与 Visual Studio 工具链，macOS 原生构建需要 macOS/Xcode。macOS 在固定 SDK 中显式启用 `--enable-macos-arm64-only`，避免默认 universal 构建引入未承诺的 Intel 目标。参见 [Flutter Windows 构建](https://docs.flutter.dev/platform-integration/windows/building)、[GitHub runner 范围](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

Flutter 固定 **3.47.6 stable / Dart 3.13.5**；升级需同时调整工作流、检查/构建脚本并重新验证。根及各包保留各自 `pubspec.lock`，pub 缓存键包含锁文件哈希。Actions 使用已查询的提交 SHA，并以注释标明主版本。Android SDK/NDK 由该 SDK 的 Flutter Gradle 配置选择，AGP/Gradle 版本沿用工程；Xcode/系统映像仍由对应 runner 提供，不能据此宣称完全可重现的原生工具链。

SDK 缓存沿用 `flutter-action` 的默认键，按系统、SDK 架构、版本和 revision 隔离。Pub 缓存键只配置系统、架构和版本前缀，由当前固定的 Action 追加所有 `pubspec.lock` 的哈希，避免重复追加。Gradle 缓存键覆盖 Android Gradle 脚本、`android/gradle.properties`、Wrapper 配置、所有 Pub 锁文件和 `.flutter-version`，使插件、SDK 或构建配置变化后保存新的依赖缓存。Release 复用 CI 的同一套缓存配置；安装包仍通过本次运行的 artifacts 传递。

CI 在工作流顶层固定 `PUB_HOSTED_URL=https://pub.flutter-io.cn`，与根应用及三个包锁文件中的 hosted URL 一致；检查、三端构建和 Release 复用流程均使用此包源。切换包源时须在同一包源下重新生成并验证四份锁文件，继续保留 `--enforce-lockfile`。

## 版本与产物

手动输入版本使用 Flutter 的 `x.y.z+N`，例如 `0.1.0+1`；留空取根 `pubspec.yaml`。脚本通过 `--build-name` 和 `--build-number` 传入，不改源码版本或锁文件。Windows MSIX 与 EXE Bundle 映射为 `x.y.z.N`；MSI 使用三段 `x.y.(z*1000+N)`，例如 `0.3.0+1` → `0.3.1`、`0.3.0+2` → `0.3.2`、`0.3.1+1` → `0.3.1001`。选择 Windows 时要求 `x/y <= 255`、`1 <= N <= 999`、`z*1000+N <= 65535`，版本解析阶段即拒绝超限值。MSI 只比较前三段，不能直接采用 MSIX 的第四段构建号；依据 [Microsoft ProductVersion](https://learn.microsoft.com/en-us/windows/win32/msi/productversion)。Android 使用 arm64 split APK，Flutter 自动将 versionCode 设为 `N + 2000`，因此 `N` 不超过 2099998000；实际 versionCode 同时写入 metadata。MSIX 升级要求递增包版本并保持 identity/publisher。已有同名 tag 时拒绝附加新构建，重跑草稿遇到冲突时也需使用新版本或显式处理旧草稿。

每个平台的 `artifacts/<target>/release/` 中包含：

- Android 的 `.apk`、Windows 的 `.msix` / `.msi` / `.exe`、macOS 的 `.dmg`，命名均为 `BiliSail-<version>-<target>.<extension>`。
- Windows 包旁的 `.cer`，只含签名证书公钥。
- `.build-info.json`：源码 revision 与 `sourceDirty`、Flutter/engine/Dart 版本、目标、签名类型、Android 签名证书 SHA-256、Windows MSI 内部版本与 WiX 版本、runner image、根锁文件 SHA-256。
- 每个上述文件对应的 `.sha256`，格式兼容 `sha256sum -c`。

CI 的 artifacts 保留 14 天；Release 从同一运行下载，所选平台失败时不创建新草稿。不使用参考仓库的 WebDAV、NuGet ZIP、UWP manifest、Chocolatey 或 TLS 验证绕过逻辑。

构建前先 `pub get --enforce-lockfile`，随后保留 Flutter build 默认的 pub 阶段，并检查构建后锁文件哈希不变。在 Flutter 3.47.6 中，`--no-pub` 还会跳过 release 原生插件注册文件的重生成：本轮 Android 初次构建因此错误引用 dev-only `integration_test`。修正采用 SDK 自身的重生成流程，不手改 `GeneratedPluginRegistrant.java`。

仅指定 `--target-platform android-arm64` 时，该 SDK 仍会把插件的其他 ABI 库装入非 split APK。本轮检查发现 armeabi-v7a/x86_64 的 mpv/JNI 库，已增加 `--split-per-abi` 并在脚本中校验 APK 内只存在 `arm64-v8a`。

## Android 固定签名与覆盖升级

2026-10-07 起，push、手动 CI 和 Release 共用固定 release keystore。仓库 Actions Secrets 配置：

| 名称 | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 长期保存的 keystore 文件的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 签名私钥别名 |
| `ANDROID_KEY_PASSWORD` | 签名私钥密码 |

Actions Variable `ANDROID_SIGNING_CERTIFICATE_SHA256` 保存该证书的 64 位十六进制 SHA-256。工作流仅在 Android 的非 PR 打包步骤注入私钥 Secrets；Release 显式将同一组 Secrets 传给复用 CI。缺失、配置不完整、文件无效、密码错误或证书指纹不符均失败，不自动生成密钥或降级为 debug 签名。

[Android 签名辅助脚本](../../tool/android-signing.ps1) 将 keystore 还原到独立临时目录，Linux 目录权限为 `700`；密码仅经进程环境传给 Gradle，不生成含密码的 `key.properties`。打包成功后使用 Android SDK 的 `apksigner verify --verbose --print-certs-pem` 验证 APK，从标准 PEM 证书的 DER 内容计算 SHA-256，要求唯一签名证书且指纹与仓库变量一致；metadata 标记 `signing=configured-keystore` 并保存实际 `androidSigningCertificateSha256`。成功或失败均清理临时 keystore。

PR 不接收长期签名 Secrets，仅通过 `-AndroidPreviewSigning` 显式启用临时 debug 签名，metadata 为 `temporary-debug-key`。这些预览包不属于长期升级链。该模式若收到 release 密钥则拒绝执行。普通 debug 开发不需要 release 凭据；直接 `flutter build apk --release` 需要设置 `ANDROID_KEYSTORE_PATH`、密码和别名环境变量，缺失时拒绝构建。

本机打包可用 `ANDROID_KEYSTORE_PATH` 替代 Base64，但二者只能选一个，并设置同一组密码、别名、证书 SHA-256 以及 `ANDROID_HOME` 或 `ANDROID_SDK_ROOT`。私钥及密码不进入源码、产物、日志或普通配置文件；离线备份须保留 keystore 与受保护的密码。

包名保持 `dev.bilisail.bilisail`。后续发布必须保持同一密钥并单调递增 `x.y.z+N` 中的 `N`，arm64 split APK 的内部版本号仍为 `N+2000`；只增加 `x.y.z` 不会增加 Android 内部版本号。旧临时 debug 签名包不能直接覆盖为不同密钥的新包，原私钥未保存时首次切换需卸载重装，卸载会影响应用私有数据。参考 [Android 签名与升级](https://developer.android.com/studio/publish/app-signing#considerations)、[Android 版本号](https://developer.android.com/studio/publish/versioning#appversioning)、[apksigner](https://developer.android.com/tools/apksigner)。

[签名边界检查](../../tool/test-android-signing.ps1) 已加入 `tool/check.ps1`，覆盖缺失配置、错误 Base64、预览密钥隔离、临时文件清理、调用方 keystore 保留和错误 APK 证书拒绝。实机安装与覆盖升级仍需单独验收。

2026-10-07 本机验证：已配置上述四个 Secrets 与证书指纹变量，生成 RSA 3072 位固定签名密钥，证书有效期至 2056-09-29；keystore 和 DPAPI 加密的密码备份保存在仓库外，仅当前 Windows 用户与 SYSTEM 可访问。证书 SHA-256 为 `be3770071a0e9c71a701405a685dd455cd1baa134abd2eac2d97b9926349996e`。

- `tool/check.ps1 -EnforceLockfile` 的格式、分析、1333 个应用／包测试和 20 个签名边界检查通过，四份锁文件未变。
- actionlint 1.7.12、PowerShell 解析、144 条相对文档链接及差异检查通过。
- Gradle 在缺少密钥时拒绝 `preReleaseBuild`，无 release 凭据时 `preDebugBuild` 通过。
- 在独立检出中生成 `0.3.0+1` 的 arm64 release APK；实际 application ID 为 `dev.bilisail.bilisail`、versionCode 为 `2001`、最低 API 为 `24`。APK 签名、固定证书指纹、单 arm64 ABI、metadata 与 SHA-256 校验通过，包内无 keystore／密码文件，临时签名目录已清理。
- 本地首次构建受其他开发操作生成的 dev-only 插件注册文件干扰；独立检出的 SQLite 原生资产下载另遇 TLS 连接中断，随后复用经包内固定 SHA-256 验证的缓存完成构建，未改 TLS 验证或生成源码。真实 Android 设备安装、旧临时签名切换与固定签名下的覆盖升级尚未实测。

后续验证修正：远端 [CI 37578713971](https://github.com/CKopoer/BiliSail/actions/runs/37578713971/job/112654748403) 已生成 APK，但原先按人类可读摘要行解析证书的检查失败，未上传 Android 产物。改为读取标准 PEM 证书并自行计算指纹，新增格式变化、重复摘要行和非法证书覆盖；21 项签名边界检查与本机实际 APK 证书校验通过。修复后的远端 CI 结果尚待确认。

## macOS DMG 安装

macOS 产物为 `BiliSail-<version>-macos-arm64.dmg`。脚本先使用 `ditto` 复制完整 `BiliSail.app`，再在镜像根目录加入指向 `/Applications` 的符号链接与 `THIRD_PARTY_NOTICES.md`。使用系统 `hdiutil create -srcfolder ... -fs HFS+ -format UDZO` 创建压缩只读镜像，随后执行 `hdiutil verify`；任一步失败均停止，不上传产物。CI 与 Release 共用此脚本，现有上传通配符同时覆盖 DMG、metadata 和 SHA-256 文件。

打开 DMG 后，将 `BiliSail.app` 拖到镜像中的 `Applications` 入口，复制完成后推出镜像，再从应用程序目录启动。此方式采用 Apple 的应用 bundle 拖拽安装方案，参见 [Apple 应用分发说明](https://developer.apple.com/library/archive/documentation/Porting/Conceptual/PortingUnix/distributing/distibuting.html)。DMG 不改变应用签名：当前仍为 ad-hoc 预览包，未完成 Developer ID 签名与公证；打包与镜像校验不等于启动或 Gatekeeper 验收。

## Windows MSI 与 EXE

2026-10-07 起，CI 与 Release 共用 [Windows 安装器辅助脚本](../../tool/windows-installers.ps1)，在 Windows runner 通过 NuGet 安装固定 **WiX 6.0.2** CLI 与同版本 `WixToolset.BootstrapperApplications.wixext`。需要 .NET 8 runtime 与 .NET SDK，仅作为构建依赖；用户机器无需安装 .NET。工具位于 `artifacts/windows-x64/installer-work/tools/`，不上传到 Release。

[MSI 定义](../../windows/packaging/Installer.wxs) 安装到 `%ProgramFiles%\BiliSail`，提供开始菜单入口与系统卸载、修复，并用固定 UpgradeCode 替换旧版本、拒绝较低版本。包内 CAB 嵌入完整 Flutter Release 目录、播放器／WebView／SQLite 原生文件、资产、字体、第三方说明和三份 VC++ runtime DLL；在 MSIX 添加 manifest、PRI 与专属图标之前打包，避免混入 MSIX 文件。系统下限通过注册表实际构建号检查 Windows 10 1809（17763）或更高版本，不依赖 MSI 的兼容性版本属性。

[EXE 定义](../../windows/packaging/Bundle.wxs) 使用原生 Burn 标准安装界面，内嵌已签名的同一 MSI 和 CAB，安装时无需下载应用文件。MSI 与 EXE 属于同一应用安装链，任选一种；安装需要管理员权限，EXE 不再额外显示底层 MSI 的卸载条目。MSIX 具有独立包身份，不自动迁移为 MSI/EXE；账户、设置及卸载后的数据保留行为仍需分别实测。

三种安装包共用既有 `MSIX_CERTIFICATE_BASE64` / `MSIX_CERTIFICATE_PASSWORD` 与 `MSIX_PUBLISHER`，也共用无 Secrets 时的临时测试证书。先签 MSIX 和 MSI，再构建 EXE，按 WiX 的 detach → 签 engine → reattach → 签 Bundle 顺序完成 EXE 签名；公钥仍通过包旁 `.cer` 导出，私钥只在既有临时签名作用域存在。每个安装包均附独立 SHA-256；任一步失败均不进入上传步骤。自签名证书不代表受系统默认信任的 Authenticode 发行身份。参见 [WiX Bundle 签名](https://docs.firegiant.com/wix/tools/signing/)。

WiX 源码采用 MS-RL，固定版本来源和内嵌 Burn 的许可见 [第三方说明](../../THIRD_PARTY_NOTICES.md)。WiX v6 的二进制发布同时适用 [Open Source Maintenance Fee 条款](https://docs.firegiant.com/wix/osmf/)；本工程不引入 FireGiant 商业扩展。`tool/check.ps1` 增加 [Windows 版本检查](../../tool/test-windows-installers.ps1)，在 Ubuntu 和 Windows 均验证补丁／构建号顺序与超限拒绝。

## Windows MSIX 签名与安装

[AppxManifest.xml](../../windows/packaging/AppxManifest.xml) 的 identity 为 `dev.bilisail.bilisail`，默认 publisher 为 `CN=BiliSail`；Windows 安装下限为 Windows 10 1809（build 17763）。`MakeAppx` 打包完整 Flutter Release 目录，`SignTool` 使用 SHA-256 签名。MSIX 图标在构建时从已有品牌 PNG 派生；生成普通、深色 `unplated`、浅色 `lightunplated` 的多尺寸图标，并使用同一 Windows SDK 的 `MakePri` 与 [PRI 配置](../../windows/packaging/priconfig.xml) 生成 `resources.pri`，供任务栏和开始菜单选择无底板图标。不引入新品牌资源或 Dart 依赖。

无签名 Secrets 时生成一年有效的临时自签证书，产物标记 `self-signed-preview`。安装前需要在测试机器上把对应 `.cer` 信任到 **本地计算机 → 受信任人**，再打开 `.msix`；这一步需要管理员权限。工作流只导出公钥，不上传 PFX、私钥或密码，打包结束后清理本次临时证书/私钥。每次运行的测试证书不同，不能视为长期可升级的正式发行链路。

使用固定签名证书时，在仓库 Actions Secrets 配置：

| 名称 | 内容 |
| --- | --- |
| `MSIX_CERTIFICATE_BASE64` | 带私钥的代码签名 PFX 的 Base64 |
| `MSIX_CERTIFICATE_PASSWORD` | 该 PFX 的密码；无密码 PFX 可留空 |

仓库 Actions Variable `MSIX_PUBLISHER` 可指定证书的完整 Subject，缺省为 `CN=BiliSail`；manifest Publisher 必须与证书 Subject 匹配。PR 构建始终使用临时测试证书，避免向 PR 提供正式私钥。已配置 PFX 无效、密码错误、证书过期或 publisher 不匹配时失败，不降级成测试签名。当前未接入可信时间戳；正式发行还需完善时间戳、证书续期与升级验证。参见 [Microsoft MSIX 证书](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)、[SignTool 签名](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool)。

macOS ad-hoc 签名不能替代 Developer ID / notarization。资源许可范围沿用 [第三方说明](../../THIRD_PARTY_NOTICES.md)，公开发布前仍需完成其待核实项。

## 验证记录

### Windows 增加 MSI 与 EXE（2026-10-07）

本机 Windows x64 / Flutter 3.47.6 / WiX 6.0.2 实际运行 `tool/build-release.ps1 -Target windows-x64 -Version '0.3.0+1'`，生成三个安装包、公钥证书、metadata 与五份 SHA-256 校验文件，位于 `artifacts/windows-x64/release/`。metadata 的源码 HEAD 为 `42ea8fd2e44c1e8a6e04104505f317c7040630b6`，包含工作区未提交修改，标记 `sourceDirty=true`，不能仅凭该 HEAD 复现本地包；此前 Windows 输出已另行保留。

- Windows Release 编译、WiX MSI 的内嵌 CAB、MakePri / MakeAppx、MSI / MSIX 签名与 EXE 的 engine / Bundle 两阶段签名全部通过。三个包和签名前的 engine 使用同一导出证书，本轮为 `self-signed-preview`；临时私钥证书已清理，没有添加系统信任。
- 解包 MSI 后，将全部 **67 个运行文件**逐一与 staging 比较 SHA-256，完整一致，包含资产、字体、原生依赖、VC++ runtime 与 WiX 许可，没有 MSIX 专属文件。读取 MSI 实际执行表确认 `InstallInitialize=1500`、`RemoveExistingProducts=1501`、`InstallFinalize=6600`，升级替换处于可回滚事务内。
- 解包 EXE，内嵌的已签名 MSI 与独立 `.msi` 的 SHA-256 完全一致。MSIX 运行文件与许可、公钥证书一致性、metadata 中 `windowsMsiVersion=0.3.1` / `windowsInstallerToolVersion=6.0.2`、五份校验文件均通过；产物无 PFX / `.wixpdb` 或旧名称 EXE。
- `tool/check.ps1 -EnforceLockfile` 已完成依赖强校验；首次测试遇到工作区并行修改的中间状态，更新后运行 `tool/check.ps1 -SkipPub` 全部通过：根应用 **1116**、API **291**、播放器 **22**、弹幕 **52** 项测试，以及 **14** 项新增 Windows 版本边界检查。根应用与三个包的格式、分析均通过，四份锁文件无差异。
- 两个工作流通过 actionlint 1.7.12；PowerShell 解析、WiX XML 编译、185 条本地文档链接与差异空白检查通过。

尚未推送或运行新版远端 Actions，没有执行 MSI / EXE 的系统安装、卸载、修复、覆盖升级或跨格式迁移，也未用仓库固定 PFX 复验本次新产物。上述验证证明本地构建、签名流程及包内容，不代表系统默认信任、实际安装或原生播放验收。

### 首次 CI/CD 本地验证（2026-10-06）

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

### Windows SDK 初始化与 macOS 架构检查修复

[CI #3](https://github.com/CKopoer/BiliSail/actions/runs/37408314360) 使用提交 `7c8684c8a6ea1dbb9aaacbb1ca723e3a5919f272`，Ubuntu 的完整分析与测试通过，进入三端构建。

- [Windows 日志](https://github.com/CKopoer/BiliSail/actions/runs/37408314360/job/112092222074)：首次执行 `flutter --version --machine` 触发 SDK 内部 `pub upgrade`，其初始化输出混入标准输出，`ConvertFrom-Json` 在真正构建前失败。检查和构建脚本均先单独执行 `flutter --version` 并检查退出码，再捕获版本 JSON，避免依赖已初始化的本机 SDK。
- [macOS 日志](https://github.com/CKopoer/BiliSail/actions/runs/37408314360/job/112092222062)：已编译出 `BiliSail.app`，随后 `lipo -verify_arch arm64 <file>` 将文件路径误当成架构名称而失败。Apple 的 `-verify_arch` 会消费后续所有架构参数，修复为 `lipo <file> -verify_arch arm64`；继续保留架构校验。

本轮验证：两份脚本的旧逻辑均复现冷启动 JSON 失败，新逻辑均进入依赖安装，初始化失败的退出码也正确传播；共 6 个模拟 CLI 场景通过。`tool/check.ps1 -EnforceLockfile` 的全部格式、分析及 838 项测试通过，四份锁文件未变。Windows 实际执行 `tool/build-release.ps1 -Target windows-x64 -Version 0.1.0+1`，Release 编译、MakeAppx 打包及临时证书签名通过；包内容、manifest 和 3 份产物的 SHA-256 通过。旧输出目录已保存在 `artifacts/windows-x64-before-cli-fix-*/`，新输出仍位于 `artifacts/windows-x64/release/`。本机包基于 `7c8684c` 加本轮未提交修复，metadata 标记 `sourceDirty=true`。

macOS 命令在本机用 LLVM lipo 对真实 arm64 Mach-O fixture 验证通过，错误架构被拒绝；此项不代替 Apple lipo/Xcode 的远端执行。两份脚本通过 PowerShell parser，两个工作流通过 actionlint 1.7.12。

### 三端远端复验通过

[CI #4](https://github.com/CKopoer/BiliSail/actions/runs/37409580779) 在 2026-10-06 对修复提交 `d818c8a8603f129b704b2e2238fc54ede88bded3` 全部通过，三个平台产物均已上传：

| 任务 | 验证结果 |
| --- | --- |
| [Ubuntu 完整检查](https://github.com/CKopoer/BiliSail/actions/runs/37409580779/job/112094826410) | 根应用及三个包的依赖强校验、格式、分析和测试通过 |
| [Windows x64](https://github.com/CKopoer/BiliSail/actions/runs/37409580779/job/112095782197) | 冷启动版本读取、Release 编译、MSIX 打包与临时证书签名、产物上传通过 |
| [macOS arm64](https://github.com/CKopoer/BiliSail/actions/runs/37409580779/job/112095782269) | Xcode 编译、Apple lipo 架构校验、ZIP 打包与上传通过 |
| [Android arm64](https://github.com/CKopoer/BiliSail/actions/runs/37409580779/job/112095782290) | Release split APK、单 arm64 ABI 断言、打包与上传通过 |

**设备与发行未测**：macOS 启动、MSIX 安装/卸载/升级、正式 PFX 签名、Android 真机播放与签名升级。未创建或公开远端 Release；三端构建成功不能代替播放、设备与发行验收，M0 尚未全部完成。

### Windows MSIX 任务栏图标透明背景修复

2026-10-06 检查本机从 Release 安装的 `0.1.0+2` 包：品牌 PNG、EXE 的 ICO 和包内 `Logo44.png` 均保留透明通道，manifest 也已有 `BackgroundColor="transparent"`；但包内只有 `Logo44.png`、`Logo50.png`、`Logo150.png`，没有带 `targetsize` / `altform` 限定的图标或 `resources.pri`。

本地直接运行 Release EXE 使用内嵌 ICO；安装 MSIX 后，Windows shell 使用 manifest 图标及其资源变体。缺少浅色或深色主题的无底板变体时，系统会缩小图标并添加底板，不能只靠 PNG alpha 或 manifest 的透明背景避免。依据：[Microsoft 图标变体要求](https://learn.microsoft.com/en-us/windows/apps/design/iconography/app-icon-construction)、[MSIX 无底板资源与 PRI](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-manual-conversion)。

修复位于本地与 CI 共用的 `tool/build-release.ps1`：从原品牌 PNG 生成 15 个目标尺寸（16–256 像素）的普通、`unplated` 和 `lightunplated` 图标，显式使用透明的 32 位 ARGB；在 MakeAppx 打包前生成 PRI。索引只列出 MSIX 图标，保留 `Files/Assets/Logo44.png` 与 manifest 路径的对应关系；临时 `.resfiles` 清单不进入安装包。

本轮在 Windows / Flutter 3.47.6 / Windows SDK 10.0.26100.0 下验证：

- `tool/check.ps1 -EnforceLockfile` 的全部格式、分析及 840 项离线测试通过（根应用 599、API 206、播放器 16、弹幕 19）；四份锁文件无差异。
- 实际运行 `tool/build-release.ps1 -Target windows-x64 -Version 0.1.0+3`，Release 编译、MakePri、MakeAppx 验证/打包、测试证书签名通过；产物在 `artifacts/windows-x64/release/`。此前输出保存在 `artifacts/windows-x64-before-taskbar-icon-*/`。
- 从最终 MSIX 提取并用 MakePri 详细导出 PRI，验证 manifest 的 `Assets/Logo44.png` 对应正确的资源 URI、15 个尺寸的三类候选共 45 个，且每个候选指向包内实际 PNG。逐个验证图片尺寸、32 位 ARGB、四角 alpha 为 0 及中心非空；包内共 48 张 MSIX 图标，PRI 仅包含 3 个图标资源，不索引 Flutter 数据。
- 完整原生运行文件、SHA-256、CMS 数学签名、导出公钥证书匹配及临时签名证书清理通过；临时资源清单与 PFX 未进入包。PowerShell parser、7 条本地文档链接和 `git diff --check` 通过。

本地验证包基于 `19caedd` 加检出目录的未提交修改，metadata 标记 `sourceDirty=true`。本轮未替换已安装的 `0.1.0+2`，未安装新版做任务栏浅/深主题及不同 DPI 的显示复验，也未推送代码或重发远端 Release；此处的验证不代表新版安装、升级或受信任发行证书链已通过。

### macOS 产物改为 DMG

2026-10-06 按用户要求，将本地与 CI 共用打包脚本的 macOS 产物由 ZIP 改为 DMG，新增 Applications 拖拽安装入口，并在生成后执行镜像校验。Release 手动选项、草稿说明、README、文档索引及实施/决策文档同步更新；此前 CI #4 的 ZIP 成功记录保留为历史证据，不能用于证明新 DMG 流程已通过。

本轮在 Windows / Flutter 3.47.6 下运行 `tool/check.ps1 -EnforceLockfile`：根应用及三个包的依赖、格式、分析和 989 项离线测试全部通过（根应用 723、API 227、播放器 16、弹幕 23），四份锁文件无差异。两个工作流通过 actionlint 1.7.12，两份 PowerShell 脚本通过语法检查；变更文档的本地链接及 `git diff --check` 通过。

本机为 Windows，未执行 macOS/Xcode、`ditto` / `ln` / `hdiutil` 原生命令；实际 DMG 生成、挂载、拖拽安装、启动及 Gatekeeper 验收仍需 macOS runner 和设备复验。Developer ID 签名与公证仍未接入。

### 定向依赖更新与 API 包 SDK 下限

2026-10-07 按用户指定范围更新以下依赖，继续使用精确版本和 `https://pub.flutter-io.cn` 包源：

| 依赖 | 位置 | 版本变化 |
| --- | --- | --- |
| `url_launcher` | 根应用直接依赖 | `6.3.2` → `6.3.3` |
| `lints` | `bili_api` 开发依赖 | `6.0.0` → `6.1.0` |
| `test` | `bili_api` 开发依赖 | `1.26.3` → `1.32.0` |
| `jni_flutter` | `path_provider_android` 间接依赖 | `1.0.4` → `1.0.4+1` |

`jni_flutter 1.0.4` 已被维护者撤回；通过根锁文件定向更新，不增加直接依赖或 `dependency_overrides`。根锁文件只更新上述两项运行时依赖。API 包锁文件同步更新新版 `test` 必需的 `analyzer`、`_fe_analyzer_shared`、`test_api`、`test_core`，移除不再需要的 `js`；其他依赖沿用已有解析版本。[JNI 版本记录](https://pub.dev/packages/jni_flutter/versions)、[测试工具版本记录](https://pub.dev/packages/test/changelog)。

按用户要求，将 `bili_api` 的最低 Dart SDK 从 `3.7.0` 提高到 `3.11.0`，与新版测试工具要求对齐。保留新语言版本下的格式更新，并将 15 处条件集合元素改为等价的空值感知元素；字段为空时仍不加入请求参数或集合。主应用和其他包的 SDK 声明、CI 固定的 Flutter 3.47.6 / Dart 3.13.5 沿用原值。[新版 lint 说明](https://pub.dev/packages/lints/changelog)。

本轮在 Windows 主机验证：

- `tool/check.ps1 -EnforceLockfile` 通过根应用与三个包的格式、静态分析及 1191 项离线测试（根应用 868、API 269、播放器 22、弹幕 32）。
- 对 37 个变更的 Dart 文件比较语法 token，排除格式空白和尾逗号后，只存在上述 15 处 lint 修正。
- `flutter build apk --release --target-platform android-arm64 --split-per-abi` 通过，生成 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`；检查 APK 的 6 个原生 `.so` 文件，ABI 仅为 `arm64-v8a`。
- `flutter build windows --release` 通过，生成 `build/windows/x64/runner/Release/bilisail.exe` 及配套运行文件。
- 四份锁文件在完整检查和两端构建前后的 SHA-256 一致；文档本地链接及 `git diff --check` 通过。

Android 构建输出 CupertinoIcons 字体声明警告，Windows 构建输出 `flutter_inappwebview_windows` 的 CMake 开发者警告，两端均构建成功。未执行 Android 真机、macOS 构建/运行、安装升级或真实账号操作；构建和离线测试不能代替这些验收。
