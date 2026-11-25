# Windows 播放库来源

播放器核心与视频插件固定到 CKopoer/media-kit 的 `3493e859fe70dff908ba2fb4070162962f449ef2`。基线为 MIT 许可的 Predidit/media-kit `484639aca5ffc754a65876c22f01dbb070225732`。两者之间的差异是 Windows 的两项原生归档。视频继续使用 libmpv 的 D3D11 render API，应用在构建副本中应用首帧和生命周期补丁。[固定清单](https://github.com/CKopoer/media-kit/blob/3493e859fe70dff908ba2fb4070162962f449ef2/media_kit/hook/native_bundles.json)

| 目标 | 原生归档 | SHA-256 |
| --- | --- | --- |
| Windows x64 | [mpv-dev-windows-x64.zip](https://github.com/CKopoer/libmpv-win32-video-cmake/releases/download/windows-ddp-2026-11-25/mpv-dev-windows-x64.zip) | `9468eb761f58e6f9397f5962f05c0712c643f7584e019e95181caf785192725a` |
| Windows ARM64 | [mpv-dev-windows-arm64.zip](https://github.com/CKopoer/libmpv-win32-video-cmake/releases/download/windows-ddp-2026-11-25/mpv-dev-windows-arm64.zip) | `dc7dd1e8505f18d47d7f5373a980603e1ff7eb231ee78a9d16559e69e51a328c` |

构建基于 Predidit 的 Windows 配方 `307dca75589a43a528183426404fea422123bd9f`，保留 mpv `1eb941fdb974fe25dc0ac68a33652c145ff41f9d`、FFmpeg `dd86debdbcec9ec057304c845859771bd6a10c8c` 及两者的上游补丁。FFmpeg 的允许组件中加入 `spdif` 封装器，使 mpv 可以将原始 E-AC-3 JOC 帧写入 IEC 61937 载波。交叉编译使用固定摘要的 BtbN LGPL 静态依赖镜像。mpv 关闭 GPL，FFmpeg 启用 version3 并关闭 GPL、nonfree。[构建配方](https://github.com/CKopoer/libmpv-win32-video-cmake/blob/e890502bf288762924ba7eeeca0bf6a479590431/scripts/bilisail-windows-sdk.sh) · [构建记录](https://github.com/CKopoer/libmpv-win32-video-cmake/actions/runs/45641869787)

Dart Native Assets hook 校验归档和解包文件。安装包的 `data/licenses/mpv` 保留许可文本、资产清单和 `provenance` 子目录，其中包含源码提交、镜像摘要、FFmpeg 配置、mpv 构建参数与子依赖声明。[播放能力与设备验证](../../docs/dolby-atmos-playback.md)
