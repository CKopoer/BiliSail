# 视频卡悬停播放与稍后再看

日期：2026-10-06。视觉参考为用户截图和本机安装的 `C:\Program Files\bilibili\哔哩哔哩.exe`（非 UWP）；协议另按用户要求只读检查相邻 `bili-kernel` 和官方网页实际悬停请求。没有复制客户端/网页源码、SVG 或资源，没有新增依赖。

**后续加载修复**：本页记录首次实现及当时音视频加载证据。现行卡片为 200 毫秒悬停、列表 cid 直传、显式无音轨预览、自动常规 CDN 优先，以及每地址外层/原生统一 3 秒和最多三个视频 URL。下文 300 毫秒/音视频/8 秒描述属于早期版本，现行来源、原因和验证见 [悬停加载延迟](video-preview-loading.md)。

## 网页接口核对

本轮在 Chrome 中检查官方首页原始视频卡。用户首页被 BewlyCat 扩展替换，因此临时覆盖原始 `#app` 与扩展 `#bewly` 的显示样式后抓取请求，完成后已恢复原始样式；没有修改扩展设置或保存 Cookie、签名、会话值和 CDN 查询串。

- 悬停触发 `GET https://api.bilibili.com/x/player/wbi/playurl`，参数包括 `bvid`、`cid`、`qn=32`、`fnver=0`、`fnval=2000`、`fourk=1`、`from_client=BROWSER`，以及 WBI 的 `wts`、`w_rid`。这次 `need_fragment=false`，响应 `code=0`、`quality=32`，返回普通 DASH 视频与音频轨道，没有请求独立的悬停预览视频流端点。
- 预览使用返回的 `.m4s` 视频资源。鼠标保持不动时，HTML video 从 12.87 秒持续播放到 39.37 秒，`paused=false`、`muted=true`；移开后变为 `paused=true`，位置停在 39.50 秒。
- 观察到官方首页脚本 [index-12fc55c2.js](https://s1.hdslb.com/bfs/static/shanks/laputa-home/assets/index-12fc55c2.js) 的 inline player，以及悬停加载的播放器 [core.b237bb82.js](https://s1.hdslb.com/bfs/static/player/main/core.b237bb82.js)。只核对交互和协议，不复制实现。
- 本地 `bili-kernel` 提交 `e26f6dbd071e20d4220806fcff7bd675f3c29fc5` 的 [IPlayerService](../../../bili-kernel/src/BiliKernel.Abstractions/Bili/Media/IPlayerService.cs)、[PlayerClient](../../../bili-kernel/src/Services/Services.Media/Core/PlayerClient.cs) 和 [BiliApis](../../../bili-kernel/src/BiliKernel.Abstractions/Bili/BiliApis.cs) 没有封装专用悬停预览接口。普通视频提供 `/x/player/playurl` 和 App `PlayView`；协议中的 `is_preview`/`has_preview` 不是新的请求入口。此结论限于当前快照和本轮网页样本，不推断所有历史版本或所有页面。

此前实现使用 `/x/player/videoshot` 的雪碧图帧；按用户补充要求，卡片已切换为真实视频自动播放。播放器时间轴仍使用既有雪碧图缩略图。

## 行为与范围

- [VideoCardCover](../../lib/shared/ui/video_card_cover.dart) 用于公共网格卡和个人主页横向投稿卡。推荐、搜索、视频动态、收藏、稍后再看、历史和相关视频沿用 `VideoCard`。
- 鼠标进入整个视频卡（包括标题）时，封面放大 1.05 倍，过渡 200 毫秒，并显示右上角稍后再看按钮；停留 300 毫秒后获取首 P 的视频源，从零开始静音自动播放。指针静止时持续播放，横移不触发 seek。
- 移开后取消读取、停止并释放预览播放器，恢复封面/统计。短暂经过不加载；隐藏工作区、禁用 TickerMode、应用转入后台、换视频、账号变化或销毁同样取消。迟到响应不能恢复旧预览。
- 触屏点击沿用打开视频；键盘聚焦可访问稍后再看按钮，Enter 独立添加且不启动预览。作者链接仍独立响应；标题、作者、网格尺寸和透明外框保持现有布局。
- 预览不可用时保留封面。预览只拥有临时引擎，不进入播放标签的 PlaybackManager/PlaybackSession，不读取或保存进度，不做历史、播放量或弹幕上报。静音通过打开源时 `volume=0` 实现。
- 稍后再看只在点击时提交；成功显示勾选和提示，重复点击不重发。游客提示登录，请求中禁用按钮；未知结果阻止当前账号生命周期内重发并提示核对列表。未用真实账号执行写操作。

## 架构与协议

组合根通过 [VideoCardInteractionScope](../../lib/shared/ui/video_card_interaction_scope.dart) 注入 [VideoCardController](../../lib/features/video/application/video_card_controller.dart)。控制器复用 VideoRepository 获取首 P 的 cid，再通过 PlaybackRepository.resolve 请求 `qn=32`、优先 H.264；权限或源可用性可能使实际选择的清晰度降级。页面不解析 JSON 或发网络请求。

进程拥有 [VideoCardPreviewPlayback](../../lib/features/video/application/video_card_preview_playback.dart)，通过既有 PlayerEngine/VideoSurface 契约播放，使用 DASH 音视频分轨与各自的请求头。最多一个活动预览引擎，新的预览等待旧引擎释放；等待期间只接受最新 generation。加载中取消也立即使旧 native open 失效。每次打开预算 8 秒，失败后最多尝试一个不同的服务端备用地址。stop 失败而 dispose 已确认时允许后续预览；dispose 未确认时，当前管理器不再创建新预览，以免叠加原生资源。卡片保持可点击的封面。

同日根据用户报告补充 CDN 设置、打开失败／超时的备用尝试，以及后台／隐藏工作区恢复后的静止悬停重启。用户样本 `BV1HcHn6UEdF` 修复前实测可播，没有把受控 403 认作原故障的直接证据；具体原因边界、验证和配置规则见 [CDN 与悬停恢复](video-cdn.md)。

首 P 元数据按账号隔离，LRU 上限 24；媒体 URL 每次悬停重新解析，不落盘。稍后再看状态上限 256，同时最多 8 次不同视频的显式写。账号转换和应用退出还由组合根停止/关闭预览管理器，不依赖页面销毁来完成进程清理。

| 能力 | 端点与规则 |
| --- | --- |
| 视频详情 | 既有 Web GET `api.bilibili.com/x/web-interface/view`，首 P cid；Cookie 可选，JSON |
| 视频播放源 | 既有 Web/WBI GET `api.bilibili.com/x/player/wbi/playurl`，bvid、cid、qn；Cookie 可选，JSON，复用签名与账号 epoch/取消策略 |
| 原生媒体读取 | 响应中的 DASH 音视频 URL，沿用 MediaKitEngine 的独立 Referer/UA、Range 与源 generation；不把 Cookie 或完整签名 URL 写入诊断 |
| 添加稍后再看 | 既有 Web POST `api.bilibili.com/x/v2/history/toview/add`，Cookie/CSRF、bvid、JSON；显式一次提交，未知结果不重放 |

应用沿用普通播放源接口的 `fnval` 配置，没有机械照搬网页的全部客户端参数，也没有新建未经验证的预览端点。

## 验证

- 控制器、临时播放器与组件测试覆盖首 P/LRU、每次解析媒体 URL、取消/迟到响应、加载中移开、串行释放、最新悬停、缺失音轨、打开失败、账号转换、游客/重复/未知写、整卡悬停、静止时进度、移开/隐藏/后台/销毁、键盘和窄卡/大字号渲染。
- `tool/check.ps1 -SkipPub` 通过：根应用 769、API 包 245、播放器包 16、弹幕包 23 项，共 1053 项；四处格式检查和分析通过。日志 `build/video-card-hover-check.log`。当前工程包含用户的同期修改，计数是整个工作区检查结果。
- 新增/更新 [控制器测试](../../test/features/video/video_card_controller_test.dart) 6 项、[预览生命周期测试](../../test/features/video/video_card_preview_playback_test.dart) 6 项和 [组件测试](../../test/shared/ui/video_card_hover_test.dart) 5 项。取消订阅的已完成 Future 在 widget fake clock 中需通过一次真实事件循环释放，不使用无限 `pumpAndSettle` 等待连续播放。
- [Windows 原生游客验证](../../integration_test/windows_video_card_hover_test.dart) 通过，并完成 Debug 构建。真实样本 `BV1GJ411x7h7` 解码 852×480 视频与双声道音频，音量为 0；指针静止时进度继续前进超过 1 秒，移出停止、进度冻结并释放，标题再次悬停正常打开新的引擎，两轮最大未释放引擎数为 1。游客按钮只提示登录，不打开视频。
- 首次原生运行的再次悬停步骤超时；后续在悬停后显式绘制帧并单独运行原生检查后通过。没有将超时归因为某种未经确认的网络或平台故障。
- 原生截图已检查：`build/validation/video-card-hover-windows.png`；日志 `build/video-card-hover-windows.log`。浅/深色、窄卡/大字号由 fake surface 离线渲染验证，不能代替其他平台的媒体验收。
- Android/macOS 实机、登录后真实添加和 Release 性能测量未验证。

```powershell
flutter test integration_test/windows_video_card_hover_test.dart -d windows --no-pub --dart-define=BILI_ONLINE_SMOKE=true
```
