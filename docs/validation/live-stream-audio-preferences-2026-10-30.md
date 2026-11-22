# 直播流选择与点播音质偏好

日期：2026-10-30。对应工作区基线 `107d233`；参考相邻 PiliPlus `936072449` 的协议和行为，自行实现，不复制其 GPLv3 应用代码、资源或状态管理，不新增依赖，不修改相邻仓库。

## 调研与取舍

- PiliPlus 的 `lib/http/live.dart` 使用同一直播 Web v2 接口，但查询 `codec=0,1,2`，并携带 `ptype=8`、`dolby=5`、`panorama=1`、`web_location=444.8` 与 WBI 签名。`lib/pages/live_room/controller.dart` / `widgets/header_control.dart` 可以选择协议、格式、编码与流内地址，并保存前三项。本项目原来固定 AVC，优先 fMP4 HLS；这使两个客户端可能拿到或选到不同的流。
- PiliPlus 的 `lib/models/video/play/url.dart` 合并 `dash.audio`、`dash.flac.audio` 和 `dash.dolby.audio`；`video_decode_type.dart` 识别 `dvh1`。音轨 ID 与实际编码不是同一个维度，不能用 ID 数值比较普通码率、无损和杜比的音质高低。
- [Apple HLS 规范](https://developer.apple.com/streaming/hls-authoring-specification-for-apple-devices.html) 列出 `dvh1` / `dvhe`、`fLaC` 和 `ec-3` 等样本类型。[Dolby profile 文档](https://ott.dolby.com/OnDelKits/Dolby_Vision_Online_Delivery_Kit/v1/Documentation/Specs/Visio_Profiles/help_files/topics/c_profiles_string_public.html) 区分编码字符串与 profile。识别这些字符串不等于设备支持完整 HDR、杜比视界显示或全景声音频输出；[mpv 手册](https://mpv.io/manual/stable/) 也指出色彩输出受合成器、驱动与显示设备影响。本次不改变原生渲染链路。

## 直播选择器

- 普通／全屏共用窗口内 Material 对话框，宽度上限 640；窄屏和横屏按可用高度滚动。标题和操作按钮固定，内容按“清晰度 → 直播流 → CDN 线路”组织，沿用应用主题与字体。窄屏“更多播放选项”增加同一个选择器入口，保留原清晰度／线路快捷项。
- 展示服务端提供且当前后端可识别的 HLS／HTTP-FLV、fMP4／TS／FLV 与 AVC／HEVC／AV1 等实际组合，不凭空拼装未提供的组合。只在按“应用”后换源，浏览选项不会反复重开播放器。当前实际清晰度和组合显示在面板顶部；CDN 只显示 host，不显示临时签名 query。
- 2026-11-21 对照 PiliPlus 更新了直播间自动选流。协议、格式和编码按接口返回顺序展示，自动模式使用第一组有可用地址且客户端可识别的组合。手动偏好优先精确匹配，房间缺少该组合时也按接口顺序回退。清晰度与 CDN 线路取自选中的组合。
- “记住直播流偏好”保存协议、格式、编码；新房间优先使用该组合，缺少时回退并提示。清晰度继续用独立的直播默认值，CDN 序号只属于当前会话，不保存 host、签名 URL 或账号凭据。设置页和播放器设置可查看偏好并恢复自动。
- 同一房间换清晰度／线路、返回保留页面沿用本次组合；新房间重新读取默认偏好。选择器捕获 source generation，保存前后均检查，旧房间／旧账号面板不能操作新源。保存失败保留面板并显示原因；关闭面板不提交。
- `LiveStreamPlaybackRepository` 为可选领域端口，由网络仓储和离线分发适配器实现；`PlaybackMedia` 携带有界的实际组合，页面不解析协议 DTO、不请求接口、不调用 media_kit。继续复用同一个 `PlaybackSession` / engine，保留暂停、音量、线路重试和账号取消隔离。

## 直播启播与默认行为（2026-11-22）

对照 PiliPlus 提交 `217fb54f51f6764176319bbdedab2a7522d75401` 的[直播间控制器](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/pages/live_room/controller.dart)、[播放器初始化](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/plugin/pl_player/controller.dart)和[网络判断](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/217fb54f51f6764176319bbdedab2a7522d75401/lib/utils/connectivity_utils.dart)，在现有会话与原生播放器中实现以下顺序。

- 进入直播间时用入口房号请求播放地址，同时加载房间资料。资料稍后补上标题、主播信息和聊天区，失败可单独重试。短房号首次解析为真实房号沿用已打开的会话，随后刷新发现真实房号改变才切源。资料沿用能提供完整简介的现有接口。
- 未配置直播画质时，移动端 Wi-Fi 与 Linux 非计量网络请求原画（`qn=10000`），移动端其他网络、Linux 计量网络及 Windows／macOS 请求超清（`qn=250`）。网络检测出错回退原画。已有明确画质（含自动 `qn=0`）按原值请求，实际画质由接口返回。
- 自动模式采用服务端给出的首个支持且有地址的组合与首条线路。手动偏好依次保留协议、格式和编码的匹配。缺少目标编码时选该格式内首个编码，缺少目标格式时选该协议内首个组合。同画质换组合或线路直接复用本次响应。切换到新画质或手动重新加载才重新请求播放地址。
- HLS 和 HTTP-FLV 先设置原生源，获得加载确认后按当前音量、1× 与播放权限发出播放指令。音视频轨道、解码和画面就绪仍单独确认。用户暂停、切房、切账号及切后台继续受会话控制。原生日志记录直播进入轨道发现、视频解码和输出等待的时间，方便区分下次慢启动卡在哪一步。

本次 Windows Release 日志中，一次 HLS 原生打开到输出就绪耗时 13.08 秒，随后两次同类打开分别约 0.78 秒和 0.52 秒。房间与播放地址 API 记录的耗时均在 0.30 秒以内。旧日志缺少轨道发现、解码与输出的分段时间，无法再定位那次等待中的具体环节。

Windows 受控回归延迟首个 HLS 分片后，在准备期间发出暂停，分片抵达时播放器保持暂停，恢复后音视频正常推进。公开房间 `6` 的 Windows 游客原生烟测使用超清默认值，请求和实际返回的清晰度都是 250。接口首选 HTTP-FLV 及同一响应中的 HLS 均确认解出音频和视频。此烟测使用 Debug 播放器，只验证在线启播。常规入口的 Windows Release 已重新构建，原慢场景没有同房间、同线路的发布版前后耗时对照。

## 接口与点播音轨

- 直播统一调用现有 `requestLiveWbiJson`，注册精确的 live host / path，复用 WBI key 单飞与有界重签。查询参数对齐上述 PiliPlus profile；无 App token、无账号写操作，保留现有超时和 session epoch。直播默认清晰度补充服务端的杜比 `30000` 档，权限和实际 `current_qn` 以接口为准。
- UGC 和 PGC 共用 DASH 音轨字段收集器，普通音频列表可为 null／缺失；单个 FLAC 对象和杜比音频列表也可独立存在。保留各自 ID、编码、码率和主备 URL；特殊列表同样有数量上限和协议类型校验。无音轨仍明确失败；静音预览维持 video-only 语义。
- `dvh1` 与 `dvhe` 识别为独立杜比视界类型，保持“先清晰度、再编码”的选择规则；不将其误当普通 HEVC。视频和影视的编码设置增加杜比视界选项。
- 音质偏好提供 AAC 64K／132K／192K、FLAC 无损、杜比。默认 AAC 192K 保留旧行为；按目标类别选择，再在类别内选较高码率。特殊类别缺少时先回退普通 AAC；AAC 132K 优先回退 64K 再 192K，64K 缺少时再尝试 132K／192K。仅当普通音轨也缺少时才尝试其余特殊类别，不因 30280 大于 30251 就覆盖用户选择。
- 音质在全局设置与播放器设置均可保存，下次解析视频、影视或所选语音时读取；不用于直播混合流，不自动应用到静音悬停预览。下载仍保留自身明确的 AAC 分轨选择与 mux 边界。
- `preferences.v1` 快照版本 31 → 32，SQLite schema 仍为 3。旧值、未知枚举和非法流组合回退到自动／AAC 192K，保留有效旧设置，恢复默认一致，不清空数据。

## 验证

- 离线协议测试覆盖 WBI 查询参数、UGC／PGC 三类音轨合并、普通音轨缺失、杜比 30250／30255 和 `dvh1`；领域／仓储测试覆盖音质顺序、特殊音轨缺失回退、实际直播组合选择及保留、CDN 顺序与点播设置隔离。
- 会话测试覆盖偏好首开、手动修改、切清晰度、返回原 owner、新房间恢复偏好，以及既有取消／账号／旧请求隔离；设置测试覆盖迁移、非法值、重载与恢复默认。组件测试覆盖亮暗主题、手机竖屏／横屏／桌面、普通／全屏、暂存后应用、保存失败和旧面板隔离。
- 游客在线执行 `dart run tool/live_stream_smoke.dart --online 6650029`：`qn=0/400/10000` 均成功，返回 7 个组合，每个 2 条线路；AVC／HEVC 实际为 250，AV1 为 400。这是本次服务端响应，不代表所有房间、账号权限或原生在线播放验收。探针只输出组合、实际清晰度与数量。
- Windows `tool/test-windows-content.ps1`：原有 UGC／PGC DASH、HLS、FLV 与独立播放窗口回归通过；新增用 FFmpeg 生成 MP4 容器 FLAC、E-AC-3 音频，使用生产 `selectDashMedia` 选择后交给锁定的 MediaKitEngine，AAC／FLAC／E-AC-3 三组均验证了解码后音视频和进度前进。合成 E-AC-3 样片不含 Atmos 元数据，不代表全景声输出验收。
- `tool/test-windows-codecs.ps1` 通过：H.264／HEVC／AV1 各自搭配独立 AAC，自动／软件两种模式共六组验证解码、进度、seek 和释放。本机自动模式为 `d3d11va`，软件为 `no`；256×144 合成片源不能证明实际直播 CDN、高分辨率或 HDR 效果。日志：`artifacts/live-windows-codecs.txt`。
- `tool/check.ps1 -SkipPub` 通过：根应用 3385、bili_api 496、bili_player 96、bili_danmaku 118、bili_mux 5，共 4100 项通过；格式、根应用／包静态分析和打包边界脚本通过。根应用另有 13 项平台／可选测试跳过；bili_mux 因未设置 `BILI_MUX_LIBRARY` 跳过 10 项原生测试，不计为 mux 原生验证。日志：`artifacts/live-full-check.txt`。最后一次 `flutter analyze --no-pub` 亦无问题。
- `flutter build windows --release --no-pub` 通过，产物 `build/windows/x64/runner/Release/bilisail.exe`；分发仍须保留完整 Release 目录。正常入口 Windows Debug 启动、DTD 热重载成功，运行时错误查询为空；测试应用已关闭。手机竖屏／横屏／桌面组件截图在 `artifacts/live-picker/`，它们属于合成 Flutter 测试环境。

Android、macOS、iOS、Linux 的原生设备播放、真实杜比视界/HDR 显示与 Atmos 输出，以及长时间直播稳定性仍未验收；Flutter 组件尺寸回归不能替代这些设备验证。
