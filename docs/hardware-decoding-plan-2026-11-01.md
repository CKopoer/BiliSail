# 直通硬件解码调研与实施方案

日期：2026-11-01。状态：**调研完成，方案待实施**。应用基线 `b0be7d9`，Flutter 3.47.6／Dart 3.13.5。本轮只读检查 issue、发布版本、参考源码与原生库扩展，未实施依赖切换、设置或 fork 合并。

**后续实施更新（同日）**：按用户后续缩小的范围，已单独实现 Windows ANGLE 配套 libmpv 的 EGL 扩展检测修复候选，并完成 NVIDIA 本机 `d3d11va-copy` → `d3d11va` 与三组性能交叉对照，见 [Windows 最小修复记录](validation/windows-angle-direct-hwdec-2026-11-01.md)。下文保留调研时的版本和完整路线；硬解设置／严格回退、DXGI、自有 fork 整合及其他平台仍未实施，不将本次最小修复视作 P1–P4 全部完成。

## 1. 建议与目标

建议使用用户的 `CKopoer/media-kit` 统一维护经审查的补丁，**按平台选择输出路径，不再整体切换某一家的所有实现**：

1. Windows 保留现有 **Skia**，优先验证 **ANGLE＋修正后的 libmpv**；将改进后的 **D3D11／DXGI** 作为独立候选，在同样的 Skia 条件下比较后决定是否采用。
2. Android 保留 MediaCodec 非 copy 硬解，增加 `mediacodec_embed` 直出模式；补齐 Surface／VO 切换生命周期，设备验收后再决定自动模式是否优先采用。
3. macOS／iOS 以 VideoToolbox＋GPU pixel buffer 互操作为目标，Linux 以 VAAPI／NVDEC＋EGLImage 互操作为目标。分别验证，不将 Windows 的渲染开关、DLL 或 DXGI 补丁带到其他平台。
4. 设置增加按平台提供的“硬解模式”，同时提供实际路径与回退状态。显式指定模式失败时明确提示，不能显示成“已直通”或偷偷修改保存偏好。
5. 第一阶段目标是**支持的设备／编码尽量不经 CPU 回读**，并减少重复视频渲染。系统视频平面／原生合成作为后续独立实验，不承诺 Flutter 弹幕下的 3D 占用接近零。

不能把下列三种“直通”混为一谈：

| 层次 | 含义 | 如何判断 |
| --- | --- | --- |
| 解码直通 | 解码结果保留在硬件／GPU surface，未走 `*-copy` 的 CPU 回读 | 实际 decoder、硬件帧格式、interop 和后端状态共同判断 |
| GPU 资源交付 | 视频输出通过共享纹理、EGLImage、CVPixelBuffer 等交给 Flutter | 检查 GPU 资源、复制与同步；共享 handle 不保证内部无 GPU copy |
| 原生呈现／合成 | 视频由系统独立 surface／plane 呈现 | 单独验证系统合成路径；`mediacodec_embed` 接 Flutter Texture 也不自动达到这一层 |

`hwdec-current=d3d11va` 不代表没有颜色转换、缩放、GPU 纹理复制或 Flutter 合成；Copy 引擎为零也不证明没有回读。Chrome 与 Flutter 的视频呈现、overlay 使用及刷新策略不同，不能仅用任务管理器百分比判定解码路径。

## 2. 必须先区分的版本和证据

### 2.1 issue #44 与当前工作区不是同一条渲染路径

[BiliSail #44](https://github.com/CKopoer/BiliSail/issues/44) 报告 Windows 11、8845HS／Radeon 780M、版本 **1.2.5+3**，3D 约 50%、Copy 约 30%、Video Codec 低于 5%。这是用户报告，未提供实际 `hwdec-current`、视频格式、刷新率和原生库摘要，尚不能判定是解码回读、GPU 输出复制还是其他原因。

追溯 [v1.2.5+3 发布](https://github.com/CKopoer/BiliSail/releases/tag/v1.2.5%2B3) 的源码提交 `a88f72ab0dd477e3715e49743850725a453e587e`：[锁文件](https://github.com/CKopoer/BiliSail/blob/a88f72ab0dd477e3715e49743850725a453e587e/pubspec.lock)指向 **Predidit `83b7ca…`**，Windows 是 **DXGI**，runner 未关闭 Impeller。调研时最新公开发布 v1.2.6+1 的目标 `7c6755e26715bd221f7e541a6b83593d3e5b5919` 也仍采用该依赖。这里只确认发布源码／锁文件，未取得反馈者机器上的 DLL 或日志。

| 对象 | 精确来源 | Windows 输出／合成 |
| --- | --- | --- |
| #44 对应发布源码 | 应用 `a88f72ab0dd477e3715e49743850725a453e587e`；Predidit `83b7ca63772856e1ea0158916177e136f7b7b0be` | DXGI／mailbox；runner 默认引擎设置 |
| 当前工作区 | 应用 `b0be7d9`；core `73771ec38176be2d984a3049c28177bce23b54a0`；video `fd8421d21eade4d6d12de137fa7df902fec20292` | ANGLE；显式 Skia；libmpv `43b14a4c9` |
| Bili.Libre.Speed | 应用 `cbedbe95f6d4a6132150f920bfd4ad5866b90f25` | 锁文件 native `73771ec…`，但 CI 另覆盖 Windows 为 `1ea01b6…` 的 DXGI |

因此，PiliPlus 的 ANGLE 扩展修复**不能直接解释 #44 旧 DXGI 包的全部症状**；当前工作区也不能沿用旧发布包“已直通”的结论。issue 中关于 AMD 或合成的归因保留为线索，不作为已确认根因。

### 2.2 当前 ANGLE 确有需要优先排除的互操作缺陷

[PiliPlus #3292](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3292) 的作者报告 UHD 770 上 `auto-safe` 实际使用 `d3d11va-copy`。[#1432 中的对照](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/1432#issuecomment-5755283629) 报告保持 ANGLE 不变，换更新 libmpv 后 H.264／HEVC／AV1 的 `d3d11va` 可用。这些是他人的设备结果，不是本项目重新实测。

上游 [mpv `1d15686142fd5d53c954aab7526cedab05ef9dc3`](https://github.com/mpv-player/mpv/commit/1d15686142fd5d53c954aab7526cedab05ef9dc3) 于 2026-07-31 修正 `EGL_EXT_device_query` 检查：同时认可 display 与 client 扩展。已读取当前 `43b14a4c9` 的 `video/out/opengl/hwdec_d3d11egl.c`，其仍只检查 display。

本轮用当前 Release 目录的 ANGLE 做了**只读 EGL 查询**：

| 扩展 | client | display |
| --- | --- | --- |
| `EGL_EXT_device_query` | 有 | 无 |
| `EGL_ANGLE_d3d_share_handle_client_buffer` | 无 | 有 |
| `EGL_ANGLE_stream_producer_d3d_texture` | 无 | 有 |

这符合上游缺陷的触发条件，支持先修正当前 Windows 库。探针只加载当前 DLL，以 `eglGetDisplay`／`eglInitialize` 初始化自己的 display，对 `EGL_NO_DISPLAY` 和该 display 分别查询 `EGL_EXTENSIONS`，最后 `eglTerminate`。查询没有创建 mpv 播放器，**不等于新库直通或性能已通过**；完整结果和三份 DLL 的 SHA-256 见 [EGL 查询记录](validation/data/hardware-decoding-egl-2026-11-01.json)。

本项目历史上还使用过带该修复的标准 ANGLE 库 `88eb9f2e73945d8bc9c133a2f67babaa9af34680`，来源与配置保留在 [旧 Windows 资产记录](../windows/native/mpv/SOURCE.md)。它是优先核验候选，不是本轮直接启用旧 `mpv.cmake`：后续须审查其构建、许可与当前 SDK／插件兼容性，并纳入唯一的资产入口。

### 2.3 已有 Skia 结果不能替代这次候选对照

[此前记录](validation/windows-skia-playback-2026-11-01.md) 在同一 ANGLE／copy 解码条件下，Windows 全屏开弹幕 3D 从 16.77% 降至 5.45%／5.25%。它证明合成后端有独立影响，不证明已完成直通，也不是 ANGLE 与 DXGI 的公平对照。后续所有候选先固定 Skia，保持弹幕密度、透明度、控件、输出尺寸和视频时间段一致。

## 3. Bili.Libre.Speed 实际采用了什么

[1-Reality 的评论](https://github.com/bggRGjQaUbCoE/PiliPlus/issues/3292#issuecomment-6258168899)描述了 DX11 直通、失败提示和 Android embed 能力。以下按源码核对其实现和适用边界：只读快照固定为 `cbedbe95f6d4a6132150f920bfd4ad5866b90f25`，不执行其 patch／build 脚本。

### Windows

1. `pubspec.lock` 的 core／video 都是 My-Responsitories native `73771ec…`，**锁文件不能描述最终原生源码**。
2. [发布工作流](https://github.com/ucxn/Bili.Libre.Speed/blob/cbedbe95f6d4a6132150f920bfd4ad5866b90f25/.github/workflows/release.yml#L519) 执行 [media_kit_windows_d3d11.ps1](https://github.com/ucxn/Bili.Libre.Speed/blob/cbedbe95f6d4a6132150f920bfd4ad5866b90f25/lib/scripts/media_kit_windows_d3d11.ps1#L7)，将 Windows video 和 Windows libs 目录替换成 **My-Responsitories `1ea01b6fc5f4a4762bd99a018e858a7d155d6fca`**。
3. 该 MIT 分支使用 `MPV_RENDER_API_TYPE_DXGI`、D3D11 device、四槽 mailbox／fence 和 DXGI shared handle。使用 Flutter 所在 adapter，但仍是新建 D3D11 device；**同 adapter 不等于同 device**。
4. 配套库为 20260911、`41f6a64` 的 DXGI 扩展构建。默认 x86-64-v3，便携脚本另换 generic x86_64。本项目不能直接沿用 v3 作为普通 Windows x64 基线。
5. [video_output.cc](https://github.com/My-Responsitories/media-kit/blob/1ea01b6fc5f4a4762bd99a018e858a7d155d6fca/media_kit_video/windows/video_output.cc#L57) 开启 `ADVANCED_CONTROL`，仅在 `MPV_RENDER_UPDATE_FRAME` 时 render／commit。不过 `MarkTextureFrameAvailable` 仍在条件外，不能认定已经消除所有重复呈现。
6. 应用设置会控制 `hwdec-software-fallback`，并定期检查实际 decoder、提示不符合白／黑名单的结果。它也有自动模式和带 fallback 的预设，故“不会偷偷降级”应按具体模式理解，不能扩展成所有配置绝不回退。

这条路径仍将 BGRA 纹理交给 Flutter，**不是绕开 Flutter 的原生视频窗口／系统 overlay**。CPU 回读可以避免，但 GPU 色彩转换、输出纹理和合成成本仍可能存在。

### Android

应用将 `mediacodec_embed` 作为一个产品模式，实际配置为 **`hwdec=mediacodec`、`vo=mediacodec_embed`**，不是把 `mediacodec_embed` 当成真正的 hwdec 名称。[mpv 输出说明](https://mpv.io/manual/stable/#video-output-drivers)说明其会绕过 mpv 的视频渲染，原生 OSD、视频滤镜及 mpv 字幕等能力受限。

[Android patch](https://github.com/ucxn/Bili.Libre.Speed/blob/cbedbe95f6d4a6132150f920bfd4ad5866b90f25/lib/scripts/patch_media_kit_android_decoder_lab.ps1) 将 hwdec／VO／fallback 放入 `on_load` 前的正确时机，并在 VO 改变时重建 Surface，避免同 URL 切模式复用错误的 Surface。

锁定 native 分支的 [Java 实现](https://github.com/My-Responsitories/media-kit/blob/73771ec38176be2d984a3049c28177bce23b54a0/media_kit_video/android/src/main/java/com/alexmercerind/media_kit_video/VideoOutput.java#L72)用的是 `TextureRegistry.createSurfaceTexture()` 与 `new Surface(surfaceTextureEntry.surfaceTexture())`。因此它省去了 mpv 的额外渲染，但**仍通过 Flutter Texture 合成**，不是 SurfaceView／SurfaceFlinger 独立视频层。

应用的主要字幕由 Flutter 控件绘制，本项目也在 `PlaybackPanel` 中绘制自己的字幕，因此 embed 不应自动禁用全部字幕；需要分别验证 Flutter 字幕与 mpv 内部字幕／滤镜。

### 可借鉴和不直接照搬的部分

| 内容 | 处理 |
| --- | --- |
| My-Responsitories DXGI renderer／mailbox、按新帧渲染 | 从原 MIT 来源审查，带入本项目已有生命周期保护后实验 |
| Android 的配置顺序、Surface 与 VO 绑定 | 借鉴行为，在 fork 的正式接口中实现，不使用应用私有 `user-data/*` 通信 |
| 实际模式检查与失败提示 | 改为结构化状态与原生事件，覆盖首帧失败、暂停、切源，不能只依赖 position 前进时轮询 |
| 修改整个 Pub 缓存、`reset --hard`、全量覆盖目录 | 不采用；固定 fork 提交或校验后的构建副本 |
| Windows 默认串联大量 D3D12／AMF／QSV／CUDA 等名称 | 不照搬；仅开放固定二进制和当前输出后端确实支持的组合 |

Bili.Libre.Speed 应用为 **AGPL-3.0**；My-Responsitories／Predidit media-kit 的 MIT 与 mpv 二进制的许可分别审查。应用脚本里的新增实现不能因被注入 MIT 文件就自动按 MIT 复制。未明确可复用许可的部分只参考行为、独立实现；不导入其整套 Flutter 或业务补丁。

## 4. Predidit 的取舍

本项目原用 [Predidit `83b7ca63772856e1ea0158916177e136f7b7b0be`](https://github.com/Predidit/media-kit/tree/83b7ca63772856e1ea0158916177e136f7b7b0be)，Windows 为 DXGI／mailbox，资产 `20260915-git-0b7ed67`，支持本机曾测得的非 copy 硬解。其 renderer 与上述 My-Responsitories DXGI 结构接近。

已检查原始源码及本项目旧发布 patch：存在请求合并，但没有上述 `ADVANCED_CONTROL`／`UPDATE_FRAME` 门控；有 callback 就可能再次 render／commit。当时本项目 runner 又未关闭 Impeller。因此，**旧版 3D 较高不能单独归因于 DXGI 或直通解码**，也不能宣称加一个门控就必定解决。

Predidit 值得保留研究的内容：Windows 的匹配 adapter／GPU 交付、Linux 独立 EGL 渲染线程与 EGLImage／fence mailbox，以及按目标校验的原生资产思路。其 Native Assets 迁移不是实现直通的必要条件；本项目刚稳定的库插件／CocoaPods 打包不宜同时整体重做。

## 5. 各平台落地路线

| 平台 | 优先路线 | 候选／回退 | 必须单独验收 |
| --- | --- | --- | --- |
| Windows x64 | Skia＋ANGLE，libmpv 包含 `1d156861…`，优先 `d3d11va` | 改进后的 DXGI；NVIDIA 可验证 NVDEC；允许兼容的模式才用 copy／软件 | AMD 780M、Intel UHD 770、NVIDIA；混合显卡与显示器切换；H.264／HEVC／AV1 |
| Android arm64 | MediaCodec surface 非 copy 硬解；增加 embed 直出选项 | embed 资格不满足时走 MediaCodec＋mpv GPU；兼容模式才继续 copy／软件 | Qualcomm／MediaTek／Exynos 至少按可用设备覆盖；旋转、切源、后台、HDR、字幕 |
| macOS arm64／x64 | VideoToolbox 非 copy＋CVPixelBuffer／IOSurface GPU 互操作 | 明确报告的 copy／软件回退 | Apple Silicon 和 Intel 分开；GL→Flutter Metal 交付、色彩、内存与释放 |
| iOS arm64 | 同上，保留 Flutter 字幕／弹幕 | 不将 Windows Skia 开关带到 iOS；原生 layer 另做实验 | iPad mini 6 等历史崩溃设备、EAGL 初始化、后台恢复、方向／Surface 生命周期 |
| Linux x64 | VAAPI（Intel／AMD）或 NVDEC（NVIDIA）＋匹配 EGL display／EGLImage | 输出上下文不兼容时明确报告，再走允许的回退 | Wayland 与 X11 分开；驱动／容器 render node 权限；独立线程与 fence |

Linux [当前视频插件](https://github.com/bggRGjQaUbCoE/media-kit/blob/fd8421d21eade4d6d12de137fa7df902fec20292/media_kit_video/linux/video_output.cc)已经传入 X11／Wayland display 并使用 EGLImage，不能再按早期“完全没有 VAAPI 互操作”描述。[Predidit 的线程／mailbox](https://github.com/Predidit/media-kit/blob/83b7ca63772856e1ea0158916177e136f7b7b0be/media_kit_video/linux/texture_gl.cc)优化需要比较后移植，不因其改进就整体替换 Linux 库与 GTK 生命周期。

Apple 当前 [iOS TextureHW](https://github.com/bggRGjQaUbCoE/media-kit/blob/fd8421d21eade4d6d12de137fa7df902fec20292/media_kit_video/ios/Classes/plugin/TextureHW.swift) 与 macOS 实现中的 `copyPixelBuffer()` 返回已有 pixel buffer 的 retained 引用；不能由方法名推断它复制了整帧。目标是保持 GPU backing 并确认 VideoToolbox 实际路径，而非仅改变一项 hwdec 字符串。当前 OpenGL／OpenGLES 跨 API 交付是否高效仍需设备验证。

Android 的 MediaCodec 名称也不绝对代表芯片硬解。若能从原生层取得实际 codec component，可结合 API 29+ 的 `isHardwareAccelerated`／`isSoftwareOnly` 辅助判断；厂商标记仍需设备数据验证，无法确认时显示未知。

## 6. 设置、状态与回退设计

### 产品设置

沿用设置页“视频编解码”区域：保留现有“视频解码方式：自动／软件”，其下增加 **“硬解模式”**。软件模式下禁用硬解选项但保留用户保存值；软件解码只设置 `hwdec=no`，**不因此关闭 GPU 视频输出**。

| 模式 | 行为 |
| --- | --- |
| 自动（优先直通，推荐） | 先尝试当前平台合格的非 copy 路径；允许受控兼容回退，实际回退时提示并显示结果 |
| 仅直通硬解 | 只接受该平台的非 copy 路径；失败明确报错，提供用户操作的兼容／软件重试 |
| 兼容硬解（允许回读） | 可选择 `auto-copy` 或已支持的 copy 路径，不标为直通；软件回退仍显示实际结果 |
| 指定硬解模式 | 当前平台支持的 D3D11VA／NVDEC／VideoToolbox／VAAPI／MediaCodec 及明确的 copy 变体；显式选择默认严格执行 |
| MediaCodec 直出（实验） | Android 专属，内部解析成 decoder＋VO 组合；说明 mpv 滤镜／内部字幕限制 |

`auto-safe` 与 `auto` 在当前 mpv 文档中是别名，不重复包装成“最佳”“普通”两个能力。第一版不开放自由 mpv 参数输入；D3D12 直通、AMF／QSV 等组合只有在固定库和输出后端验证支持后才进入选项。

“自动”和“仅直通”是产品策略，不原样传给 mpv。由解析器生成 driver 顺序、VO、interop、fallback 和 renderer 要求。例如 Windows ANGLE 候选可先尝试 `d3d11va,auto`，严格指定则使用 `d3d11va`；Android embed 生成 `mediacodec`＋`mediacodec_embed`。具体值以原型验证后固定，不能仅凭枚举项认为可用。

### 持久化和现有架构

- `AppSettings` 增加按 Windows／Android／macOS／iOS／Linux 存储的稳定模式 ID，避免跨平台导入设置后把 D3D11VA 当成 Android 模式。继续由设置控制器与 `SqliteSettingsRepository` 保存。
- 保留旧 `videoDecoding=software`；旧 automatic 且缺新字段时取推荐自动。使用名称／ID，不使用 enum index；恢复默认、非法值回退、导入导出、保存失败回滚同步处理。仅增加现有 JSON 偏好字段，不预设必须改 SQLite 表版本。
- 不支持的显式选择显示原因，不悄悄覆盖保存值。设置仍在**下次打开／重新加载源时生效**；如提供“立即应用”，通过当前会话完整重载并保留位置、倍速、音量、音轨与用户暂停意图。
- 在现有 `VideoDecodingMode`／`OpenOptions` 扩展纯 Dart 的模式与配置；平台解析留在 `bili_player`，页面不调用 media_kit 或自行拼 mpv 参数。
- `PlaybackSession` 在 source generation 开始时一起捕获新设置，沿用账号／源隔离、导航所有权和异步取消，不在加载过程中只切换一半配置。

### 实际状态与严格模式

引擎补充类型化解码路径状态：请求模式、实际 decoder、interop、GPU／软件输出、渲染后端、回退原因，以及 probing／confirmed／unknown。实际属性未就绪不能当成软件解码；音频模式标记为不适用。

`hwdec-interop` 可能包含多个已加载驱动，不是当前帧实际使用路径的单独证明；须与实际 decoder、硬件帧格式和输出状态匹配。

“播放信息”展示“解码器：D3D11VA／回读模式／软件”“输出：ANGLE／DXGI／MediaCodec 直出”“合成：Skia／Impeller”等有意义的状态。只有证据齐备才标记已确认；不从 GPU 引擎占用或设置值推断成功。

`hwdec-software-fallback=no` 不能替代对首帧和实际 decoder 的检查。“仅直通”若得到 copy／software，指定模式若得到不符合所选模式的 decoder，或发生首帧失败／运行中降级，应暂停并提供清晰的硬解不可用错误及显式重试。用户显式选择的 copy 模式可以接受对应 copy decoder，但仍标为回读。不无限刷新 CDN，也不改写持久设置。自动模式最多按约定的直接→兼容→软件顺序做有限尝试，报告本次回退，保留用户播放意图。

把检查纳入既有首帧门槛与 opening deadline，沿用 source generation 的取消／超时隔离；未确认前不发布硬解成功状态。网络尚未建立、音频源或视频参数未就绪，不应误报为硬解失败。

监视应由原生 property／生命周期事件驱动，必要时低频补查；不能只在播放 position 前进后检查，也不能逐帧读取。沿用自己的观察 client，不消费 SDK 的事件队列。日志只保留白名单字段与二进制版本／摘要，不记录 Cookie、URL query、playlist 或原生日志全文。

## 7. 原生改动必须满足的约束

### Windows 两个候选都保留现有保护

- 原生创建／释放／MethodChannel 回复的线程边界、纹理注销完成屏障、队列排空、COM 引用租约、稳定 texture ID、视口上限及 paused／首帧重绘保留。
- `ADVANCED_CONTROL` 只能在审查渲染线程后启用。[mpv render API 合同](https://github.com/mpv-player/mpv/blob/1d15686142fd5d53c954aab7526cedab05ef9dc3/include/mpv/render.h#L64)要求渲染线程不得调用会等待同一 core 的非安全 API，否则可能永久死锁。本项目由 Dart 提供显示尺寸、避免同步读取 mpv 尺寸的保护不能丢失。
- 合并 update 请求；无新视频帧时不重复 render／commit，也不重复通知 Flutter 视频纹理。弹幕继续随显示刷新率运行，**只隔离视频生产／提交，不给弹幕降帧**。
- resize、首次打开、暂停打开／seek 后仍需显式重画当前帧。不能简单加 `UPDATE_FRAME` 判断而遗漏强制重绘。
- fence 完成后的最终帧发布不能依赖“下一次视频帧到来”：暂停／EOF 可能没有下一帧。首次有效帧、最后一帧、旧资源租约和 resize 销毁顺序必须有实际像素测试。
- 记录解码／输出／Flutter 的 adapter，检查混合显卡。需要 `ID3D11Device5`／fence 时做能力检查；本项目不采用未经比较的高 GPU thread priority，也不把 v3／AVX2 DLL 当通用 x64 库。

### Android 配置作为完整输出会话切换

在 decoder 探测前设置 hwdec、VO、fallback 和有效 Surface；不能在 Surface 已经绑定后临时改 VO。重建身份至少包含 source／output generation 和 VO，不仅比较 URL。卸载时解除旧 VO／wid，等待 codec／Surface 引用释放，再创建新 Surface，避免 `native_window_api_connect=-22`。

embed 可用性还取决于旋转、裁剪、宽高比、HDR／色彩和输出能力，不能只以 codec 打开成功作为验收。Flutter 字幕、弹幕、控件、滑动亮度和全屏行为要分别测试。

## 8. 自有 media-kit 的维护方式

只读核对用户仓库：`main`／`codex/piliplus-android-surface` 为 `63b7ea7dd95fc348cecf250df5f54ff87d69d8a9`，FLAG ABI 修复在 `codex/fix-mpv-flag-abi` 的 `24f5c7cb6b78f68fa7c23c73ffe7294f0bd962ab`。不能直接在相邻旧检出上覆盖文件或认为该修复已在当前 core 中。

后续建立 `codex/bilisail-hwdec` 集成分支／隔离工作树，先形成与当前应用行为等价的基线，再分块合入：

| 来源 | 合并内容 | 边界 |
| --- | --- | --- |
| 当前 PiliPlus 对应 MIT core／video | 当前异步创建、事件桥、headers、Android Surface 基线 | 不整体升级 public API 或其他平台打包 |
| 用户旧 ABI 修复 | 在新 core 结构中修正 MPV FLAG 的 C int 宽度与生命周期，移植回归 | 当前 core 仍出现 `calloc<Bool>`；应用字符串规避先保留，验证后另清理 |
| 本项目 Windows patch | 平台线程、释放、视口、首帧、队列和租约 | 合入正式 fork 接口后，应用补丁转为兼容性校验，避免重复应用 |
| mpv 上游／匹配构建 | Windows ANGLE 扩展修复 | 通过原生二进制构建／选择完成；只合 Dart/C++ 插件不能修复 DLL 内代码 |
| My-Responsitories `1ea01b6…` | DXGI 候选与 frame update 控制 | 专用 header／DLL 成套；保留上述保护，审查门控外通知与最终帧发布风险 |
| Predidit `83b7ca…` | 经对照选中的 mailbox／EGL 线程等改进 | 逐平台移植，不把 Native Assets 全迁移作为前提 |

稳定版本先沿用已有 `media_kit_libs_*`／CocoaPods 打包。Native Assets 是后续独立打包决策；不与解码／渲染实验绑定。Windows ANGLE 与 DXGI 原型使用不同完整 bundle，禁止同目录混放不同族的 mpv headers／import lib／DLL。若以后同一库支持两种输出，须有明确的能力协议与匹配资产清单后再做运行时选择。

原生资产统一记录平台、架构、基础 CPU 指令集、mpv／FFmpeg／补丁提交、输出 API、构建选项、归档及 DLL SHA-256、许可和可重建材料。下载、缓存、构建和打包读同一清单；不能靠“解压目录非空”复用旧库。不改 Pub 缓存，不用随机 DLL 替换正式安装目录。

应用只依赖用户 fork 已推送、可获取的完整提交；同步根应用和 `bili_player` 的 core／video／libs／overrides 及两份锁文件。弹幕依赖不随这次播放器工作再次迁移。分阶段合入、每个平台保留上一稳定提交和资产，回退不涉及用户数据库清空。

## 9. 实施顺序与退出条件

| 阶段 | 交付 | 退出条件 |
| --- | --- | --- |
| P0：证据与 fork 基线 | 解码／输出诊断、发布包指纹、原生资产清单、等价的自有 fork 基线 | 能准确区分 decoder、CPU 回读、GPU 输出与 Flutter 合成；当前行为回归通过 |
| P1：Windows 最小修复＋设置 | 更新 ANGLE 配套 mpv；硬解模式与严格／自动回退；旧设置兼容 | 至少在 AMD 780M、Intel UHD 770、NVIDIA 分别确认目标 codec 的实际路径；无法取得的设备明确待验 |
| P2：性能候选 | 同 Skia 的改进 DXGI 原型、Android embed 原型 | 完整生命周期及像素验收；性能合格才替换对应平台默认，不要求两家同时胜出 |
| P3：Apple／Linux | 各自硬解互操作确认和必要的线程／资源修补 | macOS 两种架构、iOS 实机、Linux X11／Wayland 分别验收，不能用 CI 构建代替 |
| P4：按证据评估原生合成 | 仅在剩余瓶颈确为 Flutter 合成时研究独立视频层 | 样式、字幕、输入、遮挡、DPI、全屏、多窗和平台可用性不退化 |

P4 的 Windows 可评估原生 video window／DirectComposition，Android 可评估 SurfaceView 与系统合成；它们不是当前 Texture 路径的几个参数开关。Flutter 的 HCPP 仍属实验能力，要求 API 34+、Impeller Vulkan，不能覆盖项目 Android 最低版本，也不能因为 Windows Skia 改善就关闭 Android 的 Impeller。[Flutter 官方平台视图说明](https://docs.flutter.dev/platform-integration/android/platform-views)

### 性能与功能验收

1. 先用本地合法 fixture（分轨 H.264／HEVC Main10／AV1、1080P／4K、30／60fps），再用同时间段的真实视频和相同弹幕。按设备支持选择组合，不把不支持的 AV1 强行列为“必须直通”。
2. 基线 A：当前 ANGLE／copy＋Skia；候选 B：修正 ANGLE／direct＋Skia；候选 C：改进 DXGI／direct＋Skia。Impeller 只作为独立消融，不混入 fork 优劣判断。
3. 匹配实际编码、码率、输出像素、DPR、刷新率、透明度、弹幕数量与控件状态，覆盖 1×／2×／3×，重点复现 #44 的 iGPU 和 #3292 的高倍速场景。至少完成三组有效交叉对照；网络断流样本单列，离线基线不得被其阻塞。
4. 记录实际 decoder／interop／输出后端、native render／publish 次数、CPU、各 adapter 的 3D／Copy／VideoDecode、频率、功耗、掉帧、A/V 差、首帧时间及内存。必要时使用 ETW／GPUView／PIX、Perfetto 或 Instruments 确认是否存在 CPU readback。
5. “直通通过”要求实际非 copy 路径与 GPU 输出得到确认；渲染／提交次数接近视频帧更新，而非弹幕刷新次数。严格模式失败与自动回退均可观察，不伪造成功。
6. 性能结果要求在匹配场景中 CPU／带宽或总工作量有收益，且合成、功耗、首帧和稳定性无不可接受回退；不以 GPU 百分比单独通过，也不设“所有 GPU 必须低于某个固定 3D 百分比”。
7. 验证暂停打开／seek、EOF 最后帧／重播、切 P／清晰度／编码、音频模式、字幕、缓冲、账号／source generation、隐藏／关闭标签、多窗、旋转／DPI／resize、后台恢复；补设备丢失和至少一小时长播压力。支持 HDR 的声明须另有色彩／tone mapping 验证。

自动检查按根 `tool/check.ps1` 和 fork 的 core／video 回归运行；Windows 使用现有媒体、content、resize、dispose、GPU 队列脚本。新增针对设置兼容／解析、严格首帧验证、回退次数、旧事件隔离及 Surface／VO 重建的行为测试。原生修改在对应主机和设备验证；保留 mux 原生环境跳过与未测平台，不为这份方案执行 Android 构建。

## 10. 本轮完成与仍待证实

已完成两个 issue 和关联讨论、发布标签／锁文件、Bili.Libre.Speed CI 补丁链、My-Responsitories DXGI 源码、Predidit 历史实现、当前五个平台路径及用户 fork 分支的只读核对；完成本机 EGL client／display 扩展查询。

尚未执行任何候选换库、fork 合并或新性能对照，未验证 AMD／Intel 问题设备、Android／Apple／Linux 设备。上游报告与源码支持候选路线，不作为本项目的设备通过结论。本方案未改变现行 D66 的 Windows Skia 决策。
