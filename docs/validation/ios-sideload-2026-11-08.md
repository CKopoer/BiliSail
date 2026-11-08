# iOS 1.2.8 侧载重签兼容性

日期：2026-11-08（Asia/Shanghai）。对应 [issue #96](https://github.com/CKopoer/BiliSail/issues/96)：iPad Pro 使用 Sideloadly 安装 1.2.8 时，在 `Avutil.framework/Avutil` 上报 `macho sign/edit failed (-18)`；同一用户的 1.2.7 可以侧载。失败发生在电脑重签阶段，尚未进入设备启动或播放器初始化。

## 已发布资产的差异

直接读取 [1.2.7+0](https://github.com/CKopoer/BiliSail/releases/tag/v1.2.7%2B0) 和 [1.2.8+0](https://github.com/CKopoer/BiliSail/releases/tag/v1.2.8%2B0) 的 IPA 中央目录，按 ZIP entry 范围下载、解压 Avutil，并核对其 CRC-32。没有用本地源码构建物代替用户下载的文件。

| Avutil 项目 | 1.2.7+0 | 1.2.8+0 |
| --- | --- | --- |
| Mach-O 容器 | thin 64-bit arm64，magic `cffaedfe` | FAT，magic `cafebabe`，**仅一个 arm64 slice** |
| 文件长度 | 538576 bytes | 537080 bytes |
| arm64 slice | 整个文件 | offset 32768，length 504312，alignment 2^15 |
| `LC_CODE_SIGNATURE` | 无 | 无 |
| 文件 SHA-256 | `2be464b4e90598f3c13b0da80575788c509849f25dfd8dee32a37d2572a5da6b` | `61a395b748e6536b90f23eef2ec020d027eaa81911a7efc2bbd3574c19aafa23` |

1.2.7 后的[个人媒体 fork 迁移](media-kit-personal-fork-2026-11-07.md)将 iOS 原生库从旧 fork 的资产换成官方基线 v0.7.2 的固定镜像。实际 IPA 中，Avfilter、Avformat、Png16、Dav1d、Freetype、Ass、Harfbuzz、Mpv 等媒体库也从 thin 变为 FAT。旧版本部分其他插件已经包含带签名的 FAT 文件，不能把“存在 FAT”或“未签名”单独等同于所有侧载失败。

确认的打包回归是这些媒体库成为**无签名的单 slice FAT**，与 issue 的 Avutil 重签失败位置吻合；Sideloadly 需要在 FAT 内新建签名，而旧文件走 thin 重签路径。这是基于真实资产差异和用户版本对照的兼容性定位，未直接调试 Sideloadly 闭源签名器，不能仅凭 `-18` 宣称其具体内部算法有误。

原[发布脚本](../../tool/build-release.ps1)只运行 `lipo -verify_arch arm64`，它允许单 slice FAT 通过；`flutter build ios --no-codesign` 也不为未签名的第三方二进制预建签名。既有 [BiliMux 布局检查](../../tool/ios-package-validation.ps1)针对旧的 `Resources/` 安装错误，不能发现本次重签输入问题。

## 修复流程

[ios-sideload.py](../../tool/ios-sideload.py)只处理复制后的暂存 `Payload/Runner.app`，不改 Pub 缓存、上游归档、固定摘要或其他平台：

1. 枚举所有 Mach-O，包括 framework、主程序和独立 dylib；FAT 文件显式执行 `lipo -thin arm64`，即使只有一个 slice 也不跳过。替换前校验实际 thin 文件的 CPU、subtype、load commands，并保留文件权限。
2. 将内层代码、framework bundle 和应用从内向外执行 `codesign --force --sign - --timestamp=none`，重新生成资源封印；随后检查每个二进制的签名命令及 blob 边界，并运行 `codesign --verify --deep --strict`。准备、签名或校验失败均阻止打包。
3. `ditto` 压缩完成后重新读取实际 IPA，要求主程序存在，并再次检查包内每个 Mach-O 都是 arm64 thin 且有签名结构。既有 Payload、版本、身份和 BiliMux 检查继续执行。

Apple [说明](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)中的伪身份 `-` 生成 ad-hoc 签名，无需开发者证书或 Apple 账号。这里为后续重签准备二进制结构，**并未提供可直接安装的 Apple 开发／分发签名**；产物仍叫 `-unsigned.ipa`，用户仍需用自己的侧载签名流程处理。

## 本轮验证与边界

- Windows 的 LLVM `lipo -thin arm64` 对真实 1.2.8 Avutil 执行成功，输出与原 FAT 中 504312-byte arm64 slice 逐字节一致。关闭签名要求的容器／架构检查接受 1.2.7 thin、拒绝原 1.2.8 FAT、接受提取后的真实 thin；两个 Avutil 的 ZIP CRC-32 均匹配。实际 IPA 中 Flutter 已签名的 thin 二进制也通过完整的签名结构检查。
- [6 项离线回归](../../tool/test_ios_sideload.py)通过，覆盖单 slice FAT、缺签名、错误架构、损坏 load commands／签名范围、原生命令失败、无效 thinning 保留原文件、从内向外签名、资源保留、最终 ZIP 新增错误二进制和缺失主程序。已接入根检查及 CI 的 Lint 阶段。
- `tool/check.ps1 -SkipPub` 通过格式、静态分析、打包边界及 5952 项 Dart／Flutter 测试（根应用 4726、API 719、播放器 341、弹幕 161、mux 5）。13 项 Windows 符号链接用例因权限跳过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。修改的 Python／PowerShell 语法、三份文档的 259 条本地链接和 `git diff --check` 通过。
- 本机是 Windows，没有执行 Apple `lipo`／`codesign`、Xcode 构建、新 IPA 生成、Sideloadly 重签或 iPad 安装／启动。LLVM 操作与 mock 签名回归不代替这些验收；实际侧载结果仍待新构建和用户设备确认。已发布的旧附件没有被替换。

本地诊断材料与检查日志保存在忽略目录 `build/ios-sideload-investigation/`。
