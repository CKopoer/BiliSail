# Windows libmpv 原生资产

2026-11-07：当前维护入口为个人 [CKopoer/media-kit](https://github.com/CKopoer/media-kit/tree/7034784f960be84339ed6d87849ad2cef23c50b7)，mpv 源码由 [CKopoer/mpv](https://github.com/CKopoer/mpv/tree/88eb9f2e73945d8bc9c133a2f67babaa9af34680) 维护。库插件 `windows/native-assets.cmake` 统一下载、校验、解压和安装；应用只核对依赖契约，不混入旧 SDK。

- 当前资产：[个人固定镜像](https://github.com/CKopoer/media-kit/releases/tag/native-2026-11-07)，`mpv-dev-lgpl-x86_64-20261012-git-88eb9f2e73.7z`。
- 归档 SHA-256：`d1a3f57dfb3c7f07e5456e32e9ecc9e406f6457f2560ff5801c9b37a8036f507`；DLL：`222da57d12a47680df84a8d0ad06f713fbbce4da923784ddeebe9d666135e943`。
- 首批镜像与原 [zhongfly 2026-10-12-88eb9f2e73](https://github.com/zhongfly/mpv-winbuild/releases/tag/2026-10-12-88eb9f2e73) 逐字节一致，不称为个人重编译；原构建记录为 [38246402314](https://github.com/zhongfly/mpv-winbuild/actions/runs/38246402314)。
- mpv 源码 `88eb9f2e73945d8bc9c133a2f67babaa9af34680`，包含同时检查 ANGLE client/display 扩展的 [EGL 修复](https://github.com/mpv-player/mpv/commit/1d15686142fd5d53c954aab7526cedab05ef9dc3)。原始回退修复和实测边界保留在应用仓库的 `docs/validation/windows-angle-direct-hwdec-2026-11-01.md`。
- SDK 的 DLL、import library、四份头文件分别复核；ANGLE 解压文件亦逐项校验。最终 bundle 只选择该套 SDK，安装时复核 DLL。

该构建使用标准 OpenGL render API、基础 x86_64 与 `-Dgpl=false`；不混用 DXGI 扩展或 x86-64-v3 资产。自动解码仍允许设备／编码不支持时回退，实际路径按 `hwdec-current` 和交付诊断确认，不宣称完整链路零复制。

mpv 的 LGPL-2.1-or-later 文本保留在 `COPYING.LGPLv2.1`。mpv、FFmpeg、ANGLE 及其他子依赖保留各自许可；镜像不改变许可范围，也不能替代相应源码和构建材料。DLL 动态链接，保留替换和重建边界。
