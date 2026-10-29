# macOS 发布启动与安全存储

日期：2026-10-08；验证更新：2026-10-29。当前配置提供 arm64／Intel x64、ad-hoc 签名、未公证的预览 DMG，两种架构沿用相同发布门槛。[CI #221](https://github.com/CKopoer/BiliSail/actions/runs/40804720827)（代码提交 `64acaa709315b9c91e15c67ae173f56b05689570`）的两种架构均通过构建、签名校验、待打包应用首帧和跨进程合成 Keychain 读写／删除验证，并完成 DMG 打包。设备安装升级、Gatekeeper、真实账号与音画播放仍未验收。

## 根因与配置

原 [Release](../../macos/Runner/Release.entitlements) 和 [Debug/Profile](../../macos/Runner/DebugProfile.entitlements) 都声明了空 `keychain-access-groups`。空数组仍启用受限的 Keychain Sharing；它与 [构建脚本](../../tool/build-release.ps1) 的 `CODE_SIGN_IDENTITY=-` 不相容，可能在 Dart 入口执行前被系统拒绝加载。按用户提供的上一轮系统日志，这是本次待修复的启动拦截原因；本机未重新采集该日志。

修复删除两份文件的 Keychain Sharing 项，保留 Sandbox、客户端网络和 Debug/Profile 的 JIT／服务端网络权限。[SystemCredentialStore](../../lib/core/storage/credential_store.dart) 的默认插件实例使用：

```dart
const FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
)
```

macOS 使用传统系统 Keychain，不降级为明文文件或数据库。Android、Windows、iOS 等平台选项保持插件原默认值；既有 `bilisail.web_session.v1` 前缀、服务名和双 slot／active 协议保持。锁定的 `flutter_secure_storage 11.2.0` 与 `flutter_secure_storage_darwin 0.4.3` 已支持此选项，无需升级。来源为 [11.2.0 维护方说明](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0#macos-keychain-sharing-requires-provisioning)，已核对本地锁文件及插件实现。

## 发布门槛

调用链继续为 `release.yml → ci.yml → tool/build-release.ps1`。macOS 分支构建、验证对应的 arm64／x86_64 架构、使用 `ditto` 复制后，直接运行待打包 bundle。没有另编译测试应用，也没有通过重新签名规避检查。[验证辅助脚本](../../tool/macos-release-validation.ps1) 执行：

1. `codesign --verify --deep --strict` 校验应用及嵌套代码的签名完整性；从 `codesign --display --entitlements :-` 提取最终主程序权限。接受并要求启用 Sandbox、客户端网络和图片目录读写权限（2026-10-25 为原图保存新增 `com.apple.security.assets.pictures.read-write`，见[图片查看器保存与长图](image-viewer-export-long-images.md)）；空 Sharing、其他额外权限、重复／缺失／禁用权限均失败。禁止携带机器专用 `embedded.provisionprofile`。
2. 运行同一 `Contents/MacOS/BiliSail` 的 `startup` 阶段：从 headless engine 创建明确的主浏览窗，执行正常应用依赖组装与 `BiliApp`，等待首帧 rasterize，继续运行三秒，再实际创建／挂载／激活／回收两轮独立播放窗，验证新增 view 与视口及标题栏返回通道。最后卸载 UI 并关闭应用资源。应用内回退、Flutter／未处理异步错误均使探测失败。窗口初始化原因见[双标签崩溃修复](macos-dual-playback-crash.md)。
3. 全新进程执行 `write`：直接通过真实默认 `SystemCredentialStore` 写入非敏感合成值，读取核对，再写第二份快照并读取，覆盖双 slot 和 active 切换。凭据阶段只启动同一应用的 headless engine／插件，不创建窗口、不组装首页业务依赖；完整应用及窗口初始化由前一 `startup` 阶段单独验证。
4. 再启动同一应用执行 `read-delete`：读取上一进程保存的值并核对，删除，仅检查本次探测的 active／a／b 三个 key。
5. 再次启动执行 `verify-deleted`，核对三个 key 均不存在。启动、写入和读取阶段使用同一 UUID 前缀，避免“重启后重新写值”掩盖持久化失败。
6. 再次校验 bundle 签名与最终权限，通过后才创建并校验 DMG，最后生成 metadata 和 SHA-256。`macosValidation` 只记录成功状态。

每个子进程分别限制原生启动与 Dart 探测执行：从创建进程到收到第一条 `dart-entry` 最多 180 秒；收到该标记后最多再运行 60 秒，后续重复标记不能重置时限。必须退出码为 0、确认到达 Dart 入口，且返回匹配阶段和 UUID 的完整 stdout 确认行；只看到进程启动、退出码 0 或磁盘文件存在均不算通过。每个凭据步骤另有 10 秒上限，原生调用挂起时退出失败，不重放结果不明的写入。失败时终止本次创建的子进程，并用相同 bundle 的 `cleanup` 阶段删除本次前缀（含 bootstrap／recommendation 辅助前缀）；清理失败仍保持构建失败并明确警告，不自动重试真实账号写操作。进程终止和输出排空各有独立的 5 秒上限，不能在超时后的清理中无限等待。

[Dart 探测逻辑](../../lib/app/release_smoke.dart) 只接受显式 `--bilisail-release-smoke <phase> <32位UUID>`，由 [正常入口](../../lib/main.dart) 在 macOS 路由。Flutter macOS 默认将原生进程参数传给 Dart 入口，见 [FlutterDartProject](https://api.flutter.dev/macos-embedder/_flutter_dart_project_8h_source.html)。普通启动不启用探测。`startup` 注入内存 SQLite、独立的空 bootstrap 会话凭据和 recommendation 旧 App 凭据前缀，不恢复真实账号、不修改用户数据库；网络页面仍可请求公开内容，网络成功不是该探测的验收条件。

测试 key 为 `bilisail.release_smoke.v1.<UUID>.active/a/b`，只保存合成字符串；不调用 `deleteAll`，不读取正式登录 key。最终权限和脱敏的阶段／退出码／确认状态按目标保存在 `artifacts/macos-arm64/validation/` 或 `artifacts/macos-x64/validation/`，不保存原生／网络原始输出。2026-10-29 起失败任务只上传脱敏的 `*.result.json`，不上传该目录的其他文件。metadata 仅含通过状态，不含真实凭据、测试值或 Keychain 内容。

Intel CI 首次执行启动探测时曾达到原有 60 秒上限。固定 SDK 的普通窗口构造不会激活应用，而原探测在首帧完成后才激活；显式 smoke 现在先激活主窗口再等待首帧，避免后台显示前提造成的等待环。探测监督脚本实时排空两路输出，只导出固定启动阶段、数字焦点状态和脱敏 JSON；不保存原生／网络原始行。普通启动不启用这些探测日志。

## CI #222：凭据探测隔离（2026-10-29）

[失败任务](https://github.com/CKopoer/BiliSail/actions/runs/40823201155/job/123282232244) 对应提交 `5fa56a287239075a46d1124206bc2b24dc06c700`。全部离线检查、原生 mux 回归及其余五个构建目标通过；macOS x64 已完成 Release 编译、签名校验、主窗首帧和两轮播放窗验证。随后独立 `write` 进程记录了 `first-frame`，没有记录 `credentials`，60 秒后被打包脚本终止；失败清理通过。同次 arm64 四个阶段全部通过，因此不能把失败归为编译、DMG 创建或已确定的首帧问题。

原凭据进程重复挂载完整 `BiliApp`；首页恢复游客会话时，`AppRecommendationIdentityStore` 会异步清理旧 App 凭据。虽然 Web 会话已注入随机 bootstrap 前缀，推荐仓储仍在 `AppDependencies` 内硬编码正式 `bilisail.app_recommendation.v1`。锁定的 Darwin 插件在单个串行队列中处理所有 Keychain 操作，业务清理可与合成探测交错，也使原本声称隔离的启动检查访问了正式前缀。源码与新增游客清理回归确认这一隔离缺口；现有失败日志缺少细分步骤，不能确认原生调用是否等候系统授权或具体哪一次读写挂起。

修复将 `write`／`read-delete`／`verify-deleted`／`cleanup` 提前到业务依赖和窗口创建之前，仍使用待打包 bundle 的真实插件、默认 Keychain 选项及原双 slot 协议。`startup` 继续执行完整应用／多窗口门槛，并通过组合根为推荐凭据注入本次 UUID 前缀。新增固定凭据步骤标记及 10 秒步骤超时；打包脚本只接受白名单标记，将最后一步保存到既有 `*.result.json` 的 `lastStage`，不记录 key、值、异常详情或原始输出。原 60 秒进程上限、签名／权限校验、跨进程读取和失败阻断均保留。

本轮 Windows / Flutter 3.47.6 的 9 项 Dart 探测回归和 PowerShell 权限／确认行／脱敏检查通过，覆盖真实游客清理路径保留正式凭据、挂起写入超时后不重放、不执行后续步骤，以及辅助前缀清理。`tool/check.ps1 -SkipPub` 完整通过格式、静态分析、打包边界检查及 4080 项测试（根应用 3369、API 492、播放器 96、弹幕 118、封装 5）；13 项 Windows 符号链接用例因权限不足跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过。五份锁文件未变化；两份 PowerShell 脚本解析、11 个本地文档链接和 `git diff --check` 通过。未发现可连接的调试应用，未执行热重载；没有构建、安装或实机操作。macOS x64 的修复结果须由后续 CI 实际执行确认；本机不能复现或证明系统 Keychain 授权行为。

## CI #223：区分原生启动与探测执行（2026-10-29）

[后续失败任务](https://github.com/CKopoer/BiliSail/actions/runs/40841368541/job/123341427493) 对应隔离修复提交 `aa4f310c42473d145d2b524518e5ebb04f8aa998`。本次 x64 的完整 `startup`、`write`、跨进程 `read-delete` 均通过，`verify-deleted` 超时；其诊断文件明确记录 `stderrPresent=false`、`lastStage=null`、退出码 137（监督脚本终止），没有进入第一步 `deleted` 的证据，随后的同 bundle `cleanup` 也通过。因此上轮隔离缺口不能解释全部失败，本轮不能再把问题归为已确认的 Keychain 读写卡死。

旧监督脚本只给整个进程 60 秒，且退出后才打印汇总输出，无法区分原生装载／插件初始化、进入 Dart 和执行凭据调用的耗时。同次成功的 `write` 进程在前一阶段通过约 59 秒后才汇总完成，说明这个统一限额缺少可靠的执行阶段边界；日志仍不能确定无输出的原生等待发生在加载器、Cocoa、插件还是 Dart engine 内。

本次在原生 application／engine／插件注册和 Dart 入口添加固定标记。监督脚本同时逐行读取 stdout／stderr，在收到第一条 `dart-entry` 前使用 180 秒启动限额，再单独执行原有 60 秒探测限额；凭据步骤仍限制 10 秒，没有自动重试或跳过。重复入口标记不会续期。实时输出附带进程阶段和单调毫秒数；`*.result.json` 只保留白名单阶段与时间、`timeoutKind=launch/probe`、进程创建／到达 Dart／探测执行耗时及有限数量的轨迹，不写原始行、路径、凭据或测试值。

[真实子进程回归](../../tool/fixtures/macos-smoke-process.ps1) 由已有 PowerShell 边界检查调用，覆盖启动耗时超过执行限额仍可通过、原生启动超时、原生阶段记录、Dart 执行超时、重复入口不续期、非零退出、缺少确认、仅 stderr 确认、缺少 Dart 入口，以及两路大量输出无死锁与脱敏。此类回归验证监督脚本的计时、失败阻断和输出处理；不替代 macOS 的原生启动复验。

本轮 Windows / Flutter 3.47.6 的 `tool/check.ps1 -SkipPub` 完整通过格式、静态分析、打包边界及 4080 项测试（根 3369、API 492、播放器 96、弹幕 118、封装 5），13 项 Windows 符号链接和 10 项未配置 mux 原生库的用例按环境跳过。新增 10 个真实子进程场景在完整检查中及定向复验均通过；三份 PowerShell 脚本解析、12 个本地文档链接和 `git diff --check` 通过，五份锁文件未变化。没有可连接的调试应用，未热重载；Swift／真实 macOS 启动与 DMG 打包以修复提交对应的新 CI 结果为准。

### CI #224 实际执行结果

[CI #224](https://github.com/CKopoer/BiliSail/actions/runs/40851739162) 对应修复提交 `98040b8aa2c46acc2067d965716af93ea64f03c0`，工作流已结束且结论为 `success`，全部检查、独立原生 mux 回归及六个构建目标均通过。macOS [x64](https://github.com/CKopoer/BiliSail/actions/runs/40851739162/job/123376492094) 和 [arm64](https://github.com/CKopoer/BiliSail/actions/runs/40851739162/job/123376491977) 均通过 Release 编译、最终签名与权限校验、四个真实启动／跨进程凭据阶段及 DMG 创建、校验和上传。Swift 标记与实时输出监督已在两种 Mac runner 执行通过。

x64 日志中，`startup`／`write`／`read-delete`／`verify-deleted` 从创建进程到 Dart 入口分别为 3872／463／470／428 毫秒，`verify-deleted` 随即完成 Keychain 空值核对并成功退出。本次未复现 CI #223 的无输出原生等待，也未用到扩大的启动预算；该次通过不能反推上一轮具体是哪一个系统调用阻塞。新增回归已独立证明启动预算与执行预算分开、重复入口不续期、步骤超时和失败阻断，后续若再出现等待，可通过原生阶段、`timeoutKind` 与单调时间定位。实际设备安装升级、Gatekeeper、真实账号和音画播放仍不包含在本轮 CI 验收内。

## 旧数据与升级单独验收

Keychain 后端选择改变不会自动迁移原 Data Protection Keychain 的条目。传统 Keychain 中已有的同服务／同 key 条目沿用原身份；旧 Data Protection 条目的可访问性受原签名、provisioning 和系统授权影响，不能假设移除 Sharing 后仍可读取。不尝试用缺权限的新签名强读旧库，也不自动删除旧后端条目；无法恢复时按现有登录流程重新登录。

macOS 验收需分别记录：

| 场景 | 验收条件 |
| --- | --- |
| 全新安装／新用户 | 实际 DMG 挂载、拖入 Applications、从已安装路径启动；登录保存、完全退出、重启恢复、退出登录后重启保持游客 |
| 已有旧版本登录数据 | 记录旧版本签名和 Keychain 后端；升级前后恢复状态及授权提示；无法恢复时明确重新登录且无明文降级 |
| 两份不同内容的 ad-hoc 构建升级 | 第二份应用有不同签名哈希；从安装路径读第一份保存的隔离测试值，再写、重启、删除，记录系统访问提示和失败行为 |
| 不同 Mac／下载隔离属性 | 下载实际 DMG 并验证 Gatekeeper 路径；runner 同机启动不代表其他设备或受隔离下载的启动行为 |
| Debug/Profile | 本地调试能启动，传统 Keychain 写／读／删除；不将 Release 检查替代调试实测 |

## 本机验证边界

[离线 PowerShell 检查](../../tool/test-macos-release-validation.ps1) 已接入 `tool/check.ps1`，覆盖来源权限、最终权限白名单与失败确认行；[Dart 回归](../../test/app/release_smoke_test.dart) 覆盖平台选项、参数隔离、双 slot 跨实例读取、静默写失败、缺失持久化值、孤儿 slot 删除与真实 key 保留。fake 回归不等于系统 Keychain 验收。

2026-10-08 初次修复的 `tool/check.ps1 -SkipPub` 通过根应用与三个包的格式、静态分析和 1708 个测试（根 1305、API 319、播放器 32、弹幕 52）；当时新增 6 个 Dart 回归和 20 个 macOS 发布脚本边界检查通过。PowerShell 解析、149 条相关文档／源码相对链接及 `git diff --check` 通过，四份锁文件未改变。该历史结果不替代上面的 CI #222 修复验证。

本机 Windows 无 `codesign`／`hdiutil`／Xcode 或 macOS GUI，不能确认真实 Release 首帧、插件 Keychain 调用、AMFI、DMG 安装、公证／Gatekeeper 或旧数据升级授权。以上门槛已实现，macOS 真实执行结果在运行后补充。
