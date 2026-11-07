# FSPlayer 原生播放器

- 来源：[debugly/fsplayer](https://github.com/debugly/fsplayer)，1.1.2，提交 `f00c9e12b7304eca70b6ac27b09e915c24550898`。
- LGPL-2.1-or-later；许可原文随应用保留为 `LICENSE-fsplayer.txt`。上游包含 Bilibili、Zhang Rui、debugly 等作者的版权声明。
- 原始发布资产逐项固定并校验 SHA-256，见 `assets.lock.json`。不包含 FSPlayer-Pro。
- 本项目自行实现 Flutter 控制和纹理桥接，没有复制上游应用示例 UI。播放器及其 FFmpeg 与 media_kit、MDK、bili_mux 分别链接，不共享内部 ABI。
- 可重建材料位于固定提交的 `FFToolChain` 子模块、`android/fsplayer/src/main/cpp/CMakeLists.txt`、Apple XcodeGen yml 和各平台 build-framework 脚本。构建步骤见上游 README；子模块固定提交见锁文件。
- FFmpeg 与 OpenSSL、libass、libxml2、dav1d、uavs3d 等组件保留各自许可。固定工具链的默认 FFmpeg 配置明确 `--disable-gpl`／`--disable-nonfree`，并关闭 version3；这不代表其他组件统一采用 LGPL-2.1。原始 AAR 未附完整子组件 notices，本项目保留来源和 LGPL 文本；发布前仍须补齐实际二进制对应的第三方许可清单。Apple archive 的 LICENSE／README／CHANGELOG 由 podspec 保留；资产本身不提交 Git。
- 公开版本的包数／字节缓存限制不等价于精确的媒体时间窗口；性能验证须记录实际缓存量。Apple Flutter Texture 输出不承诺 HDR／杜比屏幕直通。
