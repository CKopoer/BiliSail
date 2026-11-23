# BBZQ 能力对照与移植记录

日期：2026-11-23。状态：已完成播放增强、匿名番剧解析及网络声明适配，并完成离线验证。

上游参照：[HSSkyBoy/BBZQ](https://github.com/HSSkyBoy/BBZQ) `cacde6e`（木兰公共许可证第 2 版），
本仓库基线 `5d4d0d9`。BBZQ 是官方 Android 客户端的 Xposed 模组，BiliSail 是独立 Flutter 客户端；
本次移植的是请求与选流策略，不是把 Kotlin/Xposed hook 放进 Flutter 进程。

## 本次接入

### 解锁最高码率

- `AppSettings.unlockHighestBitrate` 默认关闭，可在「设置 → 播放」开启，下次取流生效。
- 普通视频与 PGC 都请求 `qn=127`、`fnval=4048`、`fourk=1`。
- 开启后按 BBZQ 顺序选档：
  `127 > 126 > 125 > 120 > 112 > 116 > 80 > 74 > 64 > 32 > 16`。
  同一档位仍先遵循编码偏好，再取更高带宽；默认关闭时保留原有数字档位排序与用户清晰度上限。
- 该功能只能请求并选择服务端实际返回的轨道，不能把账号无权取得的轨道变成可播放轨道。

实现入口：
`playback_enhancement_policy.dart`、`api_client.dart`、`api_playback_repository.dart`、
`api_content_playback_repository.dart`、`dash_media_selection.dart`。

### 无限试用会员画质与界面同步

- `unlimitedQualityTrial` 默认关闭。普通视频取流显式加入
  `is_need_trial=1`、`is_need_view_info=1`、`try_look=1`。
- `qualityTrialUiSync` 保留 BBZQ 的独立配置，并通过 `TrialUiSyncReport` 描述真实映射：
  本地画质菜单只展示接口实际返回的 DASH 轨道，不制造官方宿主的 `needVip`／`vipFree` 字段。
- **预览保护不变**：`is_preview=true` 仍按预览处理，不能冒充完整视频；悬停预览的既有例外不受影响。
- 是否返回会员画质、完整时长或高码率由线上接口决定。本实现不是官方客户端 Protobuf hook，也不保证线上服务接受这些 Web 参数。

### 避开 HDR／杜比视界

- `avoidHdrDolby` 默认关闭。开启后按档位与编码同时剔除 HDR／杜比视界轨道，选择最高 SDR 档位。
- `hdrVideoQualities` 为 125、126、129；8K（127）不因该开关被误删。
- HDR-only 片源回退原始轨道，保留编码优先顺序，避免无片可播或误选杜比编码。
- `PlaybackMedia.isHdr` 与选流器共用同一判据。

### 番剧地区解锁：自建解析服务器

「设置 → 播放 → 番剧地区解锁」支持：

- 港澳、台湾、东南亚、中国大陆四个独立 HTTP/HTTPS 服务器地址；空地址停用该地区。
- 默认地区优先；未指定时按 `hk → tw → sea → cn`，东南亚向服务器发送 `area=th`。
- 官方详情或播放出现地区、权限或未找到拒绝时才回退；正常请求、取消及其他错误不触发。
- 播放路径：东南亚为 `web → intl → app`，其他地区为 `app → web`；
  详情路径：东南亚为 `app → web → intl`，其他地区为 `app → web`。
- 详情与播放共用动态 `PgcClient` 配置，设置保存后下一次请求生效。番剧下载、投屏仍走原有独立链路。
- 支持 `result`／`data`、`video_info`、DASH 普通／FLAC／Dolby 音频、备用 URL 和官方片头片尾信息。
- 每次解析具有总 deadline、取消传播、播放 2 MiB／详情 4 MiB 响应上限；全部候选失败时保留官方原错误。

隐私边界：解析器只发送匿名固定请求头，不复制 Cookie、Authorization，也不发送 `access_key`。
自建服务器会看到番剧/剧集标识及客户端 IP。本次未接入搜索合并、字幕补源或向解析器共享账号的选项。

### 网络与连接优化

- 原有 `MediaCdnPreference` 自定义线路和测速继续用于视频、影视及悬停预览。
- 测速弹窗新增「用最快线路」：测速进行中或没有成功样本时禁用；完成或停止后可应用当前已测最快线路。
  测速本身仍不静默修改设置。
- `fakeWifi` 默认关闭。开启后，`AppRequestDevice.load(fakeWifi: true)` 只把 App 身份中的
  `AppDeviceInfo.network` 设为 `wifi`，使 App User-Agent 使用 `network/2`；原生读取失败时也保持该声明。
  新直播间的网络默认画质同时按 Wi-Fi 处理；用户显式选择的直播清晰度优先。
- 它不改变真实 Android 网络、NetworkCapabilities、计费状态或系统设置，也不影响 Web WBI 取流。
  BBZQ 对官方宿主 Android API 的全局 hook 在独立 Flutter 客户端中没有直接等价物。
- Wi-Fi／蜂窝分别保存 CDN 优先表本次未添加；不为此引入额外连接插件。

## 已有能力对照

| BBZQ 能力 | BiliSail 状态 |
| --- | --- |
| 播放器三倍速、自定义倍速 | 已有 3.0x 及 0.25–5.0x 配置 |
| 自定义长按倍速／锁定 | 已有触摸长按临时倍速及上滑锁定 |
| 实时播放统计 | 已有码率、编码、丢帧等实时信息 |
| 后台播放、画中画、投屏 | 沿用现有平台能力与开关 |
| 空降助手 | 已有 SponsorBlock 配置 |
| 视频页广告／互动挂件净化 | 独立客户端不渲染对应官方宿主组件 |
| 自定义半屏／全屏默认画质 | 仍使用统一默认清晰度，避免全屏切换触发完整重取流 |

## 设置存储

新增播放增强、Wi-Fi 和解析器字段统一写入 `preferences.v1`，快照版本由 56 升至 **57**；
SQLite schema 保持 **3**。旧快照缺字段时使用安全默认值；URL 会去除首尾空白及末尾斜杠，
非法 URL、内嵌用户信息、query 或 fragment 不会进入解析器。

## 验证

固定工具链：Flutter **3.50.1** / Dart **3.14.0**。

已执行：

- 根应用 `flutter analyze --no-pub`：通过。
- 播放策略、UGC/PGC 仓储、DASH/HDR、设置持久化、设置界面、CDN、Android 设备身份定向测试：通过。
- 根应用完整 `flutter test --no-pub`：**6002 项通过，6 项跳过**。
- `bili_api` 完整 `dart test`：**1093 项通过**，覆盖地区顺序、匿名请求、路径回退、响应上限、取消、原错误保留及动态配置。
- `git diff --check` 与相关 Dart 格式检查。

未验证：真实账号与线上 Bilibili 接口是否接受试用参数、真实自建解析服务器兼容性、Android/iOS/桌面实机播放、
HDR 色彩与性能、运营商网络行为。没有生成安装包，也没有把离线测试表述为线上功能验收。
