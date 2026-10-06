# 视频卡悬停加载延迟修复

日期：2026-10-06。按用户要求用 Chrome 检查 `https://www.bilibili.com/` 官方首页卡片，再对照本项目加载链路。仅检查协议和行为，自行实现；未复制网页源码、资源或引入新依赖。

## 网页观察

- 官方 [首页脚本](https://s1.hdslb.com/bfs/static/shanks/laputa-home/assets/index-12fc55c2.js) 的 inline player 明确配置 `noAudioStream`、静音及禁止播放量/时长上报。实际网络只有视频 `.m4s`，没有音频资源读取。静音并不等于下载并解码音频后将音量置零。
- 请求仍为 `/x/player/wbi/playurl`，`qn=32`、`fnval=2000`、`fnver=0`、`fourk=1`、`from_client=BROWSER`、`need_fragment=false` 与 WBI 签名。不是独立预览流接口。卡片携带 cid，不需要先请求视频详情。
- 首页支持通过 `requestIdleCallback` 调用播放器 `prefetch`。后续另一张卡的观察中，开始播放前没有新 playurl/媒体请求；这与预取/缓存路径一致，不能仅凭一次请求列表推断每张卡都预取完成。
- 样本 `BV1rhHv6sEVm` 从记录起点约 877 毫秒触发 `playing`，playurl 请求约 81 毫秒；首个视频资源读取来自 `upos-sz-mirrorcoso1.bilivideo.com`（约 52 毫秒），随后也使用 `mcdn.bilivideo.cn:8082` 的 PCDN 请求。另一次卡片观察约 1023 毫秒进入播放。
- 网页播放器 [core](https://s1.hdslb.com/bfs/static/player/main/core.b237bb82.js) 管理 DASH 分段、服务端备用 URL 和 CDN/PCDN loader。以上可以确认网页具备不同的媒体加载策略，但不足以证明它会逐一测速并总是选择最快 CDN。浏览器本轮为既有登录会话，本项目原生验证为游客；不把两个样本当作严格性能基准。

只保存脱敏参数、host、时序；未保存 Cookie、WBI 签名值或媒体 URL 的查询串。

## 确认的实现问题和修复

原链路为 300 毫秒悬停等待 → 首 P 详情 → 普通播放源 → 视频轨准备 → 外部音频加载/准备 → 播放及音频解码确认。卡片在整个 open 完成后才显示 surface，音频 CDN 慢或失败也会阻止完全静音的预览。自动 CDN 原来直接沿用服务端首地址，可能优先 PCDN；首地址卡住要等外层 8 秒，原生内部仍有 35 秒预算，取消还需等待串行命令释放。

现在：

1. [预览 Repository](../../lib/features/playback/data/api_video_preview_repository.dart) 独立使用网页 profile，保留纯 Dart [端口](../../lib/features/playback/domain/video_preview_repository.dart)、WBI、账号 epoch 与取消。预览不解析/选择音频；普通点播/影视继续要求 DASH 音视频成对可用。
2. 列表返回的有效正整数 cid 经 API 模型、领域卡片传给控制器，直接解析播放源；缺失或非法 cid 沿用首 P 详情读取及有界 LRU。不从 aid/bvid 猜测 cid，不对整页自动发起播放请求。
3. [DashVideoSource](../../packages/bili_player/lib/src/player_contract.dart) 显式表达不取伴随音频的静音预览；与缺失音频的普通 `DashPairSource` 区分。原生适配器禁用音轨，确认视频解码，不等待音频；video-only 打开要求 volume=0，普通缺音频继续报错。
4. 悬停延迟降至 200 毫秒。预览的自动线路优先本次响应内的常规 `upos-*.bilivideo.com`，保留 PCDN 作为后备；手选腾讯/华为/阿里/百度仍按对应偏好排序。不改 host/path/query/port，不新增测速、DNS、媒体代理或 CDN 探测下载。
5. 外层与原生启动预算统一为每地址 3 秒，最多尝试三个不同的服务端视频 URL，旧引擎确认释放后才创建下一引擎。取消、切卡、后台、隐藏、账号变化与 generation 隔离继续生效。未确认 dispose 时仍阻止重叠引擎。普通播放维持默认 35 秒原生打开预算。

预览媒体 URL 每次悬停重新解析、只存内存；本轮没有为整页建立媒体预取缓存。缺失 cid 的接口仍需要详情请求，弱网或全部线路不可达仍会保留封面。

## 验证

- Windows Debug 原生游客样本 `BV1rhHv6sEVm`：第一次悬停约 896 毫秒、标题再次悬停约 871 毫秒达到“视频已解码、位置前进、预览已挂载”。视频 852×480、音量 0、无解码音频；静止时位置继续前进，移开停止并释放，最大未释放引擎数 1。日志 `build/hover-preview-fixed-windows.log`，截图 `build/validation/video-card-hover-windows.png`。时间包含 200 毫秒悬停等待及测试的 100 毫秒轮询误差，属于功能观测，不是 profile/release 性能测量。
- 修复前相同样本在 Windows 可播，视频使用 PCDN，另外加载音频；本轮没有复现用户所有随机失败。因此确认并移除了上述额外等待/失败依赖，不把个别 CDN 或某条 native 日志认作所有故障的唯一原因。
- 受控首地址 403：约 3 秒结束首地址等待、释放后打开真实备用，约 3996 毫秒出预览；第二次悬停约 883 毫秒。确认一次 403 请求、备用成功、最大未释放引擎数 1、全部释放，日志 `build/hover-preview-fallback-windows.log`。这验证故障恢复，不代表普通预览必须等待 4 秒。
- 回归覆盖 browser 参数/WBI、预览无需音频及普通缺音频拒绝、有效 cid/非法回退、常规/手选 CDN 和完整 URL 保留、备用次数上限、预算传递、取消/迟到完成与串行释放。
- `tool/check.ps1 -SkipPub` 全部通过：根应用 848、API 包 267、播放器包 17、弹幕包 32，共 1164 项；四处格式与分析通过。日志 `build/hover-preview-check-verified.log`。文档相对链接和 `git diff --check` 通过。
- Windows 正常 `lib/main.dart` 入口 Release 构建通过，完整 bundle 为 `artifacts/bilisail-hover-preview-windows-x64`，包含 EXE、DLL、data 和原生许可。主输出目录的标准构建被运行中程序占用的 WebView2Loader.dll 阻止；改用 Flutter `--config-only` 后的独立 CMake build/install 目录，复用既有固定版本原生依赖并由插件校验 archive hash，没有停止用户程序。日志 `build/hover-preview-release-isolated-config-final.log`、`build/hover-preview-release-isolated.log`。构建通过不等同于 Release 悬停性能或全部窗口交互验收。
- Android/macOS 原生、所有网络环境、登录状态下项目实播及 Release 启动性能未验证。

```powershell
flutter test integration_test/windows_video_card_hover_test.dart -d windows --no-pub --dart-define=BILI_ONLINE_SMOKE=true --dart-define=BILI_PREVIEW_BVID=BV1rhHv6sEVm
flutter test integration_test/windows_video_card_hover_test.dart -d windows --no-pub --dart-define=BILI_ONLINE_SMOKE=true --dart-define=BILI_PREVIEW_BVID=BV1rhHv6sEVm --dart-define=BILI_PREVIEW_DENIED_PRIMARY=true
```
