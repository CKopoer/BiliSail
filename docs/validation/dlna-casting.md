# DLNA 投屏

初版：2026-10-31；B站接收端兼容与直播扩展：2026-11-13。

## 功能与交互

- 普通视频、分 P、番剧／影视与直播共用播放面板入口。投屏图标统一放在播放控件顶栏右侧、听视频和配置按钮之前；普通、全屏、窄屏与小窗均可直接点击，底栏和更多菜单不再重复显示。普通／全屏均使用调用窗口内的 `showAppDialog`。
- 面板沿用晴湾主题、圆角卡片、主色与浅／深色配色，窄屏、横屏和放大文字通过滚动内容保留操作入口。
- 发现同一局域网中启用 DLNA 的 MediaRenderer，显示名称和设备 IP，可重新搜索。普通接收端取得完整媒体地址后接收 `SetAVTransportURI`、`Play`，确认成功才暂停本地会话；点播从头播放，直播播放当前流。不伪造远端进度或上报云端观看进度。
- 设备描述声明同主机的 Bilibili `NirvanaControl` 服务时，使用 B站扩展元数据交接内容身份：电视自行获取视频和弹幕，接收本地弹幕开关、清晰度和倍速，点播携带打开面板时的确认位置。普通接收端不接收扩展元数据，沿用原地址和 SOAP 控制。电视端账号与权益由接收应用管理，不向电视传送 Web Cookie、App token 或刷新凭据。
- 提供暂停、继续、停止。切换设备先等待旧设备 Stop 成功再交接，失败显示错误，不自动重放写命令。本机不会自动恢复播放。
- 关闭面板取消搜索和未完成请求；已交接的电视继续播放，面板说明可用电视遥控器控制。重新打开面板可重新选择设备；普通点播从头交接，B站扩展按新打开面板时的位置交接。
- 离线源和未完成解析的媒体不显示入口；iOS 暂不显示入口，尚未配置／验证受签名约束的 multicast entitlement。Web 不支持。

## B站扩展与直播（2026-11-13）

- `CastMediaRequest` 区分点播身份与真实直播间 ID，直播不借用 `cid`。`CastMedia` 只在当前操作内保留解析后的 aid／规范房间 ID 和可选媒体地址。控制器按设备能力请求接收端自行解析或普通直链；切换设备仍先等待旧设备停止，失败不自动重放。
- 发现增加 B站服务搜索目标；设备能力来自同一 MediaRenderer 自己的 serviceList，不根据友好名称推断，也不借用嵌套设备的服务。扩展控制地址与设备描述必须同主机，非法扩展服务不影响普通 AVTransport 发现。
- 对声明 B站服务的设备，`CurrentURI` 使用 `bilibili://projection?proj_source=bilibili&_nva_ext_=`，DIDL `upnp:longDescription` 携带原始 DEFLATE → AES-128-CBC／PKCS7 → 无填充 base64url 的内容信息。协议固定 key／IV 只用于兼容报文，不作为账号数据的加密保护；报文不包含账号凭据。
- 点播携带 aid／cid 或剧集／季 ID，直播携带规范 `roomId`；保留协议短字段 `ct/eid/sid/sk` 和兼容接收端所用的长字段。已有暂停／继续／停止继续走该设备 AVTransport。交接确认并暂停本地后，独立向已声明的 Nirvana 服务发送 `SetDanmakuSwitch` 应用弹幕开关；设置失败保留已经成功的投屏，明确提示可用遥控器调整，不重发播放。当前实现覆盖 SOAP 扩展，没有新增旧式 TCP NVA 长连接客户端，也不会在写命令结果不明时自动退回普通投屏。
- 普通直播投屏每次交接通过现有 `LiveClient.getPlayInfo` 重新解析签名地址，优先 AVC 的 MPEG-TS HLS，再选择 AVC fMP4 HLS、AVC HTTP-FLV。保留服务端地址及签名，不改写 CDN、不将本机播放器的 Cookie／Referer 转发给设备；无兼容流或下播时明确失败。接收端是否支持相应封装、是否可以直接拉流仍需设备验证。
- B站接收端不依赖点播 TV `durl` 成功；UGC 缺少 aid 时仍用原详情接口补齐。直播交接前验证开播状态并取得规范房间 ID，接收端自行决定实际媒体流和弹幕显示。

## 实现边界

- [CastClient](../../packages/bili_api/lib/src/clients/cast_client.dart) 使用固定 `api.bilibili.com/x/tv/playurl` 端点及已有 App profile 签名。服务端权益仍生效，Web Cookie 不转换成 App token；没有有效 App token 时按游客请求。只接受单段 `durl`，拒绝 DASH 单轨、多段及显式试看；HTTP／业务错误沿用统一分类。
- [ApiCastMediaRepository](../../lib/features/playback/data/api_cast_media_repository.dart) 在应用 data 层映射身份和安全存储中的现有 App 凭据，视频缺少 aid 时通过原有详情读取补齐；地址只保存在本次操作内存，不写数据库、设置或日志。
- [CastingController](../../lib/features/playback/application/casting_controller.dart) 管理搜索、设备选择和命令串行化。源 generation 或账号变化使面板失效；账号 lifetime 与 HTTP 取消同步。晚到的 URL／Play 回复不能触发后续设备命令或暂停新源。关闭面板移除监听并释放网络资源。
- [DlnaCastRepository](../../lib/features/playback/data/dlna_cast_repository.dart) 自行实现最小 SSDP／SOAP 适配：12 秒搜索窗口、最多 64 个描述地址及设备；HTTP 每次 5 秒、连接 3 秒、响应 256 KiB；设备描述错误不会阻止其他设备。按 UDN 去重，支持嵌套设备、相对 controlURL、URLBase 和带命名空间 XML。
- SSDP 描述地址必须与回复源 IP 一致，controlURL／URLBase 必须留在该主机；禁止跳转转发。设备 HTTP 通道不携带账号 header、Cookie、App token，不改变系统 TLS 校验。DIDL-Lite 和 SOAP 分层转义，保留带签名媒体地址与中文标题。
- 初版增加直接依赖 `xml: 6.6.1`（MIT，原已作为传递依赖锁定），无新增原生播放器或 DLNA 插件。macOS Release 增加 UDP 应答所需的 network.server 沙盒权限和局域网用途说明，发布签名校验同步检查；Debug/Profile 原已有 server 权限。
- 平台能力集中在 [casting_support.dart](../../lib/core/platform/casting_support.dart)。Android 使用既有 INTERNET 权限，SSDP 接收单播回复，不加入多播组；实际网络策略、Windows 防火墙、macOS 局域网权限和设备兼容性须实测。
- 新增精确依赖 `pointycastle: 4.0.0`（MIT，纯 Dart、无原生插件），仅实现扩展报文的标准 AES-CBC／PKCS7；压缩使用 Dart `ZLibEncoder`，根锁文件由固定 Flutter 3.47.6／Dart 3.13.5 生成，其他依赖不升级。

## 参考来源与许可

参考相邻 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/pages/video/controller.dart::onCast`、`lib/http/video.dart::tvPlayUrl`、`lib/pages/dlna/view.dart`：借鉴“专用 TV 地址 → 局域网发现 → 设置媒体 → 播放”的协议和职责流程。PiliPlus 应用为 GPLv3；本次未复制其页面、GetX／SmartDialog 实现或资源，也未新增其 `dlna_dart` 依赖，按本项目分层重新实现。

设备动作按 [UPnP AVTransport](https://openconnectivity.org/wp-content/uploads/2015/11/UPnP-av-AVTransport-Service.pdf) 的公开协议组织；[Sony AVTransport 示例](https://github.com/sonydevworld/audio_control_api_examples/blob/master/DLNA/AVTransport/play_file.adoc) 用于核对动作结构。没有修改相邻仓库或 Pub 缓存。

2026-11-13 扩展只读参考：

- MIT 的 [NeoBV](https://github.com/b1ackmarket/NeoBV/tree/6c8ce4bbf82f43681cc6c5e46cd4f8c9b9b71bf6) 的 `cast/protocol/NvaExtDecoder.kt`、`CastContentParser.kt` 与接收协议测试，核对压缩、加密、字段和 DIDL 承载；没有复制其 Kotlin 实现、官方抓包样本或任何账号数据。
- GPLv3 的 [Danmu TV](https://github.com/CurryFishBalls9527/DanmuTV/tree/d28b8aed03e6da6df47469ac22771dc40ae228f4) 的 `Packages/BiliKit/Sources/BiliKit/CastSOAP.swift` 和 `DanmuTV/Core/CastReceiver.swift`，只核对协议事实、内容身份与接收端自取弹幕职责，未复制 Swift 源码。
- GPLv3 的 [Pure Live](https://github.com/liuchuancong/pure_live/tree/1a60607cdd308132afcd85cd562f404109499633) 的 `lib/domains/live/presentation/playback/dialogs/live_dlna_dialog.dart` 与投屏生命周期审计，只借鉴直播地址交接和串行控制职责，未复制 Flutter 页面或引入 `dlna_dart`。

本项目独立实现领域模型、仓储、能力分流和协议编码，没有修改参考仓库或媒体／弹幕依赖。

## 验证

2026-11-13 新增协议模拟器和数据层回归覆盖 UGC／PGC／直播扩展身份、位置／倍速／弹幕偏好、普通设备报文不变、跨主机扩展服务隔离、直播 AVC 流优先级／地址刷新／下播，以及取消、账号变化和设备切换。共享播放面板回归包含直播普通／小窗／全屏入口与离线隐藏。

- 固定 Flutter 3.47.6／Dart 3.13.5 下，1134 个 Dart 文件格式检查、全项目静态分析、Linux 平台适配单独分析、新增文档相对链接和 `git diff --check` 通过；根与四包锁文件严格解析通过，只有根新增 pointycastle 锁定项。
- 投屏四文件加共享播放面板 **516 项通过**，包含独立弹幕开关失败不撤销交接；另外用 Python `cryptography`／`zlib` 独立解码本项目生成的三组 UGC／PGC／直播报文，校验身份、位置、偏好与无凭据字段，**3/3 通过**。
- `tool/check.ps1 -SkipPub -Stage RootTests` 通过：根应用 **5296 项通过、6 项条件跳过**，耗时约 12 分 33 秒。
- `tool/check.ps1 -EnforceLockfile -Stage PackageTests` 通过：bili_api **917**、bili_player **212**、bili_danmaku **161**、bili_mux **5** 项通过。bili_player 1 项因未配置 `BILI_TEST_NATIVE_MPV`／`BILI_TEST_MEDIA_DIR` 跳过、mux 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不能计入原生覆盖。
- 完整 `tool/check.ps1 -EnforceLockfile` 在 Linux／PowerShell 的 `test-macos-release-validation.ps1:320` 子进程回收断言中断，未修改无关构建脚本。独立补跑余下打包边界和源检查；Windows 资产模拟检查最初缺少 CMake，准备本次临时 CMake 4.1.2 后 **11 项通过**，其余补跑项通过。日志保留在执行工作区 `/workspace/scratch/casting-*.log`。

没有连接真实电视，没有进行本轮应用构建或在线账号／会员／直播烟测；不能将模拟接收器应答和协议报文校验记为云视听小电视、NeoBV 或其他接收端实机兼容通过。

### 初版与后续按钮布局验证（历史记录）

- `packages/bili_api/test/cast_client_test.dart`：UGC／PGC 身份与签名、游客、无 Web Cookie、非法／多段／DASH 地址、HTTP 错误及晚到账号响应。
- `test/features/playback/casting_controller_test.dart`：成功交接后的本地暂停、命令串行、设备切换屏障、失败不重放、源／账号／销毁取消、晚到 Play 隔离与容量限制。
- `test/features/playback/dlna_cast_repository_test.dart`：本机真实 UDP／HTTP 模拟渲染器的发现去重与搜索截止、XML 解析及地址限制、签名 URL／中文标题的 SOAP 转义、Fault 和进行中 HTTP 取消。此为受控协议回归，不代表真实电视兼容性。
- `test/features/playback/casting_dialog_test.dart`：项目浅／深色主题下窄屏选择、暂停／继续／停止，以及短窗口 2 倍文字下的滚动布局。

公开在线游客烟测：`BV17x411w7KC` 的真实 aid／cid 经 TV 接口取得地址成功，使用无 Cookie／Authorization／Referer 的独立 HTTP 客户端请求 0–1023 字节范围返回 206；ffprobe 在有限探测预算内返回成功，并确认同时包含 video、audio 两种流。未打印或落盘签名地址。此结果只覆盖该公开视频和当前游客请求，账号／会员内容与 PGC 在线鉴权仍待验证。

Windows Debug 构建通过，启动普通入口后 DTD 热重载成功，未捕获运行时错误。首轮 Windows 构建因共享构建目录的 MSVC PDB 写入冲突失败，重试时为本次命令设置 `/FS` 后成功，没有修改项目编译选项。

独立工作树基于 `d89be75`，只应用本次投屏改动：`tool/check.ps1 -EnforceLockfile` 的五份锁文件复现、格式、静态分析和打包边界检查通过。首次进入测试时既有 media-kit 归档下载遇到 TLS 握手失败；复用按固定 SHA-256 校验的本地归档后，仍经原构建钩子再次校验和解包，补跑 `-SkipPub -Stage RootTests`、`-SkipPub -Stage PackageTests` 均通过。根应用 3801 项通过、13 项条件跳过；bili_api 505、bili_player 105、bili_danmaku 145、bili_mux 5 项通过，mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不能视为原生覆盖。

共享工作区检查期间存在同期历史搜索 `loadHistory(keyword)` 接口与测试桩暂不同步的问题，未将其文件纳入本次修改或提交；播放模块及相关历史回归另有 952 项定向测试通过。提交内容单独整理，保留同期修改。

后续投屏按钮上移顶栏：当前工作区执行 `tool/check.ps1 -SkipPub` 全部通过，根应用 3818、bili_api 525、bili_player 105、bili_danmaku 145、bili_mux 5 项通过；13 项既有权限条件用例及 10 项 mux 原生用例跳过。播放面板回归确认普通／小窗／全屏的顶栏唯一入口、底栏及更多菜单不重复、320 宽度双倍文字与恢复后的底栏断点。Windows Debug 构建通过；暂停启动的调试实例执行 DTD 热重载成功，未进行人工界面验收。日志：`build/casting-topbar-check.log`。

未连接真实电视，电视实际音画／编码／拖动遥控、设备网络隔离、Android 和 macOS 构建／真机仍未验收；不将协议模拟器通过记为实机投屏通过。
