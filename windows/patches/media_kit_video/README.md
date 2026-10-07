# media_kit_video 2.0.1 Windows 释放补丁

来源：[media-kit/media-kit](https://github.com/media-kit/media-kit)，已锁定的 Pub 包 `media_kit_video 2.0.1`。仅在构建目录复制其 Windows 源文件并修正释放生命周期；不修改 Pub 缓存，不替换 Dart、Android/macOS 实现或 libmpv/ANGLE 二进制。上游代码为 MIT，许可保存在 [LICENSE](LICENSE)，源文件版权头保留。

`apply.cmake` 在 Windows 插件目标创建后校验五个上游源文件的 SHA-256，将副本作为该目标的编译输入。依赖升级或源文件变化时配置失败，必须重新审查补丁，不能静默跳过。普通 `flutter build windows` 与 MSIX 打包共用此入口。

修正包括：方法通道等待原生 Dispose 完成；停止渲染通知并排空在途任务；等待当前和旧纹理的注销回调；在有效 GL 上下文中同步释放 mpv 渲染上下文，然后销毁 ANGLE。没有纹理时不等待不存在的回调。

两个 `.inc` 是编译到上游类中的替换方法，原生单测也直接编译这两份方法体。它们不是构建产物。测试不依赖播放器、显卡或 Flutter 进程：`pwsh -File tool/test-windows-video-dispose.ps1`。

故障证据、设计及验收范围见 [验证记录](../../../docs/validation/windows-preview-dispose.md)。
