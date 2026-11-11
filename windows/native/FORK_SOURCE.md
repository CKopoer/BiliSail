# 当前 Windows 媒体来源

2026-11-12：现行核心、视频及全部平台库插件统一固定到 `CKopoer/media-kit` 的 `eaae0273a93fbd23b24e3c951b99efd9b73e702b`。此次修复 ANGLE 生产者 pbuffer 在 resize 后同时用于采样和绘制的 EGL 生命周期缺陷，保留 GPU 输出、解码选择与原生二进制资产。来源、受控回归和 Windows ARM64 实机边界见[表面修复记录](../../docs/validation/windows-arm64-egl-surface-2026-11-12.md)。下文保留历史来源说明。

2026-11-08：播放器核心、视频和全部平台库插件统一固定到 `CKopoer/media-kit` 的 `b1c7e4336140d8c4550c1e963365da8edfe56d0a`。官方源码基线为 `c533e446755f51cf53c7e57aea873f2aa5355f81`，包装源码采用 MIT，未复制 GPLv3 的 PiliPlus 应用源码。两后端 Windows 纹理快照修复见 [交接记录](../../docs/validation/windows-texture-handoff-2026-11-08.md)。

SDK、ANGLE 的下载和校验由个人库插件 `windows/native-assets.cmake` 维护；应用的同名适配入口只读取该契约。视频修复已经进入依赖，不修改 Pub 缓存或在应用构建时变换视频源码。

Windows SDK、许可和原构建记录见个人 fork 的[原生资产说明](https://github.com/CKopoer/media-kit/blob/b1c7e4336140d8c4550c1e963365da8edfe56d0a/native/README.md)。应用中的统一来源与验证记录位于 `docs/validation/media-kit-personal-fork-2026-11-07.md`。

Windows x64 的 D3D11/EGL 可见区域修复位于个人 mpv，media-kit 负责固定 SDK 和逐文件校验；应用只升级依赖，不安装诊断 shader。精确源提交、资产摘要和 ARM64 边界见 [mpv 来源](mpv/SOURCE.md)。
