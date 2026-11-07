# Android fvp 原生进程隔离

日期：2026-11-07（Asia/Shanghai）。针对打开视频时 MDK 读取线程在 `libmdk.so` 中空指针访问、产生 SIGSEGV 的故障，增加独立进程边界。它保护应用主界面，不声称已经修复 MDK 内部空指针的触发原因。

## 运行与恢复

- Android 的 fvp 使用同一包内、非导出的 `:fvp_player` 绑定服务。服务运行独立的 headless FlutterEngine，原生侧只注册固定版本的 fvp 插件和本地媒体描述符端口，不启动根应用、数据库、账号或第二份系统媒体通知。
- 主进程持有 Flutter Texture 与 Android Surface，经 Binder 将 Surface 交给子进程。MDK 的播放器、DASH 音视频、音轨探针、网络读取、解码、首帧及释放均在子进程执行；无需将 native 指针跨进程解释。
- 每个源仍由原 `PlaybackSession`／`FvpEngine` 拥有。Android 的 content URI 在子进程重新打开、独立租借，绝不传递主进程的裸 FD 数值。源取消后迟到的租约仍会关闭。
- 子进程异常退出后，通过 Binder 断开将所有受影响会话标为 `nativeProcessExited`，停止播放与采样、释放纹理，显示“播放器异常退出，请退出播放页后重新打开”。该分类不进入 CDN／网络自动重试，避免连续启动崩溃的播放器。关闭／重新进入或显式重试会创建新的 native player；主界面与账号状态继续保留。
- 同一主 FlutterEngine 共享一个 fvp 宿主，最多 16 个播放器。宿主跟随 cached engine，Activity 重新挂载时复用；引擎重启退役旧资源，引擎销毁完成服务清理。多个 fvp 标签共享这个故障边界，服务退出会让其中所有会话失败，不影响主界面。media_kit 和非 Android 平台沿用既有后端路径。
- 普通 IPC 操作有 40 秒上限，原源打开总 deadline 继续生效；释放等待 9 秒，服务启动等待 15 秒。服务卡死时只终止握手返回的当前子进程 PID，禁止操作主进程。只读播放信息超时返回不可用，不因此终止播放器。

## 日志与隐私

播放日志新增 `openStageChanged` 和 `nativeProcessExited`，含原源代次、时间、状态、后端及最后准备阶段。Android 11+ 若退出历史已可用，附正值 `nativeErrorCode`（系统退出 status，例如 SIGSEGV 的 11）。退出历史暂未可用或瞬时返回 0 时省略该字段，不能把缺失状态推断成正常退出。

不导入原始 tombstone、原生文本或 URL／headers／账号信息；既有日志导出会携带这些结构化播放记录。主进程仍存活，可以在出现故障后立即导出。进程断开也可能来自系统回收，因此事件名称表示进程退出，具体是否 native crash 由 status 和系统记录进一步判断。

## 来源与边界

- [Android 进程模型](https://developer.android.com/guide/components/processes-and-threads)、[FlutterEngine](https://api.flutter.dev/javadoc/io/flutter/embedding/engine/FlutterEngine.html) 和 [DartEntrypoint](https://api.flutter.dev/javadoc/io/flutter/embedding/engine/dart/DartExecutor.DartEntrypoint.html) 为官方接口依据。
- [Dart IPC 端口](../../packages/bili_player/lib/src/android_fvp_player.dart)、[子进程入口](../../packages/bili_player/lib/src/android_fvp_worker.dart)、[Binder 宿主](../../android/app/src/main/kotlin/dev/bilisail/bilisail/FvpProcessHandler.kt)、[服务](../../android/app/src/main/kotlin/dev/bilisail/bilisail/FvpPlaybackService.kt)。
- Surface 桥调用已固定 fvp 提交的包内 `nativeSetSurface`，适配代码位于应用自身的 `com.mediadevkit.fvp` 包；未改 Pub 缓存或引入新的 C++/MDK ABI 实现。升级 fvp 时必须重新验证这项包内接口与首帧／释放顺序。
- 当前库版本／原生资产清单偏差与 MDK 内部缺陷是独立问题，不由进程隔离自动解决。本次不依据隔离实现推导画质、解码性能或功耗收益。

## 验证

自动行为测试覆盖打开中／播放中进程退出、单次脱敏诊断、丢弃已退役端口、释放后重新打开，以及会话不自动重试 nativeProcessExited。

设备验证入口：`tool/test-android-fvp-process.ps1 -DeviceId <adb-id>`。先保留普通入口开发 Release，再使用同签名、相同 `.test` 身份的 Debug fixture；仅对 fixture 的 `:fvp_player` 子进程发送 SIGSEGV，检查主 PID 不变、按钮仍可交互并成功创建新子进程播放，最后在 finally 中覆盖恢复普通 Release。全程静音，使用本地 Range HTTP fixture，不访问真实账号或在线 Bilibili 内容。结果记录在 `build/validation/fvp-process-*.json`。

- 隔离源码快照按根检查脚本分阶段运行：根应用 **4599**、bili_api **678**、bili_player **222**、bili_danmaku **161**、bili_mux **5** 项通过，共 **5665** 项。根应用 13 项按原条件跳过；未配置 `BILI_MUX_LIBRARY`，10 项 mux 原生用例跳过。随后对播放会话重跑 274 项，通过；同步同期改动后对 fvp／进程端口重跑 23 项，通过，覆盖新增直出参数的传递与软件解码回退。
- 当前根工作区的 `flutter analyze --no-pub` 通过。完整检查最初受同期 Windows 原生测试占用 sqlite3.dll、macOS smoke flood 超时及中途编辑影响；隔离检出的打包边界、macOS/iOS 脚本已通过，后续 Lint 在同期 mini-player 测试文件格式检查处停止。未为本任务重排该无关文件，不把定向分析或分阶段测试表述为当前工作区整条 check 全通过。
- Xiaomi 2211133C／Android 16 真机：本地 HTTP Range DASH 分轨、实际画面与位置推进通过。19:12 的 SIGSEGV 注入中，主 PID **982** 保留，子进程 **6014 → 7214**，系统确认子进程 `APP CRASH(NATIVE), status=11`；界面按钮仍可点击，释放并重开后再次呈现彩条视频。19:17 再次验证，主 PID **3771** 保留，子进程 **10710 → 10862**。截图未显示覆盖主界面的系统崩溃弹窗。
- 实际主进程播放日志包含 `nativeProcessExited` 与失败状态；既有日志导出会汇总这类记录。初次即时读取退出历史得到 0，已改为省略未知码；系统稍后的 exit-info 能确认本次信号为 11。原生空指针的具体触发条件仍未确认，本轮验证的是故障隔离与恢复。
- Debug fixture 经 DTD 完成热重载，运行时无错误；两次成功测试结束均用同签名普通入口 Release 覆盖恢复。没有卸载、清数据、复制正式包凭据或正式包安装。
- 首次 fixture 构建遗漏版本 define，Flutter 将 +0 转成 +1，导致原 12800 备用包无法覆盖恢复。已修复脚本：fixture 与备用包显式保持相同版本码，安装前检查一致性。设备以 **1.2.8+1／12801** 的普通入口开发 Release 覆盖恢复，不使用强制降级；仓库源码版本保持 1.2.8+0。后续设备覆盖安装必须使用不低于 12801 的测试构建。
- 最终同步当前源代码后，Release 构建与全量静态分析通过；19:26 再次覆盖安装普通入口，确认不可调试、包名 `dev.bilisail.bilisail.test`、签名仍为原开发证书。APK SHA-256：`a8b5271450c2e2dc8bf7a7b1de6ac3b4bc80b5b986cc536f1eb4bfac1af5130d`。本地完整记录与 APK 归档在 `build/validation/fvp-process-final/`。后续仅补齐 cached-engine 生命周期归属与未知退出码过滤，这两项已参与最终 native 编译；Activity 重建与后台专项仍按下项保留未测边界。
- 多标签同时退出、离线 content URI、后台／PiP、直播、直出候选与长期性能尚未逐项实机复测；Apple／Linux 设备未测。本轮本地 fixture 的 Debug 帧率不作为性能结论。
- 提交前将共享文件里的同期直出／性能探针代码按片段剥离，在独立目录验证本次提交内容：fvp 引擎与进程端口 22 项定向测试通过，静态分析通过；并行工作区内容保留。
