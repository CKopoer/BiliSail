# 视频章节与悬停缩略图

日期：2026-10-05。已接入普通视频播放页，采用自适应分段进度条；Windows 游客样本 `BV1VEHn6TEKq` 已完成原生播放和真实图片验证。Android/macOS 尚未实机验证。

## 交互

- 章节起止时间决定轨道划分；已播放、已缓冲和未播放部分保留各自颜色，悬停片段略微增粗。无章节的视频使用连续轨道。
- 标题能放下时显示在片段上方，短片段隐藏常驻标题。右侧章节菜单始终提供完整标题和起点，可点击跳转。隐藏控制栏时的底部细进度也保留章节分隔。
- 鼠标悬停或触摸拖动显示该时间对应的预览帧、时间和章节名。卡片贴近指针，并在播放器左右边缘避让；小窗优先保留时间，空间不足时隐藏图片和章节名。图片不可用不影响时间提示与 seek。
- 拖动过程只更新本地预览，松开才提交一次 seek；点击、拖动松开及章节菜单跳转都保留目标进度，直到会话完成跳转后再交回确认时钟，失败则清除目标。悬停不 seek、不暂停，也不创建额外播放器。直播不显示点播时间轴。
- 换 P、换视频、播放源更新或停止会清除预览；隐藏控件、页面离开及全屏布局切换由 OverlayPortal 的组件生命周期移除悬浮层。

## 端点与边界

| Profile / 能力 | Host、方法、Path | 鉴权、签名、响应和读取规则 |
| --- | --- | --- |
| Web / 章节与字幕列表 | `api.bilibili.com` GET `/x/player/wbi/v2` | Web Cookie 可选、WBI；字符串 `aid`、`cid`；JSON `view_points` 与 `subtitle.subtitles`；无分页 |
| Web / 缩略图描述 | `api.bilibili.com` GET `/x/player/videoshot` | Web Cookie 可选、无签名；`bvid`、`cid`，不传 `index=1`；JSON `pvdata`、图片页、网格和单帧尺寸；无分页 |
| Public CDN / 缩略图时间索引 | 描述返回的 HTTPS `*.hdslb.com` 或 `*.bilibili.com` | 不携带 Cookie/Authorization；`pvdata` 二进制，每两个字节按大端 uint16 解析为秒；至多 40002 字节，不跟随重定向 |
| Public CDN / 图片 | 接口返回的 HTTPS `*.hdslb.com` 或 `*.bilibili.com` | 独立公开图片传输；Referer 为 Bilibili，不携带 Cookie/Authorization；至多 3 次重定向并重新检查目标 |

章节 API 使用现有只读网络／服务端故障的最多三次传输尝试。缩略图描述和 `pvdata` 每次交互各尝试一次，不在底层自动重放；两步共同遵守 `ApiRequests` 的取消、账号 epoch 和 25 秒总 deadline。协议包单独调用且未指定 deadline 时，两步共享默认 12 秒预算。缩略图描述和二进制均使用 `Mozilla/5.0` User-Agent 与 Bilibili Referer，其余 API 的 UA 和重试规则不变。

`PlaybackMetadataRepository` 为应用领域端口，`bili_api` 只提供协议模型和读取。章节与字幕合并为一次读取；任一可选组件格式错误被分类记录，不丢弃另一组件。章节最多 200 项，规范化乱序、越界、重叠，空白间隔不虚构标题。缩略图在首次移入进度条或开始拖动时请求，同一播放源只有一个在途读取。连续移动只改变预览位置，不再次请求。失败或空结果后，移出再移入、重新开始拖动可立即补试，不设置后台定时器、5/10 秒冷却或每源三次上限。成功获取后按源复用索引；失败保留时间／章节预览，不影响媒体。换源清除索引，旧源／旧账号响应不能改写新状态，账号 scope/epoch 已改变的会话也不能发起补试。

索引最多 20000 帧、图片最多 200 页、网格至多 20×20、单格尺寸至多 4096，二进制时间值至多 65535 秒。单格宽高为零表示未提供，应用仓储通过共享图片缓存读取第一页的原始编码尺寸，按网格推导有效尺寸；负数、越界、不整除或与已提供尺寸矛盾的数据仍拒绝。只移除 `[0,0,...]` 中多余的前导零，严格校验后续时间递增和网格容量。二分查找选取最近的前序帧，按页、行、列裁剪雪碧图，不使用播放器抓帧。图片复用现有容量受限缓存：编码图片单张 4 MiB、总量 64 MiB/512 项，解码缓存 64 MiB/256 项、长边至多 1280；大网格预览清晰度受该解码上限约束。

高频指针更新留在 `PlaybackTimelineBar` 的局部状态中；源级元数据交由会话管理。界面不解析 JSON、发网络请求或调用 media_kit。未添加新依赖或原生接口。

## 来源

调研了 [PiliPlus 分段进度条](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc/lib/common/widgets/progress_bar/segment_progress_bar.dart) 与 [播放器预览](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc/lib/plugin/pl_player/view/widgets.dart)，快照 `4ed5968f37af8b4aa7e0f13178cb8d8c2f86defc`，GPL-3.0-or-later。仅参考协议字段和交互职责，Dart/Flutter 实现与脱敏 fixture 独立编写；未复制源码、schema、图片或其他资源。采用自适应标题、跟随指针的预览及完整章节菜单，避免短片段文字缩到不可读。

## 验证

- 协议测试：WBI 和字符串 ID、合并读取、可选组件故障隔离、UA、索引哨兵、排序/容量/URL 验证及账号 epoch。
- 应用测试：章节重叠/间隔、跨页帧查找、换源/停止/账号切换的迟到响应、缩略图单飞、悬停不 seek、拖动只提交一次、章节菜单、边缘避让、320 像素/双倍文字、禁用与销毁。
- 真实游客读取：样本含 5 个章节，边界 `0–9、9–21、21–41、41–56、56–71` 秒；一张 10×10 雪碧图，单帧 480×270，9 个有效时间索引。样本没有字幕轨。
- Windows 原生在线测试确认音视频均已解码；悬停、重复移动及 320 像素布局不会改动已暂停位置或创建新源；多次悬停仅下载一张图片。截图位于 `build/validation/playback-timeline.png`（构建产物，不提交远程视频资源）。
- 同一原生在线测试通过全屏进入、重新悬停与 Esc 退出，播放器 generation 保持不变。既有 Windows 分轨/seek/生命周期/响应布局回归通过；HTTP 403 脱敏日志测试一次未完成并出现 Flutter 临时目录清理错误，独立重跑通过。
- 根应用全量测试日志记录 489 项通过，最终会话定向回归 47 项通过；`bili_api` 全量 156 项、`bili_player` 16 项、`bili_danmaku` 10 项通过。新增时间轴/裁剪测试和涉及的播放器文件格式检查通过，文档相对链接检查通过。
- 已执行 `tool/check.ps1`：严格脚本停在工作区账号/消息等其他文件的格式检查；随后独立完成根应用/三个包的测试。全项目最终静态分析仍报告其他模块的花括号 lint，章节相关文件无诊断，未重排无关改动。此记录不宣称完整检查脚本通过。
- `flutter build windows --release --no-pub` 成功，产物 `build/windows/x64/runner/Release/bili_lite.exe` 及配套目录；未做 release 性能测量。

重现指定视频验证：

```powershell
$env:BILI_TIMELINE_OUTPUT = (Join-Path (Get-Location) 'build/validation')
flutter test integration_test/windows_playback_timeline_test.dart -d windows --dart-define=BILI_ONLINE_SMOKE=true
Remove-Item Env:BILI_TIMELINE_OUTPUT
```

正常测试不联网，在线测试需显式启用；未做真实账号、Android/macOS 触摸/渲染以及 profile/release 性能验收。当前章节端口接入 UGC，影视仍沿用其字幕流程，直播不查询点播章节。

## 2026-10-09 索引失败后的补试

原先 `_storyboardRequested` 在请求前置为 true，网络/超时最终失败后仍不恢复，导致同一播放源后续悬停一直无法补取。现只对可恢复失败解除该标记，同时增加冷却和 3 次逻辑读取上限；开始补试时清除旧错误提示，成功后继续复用索引。图片下载与缓存、原生播放器均未修改。

新增 fake clock/repository 回归覆盖网络/超时后的恢复、5 秒/10 秒边界、在途单飞、成功复用、读取上限、空索引与不可重试错误、换源重置及旧补试失败隔离、账号 epoch 改变后的禁止补试。

本轮缩略图定向测试 13 项通过；`tool/check.ps1 -SkipPub` 完成根应用与四个独立包的格式、静态分析和测试，根应用 1550 项、`bili_api` 336 项、`bili_player` 32 项、`bili_danmaku` 65 项、`bili_mux` 2 项通过。`bili_mux` 另 7 项原生测试因未设置 `BILI_MUX_LIBRARY` 按条件跳过；签名/安装包/macOS 发布边界脚本也通过。日志为 `artifacts/storyboard-retry-check.log`，文档相对链接和 `git diff --check` 通过。此次未做真实 Bilibili 网络恢复、原生构建或三端实机验收。

## 2026-10-10 番剧缩略图零尺寸兼容

游客在线排查《名侦探柯南（中配）》`ep323085`（`BV1wi4y1b7rM`、`cid=184593713`）：`videoshot` 返回 HTTP 200／业务码 0、两张 10×10 网格图片和 186 个有效帧时间，但 `img_x_size`、`img_y_size` 均为 0。原解析器因此将整份索引归为协议错误，未进入图片加载。两张 JPEG 均可读取，原始尺寸为 2560×1440，对应单帧 256×144；相邻第 2、3 集也有零尺寸响应。对照《凡人修仙传》`ep733316` 的尺寸为 480×270，解析正常。

协议包保留零尺寸和已验证的索引，不引入图片解码依赖。`ApiPlaybackRepository` 在任一单格尺寸为零时，调用 app 注入的 `AppImageCache.dimensions`，用 `ImageDescriptor` 读取原始编码尺寸，不分配原图的完整像素缓冲。有效尺寸在 data 层推导后再交给领域模型，UI 无协议判断；正常正尺寸响应不增加图片读取。推导要求图片宽高可被对应网格整除、单格为正且不超过 4096，并与已有非零字段一致。

图片测量复用公开 CDN 传输、4 MiB 上限、缓存账号代次和已有解码限制。开启图片缓存时，测量与后续显示复用第一页字节；关闭时维持不落盘策略。测量等待继承索引操作的剩余 25 秒 deadline，换源／账号切换会取消当前消费者；共享图片下载由缓存持有，继续遵守自身取消与超时边界。失败分类保留网络／超时补试与协议错误不重放的规则。

定向回归覆盖零／单边零尺寸、正常尺寸无额外图片请求、矩形网格、跨页索引、不能整除／过大／矛盾尺寸、错误分类和测量途中源／账号取消。合成四格图片通过实际 `ImageDescriptor`、仓储映射和共享裁剪组件验证四个颜色，测量及反复显示合计仅一次下载。

本轮定向应用测试 28 项、协议测试 24 项通过。`tool/check.ps1 -SkipPub` 完成根应用及四个包的格式、静态分析和测试：根应用 1602 项、`bili_api` 345 项、`bili_player` 32 项、`bili_danmaku` 72 项、`bili_mux` 2 项通过；`bili_mux` 另 7 项因未设置 `BILI_MUX_LIBRARY` 按条件跳过。检查日志为 `artifacts/pgc-storyboard-check.log`。文档相对链接和本轮文件的差异空白检查通过。

Windows Debug 集成测试构建并运行成功，真实游客 `ep323085` 的 186 帧按 256×144 单格解析；进度条反复跨第一页／第二页，均实际解码并显示，合计仅下载两张图片，未触发 seek。日志为 `artifacts/pgc-storyboard-online.log`，截图为 `build/validation/pgc-storyboard-ep323085.png`（构建产物，不提交远程图片）。未执行 Release 构建或性能测量。

指定剧集的显式 Windows 在线回归：

```powershell
$env:BILI_TIMELINE_OUTPUT = (Join-Path (Get-Location) 'build/validation')
flutter test integration_test/windows_pgc_storyboard_test.dart -d windows --dart-define=BILI_ONLINE_SMOKE=true
Remove-Item Env:BILI_TIMELINE_OUTPUT
```

该用例只做游客只读元数据／图片请求和进度条渲染，不执行账号写入，也不验证原生音视频解码。Android/macOS 图片显示与触摸操作仍需实机验证。

## 2026-10-11 空索引后的有限补试

此前空图片列表或空时间索引被解析为 `null`，会话却保留 `_storyboardRequested=true`，导致后续悬停一直只显示时间，必须重开播放源才能再读。现空结果与网络／超时失败共用 5 秒、10 秒冷却和每个播放源最多 3 次逻辑读取的预算；后续悬停／移动／拖动触发补试，不设后台定时器。空结果保持无错误提示，真正没有缩略图的视频也只会有限查询。成功后继续复用索引，鉴权／权限／限流／未找到／协议错误的处理不变。

fake clock/repository 回归覆盖首次空结果后恢复、冷却期间禁止读取、在途单飞、成功复用、空结果与超时交替时共享预算、连续空结果的上限／无后台请求／换源重置，以及旧源迟到空结果不能清除新源索引。既有网络补试与账号 epoch 隔离回归继续通过，悬停不 seek、不重新打开媒体。

本轮缩略图定向测试 15 项、根应用全量 1821 项通过；四个独立包完成格式、分析和测试，`bili_api` 390 项、`bili_player` 40 项、`bili_danmaku` 86 项、`bili_mux` 2 项通过。`bili_mux` 另 7 项因未设置 `BILI_MUX_LIBRARY` 按条件跳过。日志为 `artifacts/storyboard-empty-retry-targeted.log`、`artifacts/storyboard-empty-retry-root-tests.log` 和 `artifacts/storyboard-empty-retry-packages.log`。

`tool/check.ps1 -SkipPub` 的平台边界脚本与根格式检查通过，首次根分析被并行音量均衡工作的 `tool/audio_normalization_smoke.dart:38` lint 阻断；该并行改动自行修正后，单独重跑根分析通过，后续根测试及四包检查分别完成。本次只提交缩略图相关差异，不包含并行功能。本轮通过受控空响应验证恢复，没有捕获原故障的真实接口响应，也未进行原生构建或三端实机验收。

## 2026-10-11 官网 pvdata 与交互补试

样本 `BV1HX8v6UEZ3`（`cid=41212379830`）有一次参数正确的 `index=1` 请求返回 HTTP 200／业务码 0、空 JSON `index`，但四张图片和 `pvdata` 均存在。后续游客读取恢复正常，不能据此把所有间歇故障都归因于超时。官网正常请求使用 `aid`、`cid`，不传 `index=1`，时间索引另从 `pvdata` 下载；应用保留已验证的 `bvid`、`cid` 别名参数，改用相同的二进制索引格式。

只读检查官网当前加载的 [播放器核心 core.ba67b466.js](https://s1.hdslb.com/bfs/static/player/main/core.ba67b466.js) 和 [进度条组件 npd.911.a6141530.js](https://s1.hdslb.com/bfs/static/player/main/widgets/npd.911.a6141530.js)：`HttpVideoShot` 没有定时重试次数／间隔，失败的 HTTP Promise 从内存缓存移除，下一次进度条 mouseenter／触摸开始重新读取；正常 HTTP 描述的内存缓存期限为 900 秒。进度条的 300 毫秒计时属于悬停显示状态，元数据请求在移入时立即发起。`pvdata` 的 XHR 只见 onload 解析，没有该组件自己的 onerror、timeout 或自动补试分支；不能据此推断官网所有网络服务的全局超时。

在独立测试标签中仅阻断 `/x/player/videoshot`：首次移入只发一次，保持停留期间没有追加请求，再次移入发一次；解除阻断后再移入，重新获取描述并下载 `pvdata`。测试阻断已解除，标签已关闭。脱敏证据为 `build/validation/storyboard-diagnostics/retry-observations.json`。未复制官网源码、图片或资源，协议解析与测试独立编写；上述来源是观察依据，不假定其源码有再分发许可。

本轮对齐的是索引格式、失败后由新交互触发补试和每次 HTTP 读取不自动重放。应用仍按播放源缓存完整结果，不增加官网的通用 15 分钟 HTTP 缓存；维持有界单飞、25 秒操作预算、取消、账号隔离与公开 CDN 校验，避免网络失败留下永久在途读取。图片 CDN 变体／错误后尝试下一图片页的官网策略未改变项目既有图片缓存；本轮不宣称整个官网网络层逐项相同。旧的冷却、次数上限与 JSON index 规则仅为上方历史验收记录。

新回归覆盖空 JSON index 不影响 pvdata、二进制大端／零哨兵／严格递增／帧容量、奇数字节与 40002 字节上限、URL 与凭据边界、描述和二进制共享 deadline、两阶段失败不自动重放、二进制迟到取消／账号切换、移入／拖动一次触发与连续移动不请求、超过三次失败仍可恢复、换源迟到失败隔离。定向协议测试 39 项、应用播放相关测试 200 项通过；真实游客接口读到指定视频 359 帧、四张 10×10 图片页、单帧 480×270。

Windows Debug 在线回归构建并运行成功：`BV1HX8v6UEZ3` 的四张图片页均实际解码／显示，六次跨页移动合计四次图片下载、一次预览请求、零次 seek；既有 `ep323085` 回归继续读到 186 帧、推导 256×144 单格并显示两页，合计两次图片下载。日志为 `artifacts/storyboard-pvdata-online.log`、`artifacts/storyboard-pvdata-pgc-online.log`。该验证覆盖元数据和 Flutter 预览渲染，不宣称本轮重新验证原生音视频解码。未执行 Android/macOS 实机回归或 Release 性能测试。

指定视频只读在线回归需显式启用：

```powershell
flutter test integration_test/windows_storyboard_pvdata_test.dart -d windows --no-pub --dart-define=BILI_ONLINE_SMOKE=true
```


`tool/check.ps1 -SkipPub` 通过根应用和四个独立包的格式、静态分析、测试及平台边界脚本：根应用 1908 项、`bili_api` 426 项、`bili_player` 51 项、`bili_danmaku` 86 项、`bili_mux` 2 项通过；`bili_mux` 另 7 项因未设置 `BILI_MUX_LIBRARY` 条件跳过。日志为 `artifacts/storyboard-pvdata-check.log`。文档相对链接和本轮差异空白检查通过。

提交前将本任务暂存区单独导出源码快照，排除并行高能进度条、设置和依赖修改；快照静态分析与 10 个 Dart 文件格式检查通过，协议回归 39 项、应用播放相关回归 184 项通过。日志为 `artifacts/storyboard-commit-analysis.log`、`artifacts/storyboard-commit-targeted.log`。前述全工程检查数量对应当时整个工作区，本提交只包含本任务及公开二进制读取所需的有界传输支持。

## 2026-10-30 点击跳转的进度回跳修复

- 原因：`PlaybackTimelineBar` 在 `onChangeEnd` 中先清空 `_drag`，随后通过无返回值的回调发起异步 seek。后端尚未确认时，Slider 恢复使用旧的 `snapshot.position`，出现「目标 → 旧位置 → 目标」的闪动。既有 fake engine 立即完成 seek，原测试未覆盖等待窗口。此前画面横滑的修复仅覆盖 `PlayerSeekControls`，没有覆盖进度条点击／拖动提交路径。
- 生命周期排查：普通／全屏、播放／暂停四组面板测试记录同一个时间轴 State，点击松开后实例保持不变；新增缓冲、seeking 状态和旧位置采样的检查。此次修复保留现有组件层级及播放源 key，不通过重建播放器解决显示问题。
- 修复：回调返回会话 seek 的 Future，进度条分别保留交互中的拖动位置与提交后等待确认的目标；`finally` 清理目标。新手势、新 seek、切源或禁用使旧操作失效，迟到完成不能清空新目标，销毁后不更新 State。章节菜单沿用同一提交逻辑；面板在提交前核对当前源代次和页面／应用活动状态，防止切源或失活后提交旧目标。预览不写入会话确认位置、续播或弹幕时钟。
- 验证在基于 `1a3771e`、仅叠加本次差异的独立检出目录进行，避免其他运行进程占用主工作区测试 DLL；依赖通过锁文件解析，不包含同期听视频／后台播放／设置等未提交改动。SQLite 与 media-kit 复用本机缓存，SHA-256 与固定依赖清单一致，并继续经过原构建钩子的完整性校验；没有修改 Pub 缓存或绕过校验。
- 修复前四组点击回归均复现目标约 126 秒回退到旧 30 秒位置，State 身份检查通过。修复后完整面板、时间轴及触控板定向回归 341 项通过，补充的章节等待确认用例连同最终时间轴 15 项通过；覆盖旧时钟采样、缓冲／seeking、失败清理、连续操作、切源、禁用及销毁。[修复前复现日志](../../build/validation/timeline-click/before.log)、[面板等定向日志](../../build/validation/timeline-click/targeted-isolated.log)、[最终时间轴日志](../../build/validation/timeline-click/timeline-final.log)。
- `tool/check.ps1 -SkipPub` 最终完整通过，此前已执行五份锁文件的 `--enforce-lockfile` 解析：格式、完整静态分析、打包边界脚本通过；根应用 3519、`bili_api` 496、`bili_player` 96、`bili_danmaku` 118、`bili_mux` 5，共 **4234 项测试通过**。根应用 13 项 Windows 符号链接测试因权限跳过；mux 10 项原生测试因未配置 `BILI_MUX_LIBRARY` 跳过，不计为原生验证。[完整检查日志](../../build/validation/timeline-click/check-final.log)。文档相对链接与 `git diff --check` 通过。
- 本轮只修改共享 Flutter 呈现层，未改变原生播放器接口；未构建安装包或执行 Android／Windows／macOS 实机视觉验收。DTD 未发现活动调试应用，热重载尝试返回无连接；不将 Widget 回归视作设备或性能验收。
