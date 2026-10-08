# macOS 发布启动与安全存储

日期：2026-10-08。当前保持 arm64、ad-hoc 签名、未公证的预览 DMG 分发方式。此修复在 Windows 主机实施；macOS 构建、真实 Keychain 和安装升级结果仍须由 macOS 执行记录确认。

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

调用链继续为 `release.yml → ci.yml → tool/build-release.ps1`。macOS 分支构建、验证 arm64、使用 `ditto` 复制后，直接运行待打包 bundle。没有另编译测试应用，也没有通过重新签名规避检查。[验证辅助脚本](../../tool/macos-release-validation.ps1) 执行：

1. `codesign --verify --deep --strict` 校验应用及嵌套代码的签名完整性；从 `codesign --display --entitlements :-` 提取最终主程序权限。仅接受启用的 Sandbox 与客户端网络权限；空 Sharing、其他额外权限、重复／缺失／禁用权限均失败。禁止携带机器专用 `embedded.provisionprofile`。
2. 运行同一 `Contents/MacOS/BiliSail` 的 `startup` 阶段：执行正常应用依赖组装与 `BiliApp`，等待首帧 rasterize，继续运行三秒，卸载 UI 并关闭应用资源。Flutter／未处理异步错误均使探测失败。
3. 全新进程执行 `write`：通过真实默认 `SystemCredentialStore` 写入非敏感合成值，读取核对，再写第二份快照并读取，覆盖双 slot 和 active 切换。
4. 再启动同一应用执行 `read-delete`：读取上一进程保存的值并核对，删除，仅检查本次探测的 active／a／b 三个 key。
5. 再次启动执行 `verify-deleted`，核对三个 key 均不存在。启动、写入和读取阶段使用同一 UUID 前缀，避免“重启后重新写值”掩盖持久化失败。
6. 再次校验 bundle 签名与最终权限，通过后才创建并校验 DMG，最后生成 metadata 和 SHA-256。`macosValidation` 只记录成功状态。

每个子进程最多运行 60 秒，必须退出码为 0 且返回匹配阶段和 UUID 的完整确认行；只看到进程启动、退出码 0 或磁盘文件存在均不算通过。失败时终止本次创建的子进程，并用相同 bundle 的 `cleanup` 阶段删除本次前缀；清理失败仍保持构建失败并明确警告，不自动重试真实账号写操作。

[Dart 探测逻辑](../../lib/app/release_smoke.dart) 只接受显式 `--bilisail-release-smoke <phase> <32位UUID>`，由 [正常入口](../../lib/main.dart) 在 macOS 路由。Flutter macOS 默认将原生进程参数传给 Dart 入口，见 [FlutterDartProject](https://api.flutter.dev/macos-embedder/_flutter_dart_project_8h_source.html)。普通启动不启用探测。启动过程注入内存 SQLite 和独立的空 bootstrap 凭据前缀，不恢复真实账号、不修改用户数据库；网络页面仍可请求公开内容，网络成功不是该探测的验收条件。

测试 key 为 `bilisail.release_smoke.v1.<UUID>.active/a/b`，只保存合成字符串；不调用 `deleteAll`，不读取正式登录 key。最终权限和脱敏的阶段／退出码／确认状态保存在 `artifacts/macos-arm64/validation/`，不保存原生／网络原始输出，不上传该目录。metadata 仅含通过状态，不含真实凭据、测试值或 Keychain 内容。

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

本轮 `tool/check.ps1 -SkipPub` 通过根应用与三个包的格式、静态分析和 1708 个测试（根 1305、API 319、播放器 32、弹幕 52）；新增 6 个 Dart 回归和 20 个 macOS 发布脚本边界检查通过。PowerShell 解析、149 条相关文档／源码相对链接及 `git diff --check` 通过，四份锁文件未改变。

本机 Windows 无 `codesign`／`hdiutil`／Xcode 或 macOS GUI，不能确认真实 Release 首帧、插件 Keychain 调用、AMFI、DMG 安装、公证／Gatekeeper 或旧数据升级授权。以上门槛已实现，macOS 真实执行结果在运行后补充。
