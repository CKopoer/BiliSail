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

## 框架布局与签名绑定

第一轮修改曾仅规范化 plist 序列化和补齐格式版本，但 [CI 的新包签名探针](https://github.com/CKopoer/BiliSail/actions/runs/40318200923/job/121558889332) 仍失败。另用 [原始 +4 BiliMux 做对照](https://github.com/CKopoer/BiliSail/actions/runs/40318635224/job/121560793060)：Apple `codesign --verify --strict` 报告 valid on disk，但 CodeDirectory 的 slot -1 不匹配根目录 Info.plist。这说明不能仅依赖 codesign 的表面验证，也不支持把紧凑 XML 当作根因。

原构建脚本把 iOS 的 `Info.plist` 放在 framework 根目录，却将许可证／来源／配置放入保留的 `Resources/` 目录，混合了扁平 iOS 和旧式框架布局。Apple [CFBundle 布局判定](https://github.com/apple-oss-distributions/CF/blob/dc54c6bb1c1e5e0b9486c1d26dd5bef110b20bf3/CFBundle_Resources.c#L222) 会优先将含 Resources 的 framework 识别为 version 0；[plist 查找](https://github.com/apple-oss-distributions/CF/blob/dc54c6bb1c1e5e0b9486c1d26dd5bef110b20bf3/CFBundle_InfoPlist.c#L451) 随之转向 Resources。Apple [签名实现](https://github.com/apple-oss-distributions/Security/blob/db15acbe6a7f257a859ad9a3bb86097bfe0679d9/OSX/libsecurity_codesigning/lib/bundlediskrep.cpp#L343) 只绑定 CFBundle 返回的 plist 路径，不会另找根目录文件。这解释了「框架签名可验证，但外部根 plist 未被正确绑定」的风险。

## 修改与验证边界

最终修改保留原始 Info.ios.plist 字节及 iOS 15 要求，撤回仅格式规范化的尝试。仅在 iOS 分支将许可证、来源与配置复制到框架根目录，保留全部合规材料；重复构建时移除原脚本生成的旧 Resources 文件并要求目录为空后删除，避免缓存残留。macOS 的 Resources 布局不变。

新增 [IPA 检查](../../tool/ios-package-validation.py) 遍历全部 Mach-O slice 的设备平台／架构，拒绝 BiliMux 的保留 Resources 目录；在临时副本 ad-hoc 签名并执行严格验证，同时直接核对非空的 Info.plist slot -1。签名副本不进入交付 IPA，不需要用户证书。CI 的三组对照使用固定哈希的旧版 IPA 和相同旧二进制，分别保留原布局、仅规范化元数据、只将 Resources 内容移到根目录；第三组还要求原始 plist 字节不变，以隔离目录布局变量。

本地 12 项定向回归覆盖错误平台／架构、fat slice、截断 Mach-O、缺失签名、空／缺失 plist 槽、内容及序列化改变后的哈希不匹配、XML 与 binary plist 的合法扁平布局，以及错误 Resources 布局拒绝；Bash 语法与 diff 检查通过。本环境无 Flutter／PowerShell／Xcode，完整构建、三组对照与实际签名探针以最新分支 CI 为准。

没有用户证书、失败后的重签名 IPA 或全能签实机验证，不能宣称最终重签名、安装及启动通过，也不能证明全能签使用的内部实现与 Apple 相同。

## 远端验证结果

[CI 40320818235](https://github.com/CKopoer/BiliSail/actions/runs/40320818235) 的代码提交为 `55ae4d9a795ab157ac623a8fc506c1010c0ae4dc`。全部格式／分析、根应用两组测试、独立包测试、原生 mux 回归通过；[iOS job](https://github.com/CKopoer/BiliSail/actions/runs/40320818235/job/121567975809) 成功构建并上传 IPA。

三组对照的实际日志：

| 对照 | Apple 严格签名验证 | 根 Info.plist 的绑定 |
| --- | --- | --- |
| 原始旧包布局 | 通过 | `Info.plist=not bound`，slot -1 为空，复现缺陷 |
| 仅修改 plist 格式／格式版本 | 通过 | 仍为 `Info.plist=not bound`，slot -1 为空 |
| 仅扁平化资源布局 | 通过 | `Info.plist entries=8`，slot -1 与原 plist 字节一致 |

第三组使用完全相同的旧 BiliMux 二进制与原始 XML，仅移动三个资源文件。最终新 IPA 又独立通过 34 个 Mach-O 的设备平台／架构检查、BiliMux 临时副本 ad-hoc 严格验证及非空 plist 哈希槽验证，日志为 `Disposable BiliMux ad-hoc signature and Info.plist slot -1 verified`。证据确认目录布局导致 plist 未绑定；这不等于全能签实机验收。

[iOS artifact](https://github.com/CKopoer/BiliSail/actions/runs/40320818235/artifacts/12648484588) 的 ZIP SHA-256 为 `dea31089c67f490dbca560830ac35d3e53fb03e3233b7f88a7632fdce46d65d4`，保留至 2026-11-09。产物源码为上述 `55ae4d9`；后续提交只补本文验证记录，不改变构建代码。未合并 master、未创建或发布 Release。
