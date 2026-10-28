# Predidit media-kit Native Assets

2026-10-29 起，Windows 播放器改为 Predidit media-kit 的 D3D11/mailbox 输出。
固定源码：<https://github.com/Predidit/media-kit/tree/83b7ca63772856e1ea0158916177e136f7b7b0be>。
核心与视频插件采用 MIT；完整通知由 Flutter 包许可与本项目 `THIRD_PARTY_NOTICES.md` 保留。

原生资产由该提交的 `media_kit/hook/native_bundles.json` 定义并由构建钩子校验：

- Windows x64：<https://github.com/Predidit/libmpv-win32-video-cmake/releases/download/202609151348/mpv-dev-x86_64-20260915-git-0b7ed67.7z>
- SHA-256：`8adceab30b6bcc5503fa9d3823b68f4acd15ee1c41d6dc2492826f373531c10a`
- 必须使用带 `MPV_RENDER_API_TYPE_DXGI` 扩展的匹配 libmpv；不替换为旧 ANGLE 使用的 DLL。

此前 `mpv/SOURCE.md` 和 `mpv.cmake` 是旧实现的历史材料，不再参与当前构建。
不能把旧库的 `gpl=false` 或 LGPL 构建配置套用于新资产。mpv、FFmpeg 及其子依赖
的二进制许可、构建配置和对应源码须按实际新归档另外核实和保留；Dart 包 MIT
不能代替这些分发条件。本轮只进行本地构建与验证，不创建发布。

实施与平台验收：<../../docs/predidit-media-migration.md>。
