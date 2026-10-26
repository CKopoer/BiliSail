# iOS BiliMux 重签名兼容性排查

日期：2026-10-26。

用户截图由主会话实际查看并逐字转录；执行环境的 Library 图片下载失败，未在本环境重新看到像素。[issue #13](https://github.com/CKopoer/BiliSail/issues/13) 也报告 Release 1.2.1 在全能签 17 失败，但尚未证明两份附件相同。用户截图 UI 为「全能签 V27.1.0」，关键错误为：

```text
开始校验（全包 Mach-O embedded，共 34 个）
Frameworks/BiliMux.framework/BiliMux embedded 签名校验失败
Info.plist无效（plist或签名已被修改）
全包 Mach-O embedded 校验失败（1/34 未通过）
打包成功（未完整签名）
```

这是重签名后的校验失败，不是 Xcode 编译失败。截图还显示将版本限制改成 iOS 10.0；项目真实最低版本为 iOS 15，改 plist 不能降低已编译二进制的系统要求。

## 原包证据

本轮独立下载 [Release +4 原始 IPA](https://github.com/CKopoer/BiliSail/releases/download/v1.2.1%2B4/BiliSail-1.2.1%2B4-ios-arm64-unsigned.ipa)，SHA-256 为 `e7e1ece6f97a73e406824046873361842500d465f355055cffe6d0f9686f056a`；配套 build-info 的源码为 `b623dd11b563aa71750df52a03bc18484cd11d86`。它早于本轮 fetch 的 master `45fb2fc6cccf57b409356244572b94b7b6d6a482`，不能将两者混为同一产物，也不能断言截图就是 +4。

原包含 34 个 Mach-O，全部 slice 为 iPhoneOS arm64。BiliMux 没有 `LC_CODE_SIGNATURE`、没有 `__info_plist`，外部 Info.plist 可以由标准 plist 解析器读取，最低版本 15.0。因此没有证据支持「BiliMux 残留签名」「嵌入 plist 与外部不一致」或「混入 simulator/macOS」作为该原包根因。其他部分 Flutter/native-assets framework 有自身签名；`--no-codesign` 表示未生成可安装的应用签名，不保证依赖完全没有签名。

当前能定位到的是重签名器对 BiliMux 的 Info.plist 绑定失败；无法从未重签名的原包还原失败后的 CodeDirectory。BiliMux 特有的手工紧凑 XML 与缺少 `CFBundleInfoDictionaryVersion` 是待实机验证的兼容性因素，不能把 XML 本身称为无效 plist，也不能声称已证明全能签内部根因。

## 修改与验证边界

兼容性修复仅针对 iOS：补齐 plist 格式版本，在框架分发前用 Apple `plutil` 生成 binary plist，两个框架副本使用同一份处理后字节。未添加嵌入 plist、清除全包签名、降低系统版本或改变 entitlement。新增 [IPA 检查](../../tool/ios-package-validation.py) 遍历全部 Mach-O slice 的设备平台／架构，核对 BiliMux 元数据；macOS 打包后在临时副本运行 ad-hoc `codesign --verify --strict` 并直接核对 CodeDirectory 的 Info.plist slot -1 与最终文件字节。该副本不进入交付 IPA，不需要用户证书。[Apple 对 special slot -1 的说明](https://developer.apple.com/documentation/technotes/tn3126-inside-code-signing-hashes)

本地 11 项定向回归覆盖 simulator／macOS arm64 拒绝、错误架构、fat slice、截断 Mach-O、缺失签名、未绑定 plist、plist 内容及序列化改变后的哈希不匹配和最终 IPA 校验；Bash 语法与 diff 检查通过。本环境无 Flutter／PowerShell／Xcode，根检查和真正的 ad-hoc 探针交由分支 CI。没有用户证书、失败后的重签名 IPA 或全能签实机验证，最终重签名、安装及启动仍未验证。
