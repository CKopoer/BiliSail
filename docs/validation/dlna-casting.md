# DLNA 投屏

日期：2026-10-31。

## 功能与交互

- 普通视频、分 P、番剧／影视共用播放面板入口。宽屏底栏显示投屏图标；窄屏和小窗使用“更多播放选项 → 投屏”。普通／全屏均使用调用窗口内的 `showAppDialog`。
- 面板沿用晴湾主题、圆角卡片、主色与浅／深色配色，窄屏、横屏和放大文字通过滚动内容保留操作入口。
- 发现同一局域网中启用 DLNA 的 MediaRenderer，显示名称和设备 IP，可重新搜索。点击设备后解析当前内容的 TV 地址，发送 `SetAVTransportURI`、`Play`，收到成功响应后暂停本地会话；远端从头播放，不伪造远端进度或上报云端观看进度。
- 提供暂停、继续、停止。切换设备先等待旧设备 Stop 成功再交接，失败显示错误，不自动重放写命令。本机不会自动恢复播放。
- 关闭面板取消搜索和未完成请求；已交接的电视继续播放，面板说明可用电视遥控器控制。重新打开面板可重新选择设备，重新交接从头播放。
- 直播、离线源和未完成解析的媒体不显示入口；iOS 暂不显示入口，尚未配置／验证受签名约束的 multicast entitlement。Web 不支持。

## 实现边界

- [CastClient](../../packages/bili_api/lib/src/clients/cast_client.dart) 使用固定 `api.bilibili.com/x/tv/playurl` 端点及已有 App profile 签名。服务端权益仍生效，Web Cookie 不转换成 App token；没有有效 App token 时按游客请求。只接受单段 `durl`，拒绝 DASH 单轨、多段及显式试看；HTTP／业务错误沿用统一分类。
- [ApiCastMediaRepository](../../lib/features/playback/data/api_cast_media_repository.dart) 在应用 data 层映射身份和安全存储中的现有 App 凭据，视频缺少 aid 时通过原有详情读取补齐；地址只保存在本次操作内存，不写数据库、设置或日志。
- [CastingController](../../lib/features/playback/application/casting_controller.dart) 管理搜索、设备选择和命令串行化。源 generation 或账号变化使面板失效；账号 lifetime 与 HTTP 取消同步。晚到的 URL／Play 回复不能触发后续设备命令或暂停新源。关闭面板移除监听并释放网络资源。
- [DlnaCastRepository](../../lib/features/playback/data/dlna_cast_repository.dart) 自行实现最小 SSDP／SOAP 适配：12 秒搜索窗口、最多 64 个描述地址及设备；HTTP 每次 5 秒、连接 3 秒、响应 256 KiB；设备描述错误不会阻止其他设备。按 UDN 去重，支持嵌套设备、相对 controlURL、URLBase 和带命名空间 XML。
- SSDP 描述地址必须与回复源 IP 一致，controlURL／URLBase 必须留在该主机；禁止跳转转发。设备 HTTP 通道不携带账号 header、Cookie、App token，不改变系统 TLS 校验。DIDL-Lite 和 SOAP 分层转义，保留带签名媒体地址与中文标题。
- 只增加直接依赖 `xml: 6.6.1`（MIT，原已作为传递依赖锁定），无新增原生播放器或 DLNA 插件。macOS Release 增加 UDP 应答所需的 network.server 沙盒权限和局域网用途说明，发布签名校验同步检查；Debug/Profile 原已有 server 权限。
- 平台能力集中在 [casting_support.dart](../../lib/core/platform/casting_support.dart)。Android 使用既有 INTERNET 权限，SSDP 接收单播回复，不加入多播组；实际网络策略、Windows 防火墙、macOS 局域网权限和设备兼容性须实测。

## 参考来源与许可

参考相邻 PiliPlus `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/pages/video/controller.dart::onCast`、`lib/http/video.dart::tvPlayUrl`、`lib/pages/dlna/view.dart`：借鉴“专用 TV 地址 → 局域网发现 → 设置媒体 → 播放”的协议和职责流程。PiliPlus 应用为 GPLv3；本次未复制其页面、GetX／SmartDialog 实现或资源，也未新增其 `dlna_dart` 依赖，按本项目分层重新实现。

设备动作按 [UPnP AVTransport](https://openconnectivity.org/wp-content/uploads/2015/11/UPnP-av-AVTransport-Service.pdf) 的公开协议组织；[Sony AVTransport 示例](https://github.com/sonydevworld/audio_control_api_examples/blob/master/DLNA/AVTransport/play_file.adoc) 用于核对动作结构。没有修改相邻仓库或 Pub 缓存。

## 验证

- `packages/bili_api/test/cast_client_test.dart`：UGC／PGC 身份与签名、游客、无 Web Cookie、非法／多段／DASH 地址、HTTP 错误及晚到账号响应。
- `test/features/playback/casting_controller_test.dart`：成功交接后的本地暂停、命令串行、设备切换屏障、失败不重放、源／账号／销毁取消、晚到 Play 隔离与容量限制。
- `test/features/playback/dlna_cast_repository_test.dart`：本机真实 UDP／HTTP 模拟渲染器的发现去重与搜索截止、XML 解析及地址限制、签名 URL／中文标题的 SOAP 转义、Fault 和进行中 HTTP 取消。此为受控协议回归，不代表真实电视兼容性。
- `test/features/playback/casting_dialog_test.dart`：项目浅／深色主题下窄屏选择、暂停／继续／停止，以及短窗口 2 倍文字下的滚动布局。

公开在线游客烟测：`BV17x411w7KC` 的真实 aid／cid 经 TV 接口取得地址成功，使用无 Cookie／Authorization／Referer 的独立 HTTP 客户端请求 0–1023 字节范围返回 206；ffprobe 在有限探测预算内返回成功，并确认同时包含 video、audio 两种流。未打印或落盘签名地址。此结果只覆盖该公开视频和当前游客请求，账号／会员内容与 PGC 在线鉴权仍待验证。

Windows Debug 构建通过，启动普通入口后 DTD 热重载成功，未捕获运行时错误。首轮 Windows 构建因共享构建目录的 MSVC PDB 写入冲突失败，重试时为本次命令设置 `/FS` 后成功，没有修改项目编译选项。

独立工作树基于 `d89be75`，只应用本次投屏改动：`tool/check.ps1 -EnforceLockfile` 的五份锁文件复现、格式、静态分析和打包边界检查通过。首次进入测试时既有 media-kit 归档下载遇到 TLS 握手失败；复用按固定 SHA-256 校验的本地归档后，仍经原构建钩子再次校验和解包，补跑 `-SkipPub -Stage RootTests`、`-SkipPub -Stage PackageTests` 均通过。根应用 3801 项通过、13 项条件跳过；bili_api 505、bili_player 105、bili_danmaku 145、bili_mux 5 项通过，mux 原生 10 项因未配置 `BILI_MUX_LIBRARY` 跳过，不能视为原生覆盖。

共享工作区检查期间存在同期历史搜索 `loadHistory(keyword)` 接口与测试桩暂不同步的问题，未将其文件纳入本次修改或提交；播放模块及相关历史回归另有 952 项定向测试通过。提交内容单独整理，保留同期修改。

未连接真实电视，电视实际音画／编码／拖动遥控、设备网络隔离、Android 和 macOS 构建／真机仍未验收；不将协议模拟器通过记为实机投屏通过。
