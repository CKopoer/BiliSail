# Windows ARM64 媒体资产清单校验修复

日期：2026-11-08。

## 失败证据与原因

[CI 42474110345](https://github.com/CKopoer/BiliSail/actions/runs/42474110345) 对应提交 `0dee85db1c1c1104e819419b3a04b5b7cd6b9664`。格式／分析、两份根测试分片、包测试、mux 原生回归及其他六个平台构建均成功；唯一失败为 [Windows ARM64 构建](https://github.com/CKopoer/BiliSail/actions/runs/42474110345/job/128713756281)。

该任务已完成 Windows 媒体归档准备、MDK 解压和 ARM64 ANGLE 导入库生成，随后在 CMake 配置阶段进入应用的 `bilisail_verify_media_assets()`，报告 `list index: 6 out of range (-6, 5)`，并误报 SDK 缺少 `LICENSE.LGPL`。失败发生于 11:25:15 UTC（北京时间 19:25:15）。

当前固定的个人 media-kit 提交为 `b1c7e4336140d8c4550c1e963365da8edfe56d0a`。[默认清单](https://github.com/CKopoer/media-kit/blob/b1c7e4336140d8c4550c1e963365da8edfe56d0a/libs/windows/media_kit_libs_windows_video/windows/native-assets.cmake) 包含 x64 SDK 的 51 个文件及配对哈希，其中前六项为 DLL、导入库和四个 mpv 头文件，其余为 x64 归档中的许可／来源材料。[ARM64 清单](https://github.com/CKopoer/media-kit/blob/b1c7e4336140d8c4550c1e963365da8edfe56d0a/libs/windows/media_kit_libs_windows_video/windows/arm64/assets.cmake) 替换了归档、地址、摘要及六个 SDK 文件的哈希，但未替换继承的文件名列表。

库插件按前六项校验并完成 SDK 准备；应用的追加校验则遍历了全部 51 个文件名。到索引 6 时仅有六项的哈希列表越界，随后尝试查找 ARM64 归档中不存在的 x64 许可文件。定向测试在修改前复现了与 CI 一致的两个错误。

## 修改范围

[应用校验入口](../../windows/native/media-assets.cmake) 对 Windows ARM64 的已知六哈希结构，以六项完整配对记录进行校验，避免遍历继承的 x64 专属尾部。x64 继续校验全部 51 项；空清单、其他数量不匹配均明确失败。ARM64 清单未来提供六项配对文件名时也可正常校验。

所有已声明的 SDK 哈希仍逐项验证，下载、摘要、归档解压及依赖固定引用沿用原实现。没有修改 Pub 缓存或相邻媒体 fork。

[新增回归](../../tool/test_windows_media_assets.py) 使用当前解析依赖的真实清单和文件校验函数，仅在独立临时目录中将预期哈希替换为受控文件的摘要，然后调用应用正式 CMake 配置入口。覆盖有效 x64／ARM64、配对 ARM64 清单、两种架构缺少 DLL、六项 SDK 文件分别损坏、x64 来源材料损坏，以及空清单和异常文件／哈希数量。共七项测试、26 次配置场景；测试不下载 SDK、不需要 C++ 编译器。已加入[根检查脚本](../../tool/check.ps1) 的 Lint 阶段。

## 验证与边界

- 新增七项回归在 Windows x64 和 WSL Ubuntu 22.04 均通过；WSL 使用临时检出目录与同一固定依赖清单，仅映射 Windows／Linux 文件路径。日志为 `build/ci-42474110345-linux.log`。
- 原有 `tool/test-windows-media-assets.ps1` 的七项真实 x64 SDK／归档完整性回归通过；应用正式校验入口针对真实 x64 SDK 的 CMake 配置通过，日志为 `build/ci-42474110345-real-x64.log`。
- 原工作区 `tool/check.ps1 -SkipPub` 完成打包边界、格式及静态分析；根测试启动时，正在运行的客户端占用 `build/native_assets/windows/sqlite3.dll`，Flutter 无法替换该文件而停止。保留客户端运行状态，未终止其进程。日志为 `build/ci-42474110345-check.log`。
- 随后在基于 `8a0ed79e`、仅加入本次修复的独立工作树启动 `tool/check.ps1 -EnforceLockfile`，已完成五份锁文件严格解析、打包边界、专项回归和格式检查。用户明确要求不继续本地回归后，主动停止该进程树；全量分析及 Dart／Flutter 测试未完成，不声称完整根检查通过。日志为 `build/ci-42474110345-isolated-check.log`。
- 文档索引与本文共 239 条本地链接通过检查，本次文件的 `git diff --check` 通过。同期 CI 缓存修改未纳入本次修复或上述独立工作树验证。

本次修改仅涉及构建时校验。尚未重新触发远端 CI，未执行 Windows ARM64 完整应用编译、安装或设备播放验收；受控文件的 CMake 配置回归不代表这些项目通过。
