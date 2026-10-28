# 视频 CDN 设置、测速与悬停故障恢复

## 具体节点与展开测速（2026-10-28）

按用户要求，只读参考 PiliPlus 提交 `936072449e82e3d90c28c728c0087bf5136fa441` 的 `lib/models/common/video/cdn_type.dart`、`lib/pages/setting/widgets/select_dialog.dart`、`lib/utils/video_utils.dart` 和 `lib/pages/setting/models/video_settings.dart`。参考节点目录、选择弹窗与读取视频片段测速的行为，独立实现本项目的领域模型、仓储、控制器和 Material 弹窗，没有复制 GPLv3 应用源码或增加依赖。

设置 → 播放 → CDN 线路现在折叠为一行，显示已保存的选择。点击展开弹窗后自动测速，逐项显示 MiB/s 与实际 host，或超时、HTTP 错误、不支持等结果；提供停止、重新测速与关闭。选择保存成功后关闭，失败留在弹窗并显示错误，继续保留原设置。测速不自动修改偏好。全部选项可滚动浏览，窄屏和放大文字沿用同一交互。

- 保留原来的自动、常规 CDN 及腾讯／华为／阿里／百度四种运营商偏好及序列化名称；新增 19 个具体节点：ali/alib/alio1、cos/cosb/coso1、hw/hwb/hwo1/08c/08h/08ct、tf_hw/tf_tx、Akamai、aliov/cosov/hwov 与香港 bcache。仍通过 `preferences.v1.mediaCdn` 保存，既有快照继续读取，缺失／非法值默认自动；没有新增存储字段或 SQLite migration。
- 自动／运营商偏好继续仅排序服务端返回地址。明确选择具体节点时，优先使用已返回的同 host 地址；否则仅从 HTTP(S)、无用户信息、无自定义端口、已知 UPOS／Akamai host 的 `/upgcxcode/` 地址构造该镜像，保留原 scheme、path 与 query。不会将 PCDN `/v1/resource` 或任意外部地址机械替换。原始地址保持为备用，恢复选择不重新插入已失败的首地址。视频、影视、悬停预览与下载共用此规则，直播继续独立。
- 测速复用既有 Web/WBI 视频预览 profile（`api.bilibili.com` GET `/x/player/wbi/playurl`、`qn=32`），公开样本 `BV1fK4y1t7hj` / `196018899`。只解析 DASH 视频轨及其备用，不创建播放器、不上报观看进度、不执行账号写操作。获取样本使用现有读请求的重试／25 秒 deadline；测速地址 GET 不重试、无分页。
- 媒体请求使用独立 HttpClient，保留系统 TLS 验证，仅带 Referer、User-Agent、Range 和 identity encoding，不带 Cookie/token。每个不同地址串行读取最多 1 MiB，总 deadline 5 秒，覆盖 DNS、连接、响应头和停滞正文；最多三次重定向，拒绝 HTTPS 降级，HTML／JSON 等错误正文不算视频测速。相同地址复用本轮结果，失败继续下一项；不足 1 MiB 的有效片段按实际字节计算，deadline 前收到部分数据时按整个耗时计算速度。
- 关闭弹窗、停止／重测、控制器释放、账号 session epoch 变化都中断旧请求，迟到结果不能覆盖新一轮；样本和带签名 URL 仅留在本轮内存，不进入设置、数据库或日志。UI/日志只显示 host、速率与脱敏错误。

本轮验证：

- 自动测试覆盖全部节点的域名替换边界、原 URL 保留与不可重复回退；DASH 双轨、测速串行与去重、关闭／重测／销毁、账号变化、Range 忽略／损坏、HTTP 403／HTML、空响应、重定向上限、响应头／正文停滞，以及展开、停止／重试、窄屏大字体、保存失败与全部偏好落盘。
- Windows 主机的公开只读烟测实际探测 19 个不同地址，其中 14 个返回有效片段；08c、08h、hwov、香港 bcache 连接失败，Akamai 返回 403。日志 `build/cdn-online-smoke.log` 只记录 host、读入字节、速率或脱敏错误。此为当次样本／网络环境的可达性检查，短片段结果不代表持续吞吐或所有视频兼容，失败节点继续保留为可选并准确显示失败。
- 152 项定向测试全部通过，覆盖上述 CDN、设置存储／界面、预览及 DASH 双轨；任务范围静态分析无问题，文档相对链接与 `git diff --check` 通过。日志 `build/cdn-targeted-tests.log`、`build/cdn-analysis.log`。四包按根检查脚本单独运行测试，合计 696 项通过，10 项 mux 原生用例因未配置 `BILI_MUX_LIBRARY` 跳过，不能视为原生通过；日志 `build/cdn-package-check.log`。
- Windows 独立预览入口使用生产 CDN 控件、BiliTheme 和真实公开测速仓储，设置保存到内存，不接触个人账号／数据库。Debug 构建与热重载成功，实际检查了弹窗、滚动后的国内／海外节点及速度／HTTP 403／连接失败显示，保存 ali 后读取到正确设置摘要。FlutterDriver 的部分 tap 命令出现响应超时，保存后的状态与画面仍已变化；此工具层超时未作为产品操作完全通过的依据，完整交互断言以 widget 测试为准。独立预览已关闭，普通 `lib/main.dart` 入口的 Windows Debug 构建通过并已恢复，日志 `build/cdn-windows-debug-build.log`；未执行原生播放验收。
- `tool/check.ps1 -SkipPub` 本次全量检查受同期其他修改阻塞：静态分析报告 `playback_panel.dart:2` 多余 `dart:ui` import 和 `window_orientation_host_test.dart:123` 缺少语句块。另行根测试记录 `navigation_bar_mode_test.dart` 两项及 `dpi_adaptation_test.dart` 一项失败；在输出 3200 通过／13 跳过后，测试子进程已退出而 runner 结束阶段停滞超过两分钟，已终止本轮 runner 并继续四包测试，没有宣称根测试全量完成。日志 `build/cdn-full-check.log`、`build/cdn-root-check.log`；保留这些并发修改，没有为通过检查改动无关文件。
- Android/macOS 等其他平台实机、持续音视频播放、Release 性能及各地区网络尚未验收；本轮片段测速和 Windows 控件检查不代替这些验收。

## 初版记录（2026-10-06）

以下为初版历史记录；其中“不替换 host／不测速”仅描述当时实现，当前具体节点模式以上文为准。

日期：2026-10-06。用户反馈部分卡片无法预览，提供 `BV1HcHn6UEdF`，并要求增加 CDN 设置及支持自动调度。

**后续加载修复**：下文记录 CDN 设置初版及当时证据。正常点播/影视仍沿用这些线路偏好；现行悬停在自动模式优先接口常规 CDN，并改为无音轨、每地址内外统一 3 秒、最多三个地址。具体对照与验证见 [悬停加载延迟](video-preview-loading.md)，覆盖下文早期预览的音视频/8 秒/两次描述。

## 选项与范围

“设置 → 播放 → CDN 线路”提供自动、优先常规 CDN、优先腾讯云／华为云／阿里云／百度云。默认自动保留播放接口返回的顺序；优先常规 CDN 将返回的 `upos-*.bilivideo.com` 地址置于 PCDN 等其他地址前。运营商选项只优先匹配本次响应中已有的对应域名，没有对应地址时沿用其他可用地址。

不替换签名 URL 的 host、path、query、scheme 或 port，不硬编码 IP，不增加自定义 DNS、测速或网络代理。相同 URL 去重，其他地址的相对顺序保留。音频和视频分别排序，保留 DASH 分轨、请求头与正常播放的有界备用尝试。普通视频、影视与悬停预览在下次解析媒体源时读取已保存的偏好；直播保留自己的线路协议。

自动模式不固定某一家 CDN。B 站接口选择 URL 的域名，系统或代理解析该域名，由其 DNS／网络调度选取节点；DNS 不能替应用把一个失败的播放 URL 改成另一个 CDN 域名。DNS 负载均衡按指定 hostname 返回节点地址的机制可参见 [Cloudflare 官方说明](https://developers.cloudflare.com/load-balancing/understand-basics/proxy-modes/)，此处不推断 B 站具体调度策略或保证某个节点最快。

纯 Dart [MediaCdnPreference](../../lib/domain/media_cdn.dart) 与 URL 排序不引用 UI、平台或网络。组合根注入偏好读取端口，视频与影视 Repository 共用 [selectDashMedia](../../lib/features/playback/data/dash_media_selection.dart)。`preferences.v1` JSON 版本 13 → 14；缺失、未知或错误类型默认自动，旧设置保留，数据库 schema 保持 v2。

## 悬停修复与原因边界

- 原预览只打开第一对 CDN URL；正式播放已有备用尝试，因此首地址不可用会造成两者表现不同。预览现在最多尝试两次，使用响应中的不同备用地址，每次打开预算 8 秒，下一次创建引擎前等待上一引擎释放。原生播放器自身的普通播放预算不变。
- 原生 open 在 Future 抛错前可能先发出 failure 事件；准备阶段保留当前悬停以允许一次备用尝试，已就绪后的确认失败仍停止并释放。取消、切卡、账号变化和旧 generation 禁止继续重试，超时的迟到 open 不能恢复旧播放器。
- 后台或隐藏工作区会清空内部悬停状态，原来返回时没有恢复。现在恢复前台／工作区且卡片仍悬停时，重新延时加载；移开仍立即停止。
- stop 抛错但 dispose 成功时，不再永久禁止后续预览。dispose 未确认时继续禁止新引擎，避免重叠原生资源。

样本的游客 `qn=32` 请求正常返回 480P 视频及三档 AAC，视频中有腾讯／华为 CDN，最高带宽音频为百度 CDN。`qn=80` 游客请求同样可用；不根据请求清晰度推断已取得对应权限。修复前 Windows 连续两次实际悬停成功，未复现用户当时的失败；因此上述为已确认的实现缺口，不能断言样本那次失败必然来自某个 CDN。原生 `unsupportedProperty`／未知日志不是终止失败证据，未据此取消健康预览。

## 验证与复跑

- CDN 顺序／去重、完整 URL 保留、域名边界、缺少首选回退和不可变结果测试；旧快照兼容、全部选项存储／复制、设置页点击保存测试。
- 预览测试覆盖 failure 事件和 Future 配对、打开超时、迟到完成、备用等待中移开、串行释放、stop 失败后的恢复、dispose 不明时阻止新引擎，以及前台／工作区恢复时无需移动鼠标。
- Windows Debug 构建与真实样本通过。受控本地首地址返回 403，达到 8 秒预算后切换接口备用地址，成功解码 852×480 视频、双声道音频且音量 0；静止悬停进度前进超过 1 秒，移开释放、标题再次悬停成功。三次创建中最大未释放引擎数 1，全部释放；选择腾讯优先时，未返回腾讯音频仍保留可用百度音频，没有拼接域名。
- 原生证据：`build/video-card-hover-repro.log`（修复前自动模式样本）、`build/video-card-hover-fix-windows.log`（受控 403、腾讯优先、备用恢复）、`build/validation/video-card-hover-windows.png`（已检查真实画面）。只输出脱敏轨道／host／阶段信息，不保存签名查询串或凭据。
- `tool/check.ps1 -SkipPub` 全部通过：根应用 802、API 包 249、播放器包 16、弹幕包 32 项，共 1099 项；四处格式与分析通过。日志 `build/video-card-hover-cdn-check.log`；普通 `git diff --check` 通过。计数包含工作区其他同期功能，本轮针对性组合为 49 项。
- 正常入口 Windows Release 构建通过，完整目录另存至 `artifacts/bilisail-video-cdn-windows-x64`（EXE、DLL、data 一起使用），日志 `build/video-card-hover-cdn-release-final.log`。首次构建被运行中的 Release 锁住 WebView2Loader.dll；曾准备隔离源码快照，首次配置因新目录的原生下载未完成而中止。随后原占用进程已退出、用户运行安装的 MSIX 版本，在主工作区重建成功并单独导出完整产物；没有终止用户应用。Release 性能与持续播放尚未测量。
- Android/macOS 原生播放、影视 CDN 在线验证、Release 性能及所有网络环境仍未验证；本轮不承诺某个运营商更快。

```powershell
# 游客只读接口对比，无账号写入
cd packages/bili_api
dart run tool/video_card_preview_smoke.dart BV1HcHn6UEdF
cd ../..

# 正常样本；可选 BILI_PREVIEW_CDN=regular/tencent/huawei/alibaba/baidu
flutter test integration_test/windows_video_card_hover_test.dart -d windows --no-pub --dart-define=BILI_ONLINE_SMOKE=true --dart-define=BILI_PREVIEW_BVID=BV1HcHn6UEdF

# 受控首地址 403，再打开真实备用 DASH
flutter test integration_test/windows_video_card_hover_test.dart -d windows --no-pub --dart-define=BILI_ONLINE_SMOKE=true --dart-define=BILI_PREVIEW_BVID=BV1HcHn6UEdF --dart-define=BILI_PREVIEW_DENIED_PRIMARY=true --dart-define=BILI_PREVIEW_CDN=tencent
```
