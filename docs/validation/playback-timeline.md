# 视频章节与悬停缩略图

日期：2026-10-05。已接入普通视频播放页，采用自适应分段进度条；Windows 游客样本 `BV1VEHn6TEKq` 已完成原生播放和真实图片验证。Android/macOS 尚未实机验证。

## 交互

- 章节起止时间决定轨道划分；已播放、已缓冲和未播放部分保留各自颜色，悬停片段略微增粗。无章节的视频使用连续轨道。
- 标题能放下时显示在片段上方，短片段隐藏常驻标题。右侧章节菜单始终提供完整标题和起点，可点击跳转。隐藏控制栏时的底部细进度也保留章节分隔。
- 鼠标悬停或触摸拖动显示该时间对应的预览帧、时间和章节名。卡片贴近指针，并在播放器左右边缘避让；小窗优先保留时间，空间不足时隐藏图片和章节名。图片不可用不影响时间提示与 seek。
- 拖动过程只更新本地预览，松开才提交一次 seek；悬停不 seek、不暂停，也不创建额外播放器。直播不显示点播时间轴。
- 换 P、换视频、播放源更新或停止会清除预览；隐藏控件、页面离开及全屏布局切换由 OverlayPortal 的组件生命周期移除悬浮层。

## 端点与边界

| Profile / 能力 | Host、方法、Path | 鉴权、签名、响应和读取规则 |
| --- | --- | --- |
| Web / 章节与字幕列表 | `api.bilibili.com` GET `/x/player/wbi/v2` | Web Cookie 可选、WBI；字符串 `aid`、`cid`；JSON `view_points` 与 `subtitle.subtitles`；无分页 |
| Web / 缩略图索引 | `api.bilibili.com` GET `/x/player/videoshot` | Web Cookie 可选、无签名；`bvid`、`cid`、`index=1`；JSON 图片页、时间索引、网格和单帧尺寸；无分页 |
| Public CDN / 图片 | 接口返回的 HTTPS `*.hdslb.com` 或 `*.bilibili.com` | 独立公开图片传输；Referer 为 Bilibili，不携带 Cookie/Authorization；至多 3 次重定向并重新检查目标 |

两项 API 使用现有 `ApiRequests` 的取消、账号 epoch 和 25 秒总 deadline，继承只读请求最多额外两次网络/服务端故障重试；认证、限流、风控、协议错误不重放。缩略图端点使用 `Mozilla/5.0` User-Agent：该样本在默认应用 UA 下返回空图片/索引，用此 UA 可读到真实帧；修改仅限此端点，其余 API 保留原 UA。

`PlaybackMetadataRepository` 为应用领域端口，`bili_api` 只提供协议模型和读取。章节与字幕合并为一次读取；任一可选组件格式错误被分类记录，不丢弃另一组件。章节最多 200 项，规范化乱序、越界、重叠；空白间隔不虚构标题。缩略图首次悬停才请求，每个播放源最多一次逻辑读取；请求失败保留时间/章节预览，换源后可重新读取。旧源、旧账号响应不能改写新状态。

索引最多 20000 帧、图片最多 200 页、网格至多 20×20、单格尺寸至多 4096，时间不超过七天。只移除 `[0,0,...]` 中多余的前导零，严格校验后续时间递增和网格容量。二分查找选取最近的前序帧，按页、行、列裁剪雪碧图，不使用播放器抓帧。图片复用现有容量受限缓存：编码图片单张 4 MiB、总量 64 MiB/512 项，解码缓存 64 MiB/256 项、长边至多 1280；大网格预览清晰度受该解码上限约束。

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
