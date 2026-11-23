# Windows 播放库来源

media_kit 和 media_kit_video 固定到 Predidit/media-kit 的 484639aca5ffc754a65876c22f01dbb070225732，以 MIT 许可分发。视频插件通过固定版 libmpv 的 D3D11 render API 与四槽 mailbox 提交画面。应用在构建副本中应用生命周期和首帧补丁。

| 目标 | 原生归档 | SHA-256 |
| --- | --- | --- |
| x64 | [202611230430 x86_64](https://github.com/Predidit/libmpv-win32-video-cmake/releases/download/202611230430/mpv-dev-x86_64-20261123-git-1eb941f.7z) | bb6ce9e53c083002fad640011632aef96167cb1d4fffcfe4ed79acbc153bb497 |
| arm64 | [202611230430 aarch64](https://github.com/Predidit/libmpv-win32-video-cmake/releases/download/202611230430/mpv-dev-aarch64-20261123-git-1eb941f.zip) | 0a9067375c6517b93549fa421a4ab16b301a93b4d91e653117e8b053e1490d83 |

原生归档由 Dart 构建钩子校验。mpv、FFmpeg 与静态链接的子依赖分别遵循各自构建配置下的许可。分发时须保留对应的许可文本和可重建材料。[固定清单](https://github.com/Predidit/media-kit/blob/484639aca5ffc754a65876c22f01dbb070225732/media_kit/hook/native_bundles.json) · [构建仓库](https://github.com/Predidit/libmpv-win32-video-cmake/tree/307dca75589a43a528183426404fea422123bd9f)

此版本的 Windows 配方从 mpv 提交 `1eb941fd` 构建并设置 `gpl=false`。FFmpeg 固定到 `dd86debd`，启用 version3 并禁用 GPL 和 nonfree。安装目录保留 LGPL 2.1、LGPL 3 和对应的 GPL 3 文本。具体子依赖和补丁以两种架构共用的固定构建仓库为准。[mpv 配方](https://github.com/Predidit/libmpv-win32-video-cmake/blob/307dca75589a43a528183426404fea422123bd9f/packages/mpv.cmake) · [FFmpeg 配方](https://github.com/Predidit/libmpv-win32-video-cmake/blob/307dca75589a43a528183426404fea422123bd9f/packages/ffmpeg.cmake)
