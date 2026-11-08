# Windows libmpv 原生资产

2026-11-08：维护入口为个人 [CKopoer/media-kit](https://github.com/CKopoer/media-kit/tree/b1c7e4336140d8c4550c1e963365da8edfe56d0a)。库插件 `windows/native-assets.cmake` 统一下载、校验、解压和安装，应用只读取该契约。本次仅更新纹理交接源码，既有 mpv 二进制与摘要未变。

Windows x64 使用个人 [mpv 固定源码](https://github.com/CKopoer/mpv/tree/afd6da8843a07f463ba4c736a2ea636b1a92e23e)，修复解码表面对齐填充区经 EGL／ANGLE 被采样产生的边缘绿线。有填充时在 GPU 内复制有效区域，保持硬解；无填充时保留原导入，不称为全链路零复制。合成 HEVC 未复现原问题，ARM64 未包含此次修复。

- [固定 SDK](https://github.com/CKopoer/media-kit/releases/tag/native-windows-hwdec-edges-2026-11-07)：`bilisail-libmpv-windows-x64-afd6da8843.zip`。
- 归档 SHA-256：`6739acd7529400cc877ea84e417714bf043769ef088cd1b248d3de2467417ced`。
- DLL SHA-256：`8fa6af29a94623d7d1e16bc6db48668f321e3fc9f1eaa86a8df8d61ec57f00e3`。
- [构建记录](https://github.com/CKopoer/mpv/actions/runs/42387266918)：固定 BtbN LGPL 容器，FFmpeg 源码保持 `615b07170e30d79ad5906418ea49f81c3cbd8457`。ANGLE 仍使用原固定归档。
- SDK 在 CI 归档上补充固定源依赖的原始许可通知；`provenance/repack.json` 记录原归档摘要并验证 DLL、import library、头文件和 JAR 未改变。DLL、头文件、许可与来源等 51 个文件分别校验，不能混用旧 SDK。
- 构建选项、各源提交、依赖版本、脚本、容器摘要与许可随 SDK 的 `provenance/` 安装到 `data/licenses/mpv/`。完整像素和应用回归见 [绿线专项](../../../docs/validation/windows-amd-hwdec-edges-2026-11-07.md)。

Windows ARM64 继续使用 `88eb9f2e73945d8bc9c133a2f67babaa9af34680` 对应的 `mpv-dev-lgpl-aarch64-20261012-git-88eb9f2e73.7z`，归档 SHA-256 为 `bdffd1f6c2ce4f083bea6fd8c0dec845065468ba7d0426c23cb9b09c8b540b86`，DLL 为 `6139b27ac410fc2535161e3e11969bbc8b27c2b6850a61e0550266f9a08c8c52`。归档与 ANGLE ARM64 的逐字节镜像发布于 [ARM64 资产](https://github.com/CKopoer/media-kit/releases/tag/native-windows-arm64-2026-11-07)。ARM64 ANGLE 固定 `a96fca8d5ee2ca61e8de419e38cd577579281c9e`，来自 [yorickreum 构建材料](https://github.com/yorickreum/angle-libs/tree/485758dd4baf87570c2aac3cc47577a9514d3429)，BSD-3-Clause；其原始 LICENSE、来源说明随 bundle 分发。

两种架构继续使用标准 OpenGL render API 与 mpv `-Dgpl=false`，不混用 DXGI 扩展。mpv 为 LGPL-2.1-or-later，文本保留在 `COPYING.LGPLv2.1`；当前 x64 FFmpeg 为 LGPL-3.0-or-later，文本与 GPLv3 配套文本位于 SDK provenance。LuaJIT、libsixel、subrandr、ANGLE 及其他子依赖保留各自许可。DLL 动态链接，保留替换、对应源码与重建边界。首批 x64 镜像及旧 DLL 的历史记录见绿线专项，不将后续构建材料倒推为旧资产来源。
