# 当前 Windows 媒体来源

2026-11-07：播放器核心、视频和全部平台库插件统一固定到 `CKopoer/media-kit` 的 `9abd8a56f24371fd8c9628b70eba5e84c29e86c8`。官方源码基线为 `c533e446755f51cf53c7e57aea873f2aa5355f81`，包装源码采用 MIT，未复制 GPLv3 的 PiliPlus 应用源码。

SDK、ANGLE 的下载和校验由个人库插件 `windows/native-assets.cmake` 维护；应用的同名适配入口只读取该契约。视频修复已经进入依赖，不修改 Pub 缓存或在应用构建时变换视频源码。

Windows SDK、许可和原构建记录见个人 fork 的[原生资产说明](https://github.com/CKopoer/media-kit/blob/9abd8a56f24371fd8c9628b70eba5e84c29e86c8/native/README.md)。应用中的统一来源与验证记录位于 `docs/validation/media-kit-personal-fork-2026-11-07.md`。
