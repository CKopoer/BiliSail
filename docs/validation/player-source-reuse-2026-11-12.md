# 播放入口对齐 PiliPlus 与双后端换源复用

日期：2026-11-12（Asia/Shanghai）。本次先将工作分支从 `3565a2031fbdca180d03fad9999e48b4b0f7a4b5` 快进到 `origin/master` 的 `920e7bbd`，在干净工作区改造播放器。

## 核对结果

只读核对 PiliPlus `915276c87db37e5f361f5d30a0ed5dfe5ed7563a` 的 `lib/plugin/pl_player/controller.dart` 中 `_initPlayer`、`_createVideoController`、`refreshPlayer` 与事件订阅，并读取其 `pubspec.yaml` / `pubspec.lock`。媒体核心仍锁定 `My-Responsitories/media-kit` 的 `73771ec38176be2d984a3049c28177bce23b54a0`。本项目保留个人 media-kit fork `eaae0273a93fbd23b24e3c951b99efd9b73e702b` 和 fvp `e81637411c58a9ae28de246ee73ad06e3418f10e`，没有变更依赖或锁文件。

| 用户提出的差异 | 最新代码核对 | 本次实现 |
| --- | --- | --- |
| DASH 双轨组合 | PiliPlus 将双轨编码为 EDL 后 `Player.open`；本项目仍写 `audio-files` | mpv 改为 EDL 的独立音视频流，共用原生时间线与请求头。长度按 UTF-8 字节数编码，保留签名 URL、文件路径与 `fd://` 的边界 |
| 原生回调 | 本项目仍创建 weak client、wakeup listener 与 `on_preloaded` hook | 通过锁定 SDK 的 `observeEvent` / `observeProperty` 接入已有事件队列；不再新建客户端、NativeCallable 或 hook。保留 START/END、SEEK/PLAYBACK_RESTART 与色彩输出证据 |
| 播放健康检查 | 250ms 采样仍存在，但最新代码已是 `mpv_get_property_async`，不是同步查询 | media_kit 停用周期健康采样，位置、缓冲、播放、完成与错误取自 SDK；不再周期查询 `audio-pts`。显式打开播放信息/诊断时仍可按需读取指标 |
| 生命周期 | 最新版已等待真实释放，不再固定等 5 秒，但配置入口和后端仍每次重建 | 同一后端、已完成准备且兼容的源复用原生实例；换配置、未完成或失败的打开、停止和关闭仍等待完整释放。5 秒只是停止确认的最长等待，不是延迟销毁 |
| 音频配置 | 点播额外写 `audio-buffer=0.05`、`af=scaletempo2`、`autosync=30` | 删除生产路径的强制设置，采用播放器默认音频策略，保留用户倍速、音量、增益及显式诊断实验参数 |

这里只参考行为和职责，独立实现本项目适配层，没有复制 PiliPlus GPLv3 应用代码/资源，也没有修改参考仓库或 Pub 缓存。EDL 语法与 SDK 公开事件接口不引入 PiliPlus 运行时依赖。

## 生命周期和平台边界

`ConfigurablePlayerEngine.select` 一次读取设置并返回后端标识与工厂，同一设置复用子引擎；切换 media_kit / fvp 时先释放旧引擎再创建。共享状态机通过可选 `ReusablePlaybackBackend` 能力复用，只有已完成准备、没有在途 seek 或失败的源可进入此路径。取消、打开超时、停止未确认或配置不兼容时保留完整释放屏障，不能跨过未知原生状态分配下一实例。

mpv 复用前取消旧订阅、等待 `Player.stop` 和 `idle-active`，然后关闭本源文件描述符租约并建立下一源租约。SDK 事件注册只在实例创建时安装、销毁时移除；每次源重置清空就绪状态，并显式写回新源增益，避免零增益继承上一源设置。色彩映射在暂停的轨道发现后配置并核对，新源确认前遮住纹理，不能继承 SDK 实例级的首帧 Future。已经使用 Dolby Vision 特殊输出的实例在下次换源时完整退役，防止滤镜或渲染配置遗留。解码模式和 Android 输出模式改变也重新分配。

media_kit 停用健康轮询后，播放过程的停滞识别依靠 SDK 缓冲/错误事件与原生网络超时，不再提供原先基于音频 PTS 的逐轨停滞判断；打开、seek、停止的有限等待及取消仍保留。没有据此宣称性能或弱网恢复已改善。

fvp / MDK 不支持 mpv 的 EDL，继续使用实际视频管线与音频伴随管线及其原生同步时钟。兼容的双轨换源在原生停止确认、回调排空后复用这组实例，重置准备完成槽、EOF、音频帧计数基线、时钟、缓存与呈现状态；听视频、静音或双轨形态改变走释放路径。源重置和最终释放有共同的等待屏障，不能释放仍被重置任务使用的原生时钟。

Android fvp 保留进程隔离。IPC 的源代次独立于 seek 代次，过期位置、EOF 和首帧消费通知全部隔离；工作进程确认停止并解绑借用 Surface 后，UI 才释放旧纹理，再为新源创建输出。两个进程的媒体 FD 租约随源关闭重建，进程退出事件不被源代次过滤。

fvp 的 250ms 位置/缓存采样和必要的原生音频活动/同步机制仍保留：该 SDK 没有与 media_kit 相同的持续位置事件，双原生管线也需要共同的欠载判断。它不会收到 EDL URI 或 mpv 参数。对齐的是源生命周期、播放意图和共享状态契约，不宣称两套原生 SDK 的实现相同。

## 验证

使用项目指定 Flutter 3.47.6 / Dart 3.13.5；五份锁文件严格解析。新增行为用例覆盖同配置复用、配置切换时先释放、停止失败、取消重置、fvp 旧 EOF、Android 旧代次消息，以及复用纹理的首帧遮罩。双后端原生契约用例也增加了正式设置入口换源后引擎/后端身份不变和暂停目标验证。

| 检查 | 结果 |
| --- | --- |
| 根应用离线测试 | 5,254 通过，6 跳过 |
| bili_api | 911 通过 |
| bili_player | 381 通过（含增益重置回归），1 个可选原生 EDL 用例在默认套件中跳过，配置环境后单独运行通过 |
| bili_danmaku | 161 通过 |
| bili_mux | 5 通过，10 个原生用例因未配置 `BILI_MUX_LIBRARY` 跳过 |
| 静态分析 | 根应用、四个独立包及 Linux WebView 适配器均无问题 |
| 格式 | 根应用、四个包与 Linux 适配器共 1,164 个文件检查通过 |
| 打包边界 | iOS PowerShell 14 项、macOS Python 15 项、iOS Python 6 项、SQLite 17 项、Android fvp 8 项、Windows 资产 19 项、纹理交接 3 项、Apple 纹理 6 项、Apple 媒体资产 7 项通过 |
| 原生 EDL 专项 | Linux libmpv 真实解封装/解码用例通过，见下文限制 |

已运行 `tool/check.ps1 -EnforceLockfile`，总入口在未修改的 `tool/test-macos-release-validation.ps1:320` 失败：`The independent parent failed to terminate a stalled worker and its child.` 在当前 Linux 环境独立复跑仍失败，因此不标记总检查通过。其后检查已分别执行；最初缺失 clang / CMake 导致的构建和脚本失败，在工作区临时工具链补齐后复跑通过。平台打包脚本的模拟检查不等于平台构建或设备验收。

原生 EDL 可用下列命令单独复跑（环境变量指定 libmpv 和含 `video.mp4`、`audio.m4a` 的受控目录）：

```sh
cd packages/bili_player
BILI_TEST_NATIVE_MPV=/path/to/libmpv.so.2 \
BILI_TEST_MEDIA_DIR=/path/to/fixtures \
flutter test test/native_edl_playback_test.dart
```

本次 Linux headless 使用 Debian libmpv 0.40.0 验证双轨 HTTP headers / Range、暂停加载、同一实例连续三次打开（两次远程轨道、一次含中文和分隔符的本地文件）、SDK 事件重置及销毁。它不是本项目固定原生发布资产的验收，也未验证最终纹理、真实声卡或可听同步。当前主机没有 Windows/macOS 工具链及 Android 设备，三端构建/设备播放、Dolby Vision 色卡、连续切清晰度、后台与长时间播放仍待对应平台运行；不能拿离线假播放器或本次 Linux SDK 用例替代这些结论。
