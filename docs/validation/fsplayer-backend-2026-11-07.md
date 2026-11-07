# 可选 fsplayer 后端与 Android 对照

日期：2026-11-07。按用户要求增加 Android、iOS、macOS 的第三个可选后端，media_kit 仍是默认，已有 fvp 和有效设置保留。Android 实测没有证明 fsplayer 整体优于现有两者；4K60 复测出现进度减慢和原生音画时钟偏差，暂保留实验性定位。

## 使用与架构

设置 → 播放 → 视频编解码 → 播放后端选择 `fsplayer（实验性）`，仅在 Android／iOS／macOS 显示。保存后下次打开或重新加载源生效，当前会话不替换。失败明确报错，不隐式换后端；默认、非法值回退与恢复默认仍为 media_kit，不改数据库表。

`bili_player` 提供三平台插件与 `FsPlayerEngine`，沿用 `PlayerEngine`／`VideoOutput`、现有 `PlaybackSession` 和 Flutter 弹幕、字幕、手势及控件。fvp／fsplayer 共用有首帧门槛的 `NativeTextureVideoOutput`。业务身份和账号留在主应用。

- Android：一个 FSPlayer 解复用和同步两轨，MediaCodec → AImageReader／AHardwareBuffer → Vulkan → Flutter Texture。软件解码仍用原生 Vulkan 输出。此后端不采用现有「解码直出纹理」开关，设置保留供其他后端使用。
- Apple：公开 `videoRenderingWillDisplay` 回调交接保留引用的 CVPixelBuffer，经 FlutterTexture 呈现，关闭 FSPlayer 自己的 drawable 绘制。iOS 使用 SDK 的音频会话配置和中断处理；线程结束后才注销纹理。识别到 PQ／HLG 或已知 Dolby Vision P5 时返回共享颜色不兼容错误，供业务选择兼容流，不承诺 HDR 屏幕直通。
- DASH：Resolver 把有效时长传给 `DashPairSource`；内存 MPD 的两个 Representation 使用显式 `SegmentList`／`SegmentURL` 指向完整独立 MP4，由同一原生实例保持时钟。两轨须使用相同、经过校验的请求头；Android content URI 文件描述符租约持有到原生释放完成。
- 网络：每个源拥有绑定 `127.0.0.1`、随机不透明路径的有界转发器。Dart HttpClient 使用默认系统信任链及主机名验证，保留 Range／206／Content-Range 和请求头，流式背压转发；HLS 子清单、分片和 key URI 改写到同一入口。并发最多 8，资源映射最多 512，清单最多 1 MiB／8192 行，设连接和读取超时；关闭源立即取消网络。普通本地媒体直读，内存 MPD 不落盘。
- 原生不允许 HTTPS／TLS 协议回退，避免 FFmpeg DASH 子资源没有继承 `tls_verify` 而绕过验证。原生只接触不透明远端入口，防止上游硬编码 ALOG 泄漏签名 URL。没有无条件证书接受回调，也没有真实账号写入。
- 静音预备并确认视频帧和必要音轨，定位续播位置后按最新播放意图恢复音量及播放。seek 等待原生目标帧通知；打开预算、取消、源代次、迟到创建回收及释放屏障隔离旧结果。网络先取消以打断原生读取，文件描述符在原生释放后关闭。

Android 当前拒绝非 1× 倍速并显示说明。公开 SDK 接受速度设置但实测媒体进度没有相应加速，不能只根据 API 返回成功显示倍速已生效。即使 1×，本轮 4K60 仍有复测异常，不能据此宣称稳定性验收完成。

## 固定来源与许可

采用官方 [FSPlayer 1.1.2](https://github.com/debugly/fsplayer/tree/f00c9e12b7304eca70b6ac27b09e915c24550898)，提交 `f00c9e12b7304eca70b6ac27b09e915c24550898`，构建子模块 `d4f1431be8e6da3738e70cc98abed61f3c69e7c8`；FFmpeg 为上游声明的 8.1.2。

[资产锁](../../packages/bili_player/native/assets.lock.json)固定原始 Android AAR 和 Apple XCFramework archive 的 SHA-256，Gradle／CocoaPods 下载时校验，不提交二进制，不修改 Pub 缓存，不借用 media_kit／MDK／bili_mux 的内部 ABI。Android 官方 Maven 坐标本轮未提供 1.1.2，因此把校验后的发布 AAR 放入 build 目录内的 Maven 仓库。Apple 使用本地固定 podspec。

许可、源码及重建入口见[原生说明](../../packages/bili_player/native/NOTICE.md)。公开版本不含 Pro 的 Dolby Vision P5 和无缝清晰度切换。原始 AAR 缺完整子组件 notices；发布分发前仍须补齐实际二进制对应的第三方许可清单，本任务没有发布安装包到 Release。

## 接入中发现的问题

初始整文件 `BaseURL`／`SegmentBase` 清单使 Android 官方发布库崩溃，栈经过 `avformat_open_input`、libxml 路径及 `strlen(NULL)`；data 和 HTTP 清单均复现。改用显式 `SegmentList`／`SegmentURL` 后启动回归通过。这是适配层绕过，不代表修复上游全部 DASH 输入。

Android `soundtouch=1` 路径在请求 3× 时实测仅约 0.84×；改用 AudioTrack 路径后，请求 3× 和 1× 都约 1.001×。最终限制 Android 为 1×。原生 frame-drop 返回 0 也不能替代媒体进度／A-V 差值的验证。

FSPlayer 公开 API 提供包数／字节缓存限制，没有与 mpv／MDK 相同的精确媒体时间窗口。适配设置有界包数和 256 MiB 包缓存；相同 120 秒请求不等于三者相同的实际缓存或内存压力，实测缓存量保留在数据中。缺失统计保持 null。

## 验证结果

- `tool/check.ps1 -EnforceLockfile` 通过：根应用 4635、bili_api 696、bili_player 271、bili_danmaku 161、bili_mux 5 个测试通过；根应用 13 项跳过，mux 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生通过。最终补跑 fsplayer 16 个定向测试通过，覆盖分轨、首帧、seek／暂停意图、取消、迟到创建与释放、错误脱敏、Range、HLS 改写及不可信 TLS 拒绝。
- Android Release／Profile 均构建通过。Xiaomi 13 受控分轨启动、播放／暂停打开、续播与截图验证通过；最终 `fs_tls_w3c` 的本地 HTTP 分轨及公开 W3C HTTPS 单文件均完成两次可见帧检查和进度前进。HTTP 的 Range、Referer、User-Agent 由服务端布尔校验，不记录其原值。无条件证书接受路径不存在；自签名 TLS 用例返回 502，源服务端收到 0 个媒体请求。
- 公开 GitHub raw HTTPS 的一次打开失败，主机亦无法完成该地址的 TLS 握手；该次不算通过。改用 [W3C 公开素材](https://media.w3.org/2010/05/sintel/trailer.mp4)完成正向 HTTPS 验证。HLS 改写做了本地集成测试，真实 CDN／直播尚未实机验收。
- Apple：[5cc85e4 的完整 Apple CI](https://github.com/CKopoer/BiliSail/actions/runs/42386627500)通过普通 iOS／macOS Release 编译，以及 macOS 原生 DASH 两轨、暂停打开、播放进度、倍速设置、seek、暂停 seek、音频单独打开与同步释放探针。此前 flutter run 启动器在探针输出成功后未退出，改为直接运行并检查退出码后通过。随后补充 iOS 音频会话配置的 62bbe25 复核已完成 iOS 编译；其余 CI 按用户要求中止，不记作该提交的完整 CI 通过。CI 构建和 macOS 托管 runner 探针不等于 iOS／用户 Mac 实机验收。
- 本机无调试 DTD 会话，hot reload 请求无法执行；Android 用 AOT 重建和重新安装验证。iOS 真机、用户 macOS 设备、后台／PiP／媒体键、真实 CDN／重定向、长期稳定性、正增益听感、HDR 及物理音画同步仍未验收。

## Android 性能条件与结果

沿用[既有基准](android-surface-output-2026-11-07.md)的 Xiaomi 13／Snapdragon 8 Gen 2、Android 16／API 36、2400×1080／120 Hz、Flutter 3.47.6 Profile／Impeller Vulkan。

同一对本地 DASH 文件：H.264 High、3840×2160、60 fps、约 24,981,946 bit/s、SDR BT.709，独立 AAC。视频 SHA-256 `378fd9df3f23e78e78a61dded68a1903246515ccdf31f00102cdce348673172d`，音频 `9486acce7909a09d2d775343ec7abca8e6896017ca7e3d09ef2e46b6834f0342`。静音但保留音频解码和时钟，20 条／媒体秒弹幕、每两媒体秒字幕、完整全屏控件常显；每场先执行同样的全屏、seek 和预热，再测 20 秒。

最终三后端均用硬解、Flutter Texture 兼容输出、请求 1×，按 media_kit → fvp → fsplayer → fsplayer → fvp → media_kit 顺序。因工作区同期 fvp 原生音频采样改动导致探针启动失败，对照隔离目录恢复任务开始时的应用适配器；保留工作区修改，SDK 固定来源不变。基线为 `569e7ea`，media-kit `9abd8a56`、fvp `e8163741`。该结果不等同于同期 fvp 改动后的版本性能。

| 后端／顺序 | 实际媒体进度／墙钟 | CPU（单核=100%） | 整机 GPU busy | Flutter raster P95 | 原生 A/V 绝对差值峰值 |
| --- | ---: | ---: | ---: | ---: | ---: |
| media_kit 正序 | 1.001× | 121.4% | 70.8% | 11.11 ms | 18.8 ms |
| fvp 正序 | 1.001× | 124.5% | 69.3% | 10.26 ms | 未提供 |
| fsplayer 正序 | 1.001× | 112.2% | 67.5% | 10.25 ms | 124.8 ms |
| fsplayer 反序 | **0.737×** | 96.2% | 53.2% | 11.80 ms | **1691.2 ms** |
| fvp 反序 | 1.001× | 130.4% | 58.7% | 11.39 ms | 未提供 |
| media_kit 反序 | 1.001× | 128.1% | 61.8% | 11.77 ms | 16.5 ms |

fsplayer 正序 CPU 较低，但反序没有达到目标进度，且出现明显原生 A/V 差值。因此不能把两轮平均或较低的反序资源占用解释成性能提升，也不能据第一轮认定整体更强。此次记录的是问题和边界，没有改写原生时钟掩盖异常。

另完成五种模式的 3× 正反序诊断：media_kit／fvp 兼容与直出实际约 3×；fsplayer 的 SoundTouch 路径仅约 0.84×、原生 A/V 差值约 2 秒，AudioTrack 路径也未达到 3×。这些 fsplayer 窗口负载不等，全部排除出同速效率结论。未完成的两次对照保留失败原因，未择取其成功片段冒充完整对照。

CPU 按应用 UID 调度时间汇总，计入 fvp worker；GPU 为整机 KGSL 忙碌比例。Flutter 帧率及 raster 只描述合成，不等于视频实际帧率。这是单设备短时实验，正反序不能完全消除温度／调频影响，没有测功率或续航。完整数值、场景、异常和来源见[脱敏数据](data/android-fsplayer-comparison-2026-11-07.json)，原始追踪保留在本机 `build/validation/fsplayer/source/build/validation/android-4k60/`。

## 安装恢复与复现

测试使用独立包名 `dev.bilisail.bilisail.test`／`BiliSail 测试版`，已有开发证书 SHA-256 `1a69fd8175656b4c091bea4dda3f30772901280f193a4c774c1412679ca30d1b`。普通入口 Release 预先保留；每次探针结束由 finally 覆盖恢复、启动并拉回 APK 校验摘要。没有卸载、清数据或修改正式包。为兼容设备现有版本码 12801，仅忽略的隔离源码目录使用 `1.2.8+1`，仓库版本不变。

最终普通入口 APK SHA-256 `25ffd85b236185d6d141a36acf9ed4e2d2d594353ac1f9a318e6779ba78b5578`。临时常亮设置恢复原值；只删除本次设备基准素材，不清理用户目录。

```powershell
./tool/check.ps1 -EnforceLockfile
./tool/test-android-surface.ps1 -DeviceId <device> -ConfigPath <startup.json> -Label <fresh-label> -StartupOnly
# 公开 HTTPS 素材须显式加 -Online。
./tool/test-android-surface.ps1 -DeviceId <device> -ConfigPath <comparison.json> -Label <fresh-label>
python tool/validation/summarize_android_surface.py <run-folder> --trace-processor <trace_processor_shell.exe> --output <summary.json>
```

场景 `backend` 为 `mpv`／`fvp`／`fsplayer`；fsplayer 用 `rate: 1`、`direct: false`、`surfaceView: false`。启动探针可用 `progressive: true` 验证单文件 HTTPS，否则使用分轨。固定素材摘要须一致；构建和安装遵守开发测试包脚本及签名、版本边界。
