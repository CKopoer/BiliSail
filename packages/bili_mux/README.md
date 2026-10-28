# bili_mux

下载完成后的本地 MP4 / MKV 流复制组件，与 `bili_player` 的 libmpv/FFmpeg 隔离。
打包目标为 Windows x64、Android arm64、macOS arm64／Intel x64、iOS arm64 和 Linux x64；Linux 同时用于 CI 原生回归。新增 iOS／Linux 应用包的首次远端构建及设备验收见[平台记录](../../docs/validation/ios-linux.md)，Intel macOS 构建状态见 [CI/CD](../../docs/validation/ci-cd.md#macos-dmg-安装)。

## 原生来源与构建

- FFmpeg 固定 tag [`n9.0.2`](https://github.com/FFmpeg/FFmpeg/tree/n9.0.2)。
- [源码归档](https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/refs/tags/n9.0.2) SHA-256：`6e374ed621e48faa40639307dff48ba6fe574a509977956d2cce9669b7cc27e9`。
- [构建脚本](tool/build.sh)只启用 MOV/MP4 / Matroska 读取、MP4 / Matroska 写入、本地文件协议和必要的码流解析；无编码器、解码器、网络、滤镜或外部编解码库。自动依赖以 `configure.log` 为准。
- 构建报告 LGPL 2.1 or later，原文见 [LICENSE-FFmpeg.txt](LICENSE-FFmpeg.txt)。原生包装代码为本项目独立实现，没有复制上游 `remuxing.c`；封装 API 的职责参考[官方示例](https://ffmpeg.org/doxygen/trunk/remuxing_8c-example.html)。
- 手写 ABI 2 绑定对应 [bili_mux.h](native/bili_mux.h)，不使用生成器，也不对外暴露 FFmpeg 结构体。仅导出 `bili_mux_*`，其他符号隐藏，Android/Linux 额外采用本库内部符号绑定。

在仓库根目录执行，下列命令仅构建组件；首次下载约 17 MB 的源码归档，缓存于 `build/download_mux`。生成的 `native/prebuilt` 不提交 Git。修改包装代码后也需重新执行。

```powershell
# Windows：MSYS2 的 UCRT64 GCC/G++、make、curl、tar。
# 本轮验证 GCC 13.2.0；可用 -MsysRoot 指定非默认安装目录。
# 安装工具：在 MSYS2 运行 pacman -S --needed make mingw-w64-ucrt-x86_64-gcc
./tool/build-download-mux.ps1 -Target windows-x64

# Android：固定 NDK 28.2.13676358，API 24，16 KiB ELF 页对齐。
# 可从 ANDROID_NDK_HOME、ANDROID_HOME 或 android/local.properties 找到 SDK。
./tool/build-download-mux.ps1 -Target android-arm64

# macOS：在 Apple Silicon / Xcode 主机执行，最低 macOS 12。
./tool/build-download-mux.ps1 -Target macos-arm64

# macOS Intel：在 Intel x64 / Xcode 主机执行，最低 macOS 12。
./tool/build-download-mux.ps1 -Target macos-x64

# iOS：Xcode 主机，iPhoneOS arm64，最低 iOS 15；不含 simulator slice。
./tool/build-download-mux.ps1 -Target ios-arm64

# Linux x64：本机 C/C++ 编译器与 make。
./tool/build-download-mux.ps1 -Target linux-x64
```

macOS、iOS、Linux 也可直接执行 `bash packages/bili_mux/tool/build.sh <target>`。
组件构建完成后按通常方式执行 Flutter 构建。Windows／Linux CMake、Android Gradle 和 Apple CocoaPods 打包对应 DLL/SO/framework；各端随组件保留许可与来源/配置。iOS 与 macOS 使用各自的 framework 构建目录，FFI 按各自的 app bundle 布局加载；Linux 按可执行文件旁的 `lib/libbili_mux.so` 加载，兼容 AppImage 挂载目录与 Flatpak 沙盒。
macOS 的两种架构分别保存在 `native/prebuilt/macos-arm64` 和 `native/prebuilt/macos-x64`，构建后将所选架构复制到同一个 CocoaPods framework 目录；切换架构必须重建组件，并让应用的 Xcode `ARCHS` 与之匹配。发布入口 `tool/build-release.ps1` 自动完成这一流程，生成两份独立 DMG。
iOS framework 使用扁平布局，`BiliMux`、`Info.plist`、`COPYING.LGPLv2.1`、`source.txt` 和 `configure.log` 均位于根目录；不能创建 macOS 式的 `Resources/`。Apple [打包步骤](tool/package-apple-framework.sh)每次重新生成 CocoaPods 使用的 framework，移除旧构建遗留目录；macOS 继续将许可与来源/配置放在 `Resources/`。无需 Xcode 的目录回归可运行 `bash packages/bili_mux/tool/test-apple-framework.sh`。
`tool/build-release.ps1` 已自动先构建组件，并在安装包旁生成对应的 `.mux-source.zip`，包含 FFmpeg 原始归档、本项目包装源码与构建说明，便于重建与替换动态组件。
缺失原生资产时 Windows/Android 构建会提示准备命令；非目标 ABI 的运行时能力为不可用。

## 行为与回归

两个已校验输入 → 显式指定 MP4 / MKV 临时输出 → 重新读取输出核对两轨逐包内容/数量 → 成功返回。
不对音视频分别归零；保留压缩数据、编码参数和共享时间轴。MP4 保留 B 帧 PTS/DTS；MKV 采用容器的毫秒时间基，不存独立 DTS，逐包内容/顺序和音画相对偏移继续校验。
AV1 分片若仅在数据包中携带序列头，MKV 写头前通过已有 parser/extradata filter 做本地探测（`probesize` 8 MiB、`max_probe_packets` 256、`max_analyze_duration` 5 秒）；未编入解码器。ABI 2 将容器参数独立于临时文件后缀，旧 ABI 1 资产不可用于新绑定，需重新构建组件。
内存只持有两条待交错写入的数据包，原生任务有 3 小时 deadline。
调用方在 worker isolate 执行同步封装，只在调用 isolate 读取原子进度与发送取消；销毁前等待 worker 返回，所有文件句柄已关闭。
取消后的临时输出清理、文件 SHA-256、原子发布、manifest/SQLite 提交和源文件清理由下载仓储负责。

普通 `flutter test` 运行无原生资产的能力/取消测试。完整原生回归：

```powershell
$env:BILI_MUX_LIBRARY = (Resolve-Path packages/bili_mux/native/prebuilt/windows-x64/bili_mux.dll).Path
$env:BILI_MUX_FFPROBE = '<测试工具 ffprobe 的绝对路径>'
cd packages/bili_mux
flutter test
```

`ffprobe` 只用作测试 oracle，不进入应用资产；手动回归使用与组件一致的 FFmpeg `9.0.2`，旧版本可能遗漏 AV1 分片输入的 `duration_time`。CI 在组件构建后运行 [build-test-ffprobe.sh](tool/build-test-ffprobe.sh)，从同一份已校验源码构建仅供测试的 ffprobe，不使用系统包中的版本。提交的[合成样片](test/fixtures/README.md)覆盖 H.264/HEVC/AV1 + AAC、B 帧、250 ms 音频偏移和 UTF-8 文件路径；检查数据包 SHA-256、数量、PTS、时长与相对起始偏移；MP4 额外检查 DTS，MKV 的时间比较允许 1.1 ms 容器量化误差，以及取消、输入错误和并发。
Windows 测试与 Android ELF 构建不替代 Android/macOS 实机或真实 DASH 长视频验收。
