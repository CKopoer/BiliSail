# Windows 视频原生回归入口

2026-11-07：生产视频源码、ANGLE GPU 队列、视口与释放修复已移入个人 [CKopoer/media-kit](https://github.com/CKopoer/media-kit/tree/53b7044a3116798d66087a3e545c029a7d281297/media_kit_video/windows)。应用不再应用此目录的历史变换。目录内 `.inc` 文件作为原移植来源保留，不参与生产编译，也不作为当前修复的维护入口。

`apply.cmake` 现在仅供受控原生回归：读取当前依赖的 `source_manifest.cmake`、校验生产源码并复制到测试构建目录，不修改依赖。`tool/test-windows-video-dispose.ps1` 与 `tool/test-windows-gpu-queue.ps1` 因而测试个人 fork 中实际编译的实现。

MIT 许可和原始版权保留在 [LICENSE](LICENSE)。现行来源与逐平台验证见[统一维护记录](../../../docs/validation/media-kit-personal-fork-2026-11-07.md)，历史来源见[原依赖切换](../../../docs/validation/piliplus-dependencies-2026-11-01.md)。
