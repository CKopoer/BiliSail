# 下载音视频合并能力评估

日期：2026-10-08。范围：核对现有依赖，评估系统原生接口、独立封装库、扩展现有原生库。**本轮没有接入下载合并开关，没有修改播放器、原生依赖或发布构建。**

后续决定（2026-10-09）：用户选择独立精简组件，已接入 `bili_mux` 和下载合并选项。本文保留评估时的建议和测量边界；当前实现与验证见[合并验收记录](download-muxing-results.md)。

## 结论与建议

下载继续由现有 Web 源解析、HTTP 续传、文件校验与 SQLite 队列完成。新增需求是将已下载的两条压缩轨道重新封装到一个 MP4 中，不需要解码、重新编码、滤镜或另一套完整播放器。

建议优先验证**扩展现有 media_kit 原生库**：保留已有播放组件，在其 FFmpeg 构建中只启用 MP4 muxer，并提供独立于播放会话的小型文件合并接口。这样能覆盖当前下载提供的 H.264 / HEVC / AV1 + AAC，且避免重复打包已有解码、网络和渲染组件。能否采用以三端构建增量和播放回归结果为准；当前不能宣称零体积增量或三端已经可用。

若维护自有 media_kit 原生构建的成本过高，第二选择是独立的、仅含 MP4 读取和写入能力的封装库。系统原生接口可作为有明确编码/系统版本约束的实现，不能仅凭“系统可以播放该编码”推导它能无损封装。

## 当前下载保存的资源

| 内容 | 当前文件 / 行为 |
| --- | --- |
| 视频 | `video.m4s`，保留所选画质与 H.264 / HEVC / AV1 编码 |
| 音频 | `audio.m4s`，当前下载解析器选择 AAC，不下载无损音频或 Dolby 音频 |
| 字幕 | 可选，正文和时间轴保存在 `extras.json`；不保存远端字幕 URL |
| 普通弹幕 | 可选，滚动/顶部/底部弹幕保存在 `extras.json`；容量有界 |
| 封面 | 尽力保存为 `cover.img`；失败作为附属资源警告 |
| 本地索引 | `manifest.json`、`.bilisail-task` 和 SQLite 任务记录，用于校验、账号归属和恢复 |

合并选项首先只处理音视频；字幕、弹幕和封面继续独立保存。烧录字幕/弹幕会引入视频转码，不纳入此需求。

现状代码：[下载模型](../../lib/features/downloads/domain/download_models.dart)、[下载源解析](../../lib/features/downloads/data/api_download_source_repository.dart)、[文件校验与索引](../../lib/features/downloads/data/download_file_store.dart)、[离线适配器](../../lib/features/playback/data/offline_playback_repository.dart)。

## 现有原生库复用核对

固定 Dart 依赖为 `media_kit 1.2.6`、`media_kit_video 2.0.1`、`media_kit_libs_video 1.0.7`，由 `bili_player` 隔离。当前平台解析版本和资产来源见[原生依赖记录](media-packages.md)与[第三方说明](../../THIRD_PARTY_NOTICES.md)。

| 平台 | 本轮证据 | 复用限制 |
| --- | --- | --- |
| Windows x64 | 本地 Release 的 `libmpv-2.dll` 为 29,764,622 字节（约 28.39 MiB），运行探针报告 mpv `v0.36.0-403-g652a1dd907`、FFmpeg `n6.0` | 检查的 `avformat_open_input`、`avformat_alloc_output_context2`、`av_interleaved_write_frame`、`av_write_trailer`、`av_packet_alloc` 均未导出；二进制内构建参数包含 `--disable-muxers`，没有重新启用的 muxer 参数 |
| Android arm64 | 使用已生成 APK 构建目录内的 `libmpv.so`，通过 NDK `llvm-readelf --dyn-syms` 确认上述函数已导出 | 二进制内构建参数同样关闭全部 muxer，未重新启用 MP4；函数存在不代表输出格式已经编译进库 |
| macOS | 当前插件 Makefile 指向 `media-kit/libmpv-darwin-build v0.6.0` 的 `macos-universal-video-default` 资产；核对该版本 FFmpeg 构建源 | `default` 先 `--disable-all`，再开启播放所需组件，没有启用 muxer；本机没有核对 macOS 最终二进制和运行结果 |

macOS 依据为固定版本的[FFmpeg 构建参数](https://github.com/media-kit/libmpv-darwin-build/blob/v0.6.0/scripts/ffmpeg/meson.build)，不能用当前主分支新增的框架或能力代替 `v0.6.0` 已打包事实。

mpv 的 `--o` 是编码模式，[所用版本编码实现](https://github.com/mpv-player/mpv/blob/v0.36.0/common/encode_lavc.c)按名称寻找真实编码器；设置 `ovc=copy` 成功只表示接受了字符串，不证明它支持 FFmpeg CLI 的流复制。现有 `--stream-record` 也不适合：官方说明它只记录主文件，忽略外部音轨，见[mpv 手册](https://mpv.io/manual/master/#options-stream-record)。因此不能通过当前播放器实例录制来完成双轨合并。

可行的复用方式是调整原生构建并链接一个小型合并入口；不是让 Dart 访问未导出的函数，也不是把 FFmpeg 结构体布局直接暴露为长期 Dart API。

## 三种路线比较

| 路线 | 体积特点 | 优点 | 成本 / 限制 |
| --- | --- | --- | --- |
| 系统原生封装 | 不额外携带媒体引擎；仅增加桥接与业务代码，实际增量待构建 | 无重复解码依赖，平台 SDK 提供基础能力 | 三端实现和时间轴行为各自验证，编码支持受系统版本限制 |
| 独立精简库 | 只带需要的 MP4 解析/写入部分；实际大小取决于库和裁剪 | 对播放原生资产影响较小，可统一封装行为 | 重复一部分解析代码，需验证 AV1、B 帧、DASH/fMP4、HDR 元数据、大文件与许可 |
| 扩展既有原生库 | 共用已有 FFmpeg，只增加 MP4 写入和桥接；当前尚无三端增量实测 | 编码覆盖统一，已有 demuxer、codec 参数和时间基处理可复用 | 接管固定版本的三端原生构建、校验与资产发布；须做播放器回归 |

### 系统原生接口

- **Android**：`MediaExtractor` 读取压缩样本，`MediaMuxer` 写 MP4。项目当前 `minSdk = 24`；HEVC 封装从 API 24 支持，AV1 从 API 34 支持，MP4 的 B 帧封装从 API 25 支持。因此覆盖整个现有编码选择还需要能力限制或后备实现。[官方接口](https://developer.android.com/reference/android/media/MediaMuxer)
- **Windows**：Media Foundation 的 Source Reader / MPEG-4 File Sink 可以用于压缩样本管线。官方接口对 H.264 和 AAC 给出明确规则；其他格式需要提供 sample description，不能由此直接宣称所有系统版本的 HEVC / AV1 输入到输出均通过。还需保留 B 帧的 PTS/DTS、NAL 格式和音频起始偏移。[MPEG-4 File Sink](https://learn.microsoft.com/en-us/windows/win32/medfound/mpeg-4-file-sink)
- **macOS**：可评估 `AVMutableComposition` 加 `AVAssetExportSession` 的 [passthrough 预设](https://developer.apple.com/documentation/avfoundation/avassetexportpresetpassthrough)，或压缩样本读取/写入管线。当前部署目标为 macOS 12.0；输出 MP4 与各编码组合必须在目标系统实测，尤其不能用 AV1 的播放解码能力推导导出支持。

上述均是候选接口核对，**本轮没有运行三端系统原生合并验收**。

### 精简库候选

- [minimp4](https://github.com/lieff/minimp4)：单头文件、CC0，公开 API 覆盖 AVC / HEVC / AAC。核对的头文件没有 AV1 的公开封装类型，且 `tfdt` 支持默认关闭；需要进一步核对 composition offset / 编辑列表保留。不能因源码小就直接采用为全部编码的实现。
- [Bento4](https://www.bento4.com/documentation/mp4mux/)：专注 ISO BMFF，`mp4mux` 能从 MP4 导入轨道，跨平台且不依赖解码器。需实测当前 DASH 文件、分片输入和 AV1；其[上游许可](https://www.bento4.com/about/)为 GPL / 商业双许可，不能按宽松许可库直接引入。
- [GPAC / MP4Box](https://wiki.gpac.io/MP4Box/MP4Box/)：已有 MP4 轨道导入和 [AV1 封装支持](https://gpac.io/2018/10/27/official-av1-and-vp9-support-in-gpac/)，但完整发行包含更多能力，需要裁剪和三端构建评估；许可按选定版本的原始文件核对。本轮没有构建该候选库，未给出未经测量的体积结论。

### 独立精简封装构建的本地实测

为回答“随应用携带会增加多少体积”，另行编译了一个 Windows x64 流复制原型。源码为 [FFmpeg `n9.0.2`](https://github.com/FFmpeg/FFmpeg/tree/n9.0.2)，工具链为 MSYS2 UCRT64 GCC 13.2.0；这是独立工具，**不是现有 FFmpeg `n6.0` 播放库的增量实测**。

| 项目 | 实测结果 |
| --- | --- |
| 去除调试符号后的 `ffmpeg-mux.exe` | 1,694,208 字节，约 **1.62 MiB** |
| 仅包含该可执行文件的 ZIP（Deflate，级别 9） | 776,793 字节，约 **0.74 MiB** |
| 输入 / 输出 | MOV/MP4 demuxer、MP4 muxer（自动依赖 MOV muxer）、本地文件协议 |
| 编码器 / 解码器 | 均未编入；关闭网络和外部库自动探测 |
| DLL 导入 | Windows 系统库和 UCRT；未依赖另一份 libmpv、外部 FFmpeg DLL 或 MinGW 运行库 DLL |
| 构建配置报告的许可 | LGPL 2.1 or later；未启用 GPL / nonfree 选项 |

构建核心配置如下；自动选中的小型辅助组件以生成的配置为准：

```sh
./configure \
  --target-os=mingw32 --arch=x86_64 --cc=gcc \
  --disable-everything --disable-autodetect --disable-network \
  --disable-doc --disable-debug --disable-x86asm \
  --disable-avdevice --disable-swscale --disable-ffplay --disable-ffprobe \
  --enable-demuxer=mov --enable-muxer=mp4 --enable-protocol=file \
  --enable-parser=aac,h264,hevc,av1 \
  --enable-bsf=aac_adtstoasc,extract_extradata --enable-small \
  --extra-cflags='-Os -ffunction-sections -fdata-sections' \
  --extra-ldflags='-static -Wl,--gc-sections'
make -j8 ffmpeg.exe
strip ffmpeg.exe
```

源码归档 SHA-256：`6e374ed621e48faa40639307dff48ba6fe574a509977956d2cce9669b7cc27e9`。本地构建脚本、日志、样片和 `results.json` 位于忽略目录 `build/validation/download-mux-size/`。

使用完整 FFmpeg 仅生成测试输入，分别生成 H.264 / HEVC / AV1 的 1 秒分片 MP4 视频（12 帧；H.264 显式启用 B 帧），配合已有 AAC fixture，由精简原型以 `-c copy` 合并。三组输出的 12 个视频数据包和 564 个音频数据包均与输入数量一致、逐包 SHA-256 一致，各轨道 PTS / DTS 间距一致（允许误差 0.1 ms）。这验证了基础封装及压缩数据保留；没有完成不同起始偏移下的音画同步、真实下载文件、长视频或三端播放器验收。

上述 ZIP 没有包含许可材料、应用桥接或安装包开销，也未按 MSIX / MSI / EXE / APK / DMG 的实际压缩方式打包。因此它证明精简封装工具可以很小，不能直接承诺所有发布包增加 0.74 MiB；其他平台产物和扩展既有库的增量仍需分别构建测量。

## 接入设计与验收门槛

此处为后续实施方案，尚未创建这些接口或状态。

1. 在下载领域中保存明确的输出方式（分轨 / 合并 MP4），旧记录默认为分轨；下载窗口提供“合并为单个 MP4”选项。能力由注入的封装端口提供，不让页面自行判断操作系统。
2. 下载和双轨校验保持现有职责。封装适配器仅接收任务归属已验证的本地文件，使用独立上下文和后台工作，不借用 PlaybackSession、不访问网络。
3. 双轨完整后进入合并阶段，将结果写到任务目录内的临时文件。保留所有视频帧、AAC 数据、时间轴及编码信息，不启用编码器或自动降画质。
4. 取消、退出、切换账号和删除任务沿用队列取消/代次隔离；等待文件句柄关闭后只清理任务自己的临时输出。合并失败保留已下载双轨，允许重试合并。
5. 校验输出音视频轨道、长度/时长与哈希，完成文件原子提交后更新 manifest 和 SQLite。只有输出及索引提交可恢复后才删除分轨文件；中断恢复不能将未完成输出当作完成项。
6. 合并后的离线播放用一个本地媒体源、`audio = null`，沿用一个 PlaybackSession 和现有管理器；字幕/弹幕仍从附属文件读取。新格式不能破坏旧分轨任务。

验收至少覆盖 H.264 / HEVC / AV1 + AAC、含 B 帧与不同起始时间的样片、普通 MP4 / 实际 DASH / 分片输入、长视频和 64 位文件偏移；对照输入输出的数据包内容、PTS/DTS、帧数和时长，并验证 seek、音画同步。再验证取消/失败重试/断电提交窗口/旧记录/账号切换，并用同一批原生播放器回归样片确认修改库后播放功能保持正常。

依赖构建需固定源码、补丁、工具链、配置和产物校验，保存相应许可及源码材料。只开启 MP4 muxer 不等于需要开启 GPL 编码器；采用范围依据[FFmpeg 上游许可说明](https://ffmpeg.org/legal.html)，不能复制上游默认启用全部编码器的构建方案。

## 本轮验证边界

- 已核对：现有下载资源与离线双轨行为、锁定依赖、Windows DLL 导出和运行版本、Android arm64 ELF 动态符号和嵌入构建参数、macOS 固定版本构建源、三端系统接口文档和精简库候选；已完成 Windows 独立精简原型的构建、体积测量和三种视频编码的基础流复制验证。
- 本地探针位于忽略目录 `build/validation/download-mux-size/`，不加入应用资产或依赖。常规工程检查不受其影响。
- 尚未完成：下载 UI/队列合并实现、自定义 media_kit 三端构建增量、Android/macOS 运行、真实账号下载合并、系统原生接口验收、安装包体积比较。没有据此声称合并功能已实现。
