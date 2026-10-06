# 视频 CDN 偏好与悬停故障恢复

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
