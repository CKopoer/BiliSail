# Windows libmpv 原生资产

2026-11-01：本轮 Windows 解码回退修复重新核验并采用此 SDK；Android/macOS 和原有 ANGLE 资产不变。

- 构建来源：[zhongfly/mpv-winbuild 2026-10-12-88eb9f2e73](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-10-12-88eb9f2e73)。选择基础 x86_64 的 **LGPL** 开发包，不使用 x86_64-v3 或 GPL 构建。
- 固定资产：`mpv-dev-lgpl-x86_64-20261012-git-88eb9f2e73.7z`。
- SHA-256：`d1a3f57dfb3c7f07e5456e32e9ecc9e406f6457f2560ff5801c9b37a8036f507`，已与上游 `sha256.txt` 和本机下载重新计算结果核对。
- DLL SHA-256：`222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`。实际 `mpv-configuration` 已确认 `-Dgpl=false`、`-Dlibmpv=true`、`-Degl-angle=enabled`，版本为 `v0.41.0-1150-g88eb9f2e7`。
- mpv 源码：[88eb9f2e73945d8bc9c133a2f67babaa9af34680](https://github.com/mpv-player/mpv/tree/88eb9f2e73945d8bc9c133a2f67babaa9af34680)。构建记录：[38246402314](https://github.com/zhongfly/mpv-winbuild/actions/runs/38246402314)。源码、子依赖、补丁和构建选项从此记录及构建仓库追溯。
- 必需修复：[1d15686142fd5d53c954aab7526cedab05ef9dc3](https://github.com/mpv-player/mpv/commit/1d15686142fd5d53c954aab7526cedab05ef9dc3)，正确同时检查 ANGLE display/client 扩展中的 `EGL_EXT_device_query`，避免拒绝 D3D11 硬解互操作后退回 copy-back。

mpv 使用 LGPL-2.1-or-later 的构建条件，许可原文保存在 `COPYING.LGPLv2.1`。mpv、静态子依赖和构建仓库保留各自许可；LGPL 标签及 mpv 许可不代替所有子依赖的分发审核。此文件随本机 Windows bundle 安装到 `data/licenses/mpv`；对外发行需要提供对应源码/构建资料，并完成子依赖材料归档，沿用项目既有第三方分发边界。

普通构建通过唯一的现行清单 `windows/native/media-assets.cmake` 下载、校验并选择固定资产，使用其 headers、import library 和 DLL。旧 `windows/native/mpv.cmake` 不启用。上游库插件仍解析自己的固定归档；应用在插件注册后将完整 Windows SDK 绑定到哈希命名的独立目录，并从最终 bundle 列表移除旧 DLL。预取脚本使用同一清单，归档、DLL、import library 及四份头文件全部检查 SHA-256，安装时复核选中的 DLL。Pub 缓存不修改。DLL 动态链接；没有加密或禁止用户替换原生库。

这份 SDK 使用标准 OpenGL render API，不提供 DXGI 扩展接口。它包含 ANGLE 的 EGL device 查询修复，不能与 DXGI 分支的自定义头文件／DLL 混用。基础 x86_64，不要求 x86-64-v3；实际解码方式仍由 `hwdec-current` 确认，自动模式允许设备／编码不支持时回退，不宣称所有设备强制直通。
