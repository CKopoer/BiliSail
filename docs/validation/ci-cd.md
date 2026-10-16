# GitHub Actions CI/CD 与安装包

更新日期：2026-10-08。配置覆盖 Android arm64、Windows x64、macOS arm64；本地验证结果与远端、设备未测项分别记录。此流程交付预览构建，不表示 M0 三端验收或 M5 正式发行完成。

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
| macOS | `macos-15`，Apple Silicon / Xcode | arm64 DMG；先验证签名／最终权限、同一 Release 应用首帧和跨进程 Keychain 读写删除，再由 `hdiutil` 打包校验；仅 ad-hoc 签名，未 notarize |
| Release 上传 | `ubuntu-24.04` | 合并本次所选平台的 Actions artifacts 后创建草稿 |

PowerShell 7 是跨平台 shell；Ubuntu 上复用 `.ps1` 不要求 Windows。Windows 原生构建需要 Windows 主机与 Visual Studio 工具链，macOS 原生构建需要 macOS/Xcode。macOS 在固定 SDK 中显式启用 `--enable-macos-arm64-only`，避免默认 universal 构建引入未承诺的 Intel 目标。参见 [Flutter Windows 构建](https://docs.flutter.dev/platform-integration/windows/building)、[GitHub runner 范围](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

Flutter 固定 **3.47.6 stable / Dart 3.13.5**；升级需同时调整工作流、检查/构建脚本并重新验证。根及各包保留各自 `pubspec.lock`，pub 缓存键包含锁文件哈希。Actions 使用已查询的提交 SHA，并以注释标明主版本。Android SDK/NDK 由该 SDK 的 Flutter Gradle 配置选择，AGP/Gradle 版本沿用工程；Xcode/系统映像仍由对应 runner 提供，不能据此宣称完全可重现的原生工具链。

SDK 缓存沿用 `flutter-action` 的默认键，按系统、SDK 架构、版本和 revision 隔离。Pub 缓存键只配置系统、架构和版本前缀，由当前固定的 Action 追加所有 `pubspec.lock` 的哈希，避免重复追加。Gradle 缓存键覆盖 Android Gradle 脚本、`android/gradle.properties`、Wrapper 配置、所有 Pub 锁文件和 `.flutter-version`，使插件、SDK 或构建配置变化后保存新的依赖缓存。Release 复用 CI 的同一套缓存配置；安装包仍通过本次运行的 artifacts 传递。

CI 在工作流顶层显式设置 `PUB_HOSTED_URL=https://pub.dev`，与根应用及 `bili_api`、`bili_player`、`bili_danmaku`、`bili_mux` 五份锁文件的官方 hosted 源一致；检查、三端构建和 Release 复用流程均使用此源。Dependabot 的 Pub 更新也使用官方源。严格检查和提交前，本地应先设置 `$env:PUB_HOSTED_URL = 'https://pub.dev'`（PowerShell）或 `export PUB_HOSTED_URL=https://pub.dev`（sh），再执行 `pwsh ./tool/check.ps1 -EnforceLockfile`。

本地临时使用镜像运行 `pub get` 可能改写锁文件中的 hosted URL；不要将这类改动混入提交。恢复官方源后重新验证五份锁文件，并确认依赖版本、约束、内容哈希没有意外变化。`FLUTTER_STORAGE_BASE_URL` 控制 Flutter SDK 下载，与 Pub 包源是不同设置。

Dart 3.13.5 内置的 [Pub 源码](https://github.com/dart-lang/pub/blob/ec276d10a7fa0f6c6ec005340fb9ad29f3b012d0/lib/src/source/hosted.dart#L40) 会将官方旧域名 `https://pub.dartlang.org` 规范化为 `https://pub.dev`，再用于 hosted 来源身份比较；两者的文本差异不等于来源冲突。`pub.flutter-io.cn` 是另一来源，不能依赖这种官方别名规范化消除镜像冲突。验证以固定 Flutter 3.47.6 的实际解析、内容哈希与 `--enforce-lockfile` 为准。

## 版本与产物

手动输入版本使用 Flutter 的 `x.y.z+N`，例如 `0.1.0+1`；留空取根 `pubspec.yaml`。脚本通过 `--build-name` 和 `--build-number` 传入，不改源码版本或锁文件。Windows MSIX 与 EXE Bundle 映射为 `x.y.z.N`；MSI 使用三段 `x.y.(z*1000+N)`，例如 `0.3.0+1` → `0.3.1`、`0.3.0+2` → `0.3.2`、`0.3.1+1` → `0.3.1001`。选择 Windows 时要求 `x/y <= 255`、`0 <= N <= 999`、`z*1000+N <= 65535`，版本解析阶段即拒绝超限值。MSI 只比较前三段，不能直接采用 MSIX 的第四段构建号；依据 [Microsoft ProductVersion](https://learn.microsoft.com/en-us/windows/win32/msi/productversion)。Android 保留 arm64 split APK，但在 `android/gradle.properties` 设置 `force-version-code-ignoring-abi=true`，关闭 Flutter 的 ABI 偏移。Gradle 从 `--build-name x.y.z` 与原始 `--build-number N` 计算 `versionCode = x*10000 + y*1000 + z*100 + N`，例如 `0.5.5+2` → `5502`，不再额外加 2000，也不要将已编码值传给 `--build-number`。CI 与打包脚本共用 [Android 版本校验](../../tool/android-version.ps1)，要求 `0 <= x <= 209999`、`0 <= y,z <= 9`、`0 <= N <= 99`，禁止前导零及最终编码为零（`0.0.0+0`）；Gradle 独立校验相同范围，直接 Flutter 构建也不能绕过数值限制。构建号满 99 后提升补丁号并重置构建号；补丁/次版本满 9 后相应提升上一段，避免进位碰撞。最大编码为 2099999999，低于 Android 上限 2100000000。打包后使用 SDK `aapt dump badging` 校验实际 APK 的 applicationId、versionName 和 versionCode；仅校验成功才将编码写入 metadata 并生成校验文件。MSIX 升级要求递增包版本并保持 identity/publisher。已有同名 tag 时拒绝附加新构建，重跑草稿遇到冲突时也需使用新版本或显式处理旧草稿。

每个平台的 `artifacts/<target>/release/` 中包含：

- Android 的 `.apk`、Windows 的 `.msix` / `.msi` / `.exe`、macOS 的 `.dmg`，命名均为 `BiliSail-<version>-<target>.<extension>`。
- Windows 包旁的 `.cer`，只含签名证书公钥。
- `.build-info.json`：源码 revision 与 `sourceDirty`、Flutter/engine/Dart 版本、目标、签名类型、Android 签名证书 SHA-256、Windows MSI 内部版本与 WiX 版本、runner image、根锁文件 SHA-256；macOS 的 `macosValidation` 保存发布门槛的通过状态。
- 每个上述文件对应的 `.sha256`，格式兼容 `sha256sum -c`。

CI 的 artifacts 保留 14 天；Release 从同一运行下载，所选平台失败时不创建新草稿。不使用参考仓库的 WebDAV、NuGet ZIP、UWP manifest、Chocolatey 或 TLS 验证绕过逻辑。

Release 草稿及全部附件上传成功后，使用 GitHub 官方 [actions/github-script v8](https://github.com/actions/github-script/tree/ed597411d8f924073f98dfc5c65a23a2325f34cd) 清理旧版本，固定提交 `ed597411d8f924073f98dfc5c65a23a2325f34cd`。分页获取正式发布、预发布和草稿，合计保留按 `created_at` 排序的最新 **15 个 Release**；时间相同时按 Release ID 从新到旧排序。超出部分删除 Release 及其附件，保留 Git 标签与 Actions 运行记录。草稿没有 `published_at`，不能直接使用按发布时间排序或排除草稿的清理包。使用该 job 已有的 `contents: write` 和默认 `github.token`，不需额外 Secret；发布流程继续由 `release-preview` 并发组串行执行。删除请求失败立即停止，清理后再次分页查询并验证总数不超过 15，查询失败或仍超限会使流程失败。本地配置检查不代表已经执行远端删除。

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

包名保持 `dev.bilisail.bilisail`。后续发布必须保持同一密钥并递增编码后的 Android versionCode；当前使用上文的紧凑编码且禁用 ABI 偏移，不再使用旧版 `N+2000`。旧临时 debug 签名包不能直接覆盖为不同密钥的新包，原私钥未保存时首次切换需卸载重装，卸载会影响应用私有数据。参考 [Android 签名与升级](https://developer.android.com/studio/publish/app-signing#considerations)、[Android 版本号](https://developer.android.com/studio/publish/versioning#appversioning)、[apksigner](https://developer.android.com/tools/apksigner)。

[签名边界检查](../../tool/test-android-signing.ps1) 已加入 `tool/check.ps1`，覆盖缺失配置、错误 Base64、预览密钥隔离、临时文件清理、调用方 keystore 保留和错误 APK 证书拒绝。实机安装与覆盖升级仍需单独验收。

2026-10-07 本机验证：已配置上述四个 Secrets 与证书指纹变量，生成 RSA 3072 位固定签名密钥，证书有效期至 2056-09-29；keystore 和 DPAPI 加密的密码备份保存在仓库外，仅当前 Windows 用户与 SYSTEM 可访问。证书 SHA-256 为 `be3770071a0e9c71a701405a685dd455cd1baa134abd2eac2d97b9926349996e`。

- `tool/check.ps1 -EnforceLockfile` 的格式、分析、1333 个应用／包测试和 20 个签名边界检查通过，四份锁文件未变。
- actionlint 1.7.12、PowerShell 解析、144 条相对文档链接及差异检查通过。
- Gradle 在缺少密钥时拒绝 `preReleaseBuild`，无 release 凭据时 `preDebugBuild` 通过。
- 在独立检出中生成 `0.3.0+1` 的 arm64 release APK；实际 application ID 为 `dev.bilisail.bilisail`、versionCode 为 `2001`、最低 API 为 `24`。APK 签名、固定证书指纹、单 arm64 ABI、metadata 与 SHA-256 校验通过，包内无 keystore／密码文件，临时签名目录已清理。
- 本地首次构建受其他开发操作生成的 dev-only 插件注册文件干扰；独立检出的 SQLite 原生资产下载另遇 TLS 连接中断，随后复用经包内固定 SHA-256 验证的缓存完成构建，未改 TLS 验证或生成源码。真实 Android 设备安装、旧临时签名切换与固定签名下的覆盖升级尚未实测。

后续验证修正：远端 [CI 37578713971](https://github.com/CKopoer/BiliSail/actions/runs/37578713971/job/112654748403) 已生成 APK，但原先按人类可读摘要行解析证书的检查失败，未上传 Android 产物。改为读取标准 PEM 证书并自行计算指纹，新增格式变化、重复摘要行和非法证书覆盖；21 项签名边界检查与本机实际 APK 证书校验通过。修复后的远端 CI 结果尚待确认。

## macOS DMG 安装

macOS 产物为 `BiliSail-<version>-macos-arm64.dmg`。脚本先使用 `ditto` 复制完整 `BiliSail.app`，调用 [macOS 发布验证](../../tool/macos-release-validation.ps1) 校验签名、最终权限，并启动这份待打包的 Release 应用验证首帧和跨进程 Keychain 读写／删除。通过后在镜像根目录加入指向 `/Applications` 的符号链接与 `THIRD_PARTY_NOTICES.md`，使用 `hdiutil create -srcfolder ... -fs HFS+ -format UDZO` 创建压缩只读镜像并执行 `hdiutil verify`；任一步失败均停止，不上传产物。CI 与 Release 共用此脚本，现有上传通配符同时覆盖 DMG、metadata 和 SHA-256 文件。

两个 entitlements 文件移除 `keychain-access-groups`，保留原 Sandbox／网络权限和 Debug/Profile 调试权限；`SystemCredentialStore` 仅对 macOS 配置 `usesDataProtectionKeychain: false`，继续使用系统安全存储。锁定的插件 11.2.0 已支持，不升级依赖。启动探测使用内存数据库和独立凭据前缀；完整验证步骤、失败清理及旧登录／升级授权验收见 [macOS 发布启动与安全存储](macos-release-startup.md)。

打开 DMG 后，将 `BiliSail.app` 拖到镜像中的 `Applications` 入口，复制完成后推出镜像，再从应用程序目录启动。此方式采用 Apple 的应用 bundle 拖拽安装方案，参见 [Apple 应用分发说明](https://developer.apple.com/library/archive/documentation/Porting/Conceptual/PortingUnix/distributing/distibuting.html)。DMG 不改变应用签名：当前仍为 ad-hoc 预览包，未完成 Developer ID 签名与公证；打包与镜像校验不等于启动或 Gatekeeper 验收。

## Windows MSI 与 EXE

2026-10-07 起，CI 与 Release 共用 [Windows 安装器辅助脚本](../../tool/windows-installers.ps1)，在 Windows runner 通过 NuGet 安装固定 **WiX 6.0.2** CLI 与同版本 `WixToolset.BootstrapperApplications.wixext`、`WixToolset.UI.wixext`、`WixToolset.Util.wixext`。需要 .NET 8 runtime 与 .NET SDK，仅作为构建依赖；用户机器无需安装 .NET。工具位于 `artifacts/windows-x64/installer-work/tools/`，不上传到 Release。

[MSI 定义](../../windows/packaging/Installer.wxs) 默认安装到 `%ProgramFiles%\BiliSail`，首次安装提供“欢迎 → 安装目录 → 确认安装 → 进度 → 完成”向导；安装目录页可编辑路径或点击 **Change…** 浏览文件夹。复用 WiX 的 `WixUI_InstallDir`，跳过其占位许可页面；第三方许可继续随应用文件分发。提供开始菜单入口与系统卸载、修复，并用固定 UpgradeCode 替换旧版本、拒绝较低版本。包内 CAB 嵌入完整 Flutter Release 目录、播放器／WebView／SQLite 原生文件、资产、字体、第三方说明和三份 VC++ runtime DLL；在 MSIX 添加 manifest、PRI 与专属图标之前打包，避免混入 MSIX 文件。系统下限通过注册表实际构建号检查 Windows 10 1809（17763）或更高版本，不依赖 MSI 的兼容性版本属性。

[EXE 定义](../../windows/packaging/Bundle.wxs) 使用原生 Burn 标准安装界面，首次安装时点击 **Options → Browse** 选择目录，确定后返回主界面点击 **Install**。界面的 `InstallFolder` 变量显式传给内嵌 MSI 的 `INSTALLFOLDER`，避免界面选择与实际落盘路径分离。EXE 内嵌已签名的同一 MSI 和 CAB，安装时无需下载应用文件。MSI 与 EXE 属于同一应用安装链，任选一种；安装需要管理员权限，EXE 不再额外显示底层 MSI 的卸载条目。MSIX 具有独立包身份，不自动迁移为 MSI/EXE；账户、设置及卸载后的数据保留行为仍需分别实测。

安装成功时，将实际目录写到 64 位 `HKLM\Software\BiliSail\Installer\InstallFolder`；MSI 和 EXE 后续升级均读取同一位置作为默认值。MSI 显式选择或命令行 `INSTALLFOLDER` 优先于旧位置，目录属性标为 secure 以通过权限提升边界；开始菜单快捷方式仍指向该目录。首次升级来自旧版固定目录安装器时，该注册表值可能不存在，此时继续默认 Program Files。修复属于原安装目录的维护操作，迁移到其他目录建议卸载后重新安装。静默部署可使用 `msiexec /i "BiliSail-<version>-windows-x64.msi" INSTALLFOLDER="D:\Apps\BiliSail" /qn`，不会显示目录选择页。

Windows 打包在签名之后运行 [实际产物检查](../../tool/test-windows-installer-packages.ps1)，反编译 MSI 并提取 EXE 的 BA 与 Burn manifest，验证目录页、浏览事件、双向向导跳转、路径持久化、x64 注册表读取及 EXE → MSI 参数传递；失败时 CI 不上传安装包。此检查只读取安装包，不在 CI 主机安装应用。配置依据 [WiX 对话库](https://docs.firegiant.com/wix/tools/wixext/wixui/)、[Burn 标准界面属性](https://docs.firegiant.com/wix/schema/bal/wixstandardbootstrapperapplication/) 与 [Windows Installer 对话事件顺序](https://learn.microsoft.com/en-us/windows/win32/msi/controlevent-table)。

三种安装包共用既有 `MSIX_CERTIFICATE_BASE64` / `MSIX_CERTIFICATE_PASSWORD`，证书 Subject 必须匹配固定的商店 Publisher；无 Secrets 时共用该 Subject 的临时测试证书。先签 MSIX 和 MSI，再构建 EXE，按 WiX 的 detach → 签 engine → reattach → 签 Bundle 顺序完成 EXE 签名；公钥仍通过包旁 `.cer` 导出，私钥只在既有临时签名作用域存在。每个安装包均附独立 SHA-256；任一步失败均不进入上传步骤。自签名证书不代表受系统默认信任的 Authenticode 发行身份。参见 [WiX Bundle 签名](https://docs.firegiant.com/wix/tools/signing/)。

WiX 源码采用 MS-RL，固定版本来源和内嵌 Burn 的许可见 [第三方说明](../../THIRD_PARTY_NOTICES.md)。WiX v6 的二进制发布同时适用 [Open Source Maintenance Fee 条款](https://docs.firegiant.com/wix/osmf/)；本工程不引入 FireGiant 商业扩展。`tool/check.ps1` 增加 [Windows 版本检查](../../tool/test-windows-installers.ps1)，在 Ubuntu 和 Windows 均验证补丁／构建号顺序与超限拒绝。

## Windows MSIX 签名与安装

[AppxManifest.xml](../../windows/packaging/AppxManifest.xml) 的 identity 为 `JerryHsu.BiliSail`，默认 publisher 为 `CN=D34F8E82-088B-4DC8-9296-620B8683A539`，PublisherDisplayName 为 `Jerry Hsu`；Windows 安装下限为 Windows 10 1809（build 17763）。`MakeAppx` 打包完整 Flutter Release 目录，`SignTool` 使用 SHA-256 签名。MSIX 图标在构建时从已有品牌 PNG 派生；生成普通、深色 `unplated`、浅色 `lightunplated` 的多尺寸图标，并使用同一 Windows SDK 的 `MakePri` 与 [PRI 配置](../../windows/packaging/priconfig.xml) 生成 `resources.pri`，供任务栏和开始菜单选择无底板图标。不引入新品牌资源或 Dart 依赖。

无签名 Secrets 时生成一年有效的临时自签证书，产物标记 `self-signed-preview`。安装前需要在测试机器上把对应 `.cer` 信任到 **本地计算机 → 受信任人**，再打开 `.msix`；这一步需要管理员权限。工作流只导出公钥，不上传 PFX、私钥或密码，打包结束后清理本次临时证书/私钥。每次运行的测试证书不同，不能视为长期可升级的正式发行链路。

使用固定签名证书时，在仓库 Actions Secrets 配置：

| 名称 | 内容 |
| --- | --- |
| `MSIX_CERTIFICATE_BASE64` | 带私钥的代码签名 PFX 的 Base64 |
| `MSIX_CERTIFICATE_PASSWORD` | 该 PFX 的密码；无密码 PFX 可留空 |

商店身份固定为源 manifest 中的 Name、Publisher 和 PublisherDisplayName，并在打包前后与确认的 Partner Center 身份比对。旧 Actions Variable `MSIX_PUBLISHER` 不再注入或覆盖包身份，可以移除。已配置 PFX 的 Subject 必须为 `CN=D34F8E82-088B-4DC8-9296-620B8683A539`；旧 `CN=BiliSail` 证书需要更新，否则签名阶段明确失败。PR 构建始终使用临时测试证书，避免向 PR 提供正式私钥。已配置 PFX 无效、密码错误、证书过期或 publisher 不匹配时失败，不降级成测试签名。当前未接入可信时间戳；正式发行还需完善时间戳、证书续期与升级验证。参见 [Microsoft MSIX 证书](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)、[SignTool 签名](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool)。

macOS ad-hoc 签名不能替代 Developer ID / notarization。资源许可范围沿用 [第三方说明](../../THIRD_PARTY_NOTICES.md)，公开发布前仍需完成其待核实项。

## 验证记录

### 播放页快捷键测试超时修复（2026-10-07）

[CI #23](https://github.com/CKopoer/BiliSail/actions/runs/37637676303/job/112848184331) 使用提交 `0b2605efe9fdb6fc5a30e7e8a920c47ba2540958`，依赖强校验、格式与静态分析通过；根应用测试 1292 项通过、1 项失败，后续包检查与三端构建未执行。失败位于 [播放面板测试](../../test/features/playback/playback_panel_test.dart) 的 `workspace player keys work on entry and after returning to video`，首次进入播放页的 `pumpAndSettle` 超时。

该测试的播放会话默认以真实 `Stopwatch` 驱动弹幕插值，[弹幕控制器](../../packages/bili_danmaku/lib/src/danmaku_controller.dart) 在最近播放状态更新后的 700 毫秒内保持动画，[绘制层](../../packages/bili_danmaku/lib/src/danmaku_overlay.dart) 持续请求下一帧。`pumpAndSettle` 推进 Flutter 测试的模拟时间，两者不共用时钟；快速执行的 runner 可在真实插值窗口结束前耗尽模拟的十分钟超时。本机旧测试单独通过，注入固定单调时钟、让插值保持活跃后，稳定复现同一行的超时。

修复只修改此测试：进入、离开和返回播放页时复用有限帧等待；使用固定单调时钟防止用例依赖机器速度，并断言播放已开始、插值仍活跃、隐藏／返回后的面板可见性。保留倍速、音量、seek、弹幕、全屏、非视频页快捷键屏蔽及单 surface 检查。没有修改播放器运行逻辑或放宽 CI 检查。

本机 Windows / Flutter 3.47.6 下，受控时钟的旧等待方式失败，修复后的同一用例通过；`tool/check.ps1 -EnforceLockfile` 完整通过根应用与三个包的格式、静态分析及 1696 项测试（根应用 1293、API 319、播放器 32、弹幕 52），另通过 21 项 Android 签名边界与 14 项 Windows 安装版本检查。四份锁文件无差异，本文件 18 条本地链接及 `git diff --check` 通过。修复尚未推送或远端重跑；本轮未执行安装包构建或平台实机验证。

### Windows 安装目录选择（2026-10-07）

- 使用本机 WiX 6.0.2 及固定 UI／Util／Bootstrapper 扩展，以已有完整 Release payload 重新打包 `0.3.0+2` 的 MSI 和 EXE，编译通过；再用同一临时测试证书完成 MSI 签名和 EXE 的 engine／Bundle 两阶段签名，签名后的包仍通过 21 项检查。临时私钥已清理，未添加系统信任。本轮只验证安装配置，未重新编译 Flutter，也未替换此前签名发行产物。验证包及日志在 `artifacts/windows-install-directory-validation/`。
- 新增实际产物检查通过 **21 项**，包括 MSI 目录页和浏览器、欢迎／返回跳转、确认安装、提权属性、升级目录读取与保存、快捷方式，以及 EXE Options／Browse／路径变量到 MSI 的传递。此前无目录向导的安装包被该检查正确拒绝。
- 使用 Windows Installer `MsiOpenPackageEx(..., MSIOPENPACKAGEFLAGS_IGNOREMACHINESTATE)` 的受限会话，执行包内目录恢复动作和原生 costing：默认 Program Files、显式中文／空格路径、沿用旧目录、显式路径优先于旧目录 **4 项通过**。该句柄禁止改变系统安装状态；测试没有安装、卸载应用或写入 HKLM。依据 [Microsoft 受限安装会话](https://learn.microsoft.com/en-us/windows/win32/api/msi/nf-msi-msiopenpackageexa)。
- `tool/check.ps1 -SkipPub` 通过根应用 **1286**、API **319**、播放器 **32**、弹幕 **52** 项测试，四组格式／分析通过，原有 Android 签名与 Windows 版本边界检查通过。
- PowerShell 三份修改脚本的语法解析、两个工作流的 actionlint、109 条修改文档的本地链接与差异检查通过。
- 尚未运行远端 GitHub CI，也未点击真实向导完成提权安装、实体盘落盘、卸载和跨版本升级；这些不由编译、受限目录解析或包结构检查推导为已验收。既有安装包不会自动变更，下次 CI／Release 打包采用新流程。

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


### Android 紧凑版本编码（2026-10-10）

根版本从 `0.5.5+1` 提升为 `0.5.5+2`。提交 `1e867206` 的父版本为 `0.5.3+7`，该提交改为 `0.5.4+1`；旧编码只使用构建号加 arm64 偏移，造成版本升级时 versionCode 回退。已读取公开 Release 的 `0.5.3+7` 与 `0.5.5+1` build-info，分别记录 2007、2001，签名证书 SHA-256 均为 `be3770071a0e9c71a701405a685dd455cd1baa134abd2eac2d97b9926349996e`。新编码预期 5502 高于两者；固定签名配置保持不变。

[版本回归脚本](../../tool/test-android-version.ps1) 已接入 `tool/check.ps1`，覆盖构建号/补丁/次版本/主版本进位、历史升级、最大值、范围与格式拒绝，以及实际 APK 元数据中的错误 ABI 偏移、旧编码、错误包名和 versionName。元数据校验在签名校验和上传之前执行。Release 工作流仍由手动触发，默认创建 draft + prerelease；本次用户授权的公开并设为 Latest 操作在产物核验后单独执行，不改变后续发布策略。


本轮云端 Linux 本地验证：新增版本/manifest 校验 34 项、原有 Android 签名 21 项、Windows 版本 14 项、macOS 发布检查 22 项通过；从实际 Gradle 脚本提取的 Kotlin 版本函数通过 22 项边界用例；全部 PowerShell 脚本语法解析、actionlint 1.7.12 和 `git diff --check` 通过。另下载历史两份 APK 并解析二进制 AndroidManifest.xml，确认 `0.5.3` / `2007` 和 `0.5.5` / `2001`，包名均为 `dev.bilisail.bilisail`，与历史 build-info 一致。

本地未完成根应用/包的 Flutter 格式、分析、测试或三端构建：环境未安装 Flutter，固定 SDK 源码下载成功，但 Dart SDK 下载被网络代理以 HTTP 403 拒绝。`tool/check.ps1 -EnforceLockfile` 的 PowerShell 检查已运行，Flutter 阶段无法启动；完整验证须由后续远端 CI 提供。没有执行 Android 真机覆盖安装、数据保留或播放验收。


### 统一官方 Pub 源（2026-10-11）

本次仅将 CI 和五份锁文件中的 hosted 源从 `https://pub.flutter-io.cn` 迁移到 `https://pub.dev`，保留各依赖版本、约束和内容 SHA-256；不执行 `pub upgrade`，应用版本保持 `0.5.6+2`。根锁文件迁移 128 个 hosted 条目，`bili_api` 50 个、`bili_player` 57 个、`bili_danmaku` 23 个、`bili_mux` 24 个。历史镜像配置和失败记录保留在上文，不能视为当前配置。

[Dependabot PR #5](https://github.com/CKopoer/BiliSail/pull/5) 同时包含包源及 drift/间接依赖升级；本次没有合并或照搬该 PR 的锁文件。此前其 CI 的来源冲突发生于镜像环境与官方来源锁文件之间；统一官方源后仍需分别检查后续 PR 的依赖变更和 CI 结果。


迁移前后逐份解析锁文件，确认只有 282 个 hosted URL 改变，其他字段完全一致；155 个不同的已锁定包名/版本均与 `pub.dev` API 返回的 `archive_sha256` 一致，原有效哈希全部保留。工作流通过 actionlint 1.7.12。Dart 来源规范化依据固定 SDK 3.13.5 的 [DEPS](https://github.com/dart-lang/sdk/blob/3.13.5/DEPS) 所引用的 Pub 提交，不以两个官方域名的文本相等为判断标准。本地环境缺少 Flutter/PowerShell，未在本地执行固定 SDK 的解析和完整 `tool/check.ps1`；实际严格锁文件检查与三端构建由本次推送触发的 CI 验证。

### 下载速度回归测试时序修复（2026-10-11）

[CI 38112987859](https://github.com/CKopoer/BiliSail/actions/runs/38112987859/job/114392259775) 的提交为 `8e74438e29b7efa0626768627408d294dc2712bb`。严格锁文件检查、格式和静态分析通过，根应用 1840 项测试通过、1 项失败；失败为 [下载仓储测试](../../test/features/downloads/sqlite_download_repository_test.dart) 的 `streaming progress publishes a nonzero transfer speed`，第 247 行预期观察到非零速度，实际为 `false`。后续包检查和三端构建因此没有执行，独立 MP4 原生回归已通过。

该用例使用真实服务器每隔 650 毫秒发送小块数据，并每隔 20 毫秒轮询当前状态；仓储则以客户端进度回调建立基线，至少间隔 500 毫秒才计算速度，完成时清零。服务器发送间隔不能保证客户端回调间隔，轮询也不能保证观察到短暂状态。[IOSink.flush](https://api.dart.dev/dart-io/IOSink/flush.html) 只保证底层 consumer 接受数据，不保证操作系统已发送；[HttpResponse.bufferOutput](https://api.dart.dev/dart-io/HttpResponse/bufferOutput.html) 默认开启。本机旧用例单独运行通过，但测试没有约束这些调度和缓冲条件。

修复只调整测试：使用仓储已有的可注入时钟，测试服务器关闭输出缓冲，并等待客户端发布当前块的进度后才允许发送下一块。断言通过 `changes` 订阅检查首次采样为零、250 毫秒时仍为零、500 毫秒时速度为 2048 字节/秒，以及双轨完整下载后速度清零。每次状态等待有 5 秒超时，失败清理释放发送门闩；下载实现、500 毫秒采样规则和 CI 工作流保持原值。

Windows x64、Flutter 3.47.6：修复后的定向用例和全部 53 项下载回归通过。完整 `tool/check.ps1 -EnforceLockfile` 通过格式、静态分析和 2360 项测试（根应用 1841、API 390、播放器 41、弹幕 86、MP4 2）；未设置 `BILI_MUX_LIBRARY` 的 7 项原生测试按既有规则跳过。五份锁文件没有变化，本节相对链接和 `git diff --check` 通过。本机没有应用构建、安装或实机下载验收；远端 CI 与三端构建以修复提交对应的工作流结果为准。

## 2026-10-11：允许构建号零

版本解析、Android Gradle 与 Windows MSI 校验均接受非负构建号，保留禁止前导零及平台上界。`1.0.2+0` 直接映射为 MSIX／EXE `1.0.2.0`、MSI `1.0.2000`，Android versionName 为 `1.0.2`、versionCode 为 `10200`；不附加 ABI 偏移。macOS 继续传入 build name `1.0.2` 和 build number `0`。Android 编码高于上一版 `0.5.7+5` 的 `5705`，签名配置不变。MSIX 的四段映射不变；本版本首段非零、末段为零，不代表已提交或通过 Microsoft Store 验证。

边界回归覆盖 `+0`、负数、前导零及既有上界拒绝。各平台打包时核验实际包／bundle 版本，并写入 build-info；CI 构建成功与 GitHub Release 创建／发布分别核验，不能相互替代。

Flutter 3.47.6 会将 Android 的 `--build-number 0` 归一化为 `1`（[固定 SDK 实现](https://github.com/flutter/flutter/blob/5fc346839b/packages/flutter_tools/lib/src/build_info.dart)）。因此 Gradle 优先从打包脚本已有的 `--dart-define=BILISAIL_RELEASE_VERSION=x.y.z+N` 读取原始构建号，校验名称一致后按同一公式编码；没有该 define 时保持 Flutter 默认来源。自行执行 Flutter 构建 `+0` 时也必须传入这个完整版本 define。首次 `1.0.2+0` CI 的 APK 校验已拦截该归一化造成的错误，新增 `10201` 拒绝回归，禁止将偏一的包上传。

## 2026-10-12：固定 Microsoft Store 包身份

用户确认的商店字段为 Name `JerryHsu.BiliSail`、Publisher `CN=D34F8E82-088B-4DC8-9296-620B8683A539`、PublisherDisplayName `Jerry Hsu`，目标 PFN 为 `JerryHsu.BiliSail_e5wcspfxwa6kj`。原模板已包含正确值，但 Actions 变量 `MSIX_PUBLISHER=CN=BiliSail` 在打包时覆盖 Publisher，导致 Store 同时报 Publisher 与 PFN 错误。

现在 CI 不再传入该变量，打包脚本不再接受覆盖，并通过 [身份校验](../../tool/windows-msix-identity.ps1) 检查源模板与实际 MSIX manifest 的三个身份字段及版本；实际读取的字段写入 `build-info.json` 的 `windowsMsixIdentity`。Windows 打包时通过系统 `PackageFamilyNameFromId` 从实际 Name 与 Publisher 派生 PFN，并与目标值比对，记录到 metadata；不向 manifest 添加虚构 PFN 字段。签名后校验包内 PKCS#7/CMS 的数学签名及签名证书与所选证书一致；该校验不声明系统信任链通过，也不修改证书信任区。回归覆盖旧变量隔离、错误 Publisher／Name／显示名／版本拒绝，并接入 `tool/check.ps1`。

已配置签名证书仍须匹配固定 Publisher，不自动替换密钥、不降级签名；需要维护者在 Actions Secrets 安全更新 PFX 及对应密码。身份变化后的 MSIX 不应视为原错误 PFN 侧载包的直接升级。版本号、runFullTrust 与依赖不变；本修改不自动提交 Store，也不替换已有 Release 资产。

## 2026-10-16：mux 与 Windows 安装工具缓存

CI 在安装实际编译器后调用 `build-download-mux.ps1 -CacheKeyOnly`，用精确键恢复 `build/download_mux/cache`；不使用前缀回退，不缓存整个 build、FFmpeg object tree 或 Flutter/CMake 生成目录。键包含目标平台、FFmpeg 源码 SHA、native 源码/头文件/导出表/Info.plist、全部 mux shell 构建脚本与 PowerShell 入口、编译器/strip/make 版本、MSYS2 包版本清单（含 CRT/头文件）、runner 镜像、NDK revision、Xcode/macOS SDK 版本与 build version及相关编译环境参数。构建参数在脚本内，脚本内容变化会失效。

命中后逐一检查所需二进制、许可证、source.txt、configure.log 和 macOS framework 元数据的非空性及 SHA-256；缺失或损坏则删除该目标中间目录、重新解包固定源码并正常构建。只复制白名单文件，macOS 同时重新填充 CocoaPods framework。SHA 校验用于发现损坏，不替代 Actions 缓存的信任边界；沿用 GitHub PR ref 缓存隔离，不增加权限或向 PR 传递 secrets。即使命中，源码包仍下载并核验固定 SHA，继续生成对应源码分发包。

Windows 使用独立的 `build/installer-downloads` 保存 NuGet package/HTTP 下载缓存，键含 OS、架构与 WiX 初始化脚本（含固定版本）。每轮重新安装当前主机工具 shim 并检查 WiX 版本，扩展仍按固定版本安装；安装失败只清理隔离下载目录与本轮 installer-work/tools，冷重试一次。证书、签名临时文件及安装包不进入缓存。`release.yml` 继续复用 CI，无需修改，未触发 Release 工作流。

日志增加 mux configure/compile/link/总耗时，以及 Flutter 命令、Windows 安装工具准备、打包/签名/校验总耗时。Flutter build windows 仍包含 CMake、依赖、插件和 Dart 阶段，不能称为纯 C++ 编译时间。暂不增加 Windows C++ 编译缓存：尚未验证 Flutter 使用的 Visual Studio/MSBuild 路径与编译缓存工具的兼容性，不能通过缓存整个 build 目录跳过原生生成与链接。

可执行回归入口为 `bash tool/test-mux-cache.sh`：在独立临时目录验证源码/参数失效、冷构建、热命中、损坏二进制及缺少配置文件后的重建。本次 Linux 验证耗时与 Windows hosted runner 不可直接比较；Windows 实际收益需由同一提交的 CI 冷/热运行确认。完整 `tool/check.ps1 -EnforceLockfile` 在本地通过五组 PowerShell 边界测试后因缺少 Flutter 停止；应用测试与 Windows/macOS 构建仍需 CI。
