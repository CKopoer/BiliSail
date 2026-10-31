# 播放控制、视频输出与平台合成拆分

日期：2026-10-23。范围：先完成接口与现有实现的职责拆分，继续使用当前 Flutter 渲染方式；不引入 Rust、不替换解码器、不修改弹幕或控件样式，不宣称性能提升。

## 1. 目标与现状

当前 `PlayerEngine` 已统一播放命令与快照，但其契约文件还包含依赖 Flutter Widget 的输出接口。`MediaKitEngine` 同时持有媒体实例、VideoController、Windows 视口通道与尺寸延迟任务；`VideoSurface` 直接探测这些能力，播放面板直接使用 Stack 合成。

本次把这些职责分开，使后续平台输出可以逐项替换；视频、PGC、直播、离线与悬停预览继续使用现有公共路径。一个播放会话仍只拥有一个 engine，源切换仍沿用现有代次隔离、分轨就绪与原生释放顺序。

## 2. 接口与依赖

```text
Flutter 页面、原有弹幕与控件
       │                         │
PlaybackSession / Manager        │
       │                         │
PlayerEngine（纯 Dart 控制）     │
       │                         │
MediaKitEngine ── VideoOutputSource.videoOutput
       │                  │      │
media_kit.Player    MediaKitVideoOutput
                          │      │
                    VideoSurface │
                          └── VideoCompositionAdapter
                                  │
                      当前 Flutter Stack / Texture
```

### 播放控制

- [player_contract.dart](../packages/bili_player/lib/src/player_contract.dart) 只保留源、命令、快照、失败与播放能力，不导入 Flutter；[bili_player_control.dart](../packages/bili_player/lib/bili_player_control.dart) 是可独立使用的纯 Dart 公共入口。
- `PlayerEngine` 的 `open/play/pause/seek/setRate/setVolume/stop/dispose` 与快照语义保持不变。
- `PlaybackSession` 和 `PlaybackManager` 继续拥有内容、播放意图、多标签与续播策略；libmpv 仍提供实际状态与媒体时钟，不新增第二套时钟。

### 视频输出

- 新增纯 Dart [VideoOutput](../packages/bili_player/lib/src/video_output.dart)：`attach`、`updateViewport`、`detach`，owner 隔离旧 surface 的延迟回调。
- `VideoOutputSource` 只提供稳定的 `videoOutput` 对象；它不是播放控制接口的父接口，无视频输出的 fake/audio engine 仍可实现 PlayerEngine。
- `FlutterVideoOutput` 是 Flutter 呈现能力，单独放在合成契约文件，不污染控制接口。
- 2026-10-31 增加可选 `VideoFrameReadiness.frameReady`，由输出汇合首帧、纹理和视频显示尺寸，并在 Flutter 帧结束后发布。共享播放面板用它约束弹幕显示；清除／重绑输出时立即重置，旧源通知不能重新放行。纯 Dart 控制接口、播放意图与弹幕时钟保持原有职责，见[首帧同步验证](validation/danmaku-first-frame.md)。
- [MediaKitVideoOutput](../packages/bili_player/lib/src/media_kit_video_output.dart) 持有现有 VideoController、首帧信号、Windows 视口通道、尺寸计算与缩小延迟。它不执行 play/seek/pause，不拥有媒体请求或业务状态。
- 输出由 engine 创建并最终释放；挂载和卸载视图不会销毁媒体实例。源释放先清除输出绑定，再沿用现有 media-kit 原生释放流程。
- 保留物理像素上限、源比例、64 像素取整、放大立即生效、缩小 300ms、预览 paintScale 与通道 deadline。源绑定、owner、revision 拦截异步旧写入。

### 平台合成

- [VideoCompositionAdapter](../packages/bili_player/lib/src/video_composition.dart) 提供输出 surface 构建与有序图层组合两个入口。
- 默认 `FlutterVideoCompositionAdapter` 使用现有 media-kit Video（NoVideoControls）和 `Stack(fit: StackFit.expand)`；传入图层顺序、Positioned、Opacity、手势、字幕、菜单和控件原样保留。
- 2026-10-24 为默认 Stack 和播放面板底部增加绘制边界，隔离外部布局与进度／字幕更新；仍使用同一路 Flutter 合成，不代表独立平台合成已实现。定位与本轮验证见[重绘性能记录](validation/playback-composition-performance-2026-10-24.md)。
- `VideoCompositionScope` 在应用组合根注入适配器，普通页面、全屏 Navigator 和悬停预览使用同一策略；独立测试没有 scope 时仍有当前 Flutter 默认值。
- `VideoSurface(engine: ...)` 保留为兼容入口，只解析 VideoOutputSource；新增显式 output 入口，使输出组件可以独立于 PlayerEngine 测试与复用。
- 不支持的输出类型必须明确报错，不能将“原生输出尚未实现”伪装成成功的黑屏。没有视频能力的 engine 保留原黑色后备。

## 3. 本次明确保留的行为

1. 原有弹幕 Ticker、文字缓存、过滤、轨道、透明度与动画时间不变。
2. 播放控件、字幕、进度条、菜单、输入法、快捷键及全屏交互不变。
3. Dart 会话与 engine 的所有权不变；输出 detach 不等于用户暂停，不能自行改变播放意图。
4. 源 generation、DASH 双轨、取消、超时与错误分类不变；初始 seek 在既有 open deadline 内确认原生位置，避免输出初始化时序影响暂停续播。
5. 不新增依赖、设置、数据库迁移、Rust 层、平台输出实验或 Flutter engine 补丁。

## 4. 后续平台迁移边界

| 平台 | 后续输出候选 | 合成工作与限制 |
| --- | --- | --- |
| Windows | mpv D3D11 composition swapchain | 单独实现 Windows embedder/DComp 合成，保证 Flutter 原有前景与输入；本次接口不代表该能力已实现 |
| Android | libmpv 输出到原生 Surface / SurfaceView | 区分解码与 Surface 生命周期，按目标系统和 Flutter 渲染器能力验证 HC/HCPP，保留现有路径 |
| macOS | 经验证的原生 NSView/图层输出 | VideoToolbox 解码不等于已提供 Metal/IOSurface 输出；Core Animation 与 Flutter 图层集成需单独验证 |

平台实现必须连同可兼容的输出与合成适配一起选择，不能只切解码名称。第一阶段按平台/能力选择后端，不承诺任意输出间无缝热切；必要时在现有会话控制下受控重建与恢复。

后续若增加独立弹幕内容层，继续使用 Flutter 绘制的文字和共享调度规则，不能借这次拆分重做原生样式。FFI/平台通道只传命令、事件或受控句柄，不逐帧回读视频像素。

## 5. 实施顺序

1. 保存本设计并建立控制、输出、合成契约。
2. 从 MediaKitEngine 提取当前 MediaKitVideoOutput，保持首帧与释放边界。
3. VideoSurface、共享播放面板与预览接入默认合成适配，组合根提供统一 scope。
4. 迁移 fake 和原生测试代理，补充职责、owner、异步尺寸与合成顺序回归。
5. 运行根检查与受影响验证，更新本文件的实施结果和索引。

## 6. 验证要求

- 独立输出的挂载、尺寸更新、替换和卸载，不得发出播放命令或释放 engine。
- 默认合成保持 z-order、透明度、尺寸和 hit-test；scope 必须覆盖全屏和预览。
- owner 交接、旧 post-frame 回调、旧源异步写入、缩小延时与释放后的任务应被隔离。
- 播放面板既有全屏、控件、字幕、快捷键、弹幕和预览测试继续执行；不靠新增浅层接口测试代替既有行为回归。
- 运行 `tool/check.ps1 -SkipPub`，如实记录 mux 配置跳过；原生测试与设备验收分别报告。
- 尝试连接调试应用并热重载；没有运行实例时记录不可用，不把静态检查写成设备验证。
- 此次结构拆分不做 GPU 收益承诺，平台输出与高刷性能仍需后续 Profile/Release 对照。

## 7. 实施结果

已按设计完成三层接口、MediaKitVideoOutput 提取、VideoSurface 双入口、应用组合根注入、播放面板/悬停预览接入与测试代理迁移。默认呈现仍为同一个 media-kit Video / Flutter Stack，弹幕和控件代码只改变组合调用入口。

纯 Dart 控制入口已通过独立 `dart compile kernel` 并执行，不依赖 Flutter 的 `dart:ui`。新增包级回归覆盖独立 output 交接、默认图层尺寸/点击、非 Flutter 输出委托、Navigator scope、显式不兼容错误和合成策略更换；正式 PlaybackPanel 回归确认普通/全屏使用同一 output，切换不重新 open，活动 surface 上限保持 1。

Windows 续播回归暴露了命令确认与位置事件之间的时序窗口：`media_kit.seek()` 返回只确认 seek 命令，可能仍读到旧位置。控制层现在在原有 open deadline、source generation 与终止错误边界内等待目标位置（250ms 容差，超出已知时长时按时长收敛），再报告打开完成；没有增加播放探测或任意延时。原生回归覆盖暂停状态的 DASH、渐进视频与纯音频续播。

本轮验证（2026-10-23）：

- `tool/check.ps1 -SkipPub`：格式、静态分析、打包边界脚本及根应用/四个包共 2,581 项测试通过；10 项 mux 原生用例因未设置 `BILI_MUX_LIBRARY` 跳过。
- `tool/test-windows-media.ps1`：22 项受控原生回归通过，包含双轨、headers/Range、续播、全屏、错误分类、启动取消/换源/超时、输出就绪、预览缓冲、归一化与前向缓冲。
- `tool/test-windows-content.ps1`：离线 HLS/FLV 的共享直播会话、原生 headers 与解码通过；在线 PGC/CDN 用例未启用。
- `tool/test-windows-video-dispose.ps1`：9 项 C++ 原生生命周期、渲染队列和尺寸用例通过。
- `tool/build-download-mux.ps1 -Target windows-x64`：固定来源的 Windows mux 资产重建通过。
- `flutter build windows --release --no-pub --build-name 1.1.0 --build-number 0 --dart-define=BILISAIL_RELEASE_VERSION=1.1.0+0`：构建通过；`build/windows/x64/runner/Release/bilisail.exe` 的文件和产品版本均为 `1.1.0+0`。本地未额外生成安装包。
- 热重载尝试未完成：集成测试运行期间仅发现短暂 DTD 实例，连接时已退出，没有可热重载的持久调试应用；上述 Windows 原生回归使用重新构建的可执行文件。

GPU 性能、180Hz 实测及 Android/macOS 实机不在此次结构拆分验收范围内；弹幕刷新策略没有改变。三端安装包交由本次版本推送后的 Release 工作流构建，触发工作流不等同于远端构建或设备验收已通过。
