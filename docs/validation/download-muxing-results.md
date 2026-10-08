# 下载可选 MP4 合并实施与验收

日期：2026-10-09。按用户选择采用独立精简封装组件；本轮测试通过后提交，**不构建应用、不安装设备**，后续应用构建与实机验收由用户执行。

## 实现

- 下载窗口新增默认关闭的“合并为单个 MP4”，下载卡区分 MP4 / 分轨，显示合并阶段和进度。能力从下载仓储注入；原生资产不可用时仅禁用合并选项。
- 新增独立 [bili_mux](../../packages/bili_mux/README.md)，固定 FFmpeg `n9.0.2`、来源归档 SHA-256 与库配置。只保留本地 MOV/MP4 解析、MP4 封装和必要码流处理，不编入编码器、解码器、滤镜、网络或完整 CLI；播放原生库保持原有职责。
- 小型 C ABI 只公开任务创建、执行、取消、进度和释放；FFmpeg 符号不导出，与播放器内部版本隔离。FFI 在 worker isolate 执行，原子取消/进度在调用 isolate 操作；销毁前等待执行结束和文件关闭。
- 原生封装保留压缩包、编码参数、共享时间轴和 B 帧 PTS/DTS；写入后重读输出，核对两轨数据包数量及按顺序/边界计算的 SHA-256。后台任务和内存都有边界。
- 合并写入 `media.mp4.part`；成功后刷新文件、计算文件 SHA-256、改名为 `media.mp4`，先保存输出身份，再写 manifest，最后提交完成索引。只有完成提交后清理源分轨；启动清理遗留分轨前重新核对输出哈希，损坏输出不得导致备份被删。失败/取消保留原轨并清理临时输出。
- 完整双轨的合并重试不重新解析远端播放地址或下载媒体。已提交输出身份但 manifest 未完成的任务复用输出；manifest 已完成但 SQLite 仍处于合并状态的任务在启动时恢复完成。未提交身份的输出不会被误认完成。
- 任务 JSON 增至版本 2，旧记录缺少输出方式时按分轨读取；manifest 分轨保留版本 1，合并使用版本 2。没有修改 SQLite 表/列，数据库 schema 保持 3；回归覆盖旧记录和文件提交窗口。
- 离线合并播放只挂载一个本地 MP4，`audio = null`，继续复用既有 PlaybackSession/PlaybackManager；字幕、弹幕、封面及其警告继续独立保存。

## 本轮验证

| 检查 | 结果与边界 |
| --- | --- |
| `tool/check.ps1 -SkipPub` | 根应用及四个包格式/分析通过；根应用 1,465、bili_api 336、bili_player 32、bili_danmaku 65、bili_mux 2 项测试通过。普通检查默认跳过 7 项需要原生资产的测试，另行启用运行见下项 |
| Windows x64 独立原生库 | GCC 13.2.0 编译通过；只导出 6 个 `bili_mux_*` 函数，DLL 导入为 Windows/UCRT 系统库，无外部 FFmpeg/MinGW 运行库 DLL |
| Windows 原生 FFI 回归 | 显式设置组件 DLL 和测试用 ffprobe，9 项全部通过：H.264/HEVC/AV1 + AAC、分片及普通 MP4、B 帧、250 ms 音频偏移、中文路径、逐包 SHA-256/数量/PTS/DTS/时长、取消后释放文件、输入错误和三个并发任务 |
| 下载与离线专项 | 60 项通过，含合并成功后删除分轨并重启、损坏输出拒绝播放、合并失败保留双轨/免重新下载重试、合并期间暂停和账号切换、两个持久化提交窗口恢复、v1 记录、两种输出方式分别去重、显式 UI 选项和单源离线适配 |
| Android arm64 原生库 | 固定 NDK 28.2.13676358 / API 24 交叉编译；ELF 动态导出只含本组件 ABI，LOAD 段使用 16 KiB 对齐。仅构建/静态核对组件，未执行 APK 构建或设备运行 |
| 发布接入 | Windows FFI bundled assets、Android jniLibs、macOS vendored framework 和来源/许可资源已配置；发布脚本先准备组件，在应用包旁另存对应 `.mux-source.zip`。新增 CI 原生回归门槛；尚未运行远端 Actions 或三端安装包验收 |

Windows DLL 实测 1,410,035 字节，约 **1.34 MiB**；这是组件文件大小，不等于 MSI/MSIX/EXE 的压缩增量。先前评估中的 1.62 MiB 是命令行原型，两者构建内容不同。

## CI 原生回归探测工具修复（2026-10-09）

[Release preview #17](https://github.com/CKopoer/BiliSail/actions/runs/37811377456/job/113428864815) 的 Linux 原生库构建成功，原生回归 8 项通过、AV1 项失败。Ubuntu 安装的 ffprobe 为 `6.1.1`，读取提交的 AV1 分片输入时遗漏全部 12 个数据包的 `duration_time`，测试强制转换字符串时抛出空值类型错误。样片容器中每帧仍保存 1024 / 12288 秒的时长，组件封装后的视频数据包哈希一致；本机 ffprobe `9.0.2` 下原生回归 9 项全部通过。

CI 改为从组件已经校验的固定源码单独构建测试用 ffprobe，并核对其版本与组件来源记录一致。探测工具保存在测试构建目录，不进入应用资产；测试继续严格比较数量、哈希、PTS/DTS、时长和共享时间轴，缺失／非法字段给出明确诊断，不填充为零或跳过比较。

提交前本机验证：`tool/check.ps1 -EnforceLockfile` 通过格式、分析及 1900 项测试，五份锁文件无差异；Windows 显式启用原生资产的 9 项回归全部通过。WSL Linux 实际构建组件和测试 ffprobe `9.0.2`，H.264／HEVC／AV1 + AAC 三组的包数、哈希、PTS/DTS、时长与相对起始偏移全部通过。两个工作流通过 actionlint，修改文档的 7 条本地链接通过。应用安装包和远端 Release 在此提交前尚未重新构建；这项修复不改变原生封装实现。

后续 [Release preview #18](https://github.com/CKopoer/BiliSail/actions/runs/37814204461) 已通过全项目检查及原生 9 项回归，继续打包时暴露 macOS 组件构建失败。平台构建包装脚本增加失败时输出配置／编译／链接日志末尾，供远端定位，不再只提示检查已经不可访问的 runner 本地文件。

## 用户后续手动构建

先按[组件构建说明](../../packages/bili_mux/README.md)准备对应目标的原生资产，再执行通常的 Flutter 构建。例如当前 Windows 主机：

```powershell
./tool/build-download-mux.ps1 -Target windows-x64
flutter build windows --release
```

Windows 需要 MSYS2 UCRT64 GCC/G++、make 等工具；当前主机已有且已验证。Android 使用同一脚本的 `android-arm64` 目标和固定 NDK；macOS 在 Apple Silicon/Xcode 主机运行 `macos-arm64`。原生产物位于忽略目录，修改原生源码或新 checkout 后需重新准备。`tool/build-release.ps1` 已自动执行准备。

待用户实测：实际 Bilibili DASH 各编码/清晰度与 HDR、长视频/大文件、播放器 seek 和音画同步、合并阶段中断/磁盘满/休眠恢复、账号切换和删除、三端打包与安装。macOS 原生组件在本 Windows 主机未构建或运行；后台系统下载服务仍不在此功能范围内。
