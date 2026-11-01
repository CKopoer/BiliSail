# PiliPlus Windows 原生播放器来源

2026-11-01：按用户要求，与相邻 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的锁文件一致。

- Dart 核心与库插件：[My-Responsitories/media-kit](https://github.com/My-Responsitories/media-kit/tree/73771ec38176be2d984a3049c28177bce23b54a0)，MIT。
- 视频插件：[bggRGjQaUbCoE/media-kit](https://github.com/bggRGjQaUbCoE/media-kit/tree/fd8421d21eade4d6d12de137fa7df902fec20292)，MIT。应用只在构建副本适配释放、平台线程、GPU 队列和视口；未复制 GPLv3 的 PiliPlus 应用源码。
- libmpv 采用该库插件指定的 [20260607 归档](https://github.com/bggRGjQaUbCoE/mpv-winbuild-cmake/releases/tag/20260607)：`mpv-dev-x86_64-20260607-git-43b14a4.7z`。上游 MD5 `b84900bbc6fcb995ca6a24f62bee671f`；补充 SHA-256 `4efaccac571b390ba12db822a0acb50a89e9ccf0797827ca0d3b223341ceff52`；DLL SHA-256 `4b517ce76493c7d6b6568dde6e2839e3bb6a41c4b46b0e972492f354ad444ba4`。
- ANGLE 采用上游指定的 [v1.0.1](https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v1.0.1)，归档 SHA-256 `cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a`，上游 MD5 `e866f13e8d552348058afaafe869b1ed`。

构建仍执行上游 MD5 校验，并额外检查上述 SHA-256，拒绝复用其他分支的旧 DLL。TLS 验证保持开启；不使用历史 `mpv.cmake` 的 LGPL DLL 覆盖，也不混入 Predidit Native Assets。

MIT 只覆盖包装源码，不替代 mpv、FFmpeg、ANGLE 与子依赖的许可。此次采用的二进制不能沿用历史 LGPL-only 声明；对外分发需保留实际构建的相应源码、配置和许可材料，参见根目录 THIRD_PARTY_NOTICES.md。
