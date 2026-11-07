# Windows libmpv 原生资产

2026-11-07：当前维护入口为个人 [CKopoer/media-kit](https://github.com/CKopoer/media-kit/tree/9abd8a56f24371fd8c9628b70eba5e84c29e86c8)，mpv 源码由 [CKopoer/mpv](https://github.com/CKopoer/mpv/tree/88eb9f2e73945d8bc9c133a2f67babaa9af34680) 维护。库插件 `windows/native-assets.cmake` 统一下载、校验、解压和安装；应用只核对依赖契约，不混入旧 SDK。

- 当前资产：[个人固定镜像](https://github.com/CKopoer/media-kit/releases/tag/native-2026-11-07)，`mpv-dev-lgpl-x86_64-20261012-git-88eb9f2e73.7z`。
- 归档 SHA-256：`d1a3f57dfb3c7f07e5456e32e9ecc9e406f6457f2560ff5801c9b37a8036f507`；DLL：`222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`。
- 首批镜像与原 [zhongfly 2026-10-12-88eb9f2e73](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-10-12-88eb9f2e73) 逐字节一致，不称为个人重编译；原构建记录为 [38246402314](https://github.com/zhongfly/mpv-winbuild/actions/runs/38246402314)。
- mpv 源码 `88eb9f2e73945d8bc9c133a2f67babaa9af34680`，包含同时检查 ANGLE client/display 扩展的 [EGL 修复](https://github.com/mpv-player/mpv/commit/1d15686142fd5d53c954aab7526cedab05ef9dc3)。原始回退修复和实测边界保留在应用仓库的 `docs/validation/windows-angle-direct-hwdec-2026-11-01.md`。
- SDK 的 DLL、import library、四份头文件分别复核；ANGLE 解压文件亦逐项校验。最终 bundle 只选择该套 SDK，安装时复核 DLL。

Windows ARM64 使用同一 mpv 源码提交对应的 `mpv-dev-lgpl-aarch64-20261012-git-88eb9f2e73.7z`，归档 SHA-256 为 `bdffd1f6c2ce4f083bea6fd8c0dec845065468ba7d0426c23cb9b09c8b540b86`，DLL 为 `6139b27ac410fc2535161e3e11969bbc8b27c2b6850a61e0550266f9a08c8c52`。归档与 ANGLE ARM64 的逐字节镜像发布于 [ARM64 资产](https://github.com/CKopoer/media-kit/releases/tag/native-windows-arm64-2026-11-07)。ARM64 ANGLE 固定 `a96fca8d5ee2ca61e8de419e38cd577579281c9e`，来自 [yorickreum 构建材料](https://github.com/yorickreum/angle-libs/tree/485758dd4baf87570c2aac3cc47577a9514d3429)，BSD-3-Clause；其原始 LICENSE、来源说明随 bundle 分发。

两种架构使用标准 OpenGL render API 与 `-Dgpl=false`；不混用 DXGI 扩展或 x86-64-v3 资产。自动解码仍允许设备／编码不支持时回退，实际路径按 `hwdec-current` 和交付诊断确认，不宣称完整链路零复制。

mpv 的 LGPL-2.1-or-later 文本保留在 `COPYING.LGPLv2.1`。mpv、FFmpeg、ANGLE 及其他子依赖保留各自许可；镜像不改变许可范围，也不能替代相应源码和构建材料。DLL 动态链接，保留替换和重建边界。
