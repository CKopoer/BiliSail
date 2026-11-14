# 直播卡悬停预览

日期：2026-11-14。直播列表卡片按视频卡交互增加静音预览。本轮按用户要求不构建，实际设备播放与手感由用户后续验收。

## 官网依据

核对[哔哩哔哩直播首页](https://live.bilibili.com/)引用的[当前首页脚本](https://s1.hdslb.com/bfs/static/fenice/home/client/home/assets/App.04c3739b.js)。只参考接口和交互，自行实现，没有复制网页源码、资源或增加依赖。

- 官网 `requestPlayUrl` 使用 `api.live.bilibili.com` 的 GET `/xlive/web-room/v2/index/getRoomPlayInfo`，参数为 `room_id`、`no_playurl=0`、`mask=1`、`qn=0`、`platform=web`、`protocol=0,1`、`format=0,1,2`、`codec=0,1`、`special_scenario=2`。该首页调用不附加 WBI 签名，不同于完整房间的播放配置。
- 官网卡片约 120 毫秒后触发悬停；自动播放开启时创建 `HomePlayer.fMp4Player`，设置 `videoTag.muted=true`，移开停止并销毁。官网在受锁定或加密响应时拒绝预览。
- 本项目采用同一取流配置，沿用项目视频卡的 **200 毫秒**延迟、封面 **1.05 倍**缩放和首帧 **200 毫秒**淡入。此处以本项目视频卡样式为准。
- 游客只读接口烟测：直接请求及本轮 `LiveClient.getPreviewInfo` 均确认短房间号 `6` 返回真实房间号 `7734200`、`live_status=1`，含 AVC／HEVC 的 FLV、TS 和 fMP4 共六组流，各有两个地址。只检查响应状态与格式数量，没有读取媒体或启动原生播放器；不将接口可用当作实际播放通过。此项为当时在线状态，脱敏输出见 `build/validation/live-card-preview-2026-11-14/api-smoke.log`。

## 实现边界

- [LiveClient](../../packages/bili_api/lib/src/clients/live_client.dart) 独立 `getPreviewInfo`，共享已有直播流解析；[领域端口](../../lib/features/live/domain/live_preview_repository.dart)及 [API Repository](../../lib/features/live/data/api_live_repository.dart)隔离协议、账号 epoch、取消与错误分类。完整直播取流配置保持原有路径。
- [直播卡预览控制器](../../lib/features/live/application/live_card_preview_controller.dart)只请求预览源，优先 AVC fMP4，保留可用 TS／FLV 后备及原始 URL；不创建正式播放会话，不连接弹幕，不调用进房、观看历史或其他账号写接口。只对当前悬停取流，不预取整页，不落盘签名地址。
- 视频和直播共用进程级 [CardPreviewPlayback](../../lib/features/playback/application/card_preview_playback.dart)。每地址打开预算 3 秒，最多三个不同服务端地址、向前预读 5 秒，始终静音；旧引擎确认释放后再创建下一引擎，释放失败阻止后续创建。视频原类型名保留兼容别名，仍使用无音轨的 DASH 预览。
- 两类卡片共用 [CardHoverPreview](../../lib/shared/ui/card_hover_preview.dart)的延迟、前后台、滚动取消、首帧淡入和失败回退。直播使用带 `isLive=true` 的媒体源，不显示点播进度条；打开返回沿用播放器已有的视频输出首帧确认。
- [直播卡封面](../../lib/shared/ui/live_card_cover.dart)和 [LiveRoomCard](../../lib/features/feed/presentation/home_feed_cards.dart)支持封面、标题及作者区域悬停。移开、点击、隐藏工作区、停用 Ticker、进入后台、切房间或账号变化均取消对应预览。闲置／触摸卡片不创建预览计时器或播放器，滚动取消时立即还原缩放。
- 设置沿用 `videoCardHoverPlayback` 的原有持久化字段、默认值和失败回退，显示名改为“卡片悬停播放”，说明同时覆盖视频与直播。没有新增设置迁移。
- 首页／直播频道、搜索结果及历史记录中的直播卡共用该封面与预览生命周期。搜索与历史已知未开播的条目不请求预览；取流结果也再次检查直播状态。各入口保留原有标题高亮、状态标记、作者及房间跳转。

## 自动验证

- 新增 API 测试覆盖官网参数、长房间号、完整备用 URL、锁定／加密拒绝、未开播、无流与非法 ID。
- 新增控制器测试覆盖 AVC fMP4 优先、FLV 直播标记、静音／预算／缓存、取消／账号 scope／epoch／销毁／旧响应隔离、空源、读失败、视频与直播串行切换以及三个地址的重试上限。
- 新增组件测试覆盖标题悬停、延迟取消、首帧前保留封面、无直播进度条、点击导航、设置开关、后台／隐藏／Ticker、滚动结束重启、换房间与触摸不取流；沿用视频预览的既有释放、首帧、备用地址和 Sliver 回归。
- 定向回归 178 项通过，覆盖新增直播控制器／组件、原有视频预览／Sliver、搜索、历史和设置；API 新增 7 项通过。定向日志 `build/validation/live-card-preview-2026-11-14/targeted.log`。
- `tool/check.ps1 -SkipPub`：格式、根静态分析与构建边界脚本通过。根全量 5456 项通过、13 项跳过、两项同期修改的用例失败，日志 `build/validation/live-card-preview-2026-11-14/check.log`，不能报告全量通过：
  - 消息 `a superseded refresh cannot refresh badges after returning to the same category`：期望 1、实际 2；该用例来自同期消息修改。之后单独复跑此用例及整个 `messages_controller_test.dart` 均通过（整文件 43 项），记录 `unrelated-message-test.log` 与 `message-controller-recheck.log`。
  - 设置 `SQLite snapshots custom settings round trip and defaults restore without a DB migration`：期望 schema 49、实际 50，对应同期预测式返回设置修改。直播预览没有变更快照版本或设置仓储；未改动该项无关代码。
- 补跑 `tool/check.ps1 -SkipPub -Stage PackageTests` 通过：`bili_api` 935、`bili_player` 280、`bili_danmaku` 161、`bili_mux` 5 项。播放器 3 项原生用例因未配置跳过，mux 10 项原生用例因未设置 `BILI_MUX_LIBRARY` 跳过，不算原生通过。日志 `build/validation/live-card-preview-2026-11-14/packages.log`。
- 应用组合根最终定向分析、文档相对链接及 `git diff --check` 通过。只提交本次文件／设置文案 hunk，保留同期消息、导航及设置修改。

未构建、未执行原生或实机播放、未测性能；本机未发现可热重载的运行中 Dart／Flutter 调试连接。

## 历史记录卡片样式对齐

同日按用户反馈，将历史记录中的直播卡与视频卡进一步对齐：

- 历史内容卡采用与视频卡相同的 1 像素边框留白、16:9 封面、6 像素封面圆角；标题预留两行，统一 15 像素／22 像素行高及字重，作者与观看日期统一 13 像素／16 像素行高、间距及宽度约束。短标题和长标题不再改变整卡高度。
- 两类卡片共用 [菜单按钮及弹出层](../../lib/shared/ui/card_menu.dart)，统一三档按钮尺寸、图标、桌面悬停／键盘焦点显示、手机常驻与底部操作面板。历史内容卡保留删除记录、作者／房间跳转和忙碌态保护，直播状态标记与悬停预览保留。
- 新增 [组件对照测试](../../test/features/library/history_content_card_test.dart)，在 140／220／320 像素宽度及 1／2 倍字体缩放下直接比较整卡高度、封面尺寸、标题／元数据样式以及菜单按钮的尺寸和位置；另覆盖窄宽屏菜单、忙碌时点击不导航、长按操作。
- 历史、直播预览、视频卡菜单与布局定向回归共 89 项通过，日志 `build/validation/live-card-preview-2026-11-14/history-style-targeted.log`。本轮 `tool/check.ps1 -SkipPub` 全部通过：格式、分析与构建边界检查通过，根应用 5468、API 935、播放器 280、弹幕 161、mux 5 项通过；根应用 13、播放器 3、mux 10 项按配置跳过，其中 `BILI_MUX_LIBRARY` 未配置，不算 mux 原生通过。日志 `history-style-check.log` 位于同一目录。
- 本轮仍不构建，未执行实机和性能验收；未发现可热重载的调试进程。
