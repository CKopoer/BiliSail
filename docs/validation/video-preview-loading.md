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

## 静止窗口初始化阻塞复查

用户随后反馈打开应用后仍经常没有预览。本轮读取本机运行日志，看到多次 `openStarted` 之后没有 `openReady`，以及约 3 秒的 opening 超时；这些记录没有提供足够证据将原因归为某个 CDN。继续检查锁定版本 `media_kit 1.2.6` / `media_kit_video 2.0.1` 的初始化和释放链路，确认了一个与网络无关的阻塞：

1. 预览先完成接口请求，再创建 `VideoController`；此时封面缩放动画可能已经结束，窗口停止请求新帧。
2. 插件构造函数通过 `addPostFrameCallback` 等待帧结束才创建视频输出。这种回调[不会主动请求下一帧](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addPostFrameCallback.html)。
3. `Player.open` 等待视频输出初始化；卡片又只在 `open` 成功返回后才挂载 `VideoSurface`，所以不会由挂载 surface 请求那一帧。
4. 超时后的原生 dispose 同样等待初始化完成。旧引擎释放不完，会阻止后面的预览和备用地址；移动鼠标或其他界面更新偶尔提供一帧，又可能让链路继续，因此看起来是随机失败。

**修复**：[播放器适配器](../../packages/bili_player/lib/src/media_kit_engine.dart) 在创建 `VideoController` 后调用 `WidgetsBinding.instance.ensureVisualUpdate()`，保证初始化回调有帧可执行。仍在打开及视频解码确认后显示预览，保持取消、串行释放和最多三个 URL 的边界；没有调整 CDN 顺序或增加超时。该处理位于通用播放器适配器，其他没有预先挂载 surface 的原生打开同样受益。

**复现及回归**：[独立原生探针](../../tool/validation/video_preview_idle_probe.dart) 使用普通 `WidgetsFlutterBinding`，静止窗口打开本地视频，两次都不挂 surface、不移动鼠标、不运行动画，也不调用 `tester.pump`。此前悬停集成测试的 100 毫秒轮询会主动供给帧，无法验证这个边界。

- 修复前两次都在 3 秒进入 failed，但截至 5024 / 5001 毫秒，open Future 仍因释放等待而未返回，视频没有解码。记录失败后才额外请求一帧，原生视频输出初始化及清理随即继续。日志 `build/hover-preview-idle-before.log`、结果 `build/validation/video-preview-idle-before.json`。
- 修复后相同探针两次都完成打开及视频解码，约 536 / 368 毫秒进入 playing，并完成释放。日志 `build/hover-preview-idle-after.log`、结果 `build/validation/video-preview-idle.json`。这是 Windows Debug 本地文件功能观测，不能作为在线 CDN 或 Release 性能指标。
- [运行脚本](../../tool/test-video-preview-idle.ps1) 同时校验探针生成的报告，防止 `flutter run` 在子进程失败退出时仍返回成功。探针不访问账号、不执行历史上报或其他账户写操作。
- 本轮在线 Windows 悬停样本 `BV1rhHv6sEVm` 再次通过：首次 / 再次悬停约 890 / 825 毫秒，视频 852×480、无解码音频、位置持续前进，移开全部释放，最多一个未释放引擎。日志 `build/hover-preview-idle-online.log`。这项集成测试主动 pump，因此仅验证在线源及卡片行为；静止窗口初始化由上述独立探针验证。
- `tool/check.ps1 -SkipPub` 全部通过：根应用 864、API 包 269、播放器包 17、弹幕包 32，共 1182 项；格式与分析通过。日志 `build/hover-preview-idle-check.log`。这是本轮实际统计，前面的 1164 项为首次加载策略修复时的记录。
- Windows 正常 `lib/main.dart` 入口 Release 标准构建通过，完整 bundle 为 `artifacts/bilisail-hover-idle-fix-windows-x64`，日志 `build/hover-preview-idle-release.log`。Android/macOS 本轮原生未测，未做 Release 在线性能基准。
- 补做普通播放 Windows 原生套件发现全屏用例的旧弹幕准备方式与今天的独立动画时钟不符；基线同样失败。修正测试准备后报告 8 项全部通过（公网 UGC 分支未启用），包含分轨、seek／释放和全屏往返；弹幕运行代码未改。日志 `build/hover-preview-idle-playback-corrected.log`，原因和验证见 [全屏用例复查](danmaku-fullscreen.md#独立动画时钟后的原生用例复查)。

```powershell
./tool/test-video-preview-idle.ps1
```

该复现确认了静止窗口下的初始化及释放阻塞；接口失败、媒体地址失效或所有线路不可达仍可能导致没有预览，不能由本地文件测试推断这些网络情况全部消失。

## 首帧之前的短暂黑屏

用户确认上面的初始化修复后预览可以稳定加载，但部分卡片在切换前短暂变黑。锁定版本的播放器中，解码器 `videoParams` 与原生输出纹理走不同的通知链路；取得视频宽高不表示输出纹理已准备好。原先 `DashVideoSource.open` 只等待解码尺寸，返回后卡片立即挂载 `VideoSurface`，此时插件可能仍在显示默认黑色背景／初始化纹理。输出先完成时不会看到黑闪，解码元数据先返回时就会露出这个空档。

**修复**：静音预览在视频解码后继续等待插件的 [waitUntilFirstFrameRendered](https://github.com/media-kit/media-kit/blob/main/media_kit_video/lib/src/video_controller/video_controller.dart) 信号，再允许 open 返回、卡片显示预览；核对的实际依赖为 `media_kit_video 2.0.1`。卡片保留原封面直到这一步完成。首帧等待使用同一 3 秒总预算，generation 变化立即中断，并释放监听；初始化错误、超时继续使用已有的释放和备用地址路径。没有添加固定等待时长或改变弹幕代码。

**证据与回归**：

- [独立原生探针](../../tool/validation/video_preview_idle_probe.dart) 现在在 open Future 返回的当刻记录 `outputAtOpen`，由当前 controller 的纹理 ID 和非零输出尺寸读取，不用解码尺寸推断输出准备。修复前本地视频两次均 `opened=true`、`decoded=true`，但 `outputAtOpen=false`，复现了“已打开仍没有输出”的显示空档。结果 `build/validation/video-preview-frame-before.json`，日志 `build/hover-preview-frame-before.log`。
- 修复后相同静止窗口、本地视频两次均在 open 返回时已具备输出；约 513 / 375 毫秒进入 playing。结果 `build/validation/video-preview-idle.json`，日志 `build/hover-preview-frame-after.log`。这是 Windows Debug 功能观测，不是性能基准，也不按画面颜色过滤视频的真实内容。
- 播放器回归覆盖首帧信号未到／已经到达、移开后取消及迟到渲染、首帧超时和初始化错误；卡片测试确认等待期间不挂载视频层，首帧就绪后才切换。
- 在线 Windows 游客样本 `BV1rhHv6sEVm` 通过，在打开返回时断言视频输出已就绪；首次 / 再次悬停约 1111 / 716 毫秒，无音频、持续播放、移开释放，最大未释放引擎数 1。受控首地址 403 也通过，首地址释放后备用出画面约 3877 毫秒，再次悬停约 821 毫秒；首帧条件没有阻止备用恢复。日志 `build/hover-preview-frame-online.log`、`build/hover-preview-frame-fallback.log`。以上为 Debug 功能观测，不作前后性能比较。
- `tool/check.ps1 -SkipPub` 最终通过：根应用 865、API 包 269、播放器包 22、弹幕包 32，共 1188 项；格式和分析通过。日志 `build/hover-preview-frame-check-final.log`。
- Windows 正常 `lib/main.dart` 入口 Release 构建通过，完整 bundle 为 `artifacts/bilisail-hover-first-frame-windows-x64`，包含程序、原生 DLL、数据和许可；日志 `build/hover-preview-frame-release.log`。Android/macOS 本轮原生未验证，未做 Release 逐帧画面或性能验收。

## 15 秒向前预读窗口

本节保留最初 15 秒实现和当时的验证记录；当前窗口已调整为 5 秒，见下一节。

日期：2026-10-07。按用户要求，预览只维持当前位置之后 15 秒媒体时间的预读窗口，不再沿用普通播放的默认大窗口。视频仍从真实完整视频轨读取，窗口随播放推进继续补充；不是只播前 15 秒。鼠标移开沿用取消、停止和释放路径。

- [预览编排](../../lib/features/video/application/video_card_preview_playback.dart) 每次打开（含 CDN 备用）显式传入 `OpenOptions.maxBufferAhead = Duration(seconds: 15)`。普通点播／影视／直播不传该选项，继续使用各自后端默认策略；每次打开创建新的 native Player，不将预览配置带入下一源。
- [原生适配器](../../packages/bili_player/lib/src/media_kit_engine.dart) 在初始化完成、打开 URL 之前设置 `cache-secs=15`、`demuxer-readahead-secs=15`，避免 mpv 取两个窗口中的较大值；同时设置 `cache-on-disk=no`，预览改用有界内存缓存，不累积 append-only 临时文件。设置与读取确认使用同一个打开预算，旧 generation 中止；锁定 SDK 不传播底层设置失败，因此读取确认失败会进入既有错误／释放路径，不静默回退后端默认大窗口。
- 这里限制的是原生解复用的媒体时间窗口，不能作为精确网络下载字节配额。解码队列、帧时间戳和网络 I/O 缓冲有少量边界误差，不能通过夹紧界面 `buffered` 数值伪装成严格零超出。参数语义核对了锁定 Windows libmpv `652a1dd` 的 [选项说明](https://github.com/mpv-player/mpv/blob/652a1dd/DOCS/man/options.rst) 与本地 `media_kit 1.2.6` 源码。

验证使用 FFmpeg 合成的 [60 秒无音轨测试图](../../test/fixtures/media/README.md)，不访问真实账号或公网媒体。[Windows 原生用例](../../integration_test/windows_preview_buffer_test.dart) 通过本地 HTTP／Range 打开，检查首帧及无音频、暂停时窗口、播放推进后补充、seek 后窗口、普通打开恢复默认缓存。Windows Debug 两次通过：初始向前 14.875 秒，播放推进后约 15.04～15.17 秒，seek 后约 15.13～15.17 秒；相同适配器未指定选项重开后缓存到 59.875 秒。测试允许 500 毫秒的原生帧／解码边界误差，不是 Release 性能或流量基准。日志 `build/preview-buffer-native.log`。

```powershell
$env:BILI_TEST_MEDIA_DIR = (Resolve-Path test/fixtures/media).Path
flutter test integration_test/windows_preview_buffer_test.dart -d windows --no-pub
```

- 预览编排 12 项、播放器包 22 项、API 包 285 项、弹幕包 32 项测试通过。播放器包和受影响的预览／原生用例／静止探针文件分析通过；本轮改动格式及 `git diff --check` 通过。
- 静止窗口首帧探针 `tool/test-video-preview-idle.ps1` 通过；两次均在 3 秒打开预算内完成视频解码及原生输出，记录约 526／375 毫秒，没有挂载 surface 或外部 pump 提供帧。新增缓存配置没有恢复先前初始化死等。日志 `build/preview-buffer-idle.log`，结果 `build/validation/video-preview-idle.json`；这是本地 Windows Debug 功能观测。
- Windows 正常 `lib/main.dart` 入口 Release 构建通过，日志 `build/preview-buffer-release.log`。这是该次构建时的工作区快照，不代表之后其他并行修改的持续验收。
- `tool/check.ps1 -SkipPub` 已执行，但被同时进行的快捷键重构文件格式检查阻止，最终日志 `build/preview-buffer-check-final.log` 指向 `shortcut_settings.dart`。单独根分析、根全量测试和普通播放原生套件也受当时快捷键／页面编译错误影响：根测试为 852 项通过、7 个文件加载失败；原生普通播放未能启动，不能宣称全量回归通过。日志分别为 `build/preview-buffer-analyze.log`、`build/preview-buffer-root-tests.log`、`build/preview-buffer-windows-media.log`；未改动这些并行工作文件。

Android/macOS 本轮未做原生验证，公网 CDN 的实际接收字节数未测；本地 HTTP 缓冲窗口验证不代表这两项已完成。

## 5 秒向前预读窗口

日期：2026-10-07。按用户后续要求，悬停预览的 `OpenOptions.maxBufferAhead` 由 15 秒改为 5 秒；每次打开及 CDN 备用都使用这个值。原生适配器继续在加载 URL 前设置 `cache-secs` 和 `demuxer-readahead-secs`，使用内存缓存；普通播放仍保持后端默认策略。窗口随当前位置推进，不将总播放时长截断到 5 秒。

预览编排断言、Windows HTTP／Range 用例和静止窗口首帧探针同步改为 5 秒。原生用例检查初始窗口、播放推进、seek 与普通打开恢复默认缓存，保留 500 毫秒的帧／解码边界误差；不将媒体时间窗口解释为严格下载字节配额。

- Windows 原生用例通过：初始向前 4.916 秒，播放推进和 seek 后均为 5.166 秒；普通打开仍缓存至 59.875 秒。约 0.17 秒超出来自原生帧／解码边界，属于媒体时间窗口验证，不是流量或性能基准。日志 `build/preview-buffer-5s-native.log`。
- 本轮 `tool/check.ps1 -SkipPub` 全部通过：根应用 1110、API 包 291、播放器包 22、弹幕包 32，共 1455 项测试；根应用与三个包的格式、分析全部通过。日志 `build/preview-buffer-5s-check.log`；上节并行快捷键修改导致的全量检查阻断是之前快照的记录，不是本轮状态。
- Windows 正常 `lib/main.dart` 入口 Release 构建通过，日志 `build/preview-buffer-5s-release.log`。5 秒配置的静止窗口首帧探针两次均完成视频解码和原生输出，约 530／380 毫秒，均在 3 秒打开预算内；日志 `build/preview-buffer-5s-idle.log`。Android/macOS 本轮原生未测，公网实际下载字节数未测。
